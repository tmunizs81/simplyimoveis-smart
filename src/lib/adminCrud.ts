/**
 * Admin CRUD helper — routes ALL operations through the admin-crud edge function
 * which uses service_role to bypass RLS. This ensures the admin panel works
 * identically on both Lovable Cloud and self-hosted VPS environments.
 */
import { supabase } from "@/integrations/supabase/client";

type CrudResult<T = any> = {
  data: T | null;
  error: { message: string } | null;
};

async function callAdminCrud(body: Record<string, unknown>): Promise<CrudResult> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) {
    return { data: null, error: { message: "Não autenticado" } };
  }

  const { data, error } = await supabase.functions.invoke("admin-crud", {
    body,
    headers: {
      Authorization: `Bearer ${session.access_token}`,
    },
  });

  if (error) {
    // Try to extract error message from response
    const msg = typeof error === "object" && "message" in error
      ? (error as any).message
      : String(error);
    return { data: null, error: { message: msg } };
  }

  // The edge function returns { data: [...] } or { error: "..." }
  if (data?.error) {
    return { data: null, error: { message: data.error } };
  }

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
 * Upload a file to storage via admin-storage edge function (uses service_role,
 * bypasses storage RLS — works on both Lovable Cloud and self-hosted VPS).
 * Uses raw fetch() instead of supabase.functions.invoke() because the SDK
 * breaks multipart/form-data encoding on self-hosted edge runtimes.
 */
export async function adminStorageUpload(
  bucket: string,
  path: string,
  file: File
): Promise<CrudResult> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { data: null, error: { message: "Não autenticado" } };

  const formData = new FormData();
  formData.append("bucket", bucket);
  formData.append("path", path);
  formData.append("file", file);

  // Build the functions URL from env — works for both Lovable Cloud and self-hosted
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
  const apiKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

  try {
    const response = await fetch(`${supabaseUrl}/functions/v1/admin-storage`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.access_token}`,
        apikey: apiKey,
      },
      body: formData,
      // Do NOT set Content-Type — browser sets it automatically with boundary
    });

    const result = await response.json();

    if (!response.ok) {
      return { data: null, error: { message: result?.error || `HTTP ${response.status}` } };
    }
    if (result?.error) {
      return { data: null, error: { message: result.error } };
    }
    return { data: result?.data ?? result, error: null };
  } catch (err: any) {
    return { data: null, error: { message: err.message || "Erro de rede no upload" } };
  }
}

/**
 * Delete files from storage via admin-storage edge function.
 */
export async function adminStorageDelete(
  bucket: string,
  paths: string[]
): Promise<CrudResult> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { data: null, error: { message: "Não autenticado" } };

  const { data, error } = await supabase.functions.invoke("admin-storage", {
    body: { action: "delete", bucket, paths },
    headers: {
      Authorization: `Bearer ${session.access_token}`,
    },
  });

  if (error) {
    const msg = typeof error === "object" && "message" in error
      ? (error as any).message : String(error);
    return { data: null, error: { message: msg } };
  }
  if (data?.error) return { data: null, error: { message: data.error } };
  return { data: data?.data ?? data, error: null };
}

/**
 * Get a signed URL for a private storage file via admin-storage edge function.
 */
export async function adminStorageSignedUrl(
  bucket: string,
  filePath: string,
  expiresIn = 3600
): Promise<string | null> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return null;

  const { data, error } = await supabase.functions.invoke("admin-storage", {
    body: { action: "signed-url", bucket, path: filePath, expiresIn },
    headers: {
      Authorization: `Bearer ${session.access_token}`,
    },
  });

  if (error || data?.error) return null;
  return data?.signedUrl || null;
}
