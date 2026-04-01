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

const getEnv = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Env ausente: ${name}`);
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

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) return json({ error: "Token inválido" }, 401);

    const { data: roleData } = await supabaseAdmin
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id)
      .eq("role", "admin")
      .maybeSingle();
    if (!roleData) return json({ error: "Sem permissão de admin" }, 403);

    // Parse multipart form data
    const contentType = req.headers.get("content-type") || "";

    // Handle DELETE action via JSON
    if (contentType.includes("application/json")) {
      const body = await req.json();

      if (body.action === "delete") {
        const { bucket, paths } = body;
        if (!bucket || !paths?.length) return json({ error: "bucket e paths obrigatórios" }, 400);
        const { error } = await supabaseAdmin.storage.from(bucket).remove(paths);
        if (error) return json({ error: error.message }, 400);
        return json({ success: true });
      }

      if (body.action === "signed-url") {
        const { bucket, path, expiresIn } = body;
        if (!bucket || !path) return json({ error: "bucket e path obrigatórios" }, 400);
        const { data, error } = await supabaseAdmin.storage
          .from(bucket)
          .createSignedUrl(path, expiresIn || 3600);
        if (error) return json({ error: error.message }, 400);
        return json({ signedUrl: data.signedUrl });
      }

      return json({ error: "Ação inválida" }, 400);
    }

    // Handle UPLOAD via FormData
    if (!contentType.includes("multipart/form-data")) {
      return json({ error: "Content-Type deve ser multipart/form-data ou application/json" }, 400);
    }

    const formData = await req.formData();
    const bucket = formData.get("bucket") as string;
    const path = formData.get("path") as string;
    const file = formData.get("file") as File;

    if (!bucket || !path || !file) {
      return json({ error: "bucket, path e file obrigatórios" }, 400);
    }

    const { data, error } = await supabaseAdmin.storage
      .from(bucket)
      .upload(path, file, {
        contentType: file.type,
        upsert: false,
      });

    if (error) return json({ error: error.message }, 400);
    return json({ data });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erro interno";
    console.error("admin-storage error:", err);
    return json({ error: message }, 500);
  }
};

if (import.meta.main && typeof Deno !== "undefined" && "serve" in Deno) {
  Deno.serve(handler);
}

export default handler;
