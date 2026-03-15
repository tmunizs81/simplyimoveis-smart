#!/bin/bash
# ============================================================
# Gera o roteador principal das Edge Functions para self-hosted
# Uso: bash render-functions-main.sh [diretorio_funcoes]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FUNC_DIR="${1:-volumes/functions}"
mkdir -p "$FUNC_DIR/main"

cat > "$FUNC_DIR/main/index.ts" <<'MAINEOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const jsonHeaders = { "Content-Type": "application/json" };

serve(async (req) => {
  const url = new URL(req.url);
  const [functionName] = url.pathname.split("/").filter(Boolean);

  if (!functionName) {
    return new Response(JSON.stringify({ status: "ok", version: "2.1" }), {
      headers: jsonHeaders,
    });
  }

  try {
    const mod = await import(`../${functionName}/index.ts`);

    if (typeof mod.default === "function") {
      return await mod.default(req);
    }

    if (typeof mod.handler === "function") {
      return await mod.handler(req);
    }

    return new Response(
      JSON.stringify({ error: `Function '${functionName}' has no handler export` }),
      { status: 500, headers: jsonHeaders }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[functions-main] Failed to load '${functionName}':`, error);

    const notFound =
      message.includes("Cannot find module") ||
      message.includes("Module not found") ||
      message.includes("No such file or directory");

    return new Response(
      JSON.stringify({
        error: notFound
          ? `Function '${functionName}' not found`
          : `Function '${functionName}' failed to load`,
        details: message,
      }),
      { status: notFound ? 404 : 500, headers: jsonHeaders }
    );
  }
});
MAINEOF

echo "✅ Router de Edge Functions atualizado em $FUNC_DIR/main/index.ts"
