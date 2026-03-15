import { useState, useRef, useEffect } from "react";
import { MessageCircle, X, Send, Bot, User } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { supabase } from "@/integrations/supabase/client";
import ReactMarkdown from "react-markdown";

type Message = { role: "user" | "assistant"; content: string };

const SCHEDULE_REGEX = /<<<AGENDAR_VISITA>>>\s*(\{[\s\S]*?\})\s*<<<FIM_AGENDAMENTO>>>/;
const CONTACT_REGEX = /<<<REGISTRAR_CONTATO>>>\s*(\{[\s\S]*?\})\s*<<<FIM_CONTATO>>>/;

const ChatWidget = ({ propertyId }: { propertyId?: string }) => {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<Message[]>([
    {
      role: "assistant",
      content:
        "Olá! 👋 Sou a **Luma**, assistente virtual da Simply Imóveis. Estou aqui para ajudar com informações sobre nossos imóveis, agendar visitas e tirar suas dúvidas.\n\nPara começar, poderia me informar seu **nome completo** e **telefone com DDD**? Assim consigo te atender de forma personalizada! 😊",
    },
  ]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const formatChatTranscript = (msgs: Message[]) => {
    return msgs
      .map((m) => `[${m.role === "user" ? "Cliente" : "Luma"}]: ${m.content}`)
      .join("\n\n");
  };

  const resolveFunctionUrl = (functionName: string, forceSameOrigin = false) => {
    const envBase = (import.meta.env.VITE_SUPABASE_URL || "").replace(/\/$/, "");
    const sameOriginBase = `${window.location.origin}/api`;
    const hostname = window.location.hostname;
    const isLovableHost = hostname.includes("lovable.app") || hostname.includes("lovableproject.com");

    const baseUrl = forceSameOrigin ? sameOriginBase : isLovableHost ? envBase || sameOriginBase : sameOriginBase;
    return `${baseUrl}/functions/v1/${functionName}`;
  };

  const saveContactSubmission = async (data: {
    name: string;
    phone: string;
    email?: string;
    subject?: string;
    message: string;
    visit_date?: string;
    source: string;
    chatMessages: Message[];
  }) => {
    try {
      await supabase.from("contact_submissions").insert({
        name: data.name,
        phone: data.phone || null,
        email: data.email || "não informado",
        subject: data.subject || "Chat com Luma",
        message: data.message,
        chat_transcript: formatChatTranscript(data.chatMessages),
        visit_date: data.visit_date || null,
        source: data.source,
      });
    } catch (err) {
      console.error("Error saving contact:", err);
    }
  };

  const processSchedule = async (text: string, allMessages: Message[]) => {
    const match = text.match(SCHEDULE_REGEX);
    if (!match) return;

    try {
      const visitData = JSON.parse(match[1]);

      let propertyTitle = "";
      let propertyAddress = "";
      if (visitData.property_id) {
        const { data: prop } = await supabase
          .from("properties")
          .select("title, address")
          .eq("id", visitData.property_id)
          .single();
        if (prop) {
          propertyTitle = prop.title;
          propertyAddress = prop.address;
        }
      }

      await supabase.from("scheduled_visits").insert({
        property_id: visitData.property_id || null,
        client_name: visitData.client_name,
        client_phone: visitData.client_phone,
        client_email: visitData.client_email || null,
        preferred_date: visitData.preferred_date,
        preferred_time: visitData.preferred_time,
        notes: visitData.notes || null,
      });

      // Save to contact_submissions with chat transcript
      await saveContactSubmission({
        name: visitData.client_name,
        phone: visitData.client_phone,
        email: visitData.client_email,
        subject: `Visita agendada - ${propertyTitle || "Imóvel não especificado"}`,
        message: `Visita agendada para ${visitData.preferred_date} às ${visitData.preferred_time}. Imóvel: ${propertyTitle || "Não especificado"} (${propertyAddress || ""})`,
        visit_date: `${visitData.preferred_date} ${visitData.preferred_time}`,
        source: "chat-agendamento",
        chatMessages: allMessages,
      });

      const notifyUrl = resolveFunctionUrl("notify-telegram");
      await fetch(notifyUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY}`,
        },
        body: JSON.stringify({
          visit: {
            ...visitData,
            property_title: propertyTitle,
            property_address: propertyAddress,
          },
        }),
      });
    } catch (err) {
      console.error("Error processing schedule:", err);
    }
  };

  const processContact = async (text: string, allMessages: Message[]) => {
    const match = text.match(CONTACT_REGEX);
    if (!match) return;

    try {
      const contactData = JSON.parse(match[1]);
      await saveContactSubmission({
        name: contactData.client_name,
        phone: contactData.client_phone,
        email: contactData.client_email,
        subject: contactData.subject || "Contato via Chat",
        message: contactData.notes || "Cliente deixou contato pelo chat",
        source: "chat-contato",
        chatMessages: allMessages,
      });
    } catch (err) {
      console.error("Error processing contact:", err);
    }
  };

  const cleanContent = (text: string) => {
    return text.replace(SCHEDULE_REGEX, "").replace(CONTACT_REGEX, "").trim();
  };

  const sendMessage = async () => {
    if (!input.trim() || loading) return;
    const userMsg: Message = { role: "user", content: input.trim() };
    const allMessages = [...messages, userMsg];
    setMessages(allMessages);
    setInput("");
    setLoading(true);

    try {
      const primaryUrl = resolveFunctionUrl("chat");
      const fallbackUrl = resolveFunctionUrl("chat", true);
      const requestOptions: RequestInit = {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY}`,
        },
        body: JSON.stringify({ messages: allMessages, propertyId }),
      };

      let resp: Response;
      try {
        resp = await fetch(primaryUrl, requestOptions);
      } catch (primaryError) {
        if (fallbackUrl === primaryUrl) throw primaryError;
        resp = await fetch(fallbackUrl, requestOptions);
      }

      if (!resp.ok && [404, 502, 503, 504].includes(resp.status) && fallbackUrl !== primaryUrl) {
        resp = await fetch(fallbackUrl, requestOptions);
      }

      if (!resp.ok) {
        const rawText = await resp.text();
        let errorMessage = `Erro ao conectar (${resp.status})`;

        if (rawText) {
          try {
            const errorData = JSON.parse(rawText);
            if (errorData?.error) {
              errorMessage = String(errorData.error);
            } else {
              errorMessage = `${errorMessage}: ${rawText.slice(0, 180)}`;
            }
          } catch {
            errorMessage = `${errorMessage}: ${rawText.slice(0, 180)}`;
          }
        }

        throw new Error(errorMessage);
      }

      if (!resp.body) throw new Error("Resposta sem stream");

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let textBuffer = "";
      let assistantSoFar = "";

      const upsert = (chunk: string) => {
        assistantSoFar += chunk;
        const displayContent = cleanContent(assistantSoFar);
        setMessages((prev) => {
          const last = prev[prev.length - 1];
          if (last?.role === "assistant" && prev.length > allMessages.length) {
            return prev.map((m, i) =>
              i === prev.length - 1 ? { ...m, content: displayContent } : m
            );
          }
          return [...prev, { role: "assistant", content: displayContent }];
        });
      };

      let streamDone = false;
      while (!streamDone) {
        const { done, value } = await reader.read();
        if (done) break;
        textBuffer += decoder.decode(value, { stream: true });

        let newlineIndex: number;
        while ((newlineIndex = textBuffer.indexOf("\n")) !== -1) {
          let line = textBuffer.slice(0, newlineIndex);
          textBuffer = textBuffer.slice(newlineIndex + 1);
          if (line.endsWith("\r")) line = line.slice(0, -1);
          if (!line.startsWith("data: ")) continue;
          const jsonStr = line.slice(6).trim();
          if (jsonStr === "[DONE]") {
            streamDone = true;
            break;
          }
          try {
            const parsed = JSON.parse(jsonStr);
            const content = parsed.choices?.[0]?.delta?.content;
            if (content) upsert(content);
          } catch {
            /* partial */
          }
        }
      }

      // After stream ends, check for scheduled visit or contact
      await processSchedule(assistantSoFar, allMessages);
      await processContact(assistantSoFar, allMessages);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Erro desconhecido";
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content:
            `Desculpe, ocorreu um erro no atendimento automático: **${message}**.\n\nTente novamente ou fale pelo WhatsApp: **(85) 99999-0000**.`,
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: 20, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 20, scale: 0.95 }}
            className="fixed bottom-28 right-4 sm:right-6 z-50 w-[360px] sm:w-[400px] max-h-[550px] bg-card rounded-2xl shadow-2xl flex flex-col overflow-hidden border border-border"
          >
            {/* Header */}
            <div className="bg-gradient-to-r from-primary to-primary/80 p-4 flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center">
                <Bot size={20} className="text-primary-foreground" />
              </div>
              <div className="flex-1">
                <h3 className="text-primary-foreground font-bold text-sm">Luma · Simply Imóveis</h3>
                <div className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
                  <p className="text-primary-foreground/80 text-xs">Online agora</p>
                </div>
              </div>
              <button
                onClick={() => setOpen(false)}
                className="text-primary-foreground/70 hover:text-primary-foreground transition-colors"
              >
                <X size={18} />
              </button>
            </div>

            {/* Messages */}
            <div className="flex-1 overflow-y-auto p-4 space-y-3 max-h-[380px] bg-background/50">
              {messages.map((msg, i) => (
                <div
                  key={i}
                  className={`flex gap-2 ${msg.role === "user" ? "justify-end" : "justify-start"}`}
                >
                  {msg.role === "assistant" && (
                    <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 mt-1">
                      <Bot size={14} className="text-primary" />
                    </div>
                  )}
                  <div
                    className={`max-w-[80%] px-3.5 py-2.5 rounded-2xl text-sm leading-relaxed ${
                      msg.role === "user"
                        ? "bg-primary text-primary-foreground rounded-br-md"
                        : "bg-secondary text-secondary-foreground rounded-bl-md"
                    }`}
                  >
                    {msg.role === "assistant" ? (
                      <div className="prose prose-sm dark:prose-invert max-w-none [&>p]:m-0 [&>ul]:my-1 [&>ol]:my-1">
                        <ReactMarkdown>{msg.content}</ReactMarkdown>
                      </div>
                    ) : (
                      msg.content
                    )}
                  </div>
                  {msg.role === "user" && (
                    <div className="w-7 h-7 rounded-full bg-muted flex items-center justify-center flex-shrink-0 mt-1">
                      <User size={14} className="text-muted-foreground" />
                    </div>
                  )}
                </div>
              ))}
              {loading && (
                <div className="flex gap-2 justify-start">
                  <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                    <Bot size={14} className="text-primary" />
                  </div>
                  <div className="bg-secondary text-secondary-foreground px-3.5 py-2.5 rounded-2xl rounded-bl-md text-sm">
                    <div className="flex gap-1">
                      <span className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce [animation-delay:0ms]" />
                      <span className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce [animation-delay:150ms]" />
                      <span className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce [animation-delay:300ms]" />
                    </div>
                  </div>
                </div>
              )}
              <div ref={bottomRef} />
            </div>

            {/* Input */}
            <div className="p-3 border-t border-border bg-card">
              <div className="flex gap-2">
                <input
                  type="text"
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && sendMessage()}
                  placeholder="Digite sua mensagem..."
                  className="flex-1 px-3.5 py-2.5 rounded-xl bg-background border border-input text-sm text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none transition-shadow"
                />
                <button
                  onClick={sendMessage}
                  disabled={loading || !input.trim()}
                  className="bg-primary text-primary-foreground p-2.5 rounded-xl hover:opacity-90 disabled:opacity-50 transition-opacity"
                >
                  <Send size={16} />
                </button>
              </div>
              <p className="text-[10px] text-muted-foreground/60 text-center mt-2">
                Powered by Luma AI · Simply Imóveis
              </p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Chat toggle button */}
      <button
        onClick={() => setOpen(!open)}
        aria-label="Abrir chat"
        className="fixed bottom-6 right-[5.5rem] sm:right-24 z-50 group"
      >
        <span className="absolute inset-0 rounded-full bg-primary animate-ping opacity-20" />
        <div className="relative w-14 h-14 rounded-full bg-primary hover:bg-primary/90 shadow-2xl shadow-primary/30 flex items-center justify-center transition-all duration-300 group-hover:scale-110">
          {open ? <X size={24} className="text-primary-foreground" /> : <Bot size={26} className="text-primary-foreground" />}
        </div>
        <span className="absolute right-full mr-3 top-1/2 -translate-y-1/2 bg-foreground text-background text-xs font-semibold px-3 py-2 rounded-lg whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none shadow-lg">
          Fale com a Luma
        </span>
      </button>
    </>
  );
};

export default ChatWidget;
