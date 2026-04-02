import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-admin-action, x-storage-bucket, x-storage-path, x-storage-upsert, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
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

const ALLOWED_BUCKETS = [
  "property-media",
  "contract-documents",
  "tenant-documents",
  "inspection-media",
  "sales-documents",
] as const;

const getEnv = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Variável de ambiente obrigatória ausente: ${name}`);
  return value;
};

const isAllowedBucket = (bucket: string) => (
  ALLOWED_BUCKETS.includes(bucket as (typeof ALLOWED_BUCKETS)[number])
);

const isLikelyJsonRequest = (contentType: string) => {
  const normalized = contentType.toLowerCase();
  return normalized.includes("application/json") || normalized.includes("text/json");
};

const getBinaryUploadConfig = (req: Request) => {
  const url = new URL(req.url);
  const contentType = req.headers.get("content-type") || "application/octet-stream";
  const queryAction = (
    url.searchParams.get("storage_action") ||
    url.searchParams.get("storageAction") ||
    url.searchParams.get("action") ||
    ""
  ).trim();
  const queryBucket = (url.searchParams.get("bucket") || "").trim();
  const queryPath = (url.searchParams.get("path") || "").trim();
  const queryUpsert = (url.searchParams.get("upsert") || "false").trim().toLowerCase() === "true";

  if (
    queryBucket &&
    queryPath &&
    (
      queryAction === "upload" ||
      queryAction === "storage-upload" ||
      !isLikelyJsonRequest(contentType)
    )
  ) {
    return {
      bucket: queryBucket,
      path: queryPath,
      upsert: queryUpsert,
      contentType,
    };
  }

  const action = req.headers.get("x-admin-action") || req.headers.get("x-storage-action");
  if (action !== "storage-upload") return null;

  return {
    bucket: (req.headers.get("x-storage-bucket") || "").trim(),
    path: (req.headers.get("x-storage-path") || "").trim(),
    upsert: (req.headers.get("x-storage-upsert") || "false").toLowerCase() === "true",
    contentType,
  };
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
      getEnv("SUPABASE_SERVICE_ROLE_KEY"),
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      }
    );

    const binaryUpload = getBinaryUploadConfig(req);
    if (binaryUpload) {
      const user = await verifyAdmin(supabaseAdmin, req);
      if (!user) return json({ error: "Não autorizado ou sem permissão de admin" }, 401);
      if (!binaryUpload.bucket || !binaryUpload.path) {
        return json({ error: "bucket e path obrigatórios" }, 400);
      }
      if (!isAllowedBucket(binaryUpload.bucket)) {
        return json({ error: `Bucket '${binaryUpload.bucket}' não permitido` }, 400);
      }

      const fileBuffer = await req.arrayBuffer();
      if (!fileBuffer.byteLength) {
        return json({ error: "Arquivo vazio" }, 400);
      }

      const { data, error } = await supabaseAdmin.storage
        .from(binaryUpload.bucket)
        .upload(binaryUpload.path, fileBuffer, {
          contentType: binaryUpload.contentType,
          upsert: binaryUpload.upsert,
        });

      if (error) return json({ error: error.message }, 400);
      return json({ data });
    }

    const contentType = req.headers.get("content-type") || "";

    // === MULTIPART UPLOAD (FormData) ===
    if (contentType.includes("multipart/form-data")) {
      const user = await verifyAdmin(supabaseAdmin, req);
      if (!user) return json({ error: "Não autorizado ou sem permissão de admin" }, 401);

      let formData: FormData;
      try {
        formData = await req.formData();
      } catch (e) {
        console.error("admin-crud: formData parse error:", e);
        return json({ error: "Falha ao processar upload." }, 400);
      }

      const bucket = formData.get("bucket");
      const path = formData.get("path");
      const file = formData.get("file");

      if (!bucket || !path || !file) {
        return json({ error: "bucket, path e file obrigatórios" }, 400);
      }

      if (!isAllowedBucket(String(bucket))) {
        return json({ error: `Bucket '${bucket}' não permitido` }, 400);
      }

      let fileBuffer: ArrayBuffer;
      let fileContentType = "application/octet-stream";

      if (file instanceof File || file instanceof Blob) {
        fileBuffer = await file.arrayBuffer();
        fileContentType = (file as File).type || "application/octet-stream";
      } else {
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
    }

    // === JSON ACTIONS ===
    const user = await verifyAdmin(supabaseAdmin, req);
    if (!user) return json({ error: "Não autorizado ou sem permissão de admin" }, 401);

    const body = await req.json().catch(() => ({}));
    const { action, table, data, match, select: selectCols, order } = body as {
      action: string;
      table?: string;
      data?: Record<string, unknown> | Record<string, unknown>[];
      match?: Record<string, unknown>;
      select?: string;
      order?: { column: string; ascending?: boolean };
    };

    if (!action) return json({ error: "action obrigatório" }, 400);

    // --- Storage actions ---
    if (action === "storage-delete") {
      const { bucket, paths } = body;
      if (!bucket || !paths?.length) return json({ error: "bucket e paths obrigatórios" }, 400);
      if (!isAllowedBucket(String(bucket))) {
        return json({ error: `Bucket '${bucket}' não permitido` }, 400);
      }
      const { error } = await supabaseAdmin.storage.from(bucket).remove(paths);
      if (error) return json({ error: error.message }, 400);
      return json({ success: true });
    }

    if (action === "storage-signed-url") {
      const { bucket, path: filePath, expiresIn } = body;
      if (!bucket || !filePath) return json({ error: "bucket e path obrigatórios" }, 400);
      if (!isAllowedBucket(String(bucket))) {
        return json({ error: `Bucket '${bucket}' não permitido` }, 400);
      }
      const { data: urlData, error } = await supabaseAdmin.storage
        .from(bucket)
        .createSignedUrl(filePath, expiresIn || 3600);
      if (error) return json({ error: error.message }, 400);
      return json({ signedUrl: urlData.signedUrl });
    }

    // --- CRUD actions ---
    if (!table) return json({ error: "table obrigatório" }, 400);
    if (!ALLOWED_TABLES.includes(table as (typeof ALLOWED_TABLES)[number])) {
      return json({ error: `Tabela '${table}' não permitida` }, 400);
    }

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
