import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminInsert, adminUpdate, adminDelete, adminSelect } from "@/lib/adminCrud";
import { toast } from "sonner";
import { motion, AnimatePresence } from "framer-motion";
import { 
  Plus, Search, Phone, Mail, Calendar, Edit, Trash2, 
  Users, X, Save, LayoutGrid, List, MessageSquare, 
  Clock, History, Building2, Sparkles, TrendingUp, ArrowRight
} from "lucide-react";

const STATUS_LABELS: Record<string, { label: string; color: string; border: string; bg: string }> = {
  novo: { label: "Novo", color: "bg-blue-500", border: "border-blue-500", bg: "bg-blue-50" },
  contato_feito: { label: "Contato Feito", color: "bg-cyan-500", border: "border-cyan-500", bg: "bg-cyan-50" },
  visita_agendada: { label: "Visita Agendada", color: "bg-amber-500", border: "border-amber-500", bg: "bg-amber-50" },
  proposta: { label: "Proposta", color: "bg-purple-500", border: "border-purple-500", bg: "bg-purple-50" },
  negociacao: { label: "Negociação", color: "bg-orange-500", border: "border-orange-500", bg: "bg-orange-50" },
  fechado_ganho: { label: "Fechado (Ganho)", color: "bg-green-500", border: "border-green-500", bg: "bg-green-50" },
  fechado_perdido: { label: "Fechado (Perdido)", color: "bg-destructive", border: "border-destructive", bg: "bg-destructive/10" },
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

type LeadActivity = {
  id: string; lead_id: string; type: string; description: string; created_at: string;
};

const LeadsTab = () => {
  const [leads, setLeads] = useState<Lead[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingLead, setEditingLead] = useState<Lead | null>(null);
  const [search, setSearch] = useState("");
  const [viewMode, setViewMode] = useState<"list" | "kanban">("list");
  const [activities, setActivities] = useState<LeadActivity[]>([]);
  const [newActivity, setNewActivity] = useState({ type: "nota", description: "" });
  const [matchedProperties, setMatchedProperties] = useState<any[]>([]);
  const [form, setForm] = useState({
    name: "", email: "", phone: "", source: "site" as string,
    status: "novo" as string, interest_type: "venda",
    budget_min: 0, budget_max: 0, notes: "", next_follow_up: "",
  });

  const fetchLeads = async () => {
    const { data, error } = await adminSelect("leads", { order: { column: "created_at", ascending: false } });
    if (error) { toast.error("Erro ao carregar leads"); console.error(error); }
    else setLeads((data as Lead[]) || []);
    setLoading(false);
  };

  const fetchActivities = async (leadId: string) => {
    const { data } = await adminSelect("lead_activities", { 
      match: { lead_id: leadId }, 
      order: { column: "created_at", ascending: false } 
    });
    setActivities((data as LeadActivity[]) || []);
  };

  const fetchMatches = async (lead: Lead) => {
    const { data } = await adminSelect("properties", { 
      match: { status: lead.interest_type, active: true } 
    });
    if (data) {
      const filtered = (data as any[]).filter(p => {
        const price = Number(p.price);
        if (lead.budget_max && price > lead.budget_max) return false;
        if (lead.budget_min && price < lead.budget_min) return false;
        return true;
      });
      setMatchedProperties(filtered);
    }
  };

  useEffect(() => { fetchLeads(); }, []);

  const openNewForm = () => {
    setEditingLead(null);
    setActivities([]);
    setMatchedProperties([]);
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
    fetchActivities(lead.id);
    fetchMatches(lead);
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
      
      if (editingLead.status !== form.status) {
        await addActivity(editingLead.id, "status_change", `Status alterado para ${STATUS_LABELS[form.status].label}`);
      }
      toast.success("Lead atualizado!");
    } else {
      const { data, error } = await adminInsert("leads", payload);
      if (error) { toast.error("Erro ao criar lead"); return; }
      toast.success("Lead criado!");
    }
    setShowForm(false);
    fetchLeads();
  };

  const addActivity = async (leadId: string, type: string, description: string) => {
    const { data: { user } } = await supabase.auth.getUser();
    await adminInsert("lead_activities", {
      lead_id: leadId,
      type,
      description,
      user_id: user?.id
    });
    if (editingLead?.id === leadId) fetchActivities(leadId);
  };

  const handleAddManualActivity = async () => {
    if (!editingLead || !newActivity.description) return;
    await addActivity(editingLead.id, newActivity.type, newActivity.description);
    setNewActivity({ type: "nota", description: "" });
    toast.success("Atividade registrada");
  };

  const deleteLead = async (id: string) => {
    if (!confirm("Excluir este lead?")) return;
    await adminDelete("leads", { id });
    toast.success("Lead excluído");
    fetchLeads();
  };

  const updateStatus = async (id: string, status: string) => {
    const lead = leads.find(l => l.id === id);
    if (!lead) return;
    await adminUpdate("leads", { status }, { id });
    await addActivity(id, "status_change", `Status alterado para ${STATUS_LABELS[status].label}`);
    toast.success("Status atualizado");
    fetchLeads();
  };

  const filtered = leads.filter(l => {
    if (search && !l.name.toLowerCase().includes(search.toLowerCase()) && !l.email?.toLowerCase().includes(search.toLowerCase()) && !l.phone?.includes(search)) return false;
    return true;
  });

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  if (showForm) {
    return (
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <motion.div initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} className="lg:col-span-2">
          <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
            <div className="gradient-primary px-6 py-5 flex items-center justify-between">
              <div>
                <h2 className="font-display text-lg font-bold text-primary-foreground">{editingLead ? "Editar Lead" : "Novo Lead"}</h2>
                <p className="text-primary-foreground/60 text-xs">Informações cadastrais e perfil de busca</p>
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
                  <input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inputClass} />
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Telefone</label>
                  <input value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} className={inputClass} />
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
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Orçamento Mín.</label>
                  <input type="number" value={form.budget_min || ""} onChange={e => setForm({ ...form, budget_min: Number(e.target.value) })} className={inputClass} />
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Orçamento Máx.</label>
                  <input type="number" value={form.budget_max || ""} onChange={e => setForm({ ...form, budget_max: Number(e.target.value) })} className={inputClass} />
                </div>
              </div>
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setShowForm(false)} className="flex-1 py-3 rounded-xl border border-input text-muted-foreground font-semibold text-sm hover:bg-secondary transition-all">Cancelar</button>
                <button type="submit" className="flex-1 gradient-primary text-primary-foreground py-3 rounded-xl font-bold text-sm hover:opacity-90 flex items-center justify-center gap-2">
                  <Save size={16} /> Salvar Alterações
                </button>
              </div>
            </form>
          </div>

          {/* Matchmaking Section */}
          {editingLead && matchedProperties.length > 0 && (
            <div className="mt-6 bg-card rounded-2xl border border-border p-6">
              <h3 className="font-display font-bold text-foreground mb-4 flex items-center gap-2">
                <Sparkles size={18} className="text-primary" /> Imóveis Compatíveis ({matchedProperties.length})
              </h3>
              <div className="space-y-3">
                {matchedProperties.slice(0, 3).map(p => (
                  <div key={p.id} className="flex items-center gap-3 p-3 rounded-xl bg-secondary/20 border border-border hover:border-primary/30 transition-all cursor-pointer">
                    <div className="w-12 h-12 rounded-lg bg-muted overflow-hidden shrink-0">
                       {/* Simplified thumbnail */}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-bold truncate">{p.title}</p>
                      <p className="text-xs text-primary font-bold">{Number(p.price).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
                    </div>
                    <ArrowRight size={16} className="text-muted-foreground" />
                  </div>
                ))}
              </div>
            </div>
          )}
        </motion.div>

        {/* Timeline / Activities */}
        <motion.div initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} className="space-y-6">
          <div className="bg-card rounded-2xl border border-border flex flex-col h-full max-h-[600px]">
            <div className="px-5 py-4 border-b border-border flex items-center gap-2">
              <History size={18} className="text-primary" />
              <h3 className="font-display font-bold text-sm">Linha do Tempo</h3>
            </div>
            
            <div className="p-4 border-b border-border bg-secondary/10">
              <div className="flex gap-2 mb-2">
                <select 
                  value={newActivity.type} 
                  onChange={e => setNewActivity({...newActivity, type: e.target.value})}
                  className="text-xs bg-card border border-border rounded-lg px-2 py-1 focus:outline-none"
                >
                  <option value="nota">Nota</option>
                  <option value="ligacao">Ligação</option>
                  <option value="visita">Visita</option>
                  <option value="proposta">Proposta</option>
                </select>
                <button 
                  onClick={handleAddManualActivity}
                  disabled={!newActivity.description}
                  className="ml-auto text-xs font-bold text-primary hover:underline disabled:opacity-50"
                >
                  Adicionar
                </button>
              </div>
              <textarea 
                value={newActivity.description}
                onChange={e => setNewActivity({...newActivity, description: e.target.value})}
                placeholder="Descreva a atividade..."
                className="w-full text-xs p-2 rounded-lg bg-card border border-border focus:ring-1 focus:ring-primary outline-none resize-none"
                rows={2}
              />
            </div>

            <div className="flex-1 overflow-y-auto p-4 space-y-4">
              {activities.length === 0 ? (
                <p className="text-center text-xs text-muted-foreground py-10">Nenhuma atividade registrada.</p>
              ) : (
                activities.map((act, i) => (
                  <div key={act.id} className="relative pl-6 pb-2">
                    {i !== activities.length - 1 && <div className="absolute left-[7px] top-3 bottom-0 w-[2px] bg-border" />}
                    <div className={`absolute left-0 top-1 w-4 h-4 rounded-full border-2 border-card flex items-center justify-center ${
                      act.type === 'status_change' ? 'bg-primary' : 'bg-muted-foreground'
                    }`}>
                       {act.type === 'status_change' ? <TrendingUp size={8} className="text-white" /> : <Clock size={8} className="text-white" />}
                    </div>
                    <div>
                      <p className="text-xs text-foreground font-medium">{act.description}</p>
                      <p className="text-[10px] text-muted-foreground">{new Date(act.created_at).toLocaleString("pt-BR")}</p>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header & View Switcher */}
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center bg-secondary/30 p-1 rounded-xl border border-border">
          <button 
            onClick={() => setViewMode("list")}
            className={`px-3 py-1.5 rounded-lg flex items-center gap-2 text-xs font-bold transition-all ${viewMode === 'list' ? 'bg-card text-primary shadow-sm' : 'text-muted-foreground hover:text-foreground'}`}
          >
            <List size={14} /> Lista
          </button>
          <button 
            onClick={() => setViewMode("kanban")}
            className={`px-3 py-1.5 rounded-lg flex items-center gap-2 text-xs font-bold transition-all ${viewMode === 'kanban' ? 'bg-card text-primary shadow-sm' : 'text-muted-foreground hover:text-foreground'}`}
          >
            <LayoutGrid size={14} /> Kanban
          </button>
        </div>

        <div className="flex-1 max-w-md relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar leads..." className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-secondary/30 border border-input text-sm text-foreground focus:ring-2 focus:ring-primary/30 outline-none" />
        </div>
        
        <button onClick={openNewForm} className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 shadow-lg shadow-primary/20">
          <Plus size={16} /> Novo Lead
        </button>
      </div>

      <AnimatePresence mode="wait">
        {viewMode === "list" ? (
          <motion.div 
            key="list"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            className="space-y-2"
          >
            {filtered.map((lead, i) => (
              <div key={lead.id} className="bg-card rounded-xl border border-border hover:border-primary/20 hover:shadow-md transition-all p-4 flex items-center gap-4">
                <div className={`w-2 h-12 rounded-full ${STATUS_LABELS[lead.status]?.color || 'bg-muted'}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-semibold text-sm text-foreground">{lead.name}</span>
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${STATUS_LABELS[lead.status]?.color} text-white`}>
                      {STATUS_LABELS[lead.status]?.label}
                    </span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    {lead.phone && <span className="flex items-center gap-1"><Phone size={11} /> {lead.phone}</span>}
                    {lead.email && <span className="flex items-center gap-1"><Mail size={11} /> {lead.email}</span>}
                    {lead.interest_type && <span className="text-primary font-medium">{lead.interest_type === 'venda' ? 'Compra' : 'Aluguel'}</span>}
                  </div>
                </div>
                <div className="flex items-center gap-1.5">
                   <button onClick={() => openEditForm(lead)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Edit size={14} /></button>
                   <button onClick={() => deleteLead(lead.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
                </div>
              </div>
            ))}
          </motion.div>
        ) : (
          <motion.div 
            key="kanban"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            className="flex gap-4 overflow-x-auto pb-6 -mx-4 px-4 min-h-[500px]"
          >
            {Object.entries(STATUS_LABELS).map(([statusKey, label]) => {
              const statusLeads = filtered.filter(l => l.status === statusKey);
              return (
                <div key={statusKey} className="flex-shrink-0 w-80 bg-secondary/10 rounded-2xl border border-border flex flex-col">
                  <div className={`px-4 py-3 border-b-2 ${label.border} flex items-center justify-between`}>
                    <h4 className="text-xs font-bold uppercase tracking-wider text-foreground">{label.label}</h4>
                    <span className="bg-secondary text-[10px] font-bold px-2 py-0.5 rounded-full">{statusLeads.length}</span>
                  </div>
                  <div className="p-3 flex-1 space-y-3 overflow-y-auto">
                    {statusLeads.map(lead => (
                      <div 
                        key={lead.id} 
                        onClick={() => openEditForm(lead)}
                        className="bg-card p-4 rounded-xl border border-border shadow-sm hover:shadow-md hover:border-primary/30 transition-all cursor-pointer group"
                      >
                        <p className="text-sm font-bold text-foreground mb-2 group-hover:text-primary">{lead.name}</p>
                        <div className="flex items-center justify-between text-[10px] text-muted-foreground">
                          <span className="flex items-center gap-1"><Clock size={10} /> {new Date(lead.created_at).toLocaleDateString("pt-BR")}</span>
                          <span className="bg-secondary px-1.5 py-0.5 rounded-md">{SOURCE_LABELS[lead.source] || lead.source}</span>
                        </div>
                      </div>
                    ))}
                    {statusLeads.length === 0 && (
                      <div className="h-20 border-2 border-dashed border-border rounded-xl flex items-center justify-center text-xs text-muted-foreground">Vazio</div>
                    )}
                  </div>
                </div>
              );
            })}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};

export default LeadsTab;
