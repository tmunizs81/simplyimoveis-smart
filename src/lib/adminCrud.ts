/**
 * Admin CRUD helper — routes ALL operations (CRUD + Storage) through the
 * admin-crud edge function which uses service_role to bypass RLS.
 * This ensures the admin panel works identically on both Lovable Cloud
 * and self-hosted VPS environments.
 */
import { supabase } from "@/integrations/supabase/client";

type CrudResult<T = any> = {
  data: T | null;
  error: { message: string } | null;
};

async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

async function callAdminCrud(body: Record<string, unknown>): Promise<CrudResult> {
  const session = await getSession();
  if (!session) return { data: null, error: { message: "Não autenticado" } };

  const { data, error } = await supabase.functions.invoke("admin-crud", {
    body,
    headers: { Authorization: `Bearer ${session.access_token}` },
  });

  if (error) {
    const msg = typeof error === "object" && "message" in error
      ? (error as any).message : String(error);
    return { data: null, error: { message: msg } };
  }
  if (data?.error) return { data: null, error: { message: data.error } };
  return { data: data?.data ?? data, error: null };
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
 * Upload a file to storage via admin-crud edge function (multipart/form-data).
 * Uses raw fetch() because supabase.functions.invoke() breaks FormData encoding.
 */
export async function adminStorageUpload(
  bucket: string,
  path: string,
  file: File
): Promise<CrudResult> {
  const session = await getSession();
  if (!session) return { data: null, error: { message: "Não autenticado" } };

  const formData = new FormData();
  formData.append("bucket", bucket);
  formData.append("path", path);
  formData.append("file", file);

  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
  const apiKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

  try {
    const response = await fetch(`${supabaseUrl}/functions/v1/admin-crud`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        apikey: apiKey,
      },
      body: formData,
    });

    const result = await response.json();
    if (!response.ok) return { data: null, error: { message: result?.error || `HTTP ${response.status}` } };
    if (result?.error) return { data: null, error: { message: result.error } };
    return { data: result?.data ?? result, error: null };
  } catch (err: any) {
    return { data: null, error: { message: err.message || "Erro de rede no upload" } };
  }
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
