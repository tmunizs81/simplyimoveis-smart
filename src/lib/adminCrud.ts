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
