#!/bin/bash
# ============================================================
# Gera o roteador principal das Edge Functions para self-hosted
# Usa importações ESTÁTICAS (dynamic import não funciona no edge-runtime)
# Uso: bash render-functions-main.sh [diretorio_funcoes]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FUNC_DIR="${1:-volumes/functions}"
mkdir -p "$FUNC_DIR/main"

REQUIRED_FUNCTIONS=("chat" "create-admin-user" "notify-telegram" "admin-crud" "ai-insights")

for fn in "${REQUIRED_FUNCTIONS[@]}"; do
  if [ ! -f "$FUNC_DIR/$fn/index.ts" ]; then
    echo "❌ Não foi possível gerar main router: função ausente em $FUNC_DIR/$fn/index.ts"
    echo "💡 Rode: bash sync-functions.sh"
    exit 1
  fi
done

cat > "$FUNC_DIR/main/index.ts" <<'MAINEOF'
import * as chatModule from "../chat/index.ts";
import * as createAdminUserModule from "../create-admin-user/index.ts";
import * as notifyTelegramModule from "../notify-telegram/index.ts";
import * as adminCrudModule from "../admin-crud/index.ts";
import * as aiInsightsModule from "../ai-insights/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

type Handler = (req: Request) => Promise<Response> | Response;

const modules: Record<string, Record<string, unknown>> = {
  "chat": chatModule,
  "create-admin-user": createAdminUserModule,
  "notify-telegram": notifyTelegramModule,
  "admin-crud": adminCrudModule,
  "ai-insights": aiInsightsModule,
};

const getHandler = (functionName: string): Handler | null => {
  const mod = modules[functionName];
  if (!mod) return null;

  const candidate = mod.default ?? mod.handler;
  return typeof candidate === "function" ? (candidate as Handler) : null;
};

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const functionName = parts[0] || "";

  if (!functionName) {
    return new Response(JSON.stringify({ status: "ok", version: "3.2" }), {
      headers: jsonHeaders,
    });
  }

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (!(functionName in modules)) {
    return new Response(
      JSON.stringify({ error: `Function '${functionName}' not found` }),
      { status: 404, headers: jsonHeaders }
    );
  }

  const handler = getHandler(functionName);
  if (!handler) {
    return new Response(
      JSON.stringify({ error: `Function '${functionName}' is missing export default/handler` }),
      { status: 500, headers: jsonHeaders }
    );
  }

  try {
    return await handler(req);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[functions-main] Error in '${functionName}':`, error);
    return new Response(
      JSON.stringify({ error: `Function '${functionName}' failed`, details: message }),
      { status: 500, headers: jsonHeaders }
    );
  }
});
MAINEOF

echo "✅ Router de Edge Functions (static imports) atualizado em $FUNC_DIR/main/index.ts"
