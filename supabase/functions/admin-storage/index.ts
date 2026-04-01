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
  console.log("[admin-storage] authHeader present:", !!authHeader);
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  console.log("[admin-storage] calling getUser...");
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
  console.log("[admin-storage] getUser result:", user?.id, "error:", error?.message);
  if (error || !user) return null;

  console.log("[admin-storage] checking role for user:", user.id);
  const { data: roleData } = await supabaseAdmin
    .from("user_roles")
    .select("role")
    .eq("user_id", user.id)
    .eq("role", "admin")
    .maybeSingle();
  console.log("[admin-storage] roleData:", roleData);

  return roleData ? user : null;
}

const handler = async (req: Request): Promise<Response> => {
  console.log("[admin-storage] === REQUEST START ===");
  console.log("[admin-storage] method:", req.method);
  console.log("[admin-storage] url:", req.url);

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    console.log("[admin-storage] creating supabase client...");
    const supabaseUrl = getEnv("SUPABASE_URL");
    const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
    console.log("[admin-storage] SUPABASE_URL:", supabaseUrl);
    console.log("[admin-storage] SERVICE_KEY present:", !!serviceKey);

    const supabaseAdmin = createClient(supabaseUrl, serviceKey);
    console.log("[admin-storage] client created OK");

    const user = await verifyAdmin(supabaseAdmin, req);
    if (!user) {
      console.log("[admin-storage] verifyAdmin returned null → 401");
      return json({ error: "Não autorizado ou sem permissão de admin" }, 401);
    }
    console.log("[admin-storage] admin verified:", user.id);

    const contentType = req.headers.get("content-type") || "";
    console.log("[admin-storage] content-type:", contentType);

    // === JSON actions: delete, signed-url ===
    if (contentType.includes("application/json")) {
      console.log("[admin-storage] parsing JSON body...");
      const body = await req.json();
      console.log("[admin-storage] JSON body action:", body.action);

      if (body.action === "delete") {
        const { bucket, paths } = body;
        if (!bucket || !paths?.length) return json({ error: "bucket e paths obrigatórios" }, 400);
        console.log("[admin-storage] deleting from bucket:", bucket, "paths:", paths);
        const { error } = await supabaseAdmin.storage.from(bucket).remove(paths);
        if (error) {
          console.log("[admin-storage] delete error:", error.message);
          return json({ error: error.message }, 400);
        }
        console.log("[admin-storage] delete OK");
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
    console.log("[admin-storage] parsing FormData...");
    let formData: FormData;
    try {
      formData = await req.formData();
    } catch (e) {
      console.error("[admin-storage] formData parse error:", e);
      return json({ error: "Falha ao processar upload. Verifique o formato do envio." }, 400);
    }

    const bucket = formData.get("bucket");
    const path = formData.get("path");
    const file = formData.get("file");
    console.log("[admin-storage] bucket:", bucket, "path:", path, "hasFile:", !!file);

    if (!bucket || !path || !file) {
      return json({
        error: "bucket, path e file obrigatórios",
        debug: { hasBucket: !!bucket, hasPath: !!path, hasFile: !!file, contentType },
      }, 400);
    }

    let fileBuffer: ArrayBuffer;
    let fileContentType = "application/octet-stream";

    if (file instanceof File || file instanceof Blob) {
      fileBuffer = await file.arrayBuffer();
      fileContentType = (file as File).type || "application/octet-stream";
    } else {
      fileBuffer = new TextEncoder().encode(String(file)).buffer;
    }

    console.log("[admin-storage] uploading to storage, size:", fileBuffer.byteLength, "type:", fileContentType);
    const { data, error } = await supabaseAdmin.storage
      .from(String(bucket))
      .upload(String(path), fileBuffer, {
        contentType: fileContentType,
        upsert: false,
      });

    if (error) {
      console.log("[admin-storage] upload error:", error.message);
      return json({ error: error.message }, 400);
    }
    console.log("[admin-storage] upload OK:", data);
    return json({ data });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erro interno";
    console.error("[admin-storage] CATCH error:", err);
    return json({ error: message }, 500);
  }
};

if (import.meta.main && typeof Deno !== "undefined" && "serve" in Deno) {
  Deno.serve(handler);
}

export default handler;
