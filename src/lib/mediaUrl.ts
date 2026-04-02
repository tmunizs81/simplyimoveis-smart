/**
 * Generates the public URL for a file in a storage bucket.
 * On self-hosted (non-Lovable) environments, uses the same-origin /api path.
 * On Lovable Cloud, uses VITE_SUPABASE_URL.
 */
export function getStoragePublicUrl(bucket: string, filePath: string): string {
  const base = getStorageBaseUrl();
  return `${base}/storage/v1/object/public/${bucket}/${filePath}`;
}

function getStorageBaseUrl(): string {
  const envUrl = String(import.meta.env.VITE_SUPABASE_URL ?? "").trim().replace(/\/+$/, "");

  if (typeof window !== "undefined") {
    const hostname = window.location.hostname;
    const isLovableHost = hostname.includes("lovable.app") || hostname.includes("lovableproject.com");
    return isLovableHost ? envUrl || `${window.location.origin}/api` : `${window.location.origin}/api`;
  }

  return envUrl;
}

export function getMediaUrl(filePath: string): string {
  return getStoragePublicUrl("property-media", filePath);
}
