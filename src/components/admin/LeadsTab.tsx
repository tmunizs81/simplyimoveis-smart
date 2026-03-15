import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminInsert, adminUpdate, adminDelete } from "@/lib/adminCrud";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { Plus, Search, Phone, Mail, Calendar, ChevronDown, Edit, Trash2, Users, Filter, X, Save, ArrowRight } from "lucide-react";

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  novo: { label: "Novo", color: "bg-blue-500" },
  contato_feito: { label: "Contato Feito", color: "bg-cyan-500" },
  visita_agendada: { label: "Visita Agendada", color: "bg-amber-500" },
  proposta: { label: "Proposta", color: "bg-purple-500" },
  negociacao: { label: "Negociação", color: "bg-orange-500" },
  fechado_ganho: { label: "Fechado (Ganho)", color: "bg-green-500" },
  fechado_perdido: { label: "Fechado (Perdido)", color: "bg-destructive" },
};

const SOURCE_LABELS: Record<string, string> = {
  site: "Site", whatsapp: "WhatsApp", indicacao: "Indicação", portal: "Portal",
  placa: "Placa", telefone: "Telefone", chat: "Chat", outro: "Outro",
};

type Lead = {
  id: string; name: string; email: string | null; phone: string | null;
  source: string; status: string; interest_type: string | null;
  budget_min: number | null; budget_max: number | null; notes: string | null;
  next_follow_up: string | null; property_id: string | null;
  created_at: string; user_id: string;
};

