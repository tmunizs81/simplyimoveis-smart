import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-admin-action, x-storage-bucket, x-storage-path, x-storage-upsert, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const ADMIN_CRUD_VERSION = "2026-04-02-selfhosted-r5";

const buildJsonHeaders = (requestId?: string) => ({
  ...corsHeaders,
  "Content-Type": "application/json",
  "x-admin-crud-version": ADMIN_CRUD_VERSION,
  ...(requestId ? { "x-admin-crud-request-id": requestId } : {}),
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: buildJsonHeaders(),
  });

const jsonWithRequestId = (body: unknown, requestId: string, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: buildJsonHeaders(requestId),
  });

const errorJson = (
  requestId: string,
  error: string,
  status = 400,
  extra: Record<string, unknown> = {},
) => jsonWithRequestId({ error, debugId: requestId, ...extra }, requestId, status);

const createRequestId = () => globalThis.crypto?.randomUUID?.() ?? `req-${Date.now()}`;

const getStorageObjectUrl = (supabaseUrl: string, bucket: string, encodedPath: string) => {
  const normalizedBase = supabaseUrl.replace(/\/+$/, "");

  try {
    const parsed = new URL(normalizedBase);
    if (parsed.hostname === "kong") {
      return `http://storage:5000/object/${bucket}/${encodedPath}`;
    }
  } catch {
    // fallback abaixo
  }

  return `${normalizedBase}/storage/v1/object/${bucket}/${encodedPath}`;
};

const getRequestAuthHeader = (req: Request) => (
  req.headers.get("authorization") || req.headers.get("Authorization") || ""
);

const getRequestBearerToken = (req: Request) => (
  getRequestAuthHeader(req).replace(/^Bearer\s+/i, "").trim()
);

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

const formatStorageUploadDetails = (
  storageBody: string,
  bucket: string,
  path: string,
  storageUrl: string,
  attemptLabel: string,
) => {
  const compactBody = storageBody.replace(/\s+/g, " ").trim().slice(0, 500);

  if (/row-level security/i.test(compactBody)) {
    return [
      `admin-crud=${ADMIN_CRUD_VERSION}`,
      `attempt=${attemptLabel}`,
      "self-hosted storage bloqueou o INSERT em storage.objects",
      attemptLabel === "admin-user-jwt"
        ? "o storage recebeu o JWT autenticado do admin; verifique auth.uid(), user_roles e policies TO authenticated em storage.objects"
        : "o storage recebeu SERVICE_ROLE_KEY puro; em self-hosted isso pode falhar mesmo com BYPASSRLS se o runtime não assumir a role esperada",
      "confirme que supabase_storage_admin tem BYPASSRLS e é MEMBRO de service_role",
      "confirme grants em storage.objects/storage.buckets para authenticated/service_role",
      "confirme que SERVICE_ROLE_KEY é um JWT válido com role=service_role assinado pelo JWT_SECRET atual",
      "reaplique: bash sync-db-passwords.sh && bash bootstrap-db.sh && docker compose up -d --force-recreate rest storage functions",
      `bucket=${bucket}`,
      `path=${path}`,
      `storage_url=${storageUrl}`,
      compactBody ? `upstream=${compactBody}` : null,
    ].filter(Boolean).join(" | ");
  }

  return compactBody || `admin-crud=${ADMIN_CRUD_VERSION} | attempt=${attemptLabel} | bucket=${bucket} | path=${path} | storage_url=${storageUrl}`;
};

