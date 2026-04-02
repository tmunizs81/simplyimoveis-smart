/**
 * Admin CRUD helper — routes ALL operations (CRUD + Storage) through the
 * admin-crud edge function which uses service_role to bypass RLS.
 * This ensures the admin panel works identically on both Lovable Cloud
 * and self-hosted VPS environments.
 */
import { supabase } from "@/integrations/supabase/client";

export type CrudError = {
  message: string;
  code?: string;
  stage?: string;
  debugId?: string;
  details?: string;
  status?: number;
};

export type CrudResult<T = any> = {
  data: T | null;
  error: CrudError | null;
};

async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

function getAdminCrudBaseUrl() {
  const envUrl = String(import.meta.env.VITE_SUPABASE_URL ?? "").trim().replace(/\/+$/, "");

  if (typeof window !== "undefined") {
    const sameOriginBase = `${window.location.origin}/api`;
    const hostname = window.location.hostname;
    const isLovableHost = hostname.includes("lovable.app") || hostname.includes("lovableproject.com");

    return isLovableHost ? envUrl || sameOriginBase : sameOriginBase;
  }

  if (envUrl) return envUrl;

  throw new Error("URL do backend não configurada");
}

function getAdminCrudUrl() {
  return `${getAdminCrudBaseUrl()}/functions/v1/admin-crud`;
}

function getAdminCrudApiKey() {
  return String(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? "").trim();
}

function buildAdminCrudUploadUrl(bucket: string, path: string, upsert = false) {
  const url = new URL(getAdminCrudUrl());
  url.searchParams.set("storage_action", "upload");
  url.searchParams.set("bucket", bucket);
  url.searchParams.set("path", path);
  url.searchParams.set("upsert", String(upsert));
  return url.toString();
}

async function parseAdminCrudResponse(response: Response): Promise<CrudResult> {
  const responseText = await response.text();

  let result: any = null;
  try {
    result = responseText ? JSON.parse(responseText) : null;
  } catch {
    result = { error: responseText || `HTTP ${response.status}` };
  }

  const debugId = response.headers.get("x-admin-crud-request-id") || result?.debugId || result?.requestId;
  const details = typeof result?.details === "string" && result.details.trim()
    ? result.details.trim()
    : undefined;

  if (!response.ok) {
    return {
      data: null,
      error: {
        message: result?.error || result?.message || `HTTP ${response.status}`,
        code: result?.code,
        stage: result?.stage,
        debugId,
        details,
        status: response.status,
      },
    };
  }

  if (result?.error) {
    return {
      data: null,
      error: {
        message: result.error,
        code: result?.code,
        stage: result?.stage,
        debugId,
        details,
        status: response.status,
      },
    };
  }

  return { data: result?.data ?? result, error: null };
}

async function performAdminCrudRequest(
  url: string,
  options: {
    body: BodyInit;
    headers?: HeadersInit;
  }
): Promise<CrudResult> {
  const session = await getSession();
  if (!session) return { data: null, error: { message: "Não autenticado" } };

  const apiKey = getAdminCrudApiKey();
  if (!apiKey) {
    return {
      data: null,
      error: {
        message: "Chave pública do backend não configurada",
        stage: "client.config",
      },
    };
  }

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        apikey: apiKey,
        ...options.headers,
      },
      body: options.body,
    });

    return await parseAdminCrudResponse(response);
  } catch (err: any) {
    return {
      data: null,
      error: {
        message: err?.message || "Erro de rede ao chamar admin-crud",
        stage: "client.network",
      },
    };
  }
}

async function callAdminCrud(body: Record<string, unknown>): Promise<CrudResult> {
  return performAdminCrudRequest(getAdminCrudUrl(), {
    body: JSON.stringify(body),
    headers: { "Content-Type": "application/json" },
  });
}

export async function adminSelect(
  table: string,
  options?: {
    select?: string;
    match?: Record<string, unknown>;
    order?: { column: string; ascending?: boolean };
  }
): Promise<CrudResult> {
  return callAdminCrud({
    action: "select",
    table,
    select: options?.select,
    match: options?.match,
    order: options?.order,
  });
}

export async function adminInsert(
  table: string,
  insertData: Record<string, unknown> | Record<string, unknown>[],
  options?: { select?: string }
): Promise<CrudResult> {
  return callAdminCrud({
    action: "insert",
    table,
    data: insertData,
    select: options?.select,
  });
}

export async function adminUpdate(
  table: string,
  updateData: Record<string, unknown>,
  match: Record<string, unknown>
): Promise<CrudResult> {
  return callAdminCrud({
    action: "update",
    table,
    data: updateData,
    match,
  });
}

export async function adminDelete(
  table: string,
  match: Record<string, unknown>
): Promise<CrudResult> {
  return callAdminCrud({
    action: "delete",
    table,
    match,
  });
}

/**
 * Upload a file to storage via admin-crud edge function using a raw binary body.
 * This avoids multipart parsing issues in self-hosted edge-runtime deployments.
 */
export async function adminStorageUpload(
  bucket: string,
  path: string,
  file: File
): Promise<CrudResult> {
  return performAdminCrudRequest(buildAdminCrudUploadUrl(bucket, path), {
    body: file,
    headers: {
      "Content-Type": file.type || "application/octet-stream",
    },
  });
}

/**
 * Delete files from storage via admin-crud edge function.
 */
export async function adminStorageDelete(
  bucket: string,
  paths: string[]
): Promise<CrudResult> {
  return callAdminCrud({ action: "storage-delete", bucket, paths });
}

/**
 * Get a signed URL for a private storage file.
 */
export async function adminStorageSignedUrl(
  bucket: string,
  filePath: string,
  expiresIn = 3600
): Promise<string | null> {
  const result = await callAdminCrud({
    action: "storage-signed-url",
    bucket,
    path: filePath,
    expiresIn,
  });
  if (result.error || !result.data) return null;
  return result.data?.signedUrl || result.data;
}
