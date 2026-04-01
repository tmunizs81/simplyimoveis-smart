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

async function verifyAdmin(supabaseAdmin: ReturnType<typeof createClient>, req: Request) {
  const authHeader = req.headers.get("authorization") || req.headers.get("Authorization");
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
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

const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseAdmin = createClient(
      getEnv("SUPABASE_URL"),
      getEnv("SUPABASE_SERVICE_ROLE_KEY")
    );

    const user = await verifyAdmin(supabaseAdmin, req);
    if (!user) return json({ error: "Não autorizado ou sem permissão de admin" }, 401);

    const contentType = req.headers.get("content-type") || "";

    // === JSON actions: delete, signed-url ===
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

    // === UPLOAD via FormData (multipart/form-data) ===
    let formData: FormData;
    try {
      formData = await req.formData();
    } catch (e) {
      console.error("admin-storage: formData parse error:", e);
      return json({ error: "Falha ao processar upload. Verifique o formato do envio." }, 400);
    }

    const bucket = formData.get("bucket");
    const path = formData.get("path");
    const file = formData.get("file");

    if (!bucket || !path || !file) {
      return json({
        error: "bucket, path e file obrigatórios",
        debug: {
          hasBucket: !!bucket,
          hasPath: !!path,
          hasFile: !!file,
          contentType,
        }
      }, 400);
    }

    // Convert File/Blob to ArrayBuffer for maximum compatibility with self-hosted runtime
    let fileBuffer: ArrayBuffer;
    let fileContentType = "application/octet-stream";

    if (file instanceof File || file instanceof Blob) {
      fileBuffer = await file.arrayBuffer();
      fileContentType = (file as File).type || "application/octet-stream";
    } else {
      // If it's a string (shouldn't happen, but handle gracefully)
      fileBuffer = new TextEncoder().encode(String(file)).buffer;
    }

    const { data, error } = await supabaseAdmin.storage
      .from(String(bucket))
      .upload(String(path), fileBuffer, {
        contentType: fileContentType,
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
