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

cat > "$FUNC_DIR/main/index.ts" <<'MAINEOF'
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import chatHandler from "../chat/index.ts";
import createAdminUserHandler from "../create-admin-user/index.ts";
import notifyTelegramHandler from "../notify-telegram/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

const handlers: Record<string, (req: Request) => Promise<Response> | Response> = {
  "chat": chatHandler,
  "create-admin-user": createAdminUserHandler,
  "notify-telegram": notifyTelegramHandler,
};

serve(async (req) => {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const functionName = parts[0] || "";

  if (!functionName) {
    return new Response(JSON.stringify({ status: "ok", version: "3.0" }), {
      headers: jsonHeaders,
    });
  }

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const handler = handlers[functionName];
  if (!handler) {
    return new Response(
      JSON.stringify({ error: `Function '${functionName}' not found` }),
      { status: 404, headers: jsonHeaders }
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