async function verifyAdmin(supabaseAdmin: any, req: Request) {
  const token = getRequestBearerToken(req);
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
  const requestId = createRequestId();

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
      if (!user) {
        return errorJson(requestId, "Não autorizado ou sem permissão de admin", 401, {
          stage: "storage.auth.verify_admin",
        });
      }
      if (!binaryUpload.bucket || !binaryUpload.path) {
        return errorJson(requestId, "bucket e path obrigatórios", 400, {
          stage: "storage.validate_input",
        });
      }
      if (!isAllowedBucket(binaryUpload.bucket)) {
        return errorJson(requestId, `Bucket '${binaryUpload.bucket}' não permitido`, 400, {
          stage: "storage.validate_bucket",
          details: `bucket=${binaryUpload.bucket}`,
        });
      }

      const fileBuffer = await req.arrayBuffer();
      if (!fileBuffer.byteLength) {
        return errorJson(requestId, "Arquivo vazio", 400, {
          stage: "storage.read_body",
        });
      }

      // Em self-hosted, o upload mais confiável é reenviar o JWT autenticado do admin.
      // Quando isso falha, tentamos SERVICE_ROLE_KEY puro apenas como fallback/diagnóstico.
      const supabaseUrl = getEnv("SUPABASE_URL").replace(/\/+$/, "");
      const serviceKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
      const anonKey = (Deno.env.get("SUPABASE_ANON_KEY") || "").trim() || serviceKey;
      const userAuthHeader = getRequestAuthHeader(req);
      const encodedPath = binaryUpload.path.split("/").map(encodeURIComponent).join("/");
      const storageUrl = getStorageObjectUrl(supabaseUrl, binaryUpload.bucket, encodedPath);

      const attempts = [
        {
          label: "admin-user-jwt",
          authorization: userAuthHeader,
          apiKey: anonKey,
        },
        {
          label: "service-role-jwt",
          authorization: `Bearer ${serviceKey}`,
          apiKey: serviceKey,
        },
      ].filter((attempt) => attempt.authorization.trim().length > 0);

      const failedAttempts: Array<{
        label: string;
        status: number;
        body: string;
        message: string;
        details: string;
      }> = [];

      for (const attempt of attempts) {
        const storageResponse = await fetch(storageUrl, {
          method: "POST",
          headers: {
            Authorization: attempt.authorization,
            apikey: attempt.apiKey,
            "Content-Type": binaryUpload.contentType,
            ...(binaryUpload.upsert ? { "x-upsert": "true" } : {}),
          },
          body: fileBuffer,
        });

        const storageBody = await storageResponse.text();
        let storageResult: any;
        try { storageResult = JSON.parse(storageBody); } catch { storageResult = { error: storageBody }; }

        if (storageResponse.ok) {
          return jsonWithRequestId(
            {
              data: storageResult,
              debugId: requestId,
              version: ADMIN_CRUD_VERSION,
              uploadMode: attempt.label,
            },
            requestId,
          );
        }

        failedAttempts.push({
          label: attempt.label,
          status: storageResponse.status,
          body: storageBody,
          message: storageResult?.message || storageResult?.error || `Storage HTTP ${storageResponse.status}`,
          details: formatStorageUploadDetails(
            typeof storageBody === "string" ? storageBody : "",
            binaryUpload.bucket,
            binaryUpload.path,
            storageUrl,
            attempt.label,
          ),
        });
      }

      const primaryFailure = failedAttempts[0];
      console.error(`[admin-crud][${requestId}] storage upload failed in all modes:`, {
        bucket: binaryUpload.bucket,
        path: binaryUpload.path,
        version: ADMIN_CRUD_VERSION,
        storageUrl,
        attempts: failedAttempts.map((attempt) => ({
          label: attempt.label,
          status: attempt.status,
          body: attempt.body,
        })),
      });

      return errorJson(
        requestId,
        primaryFailure?.message || "Falha no upload para o storage",
        400,
        {
          stage: "storage.upstream_upload",
          details: failedAttempts.map((attempt) => attempt.details).join(" || "),
          upstreamStatus: primaryFailure?.status,
          version: ADMIN_CRUD_VERSION,
          storageUrl,
          attempts: failedAttempts.map((attempt) => ({
            mode: attempt.label,
            status: attempt.status,
            body: attempt.body.replace(/\s+/g, " ").trim().slice(0, 220),
          })),
        },
      );
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

      if (typeof file !== "string") {
        fileBuffer = await file.arrayBuffer();
        fileContentType = file.type || "application/octet-stream";
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
    if (!user) return json({ error: "Não autorizado ou sem permissão de admin", version: ADMIN_CRUD_VERSION }, 401);

    const body = await req.json().catch(() => ({}));
    const { action, table, data, match, select: selectCols, order } = body as {
      action: string;
      table?: string;
      data?: Record<string, unknown> | Record<string, unknown>[];
      match?: Record<string, unknown>;
      select?: string;
      order?: { column: string; ascending?: boolean };
    };

    if (!action) return json({ error: "action obrigatório", version: ADMIN_CRUD_VERSION }, 400);

    // --- Storage actions ---
    if (action === "storage-delete") {
      const { bucket, paths } = body;
       if (!bucket || !paths?.length) return json({ error: "bucket e paths obrigatórios", version: ADMIN_CRUD_VERSION }, 400);
      if (!isAllowedBucket(String(bucket))) {
         return json({ error: `Bucket '${bucket}' não permitido`, version: ADMIN_CRUD_VERSION }, 400);
      }
      const { error } = await supabaseAdmin.storage.from(bucket).remove(paths);
       if (error) return json({ error: error.message, version: ADMIN_CRUD_VERSION }, 400);
      return json({ success: true });
    }

    if (action === "storage-signed-url") {
      const { bucket, path: filePath, expiresIn } = body;
       if (!bucket || !filePath) return json({ error: "bucket e path obrigatórios", version: ADMIN_CRUD_VERSION }, 400);
      if (!isAllowedBucket(String(bucket))) {
         return json({ error: `Bucket '${bucket}' não permitido`, version: ADMIN_CRUD_VERSION }, 400);
      }
      const { data: urlData, error } = await supabaseAdmin.storage
        .from(bucket)
        .createSignedUrl(filePath, expiresIn || 3600);
       if (error) return json({ error: error.message, version: ADMIN_CRUD_VERSION }, 400);
       return json({ signedUrl: urlData.signedUrl, version: ADMIN_CRUD_VERSION });
    }

    // --- CRUD actions ---
    if (!table) return json({ error: "table obrigatório", version: ADMIN_CRUD_VERSION }, 400);
    if (!ALLOWED_TABLES.includes(table as (typeof ALLOWED_TABLES)[number])) {
      return json({ error: `Tabela '${table}' não permitida`, version: ADMIN_CRUD_VERSION }, 400);
    }

    if (action === "insert") {
      if (!data) return json({ error: "data obrigatório para insert", version: ADMIN_CRUD_VERSION }, 400);
      const q = supabaseAdmin.from(table).insert(data as never);
      const result = selectCols !== undefined
        ? await q.select(selectCols || "*")
        : await q.select("*");
      if (result.error) return json({ error: result.error.message, version: ADMIN_CRUD_VERSION }, 400);
      return json({ data: result.data, version: ADMIN_CRUD_VERSION });
    }

    if (action === "update") {
      if (!data || !match) return json({ error: "data e match obrigatórios para update", version: ADMIN_CRUD_VERSION }, 400);
      let q = supabaseAdmin.from(table).update(data as never);
      for (const [k, v] of Object.entries(match)) {
        q = q.eq(k, v as never);
      }
      const result = await q.select("*");
      if (result.error) return json({ error: result.error.message, version: ADMIN_CRUD_VERSION }, 400);
      return json({ data: result.data, version: ADMIN_CRUD_VERSION });
    }

    if (action === "delete") {
      if (!match) return json({ error: "match obrigatório para delete", version: ADMIN_CRUD_VERSION }, 400);
      let q = supabaseAdmin.from(table).delete();
      for (const [k, v] of Object.entries(match)) {
        q = q.eq(k, v as never);
      }
      const result = await q;
      if (result.error) return json({ error: result.error.message, version: ADMIN_CRUD_VERSION }, 400);
      return json({ success: true, version: ADMIN_CRUD_VERSION });
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
      if (result.error) return json({ error: result.error.message, version: ADMIN_CRUD_VERSION }, 400);
      return json({ data: result.data, version: ADMIN_CRUD_VERSION });
    }

    return json({ error: "Ação inválida", version: ADMIN_CRUD_VERSION }, 400);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Erro interno";
    console.error(`[admin-crud][${requestId}] error:`, err);
    return errorJson(requestId, message, 500, { stage: "handler.catch", version: ADMIN_CRUD_VERSION });
  }
};

if (import.meta.main && typeof Deno !== "undefined" && "serve" in Deno) {
  Deno.serve(handler);
}

export default handler;
