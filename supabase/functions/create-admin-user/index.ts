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

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes" }, 500);
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    const authHeader = req.headers.get("authorization") || req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Não autorizado" }, 401);

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "Token inválido" }, 401);

    const {
      data: { user: caller },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);

    if (authError || !caller) return json({ error: "Token inválido" }, 401);

    const { data: roleData, error: roleError } = await supabaseAdmin
      .from("user_roles")
      .select("role")
      .eq("user_id", caller.id)
      .eq("role", "admin")
      .maybeSingle();

    if (roleError) return json({ error: `Falha ao validar permissões: ${roleError.message}` }, 500);
    if (!roleData) return json({ error: "Sem permissão de admin" }, 403);

    const body = await req.json().catch(() => ({}));
    const { action = "create", email, password, userId } = body as {
      action?: "list" | "create" | "update" | "delete";
      email?: string;
      password?: string;
      userId?: string;
    };

    if (action === "list") {
      const { data: roles } = await supabaseAdmin.from("user_roles").select("user_id, role");
      const roleMap = new Map((roles || []).map((r) => [r.user_id, r.role]));

      const {
        data: listData,
        error: listErr,
      } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });

      if (listErr) return json({ error: listErr.message }, 500);

      const users = (listData?.users || []).map((u) => ({
        id: u.id,
        email: u.email,
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at,
        role: roleMap.get(u.id) || "user",
      }));

      return json({ users });
    }

    if (action === "create") {
      if (!email || !password) return json({ error: "Email e senha obrigatórios" }, 400);

      const { data, error } = await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });

      if (error) return json({ error: error.message }, 400);

      const { error: roleInsertError } = await supabaseAdmin
        .from("user_roles")
        .upsert({ user_id: data.user.id, role: "admin" }, { onConflict: "user_id,role" });

      if (roleInsertError) return json({ error: roleInsertError.message }, 500);

      return json({ user: { id: data.user.id, email: data.user.email } });
    }

    if (action === "update") {
      if (!userId) return json({ error: "userId obrigatório" }, 400);
      if (!password && !email) return json({ error: "Informe email ou senha para atualizar" }, 400);

      const updateData: Record<string, string> = {};
      if (password) updateData.password = password;
      if (email) updateData.email = email;

      const { error } = await supabaseAdmin.auth.admin.updateUserById(userId, updateData);
      if (error) return json({ error: error.message }, 400);

      return json({ success: true });
    }

    if (action === "delete") {
      if (!userId) return json({ error: "userId obrigatório" }, 400);
      if (userId === caller.id) return json({ error: "Não pode deletar a si mesmo" }, 400);

      await supabaseAdmin.from("user_roles").delete().eq("user_id", userId);

      const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
      if (error) return json({ error: error.message }, 400);

      return json({ success: true });
    }

    return json({ error: "Ação inválida" }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erro interno";
    return json({ error: message }, 500);
  }
};

if (import.meta.main && typeof Deno !== "undefined" && "serve" in Deno) {
  Deno.serve(handler);
}

export default handler;
