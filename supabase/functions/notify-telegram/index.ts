import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const GATEWAY_URL = "https://connector-gateway.lovable.dev/telegram";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const LOVABLE_API_KEY = Deno.env.get("LOVABLE_API_KEY");
    const TELEGRAM_API_KEY = Deno.env.get("TELEGRAM_API_KEY");
    const TELEGRAM_BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN");

    if (!TELEGRAM_API_KEY && !TELEGRAM_BOT_TOKEN) {
      throw new Error("Configure TELEGRAM_API_KEY (connector) ou TELEGRAM_BOT_TOKEN (.env)");
    }

    const { visit } = await req.json();

    const text = `🏠 <b>Nova Visita Agendada!</b>

👤 <b>Cliente:</b> ${visit.client_name}
📱 <b>Telefone:</b> ${visit.client_phone}
${visit.client_email ? `📧 <b>Email:</b> ${visit.client_email}\n` : ""}
🏡 <b>Imóvel:</b> ${visit.property_title || "Não especificado"}
📍 <b>Endereço:</b> ${visit.property_address || "Não especificado"}

📅 <b>Data:</b> ${visit.preferred_date}
🕐 <b>Horário:</b> ${visit.preferred_time}
${visit.notes ? `📝 <b>Obs:</b> ${visit.notes}` : ""}`;

    // Send to Talita's chat - she needs to message the bot first with /start
    // Then get her chat_id. For now use the TELEGRAM_CHAT_ID secret.
    const chatId = Deno.env.get("TELEGRAM_CHAT_ID");
    if (!chatId) {
      console.warn("TELEGRAM_CHAT_ID not set, skipping notification");
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = {
      chat_id: chatId,
      text,
      parse_mode: "HTML",
    };

    const response = TELEGRAM_API_KEY && LOVABLE_API_KEY
      ? await fetch(`${GATEWAY_URL}/sendMessage`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${LOVABLE_API_KEY}`,
            "X-Connection-Api-Key": TELEGRAM_API_KEY,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(payload),
        })
      : await fetch(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });

    const data = await response.json();
    if (!response.ok || data?.ok === false) {
      throw new Error(`Telegram API failed [${response.status}]: ${JSON.stringify(data)}`);
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("notify-telegram error:", e);
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
