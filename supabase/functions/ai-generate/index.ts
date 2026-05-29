import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const AI_GENERATE_VERSION = "2026-05-29-selfhosted-ai-generate-v1";

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify({ version: AI_GENERATE_VERSION, ...body }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const getBearerToken = (req: Request) => (
  (req.headers.get("authorization") || req.headers.get("Authorization") || "")
    .replace(/^Bearer\s+/i, "")
    .trim()
);

async function verifyAdmin(supabaseAdmin: ReturnType<typeof createClient>, req: Request) {
  const token = getBearerToken(req);
  if (!token) return null;

  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !user) return null;

  const { data: roleData } = await supabaseAdmin
    .from("user_roles")
    .select("role")
    .eq("user_id", user.id)
    .eq("role", "admin")
    .maybeSingle();

  return roleData ? user : null;
}

function resolveProvider(requestedModel?: string) {
  const deepseekKey = (Deno.env.get("DEEPSEEK_API_KEY") || "").trim();
  const groqKey = (Deno.env.get("GROQ_API_KEY") || "").trim();
  const lovableKey = (Deno.env.get("LOVABLE_API_KEY") || "").trim();

  if (deepseekKey) {
    return {
      name: "DeepSeek",
      url: "https://api.deepseek.com/v1/chat/completions",
      model: requestedModel || "deepseek-chat",
      headers: { Authorization: `Bearer ${deepseekKey}` },
    };
  }

  if (groqKey) {
    return {
      name: "Groq",
      url: "https://api.groq.com/openai/v1/chat/completions",
      model: requestedModel && !requestedModel.includes("deepseek") ? requestedModel : "llama-3.3-70b-versatile",
      headers: { Authorization: `Bearer ${groqKey}` },
    };
  }

  if (lovableKey) {
    return {
      name: "Lovable AI",
      url: "https://ai.gateway.lovable.dev/v1/chat/completions",
      model: requestedModel && requestedModel.includes("/") ? requestedModel : "google/gemini-3-flash-preview",
      headers: { "Lovable-API-Key": lovableKey },
    };
  }

  return null;
}

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Método não permitido" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      return json({ error: "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes" }, 500);
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const user = await verifyAdmin(supabaseAdmin, req);
    if (!user) return json({ error: "Não autorizado ou sem permissão de admin" }, 401);

    const body = await req.json().catch(() => ({}));
    const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
    const systemPrompt = typeof body.systemPrompt === "string" ? body.systemPrompt.trim() : "";
    const requestedModel = typeof body.model === "string" ? body.model.trim() : "";
    const temperature = typeof body.temperature === "number" ? body.temperature : 0.7;

    if (!prompt) return json({ error: "prompt obrigatório" }, 400);

    const provider = resolveProvider(requestedModel);
    if (!provider) {
      return json({ error: "Nenhuma API Key de IA configurada no VPS (DEEPSEEK_API_KEY ou GROQ_API_KEY)." }, 500);
    }

    const aiResp = await fetch(provider.url, {
      method: "POST",
      headers: {
        ...provider.headers,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: provider.model,
        messages: [
          ...(systemPrompt ? [{ role: "system", content: systemPrompt }] : []),
          { role: "user", content: prompt },
        ],
        temperature,
        max_tokens: 4096,
      }),
    });

    if (!aiResp.ok) {
      const upstream = await aiResp.text();
      console.error("[ai-generate] upstream error", provider.name, aiResp.status, upstream);
      return json({
        error: `Erro na IA (${provider.name}/${provider.model})`,
        details: upstream.replace(/\s+/g, " ").trim().slice(0, 500),
      }, 500);
    }

    const aiData = await aiResp.json();
    const content = aiData.choices?.[0]?.message?.content;
    if (!content) return json({ error: "IA respondeu sem conteúdo" }, 500);

    return json({ data: content, provider: provider.name, model: provider.model });
  } catch (err) {
    console.error("[ai-generate] error", err);
    return json({ error: err instanceof Error ? err.message : "Erro interno" }, 500);
  }
};

if (import.meta.main && typeof Deno !== "undefined" && "serve" in Deno) {
  Deno.serve(handler);
}

export default handler;