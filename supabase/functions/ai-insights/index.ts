import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Verify admin via JWT
    const authHeader = req.headers.get("authorization") || "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    // Verify the caller is admin
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || "";
    const token = authHeader.replace("Bearer ", "");
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Não autenticado" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: roleData } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id)
      .eq("role", "admin")
      .limit(1);

    if (!roleData || roleData.length === 0) {
      return new Response(JSON.stringify({ error: "Acesso negado" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch data for analysis
    const [leadsRes, contactsRes, salesRes, propertiesRes] = await Promise.all([
      supabase.from("leads").select("*").order("created_at", { ascending: false }).limit(200),
      supabase.from("contact_submissions").select("*").order("created_at", { ascending: false }).limit(200),
      supabase.from("sales").select("*").order("created_at", { ascending: false }).limit(100),
      supabase.from("properties").select("id, title, type, status, price, neighborhood, city, bedrooms, area, featured, active").limit(100),
    ]);

    const leads = leadsRes.data || [];
    const contacts = contactsRes.data || [];
    const sales = salesRes.data || [];
    const properties = propertiesRes.data || [];

    // Build context for AI
    const dataContext = `
## DADOS PARA ANÁLISE

### Leads (${leads.length} registros)
${leads.map((l: any) => `- ${l.name} | Status: ${l.status} | Fonte: ${l.source} | Interesse: ${l.interest_type || "N/A"} | Budget: R$${l.budget_min || 0}-${l.budget_max || 0} | Criado: ${l.created_at}`).join("\n")}

### Contatos/Conversas (${contacts.length} registros)
${contacts.map((c: any) => `- ${c.name} | Fonte: ${c.source} | Assunto: ${c.subject || "N/A"} | Data: ${c.created_at}${c.chat_transcript ? `\nTranscrição:\n${c.chat_transcript.slice(0, 500)}` : ""}`).join("\n\n")}

### Vendas (${sales.length} registros)
${sales.map((s: any) => `- Comprador: ${s.buyer_name || "N/A"} | Status: ${s.status} | Valor: R$${s.sale_value || 0} | Data proposta: ${s.proposal_date || "N/A"} | Fechamento: ${s.closing_date || "N/A"}`).join("\n")}

### Imóveis Ativos (${properties.length} registros)
${properties.map((p: any) => `- ${p.title} | ${p.type} | ${p.status} | R$${p.price} | ${p.neighborhood || ""}/${p.city || ""} | ${p.bedrooms}q | ${p.area}m²`).join("\n")}
`;

    const systemPrompt = `Você é um analista de Business Intelligence especializado no mercado imobiliário de Fortaleza, CE. Analise os dados fornecidos e gere insights estratégicos DETALHADOS.

Responda SEMPRE em português brasileiro, com formatação Markdown rica.

## ESTRUTURA OBRIGATÓRIA DA RESPOSTA:

### 📊 Resumo Executivo
Um parágrafo com a visão geral do momento atual do negócio.

### 🎯 Principais Insights
Análise dos padrões encontrados nos dados (mínimo 5 insights com dados específicos).

### 📍 Análise de Localização
- Bairros mais procurados
- Regiões com maior interesse
- Tendências geográficas

### 🏠 Preferências de Imóveis
- Tipos mais procurados (apartamento, casa, etc.)
- Faixa de preço predominante
- Quantidade de quartos mais buscada
- Área média desejada

### 📈 Análise do Funil de Vendas
- Taxa de conversão de leads
- Gargalos no pipeline
- Tempo médio de conversão
- Fontes mais eficientes

### ⚠️ Pontos de Atenção
- Desistências e motivos prováveis
- Leads sem follow-up
- Oportunidades perdidas

### 💡 Recomendações Estratégicas
- Ações práticas para melhorar resultados
- Sugestões de marketing
- Oportunidades de mercado

### 📋 Métricas-Chave
Uma tabela markdown com KPIs importantes.

Se alguma seção não tiver dados suficientes, mencione isso e sugira como coletar os dados faltantes.`;

    // Use Lovable AI or Groq
    const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
    const LOVABLE_API_KEY = Deno.env.get("LOVABLE_API_KEY");
    const useLovable = !GROQ_API_KEY && !!LOVABLE_API_KEY;
    const apiKey = GROQ_API_KEY || LOVABLE_API_KEY;

    if (!apiKey) {
      return new Response(JSON.stringify({ error: "Nenhuma API key de IA configurada" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const aiUrl = useLovable
      ? "https://ai.gateway.lovable.dev/v1/chat/completions"
      : "https://api.groq.com/openai/v1/chat/completions";

    const aiModel = useLovable ? "google/gemini-2.5-flash" : "llama-3.3-70b-versatile";

    const aiResp = await fetch(aiUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: aiModel,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: `Analise os seguintes dados do meu negócio imobiliário e gere insights completos:\n${dataContext}` },
        ],
        temperature: 0.4,
        max_tokens: 4096,
      }),
    });

    if (!aiResp.ok) {
      const errText = await aiResp.text();
      console.error("AI error:", aiResp.status, errText);

      if (aiResp.status === 429) {
        return new Response(JSON.stringify({ error: "Muitas solicitações. Tente novamente em alguns segundos." }), {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (aiResp.status === 402) {
        return new Response(JSON.stringify({ error: "Créditos de IA insuficientes." }), {
          status: 402,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({ error: "Erro ao gerar insights com IA" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const aiData = await aiResp.json();
    const insightsText = aiData.choices?.[0]?.message?.content || "Não foi possível gerar insights.";

    // Also return raw metrics
    const metrics = {
      totalLeads: leads.length,
      leadsNovos: leads.filter((l: any) => l.status === "novo").length,
      leadsFechados: leads.filter((l: any) => l.status === "fechado_ganho").length,
      leadsPerdidos: leads.filter((l: any) => l.status === "fechado_perdido").length,
      totalContacts: contacts.length,
      totalSales: sales.length,
      totalProperties: properties.length,
      chatContacts: contacts.filter((c: any) => c.source?.includes("chat")).length,
      fontes: Object.entries(
        leads.reduce((acc: any, l: any) => {
          acc[l.source] = (acc[l.source] || 0) + 1;
          return acc;
        }, {})
      ),
    };

    return new Response(
      JSON.stringify({ insights: insightsText, metrics, generatedAt: new Date().toISOString() }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("insights error:", e);
    return new Response(
      JSON.stringify({ error: e instanceof Error ? e.message : "Erro desconhecido" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
};

if (import.meta.main && typeof Deno !== "undefined" && "serve" in Deno) {
  Deno.serve(handler);
}

export default handler;