const LeadsTab = () => {
  const [leads, setLeads] = useState<Lead[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingLead, setEditingLead] = useState<Lead | null>(null);
  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [form, setForm] = useState({
    name: "", email: "", phone: "", source: "site" as string,
    status: "novo" as string, interest_type: "venda",
    budget_min: 0, budget_max: 0, notes: "", next_follow_up: "",
  });

  const fetchLeads = async () => {
    const { data, error } = await supabase.from("leads").select("*").order("created_at", { ascending: false });
    if (error) { toast.error("Erro ao carregar leads"); console.error(error); }
    else setLeads((data as Lead[]) || []);
    setLoading(false);
  };

  useEffect(() => { fetchLeads(); }, []);

  const openNewForm = () => {
    setEditingLead(null);
    setForm({ name: "", email: "", phone: "", source: "site", status: "novo", interest_type: "venda", budget_min: 0, budget_max: 0, notes: "", next_follow_up: "" });
    setShowForm(true);
  };

  const openEditForm = (lead: Lead) => {
    setEditingLead(lead);
    setForm({
      name: lead.name, email: lead.email || "", phone: lead.phone || "",
      source: lead.source, status: lead.status, interest_type: lead.interest_type || "venda",
      budget_min: lead.budget_min ? Number(lead.budget_min) : 0,
      budget_max: lead.budget_max ? Number(lead.budget_max) : 0,
      notes: lead.notes || "",
      next_follow_up: lead.next_follow_up ? new Date(lead.next_follow_up).toISOString().slice(0, 16) : "",
    });
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const payload = {
      name: form.name, email: form.email || null, phone: form.phone || null,
      source: form.source, status: form.status,
      interest_type: form.interest_type, budget_min: form.budget_min || null,
      budget_max: form.budget_max || null, notes: form.notes || null,
      next_follow_up: form.next_follow_up || null, user_id: user.id,
    };

    if (editingLead) {
      const { error } = await adminUpdate("leads", payload, { id: editingLead.id });
      if (error) { toast.error("Erro ao atualizar lead"); return; }
      toast.success("Lead atualizado!");
    } else {
      const { error } = await adminInsert("leads", payload);
      if (error) { toast.error("Erro ao criar lead"); return; }
      toast.success("Lead criado!");
    }
    setShowForm(false);
    fetchLeads();
  };

  const deleteLead = async (id: string) => {
    if (!confirm("Excluir este lead?")) return;
    await adminDelete("leads", { id });
    toast.success("Lead excluído");
    fetchLeads();
  };

  const updateStatus = async (id: string, status: string) => {
    await adminUpdate("leads", { status }, { id });
    toast.success("Status atualizado");
    fetchLeads();
  };

  const filtered = leads.filter(l => {
    if (filterStatus !== "all" && l.status !== filterStatus) return false;
    if (search && !l.name.toLowerCase().includes(search.toLowerCase()) && !l.email?.toLowerCase().includes(search.toLowerCase()) && !l.phone?.includes(search)) return false;
    return true;
  });

  const stats = Object.entries(STATUS_LABELS).map(([key, val]) => ({
    key, label: val.label, color: val.color,
    count: leads.filter(l => l.status === key).length,
  }));

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  if (showForm) {
    return (
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-2xl">
        <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
          <div className="gradient-primary px-6 py-5 flex items-center justify-between">
            <div>
              <h2 className="font-display text-lg font-bold text-primary-foreground">{editingLead ? "Editar Lead" : "Novo Lead"}</h2>
              <p className="text-primary-foreground/60 text-xs">Preencha os dados do prospect</p>
            </div>
            <button onClick={() => setShowForm(false)} className="text-primary-foreground/60 hover:text-primary-foreground"><X size={20} /></button>
          </div>
          <form onSubmit={handleSubmit} className="p-6 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Nome *</label>
                <input required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} className={inputClass} placeholder="Nome completo" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">E-mail</label>
                <input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inputClass} placeholder="email@exemplo.com" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Telefone</label>
                <input value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} className={inputClass} placeholder="(85) 99999-9999" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Origem</label>
                <select value={form.source} onChange={e => setForm({ ...form, source: e.target.value })} className={inputClass}>
                  {Object.entries(SOURCE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Status</label>
                <select value={form.status} onChange={e => setForm({ ...form, status: e.target.value })} className={inputClass}>
                  {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Interesse</label>
                <select value={form.interest_type} onChange={e => setForm({ ...form, interest_type: e.target.value })} className={inputClass}>
                  <option value="venda">Compra</option>
                  <option value="aluguel">Aluguel</option>
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Follow-up</label>
                <input type="datetime-local" value={form.next_follow_up} onChange={e => setForm({ ...form, next_follow_up: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Orçamento Mín.</label>
                <input type="number" value={form.budget_min || ""} onChange={e => setForm({ ...form, budget_min: Number(e.target.value) })} className={inputClass} placeholder="R$ 0" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Orçamento Máx.</label>
                <input type="number" value={form.budget_max || ""} onChange={e => setForm({ ...form, budget_max: Number(e.target.value) })} className={inputClass} placeholder="R$ 0" />
              </div>
            </div>
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Observações</label>
              <textarea rows={3} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={`${inputClass} resize-none`} placeholder="Notas sobre o lead..." />
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowForm(false)} className="flex-1 py-3 rounded-xl border border-input text-muted-foreground font-semibold text-sm hover:bg-secondary transition-all">Cancelar</button>
              <button type="submit" className="flex-1 gradient-primary text-primary-foreground py-3 rounded-xl font-bold text-sm hover:opacity-90 flex items-center justify-center gap-2">
                <Save size={16} /> Salvar
              </button>
            </div>
          </form>
        </div>
      </motion.div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-2">
        {stats.map(s => (
          <button key={s.key} onClick={() => setFilterStatus(filterStatus === s.key ? "all" : s.key)}
            className={`bg-card rounded-xl border p-3 text-center transition-all ${filterStatus === s.key ? "border-primary shadow-md" : "border-border hover:border-primary/30"}`}>
            <p className="font-display text-xl font-bold text-foreground">{s.count}</p>
            <p className="text-[10px] text-muted-foreground font-medium truncate">{s.label}</p>
          </button>
        ))}
      </div>

      {/* Header */}
      <div className="flex items-center justify-between gap-4">
        <div className="flex-1 relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar leads..." className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-secondary/30 border border-input text-sm text-foreground focus:ring-2 focus:ring-primary/30 outline-none" />
        </div>
        <button onClick={openNewForm} className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 shadow-lg shadow-primary/20">
          <Plus size={16} /> Novo Lead
        </button>
      </div>

      {/* List */}
      {filtered.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <Users size={48} className="mx-auto mb-4 opacity-30" />
          <p>Nenhum lead encontrado.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((lead, i) => {
            const statusInfo = STATUS_LABELS[lead.status] || { label: lead.status, color: "bg-muted" };
            return (
              <motion.div key={lead.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.03 }}
                className="bg-card rounded-xl border border-border hover:border-primary/20 hover:shadow-md transition-all p-4 flex items-center gap-4">
                <div className={`w-2 h-12 rounded-full ${statusInfo.color}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-semibold text-sm text-foreground">{lead.name}</span>
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${statusInfo.color} text-white`}>{statusInfo.label}</span>
                    <span className="text-[10px] px-2 py-0.5 rounded-full bg-secondary text-muted-foreground font-medium">{SOURCE_LABELS[lead.source] || lead.source}</span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    {lead.email && <span className="flex items-center gap-1"><Mail size={11} /> {lead.email}</span>}
                    {lead.phone && <span className="flex items-center gap-1"><Phone size={11} /> {lead.phone}</span>}
                    {lead.next_follow_up && <span className="flex items-center gap-1"><Calendar size={11} /> {new Date(lead.next_follow_up).toLocaleDateString("pt-BR")}</span>}
                    {lead.interest_type && <span className="text-primary font-medium">{lead.interest_type === "venda" ? "Compra" : "Aluguel"}</span>}
                  </div>
                </div>
                <div className="flex items-center gap-1.5">
                  <select value={lead.status} onChange={e => updateStatus(lead.id, e.target.value)}
                    className="text-xs bg-secondary/50 border border-input rounded-lg px-2 py-1.5 text-muted-foreground focus:outline-none">
                    {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                  </select>
                  <button onClick={() => openEditForm(lead)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Edit size={14} /></button>
                  <button onClick={() => deleteLead(lead.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default LeadsTab;
