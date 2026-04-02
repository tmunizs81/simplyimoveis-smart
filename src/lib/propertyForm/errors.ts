import type { CrudError } from "@/lib/adminCrud";

export const formatCrudError = (prefix: string, error: CrudError | null | undefined) => {
  if (!error) return prefix;

  const details = error.details?.replace(/\s+/g, " ").trim();
  const meta = [
    error.stage ? `etapa: ${error.stage}` : null,
    error.debugId ? `ref: ${error.debugId}` : null,
    details ? `detalhe: ${details.slice(0, 220)}` : null,
  ].filter(Boolean).join(" | ");

  return meta ? `${prefix}: ${error.message} (${meta})` : `${prefix}: ${error.message}`;
};