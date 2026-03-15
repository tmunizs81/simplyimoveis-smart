import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminUpdate, adminDelete, adminSelect } from "@/lib/adminCrud";
import { toast } from "sonner";
import { Mail, Phone, Clock, Eye, EyeOff, Trash2, ChevronDown, ChevronUp, MessageCircle, Calendar, Bot } from "lucide-react";

type ContactSubmission = {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  subject: string | null;
  message: string;
  read: boolean;
  created_at: string;
  chat_transcript: string | null;
  visit_date: string | null;
  source: string | null;
};

const ContactsTab = () => {
  const [contacts, setContacts] = useState<ContactSubmission[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [filter, setFilter] = useState<"all" | "unread" | "read">("all");

  const fetchContacts = async () => {
    const { data, error } = await adminSelect("contact_submissions", { order: { column: "created_at", ascending: false } });
    if (error) {
      toast.error("Erro ao carregar contatos.");
      console.error(error);
    } else {
      setContacts((data as ContactSubmission[]) || []);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchContacts();
  }, []);

  const toggleRead = async (contact: ContactSubmission) => {
    const { error } = await adminUpdate("contact_submissions", { read: !contact.read }, { id: contact.id });
    if (error) {
      toast.error("Erro ao atualizar status.");
    } else {
      setContacts((prev) =>
        prev.map((c) => (c.id === contact.id ? { ...c, read: !c.read } : c))
      );
    }
  };

  const deleteContact = async (id: string) => {
    const { error } = await adminDelete("contact_submissions", { id });
    if (error) {
      toast.error("Erro ao excluir contato.");
    } else {
      setContacts((prev) => prev.filter((c) => c.id !== id));
      toast.success("Contato excluído.");
    }
  };

  const filtered = contacts.filter((c) => {
    if (filter === "unread") return !c.read;
    if (filter === "read") return c.read;
    return true;
  });

  const unreadCount = contacts.filter((c) => !c.read).length;

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="text-2xl font-bold text-foreground">Solicitações de Contato</h2>
          <p className="text-muted-foreground text-sm mt-1">
            {contacts.length} contato{contacts.length !== 1 ? "s" : ""} • {unreadCount} não lido{unreadCount !== 1 ? "s" : ""}
          </p>
        </div>

        <div className="flex gap-2">
          {(["all", "unread", "read"] as const).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold uppercase tracking-wider transition-colors ${
                filter === f
                  ? "bg-primary text-primary-foreground"
                  : "bg-secondary text-muted-foreground hover:text-foreground"
              }`}
            >
              {f === "all" ? "Todos" : f === "unread" ? "Não lidos" : "Lidos"}
            </button>
          ))}
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <Mail size={48} className="mx-auto mb-4 opacity-30" />
          <p>Nenhuma solicitação de contato {filter !== "all" ? "neste filtro" : "ainda"}.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {filtered.map((contact) => {
            const isExpanded = expandedId === contact.id;
            const date = new Date(contact.created_at);

            return (
              <div
                key={contact.id}
                className={`border rounded-xl overflow-hidden transition-all ${
                  contact.read
                    ? "border-border bg-card"
                    : "border-primary/30 bg-primary/5"
                }`}
              >
                {/* Header row */}
                <button
                  onClick={() => setExpandedId(isExpanded ? null : contact.id)}
                  className="w-full px-5 py-4 flex items-center gap-4 text-left hover:bg-secondary/30 transition-colors"
                >
                   {!contact.read && (
                     <span className="w-2.5 h-2.5 rounded-full bg-primary flex-shrink-0" />
                   )}
                   {contact.source && contact.source.startsWith("chat") && (
                     <Bot size={16} className="text-primary flex-shrink-0" />
                   )}
                   <div className="flex-1 min-w-0">
                     <div className="flex items-center gap-2">
                       <span className="font-semibold text-foreground text-sm truncate">
                         {contact.name}
                       </span>
                       {contact.source && contact.source !== "form" && (
                         <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-primary/10 text-primary font-medium">
                           {contact.source === "chat-agendamento" ? "Visita" : "Chat"}
                         </span>
                       )}
                       {contact.subject && (
                         <span className="text-muted-foreground text-xs truncate">
                           — {contact.subject}
                         </span>
                       )}
                     </div>
                     <p className="text-muted-foreground text-xs truncate mt-0.5">
                       {contact.message}
                     </p>
                   </div>
                  <div className="flex items-center gap-3 flex-shrink-0">
                    <span className="text-muted-foreground/60 text-xs flex items-center gap-1">
                      <Clock size={12} />
                      {date.toLocaleDateString("pt-BR")} {date.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })}
                    </span>
                    {isExpanded ? <ChevronUp size={16} className="text-muted-foreground" /> : <ChevronDown size={16} className="text-muted-foreground" />}
                  </div>
                </button>

                {/* Expanded details */}
                {isExpanded && (
                  <div className="px-5 pb-5 border-t border-border/50">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
                      <div className="flex items-center gap-2 text-sm">
                        <Mail size={14} className="text-primary" />
                        <a href={`mailto:${contact.email}`} className="text-foreground hover:text-primary transition-colors">
                          {contact.email}
                        </a>
                      </div>
                      {contact.phone && (
                        <div className="flex items-center gap-2 text-sm">
                          <Phone size={14} className="text-primary" />
                          <a href={`tel:${contact.phone}`} className="text-foreground hover:text-primary transition-colors">
                            {contact.phone}
                          </a>
                        </div>
                      )}
                     {contact.visit_date && (
                       <div className="flex items-center gap-2 text-sm">
                         <Calendar size={14} className="text-primary" />
                         <span className="text-foreground">Visita: {contact.visit_date}</span>
                       </div>
                     )}
                     </div>

                     <div className="mt-4 bg-secondary/50 rounded-lg p-4">
                       <p className="text-sm text-foreground leading-relaxed whitespace-pre-wrap">
                         {contact.message}
                       </p>
                     </div>

                     {contact.chat_transcript && (
                       <div className="mt-4">
                         <div className="flex items-center gap-2 mb-2">
                           <MessageCircle size={14} className="text-primary" />
                           <span className="text-sm font-semibold text-foreground">Conversa com a Luma</span>
                         </div>
                         <div className="bg-secondary/30 rounded-lg p-4 max-h-80 overflow-y-auto border border-border/50">
                           {contact.chat_transcript.split("\n\n").map((line, i) => {
                             const isClient = line.startsWith("[Cliente]:");
                             const isLuma = line.startsWith("[Luma]:");
                             const content = line.replace(/^\[(Cliente|Luma)\]:\s*/, "");
                             return (
                               <div key={i} className={`mb-3 last:mb-0 flex ${isClient ? "justify-end" : "justify-start"}`}>
                                 <div className={`max-w-[85%] px-3 py-2 rounded-xl text-xs leading-relaxed ${
                                   isClient
                                     ? "bg-primary/10 text-foreground rounded-br-sm"
                                     : isLuma
                                     ? "bg-muted text-foreground rounded-bl-sm"
                                     : "text-muted-foreground"
                                 }`}>
                                   {isClient && <span className="font-semibold text-primary block mb-0.5">Cliente</span>}
                                   {isLuma && <span className="font-semibold text-primary block mb-0.5">Luma</span>}
                                   {content}
                                 </div>
                               </div>
                             );
                           })}
                         </div>
                       </div>
                     )}

                    <div className="flex gap-2 mt-4">
                      <button
                        onClick={() => toggleRead(contact)}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-secondary text-muted-foreground hover:text-foreground transition-colors"
                      >
                        {contact.read ? <EyeOff size={14} /> : <Eye size={14} />}
                        {contact.read ? "Marcar não lido" : "Marcar como lido"}
                      </button>
                      <button
                        onClick={() => deleteContact(contact.id)}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-destructive/10 text-destructive hover:bg-destructive/20 transition-colors"
                      >
                        <Trash2 size={14} />
                        Excluir
                      </button>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default ContactsTab;
