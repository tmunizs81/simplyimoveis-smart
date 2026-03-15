import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const ALLOWED_TABLES = [
  "tenants",
  "leads",
  "sales",
  "rental_contracts",
  "financial_transactions",
  "property_inspections",
  "inspection_media",
  "contract_documents",
  "tenant_documents",
  "sales_documents",
  "properties",
  "property_media",
  "property_code_sequences",
  "contact_submissions",
  "scheduled_visits",
  "user_roles",
] as const;

const getEnv = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Variável de ambiente obrigatória ausente: ${name}`);
  }
  return value;
};

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      getEnv("SUPABASE_URL"),
      getEnv("SUPABASE_SERVICE_ROLE_KEY")
    );

    // Verify caller is authenticated admin
    const authHeader = req.headers.get("authorization") || req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Não autorizado" }, 401);

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "Token inválido" }, 401);

    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) return json({ error: "Token inválido" }, 401);

    // Check admin role using service_role client (bypasses RLS)
    const { data: roleData } = await supabaseAdmin
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id)
      .eq("role", "admin")
      .maybeSingle();

    if (!roleData) return json({ error: "Sem permissão de admin" }, 403);

    // Parse request
    const body = await req.json().catch(() => ({}));
    const { action, table, data, match, select: selectCols, order } = body as {
      action: "insert" | "update" | "delete" | "select";
      table: string;
      data?: Record<string, unknown> | Record<string, unknown>[];
      match?: Record<string, unknown>;
      select?: string;
      order?: { column: string; ascending?: boolean };
    };

    if (!action || !table) return json({ error: "action e table obrigatórios" }, 400);
    if (!ALLOWED_TABLES.includes(table as (typeof ALLOWED_TABLES)[number])) {
      return json({ error: `Tabela '${table}' não permitida` }, 400);
    }

    // Execute with service_role (bypasses RLS)
    if (action === "insert") {
      if (!data) return json({ error: "data obrigatório para insert" }, 400);
      const q = supabaseAdmin.from(table).insert(data as never);
      const result = selectCols !== undefined
        ? await q.select(selectCols || "*")
        : await q.select("*");
      if (result.error) return json({ error: result.error.message }, 400);
      return json({ data: result.data });
    }

    if (action === "update") {
      if (!data || !match) return json({ error: "data e match obrigatórios para update" }, 400);
      let q = supabaseAdmin.from(table).update(data as never);
      for (const [k, v] of Object.entries(match)) {
        q = q.eq(k, v as never);
      }
      const result = await q.select("*");
      if (result.error) return json({ error: result.error.message }, 400);
      return json({ data: result.data });
    }

    if (action === "delete") {
      if (!match) return json({ error: "match obrigatório para delete" }, 400);
      let q = supabaseAdmin.from(table).delete();
      for (const [k, v] of Object.entries(match)) {
        q = q.eq(k, v as never);
      }
      const result = await q;
      if (result.error) return json({ error: result.error.message }, 400);
      return json({ success: true });
    }

    if (action === "select") {
      let q = supabaseAdmin.from(table).select(selectCols || "*");
      if (match) {
        for (const [k, v] of Object.entries(match)) {
          q = q.eq(k, v as never);
        }
      }
      if (order && order.column) {
        q = q.order(order.column, { ascending: order.ascending ?? true });
      }
      const result = await q;
      if (result.error) return json({ error: result.error.message }, 400);
      return json({ data: result.data });
    }

    return json({ error: "Ação inválida" }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erro interno";
    console.error("admin-crud error:", err);
    return json({ error: message }, 500);
  }
};

if (import.meta.main && typeof Deno !== "undefined" && "serve" in Deno) {
  Deno.serve(handler);
}

export default handler;
