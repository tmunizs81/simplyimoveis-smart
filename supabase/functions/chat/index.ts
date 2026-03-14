import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const { messages, propertyId } = await req.json();
    const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY");
    if (!GROQ_API_KEY) throw new Error("GROQ_API_KEY is not configured");

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Fetch properties from database for context
    let propertiesContext = "";

    if (propertyId) {
      const { data: prop } = await supabase
        .from("properties")
        .select("*, property_media(file_path, file_type)")
        .eq("id", propertyId)
        .eq("active", true)
        .single();

      if (prop) {
        propertiesContext = `\n\n--- IMÓVEL EM FOCO (ID: ${prop.id}) ---
Título: ${prop.title}
Endereço: ${prop.address}
Bairro: ${(prop as any).neighborhood || "Não informado"}
Cidade: ${(prop as any).city || "Não informada"}
Preço: R$ ${Number(prop.price).toLocaleString("pt-BR")}
Tipo: ${prop.type}
Status: ${prop.status === "venda" ? "À Venda" : "Para Aluguel"}
Quartos: ${prop.bedrooms} | Suítes: ${prop.suites || 0} | Banheiros: ${prop.bathrooms} | Garagem: ${prop.garage_spots || 0} | Área: ${prop.area}m²
Piscina: ${(prop as any).pool_size > 0 ? `Sim, ${(prop as any).pool_size}m²` : "Não"}
Descrição: ${prop.description || "Sem descrição"}
Proximidades: ${(prop as any).nearby_points || "Não informado"}
Destaque: ${prop.featured ? "Sim" : "Não"}
---`;
      }
    }

    const { data: allProps } = await supabase
      .from("properties")
      .select("id, title, address, neighborhood, city, price, type, status, bedrooms, suites, bathrooms, garage_spots, area, description, featured, pool_size, nearby_points")
      .eq("active", true)
      .order("featured", { ascending: false })
      .limit(50);

    if (allProps && allProps.length > 0) {
      propertiesContext += "\n\n--- IMÓVEIS DISPONÍVEIS ---\n";
      propertiesContext += allProps
        .map(
          (p: any) =>
            `• [ID:${p.id}] ${p.title} — ${p.address}${p.neighborhood ? `, ${p.neighborhood}` : ""}${p.city ? ` - ${p.city}` : ""} — R$ ${Number(p.price).toLocaleString("pt-BR")} — ${p.type} — ${p.status === "venda" ? "Venda" : "Aluguel"} — ${p.bedrooms}q/${p.suites || 0}s/${p.bathrooms}b/${p.garage_spots || 0}g/${p.area}m² ${p.pool_size > 0 ? `🏊 Piscina ${p.pool_size}m²` : ""} ${p.featured ? "⭐" : ""} ${p.description ? `— ${p.description}` : ""} ${p.nearby_points ? `— Proximidades: ${p.nearby_points}` : ""}`
        )
        .join("\n");
    }

    const systemPrompt = `Você é a Luma, assistente virtual premium da Simply Imóveis, imobiliária da corretora Talita Muniz em Fortaleza, Ceará.

## Personalidade
- Sofisticada, acolhedora e extremamente profissional
- Conhecimento profundo do mercado imobiliário de Fortaleza
- Usa linguagem clara, elegante e acessível
- Responde sempre em português brasileiro
- Usa emojis com moderação para dar personalidade

## Capacidades
1. **Consultor Imobiliário**: Responde sobre qualquer imóvel do portfólio usando dados reais do banco
2. **Agendador de Visitas**: Quando o cliente demonstra interesse em visitar, coleta data e horário preferidos (já terá nome e telefone)
3. **Especialista em Financiamento**: Orienta sobre opções de financiamento, documentação necessária
4. **Conhecedor da Região**: Informações sobre bairros de Fortaleza e região metropolitana

## REGRA CRÍTICA: Coleta Inicial de Contato
- Na sua PRIMEIRA resposta da conversa, você DEVE pedir o nome completo e telefone com DDD do cliente de forma natural e acolhedora.
- Exemplo: "Para que eu possa te atender melhor e nossa equipe entre em contato se necessário, poderia me informar seu nome completo e telefone com DDD? 😊"
- Quando o cliente fornecer nome e telefone, registre IMEDIATAMENTE com o bloco <<<REGISTRAR_CONTATO>>> e depois continue ajudando normalmente.
- NUNCA peça nome e telefone novamente após já ter recebido. Se o cliente já forneceu, siga a conversa sem repetir a solicitação.
- Use o nome do cliente nas respostas seguintes para personalizar o atendimento.

## Regras de Agendamento
Quando o cliente quiser agendar uma visita:
1. Pergunte qual imóvel (se não ficou claro)
2. Já terá nome e telefone da coleta inicial — NÃO peça novamente
3. Pergunte data e horário preferidos
4. Quando tiver TODOS os dados, responda com um bloco especial no formato:
   <<<AGENDAR_VISITA>>>
   {"client_name":"Nome","client_phone":"(85) 99999-9999","client_email":"email@opcional.com","preferred_date":"dd/mm/aaaa","preferred_time":"HH:mm","property_id":"uuid-do-imovel","notes":"observações opcionais"}
   <<<FIM_AGENDAMENTO>>>
   Seguido de uma mensagem de confirmação amigável.

## Regras de Coleta de Contato
Quando o cliente fornecer nome e telefone, registre UMA ÚNICA VEZ com:
   <<<REGISTRAR_CONTATO>>>
   {"client_name":"Nome","client_phone":"(85) 99999-9999","client_email":"email@opcional.com","subject":"Assunto/interesse do cliente","notes":"resumo do interesse"}
   <<<FIM_CONTATO>>>

REGRAS ABSOLUTAS sobre o registro:
- NUNCA mencione ao cliente que está registrando, fazendo registro interno, ou salvando dados. O registro é 100% SILENCIOSO e INVISÍVEL.
- NUNCA diga frases como "vou fazer um registro", "registrando seu contato", "salvando seus dados", "para registrar seu interesse" ou qualquer variação.
- Após receber nome e telefone, apenas agradeça naturalmente e pergunte como pode ajudar. Exemplo: "Obrigada, [Nome]! 😊 Como posso te ajudar hoje? Está procurando algum imóvel específico?"
- NUNCA envie o bloco <<<REGISTRAR_CONTATO>>> mais de uma vez na mesma conversa.
- O bloco de registro deve ser inserido de forma INVISÍVEL na resposta, sem qualquer menção verbal sobre ele.

## Dados do Portfólio
${propertiesContext || "Nenhum imóvel cadastrado no momento."}

## Informações da Imobiliária
- Corretora: Talita Muniz
- WhatsApp: (85) 99999-0000
- Localização: Fortaleza, CE e Região Metropolitana
- CRECI/CE ativo

Se não souber uma informação específica, oriente o cliente a falar diretamente com a Talita pelo WhatsApp.`;

    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${GROQ_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "llama-3.3-70b-versatile",
        messages: [{ role: "system", content: systemPrompt }, ...messages],
        stream: true,
        temperature: 0.7,
        max_tokens: 1024,
      }),
    });

    if (!response.ok) {
      const t = await response.text();
      console.error("Groq API error:", response.status, t);
      if (response.status === 429) {
        return new Response(JSON.stringify({ error: "Muitas solicitações. Tente novamente em alguns segundos." }), {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      return new Response(JSON.stringify({ error: "Erro no serviço de IA" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(response.body, {
      headers: { ...corsHeaders, "Content-Type": "text/event-stream" },
    });
  } catch (e) {
    console.error("chat error:", e);
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Erro desconhecido" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
