/**
 * Em ambiente self-hosted, o gateway protege /storage/v1 com key-auth.
 * Por isso, URLs usadas em <img> e <video> precisam carregar o apikey
 * como query string pública para que a mídia renderize sem headers customizados.
 */

const stripTrailingSlash = (value: string) => value.trim().replace(/\/+$/, "");

const encodeStoragePath = (filePath: string) => (
  String(filePath)
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/")
);

const getPublicStorageApiKey = () => (
  String(
    import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
      ?? import.meta.env.VITE_SUPABASE_ANON_KEY
      ?? "",
  ).trim()
);

const appendApiKey = (url: string) => {
  const apiKey = getPublicStorageApiKey();
  if (!apiKey) return url;

  try {
    const resolvedUrl = typeof window !== "undefined"
      ? new URL(url, window.location.origin)
      : new URL(url);

    resolvedUrl.searchParams.set("apikey", apiKey);
    return resolvedUrl.toString();
  } catch {
    const joiner = url.includes("?") ? "&" : "?";
    return `${url}${joiner}apikey=${encodeURIComponent(apiKey)}`;
  }
};

const isDirectBrowserSafeEnvUrl = (envUrl: string) => {
  if (!envUrl) return false;

  try {
    const parsed = new URL(envUrl);
    return !["kong", "auth", "rest", "storage", "functions"].includes(parsed.hostname);
  } catch {
    return false;
  }
};

export function getStoragePublicUrl(bucket: string, filePath: string): string {
  const base = getStorageBaseUrl();
  const encodedPath = encodeStoragePath(filePath);
  return appendApiKey(`${base}/storage/v1/object/public/${bucket}/${encodedPath}`);
}

function getStorageBaseUrl(): string {
  const envUrl = stripTrailingSlash(String(import.meta.env.VITE_SUPABASE_URL ?? ""));

  if (typeof window !== "undefined") {
    const sameOriginBase = `${window.location.origin}/api`;
    const hostname = window.location.hostname;
    const isLovableHost = hostname.includes("lovable.app") || hostname.includes("lovableproject.com");
    const isLocalBrowser = hostname === "localhost" || hostname === "127.0.0.1";

    if (isLovableHost) {
      return envUrl || sameOriginBase;
    }

    if (isLocalBrowser && isDirectBrowserSafeEnvUrl(envUrl)) {
      return envUrl;
    }

    return sameOriginBase;
  }

  return envUrl;
}

export function getMediaUrl(filePath: string): string {
  return getStoragePublicUrl("property-media", filePath);
}
