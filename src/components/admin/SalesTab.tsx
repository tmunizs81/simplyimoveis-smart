import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminInsert, adminUpdate, adminDelete } from "@/lib/adminCrud";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { Plus, TrendingUp, DollarSign, Calendar, Edit, Trash2, X, Save, Search, FileText } from "lucide-react";
import SaleDocuments from "./SaleDocuments";

type Sale = {
  id: string; property_id: string | null; lead_id: string | null;
  buyer_name: string | null; buyer_email: string | null; buyer_phone: string | null;
  buyer_cpf: string | null; sale_value: number | null; commission_rate: number | null;
  commission_value: number | null; status: string; proposal_date: string | null;
  closing_date: string | null; notes: string | null; created_at: string; user_id: string;
};

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  em_andamento: { label: "Em Andamento", color: "bg-blue-500" },
  proposta_enviada: { label: "Proposta Enviada", color: "bg-amber-500" },
  documentacao: { label: "Documentação", color: "bg-purple-500" },
  fechado: { label: "Fechado", color: "bg-green-500" },
  cancelado: { label: "Cancelado", color: "bg-destructive" },
};

const SalesTab = () => {
  const [sales, setSales] = useState<Sale[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editingSale, setEditingSale] = useState<Sale | null>(null);
  const [search, setSearch] = useState("");
  const [viewDocsSaleId, setViewDocsSaleId] = useState<string | null>(null);
  const [form, setForm] = useState({
    buyer_name: "", buyer_email: "", buyer_phone: "", buyer_cpf: "",
    sale_value: 0, commission_rate: 5, status: "em_andamento",
    proposal_date: "", closing_date: "", notes: "",
  });

  const fetchSales = async () => {
    const { data, error } = await supabase.from("sales").select("*").order("created_at", { ascending: false });
    if (error) toast.error("Erro ao carregar vendas");
    else setSales((data as Sale[]) || []);
    setLoading(false);
  };

  useEffect(() => { fetchSales(); }, []);

  const openNewForm = () => {
    setEditingSale(null);
    setForm({ buyer_name: "", buyer_email: "", buyer_phone: "", buyer_cpf: "", sale_value: 0, commission_rate: 5, status: "em_andamento", proposal_date: "", closing_date: "", notes: "" });
    setShowForm(true);
  };

  const openEditForm = (s: Sale) => {
    setEditingSale(s);
    setForm({
      buyer_name: s.buyer_name || "", buyer_email: s.buyer_email || "",
      buyer_phone: s.buyer_phone || "", buyer_cpf: s.buyer_cpf || "",
      sale_value: s.sale_value ? Number(s.sale_value) : 0,
      commission_rate: s.commission_rate ? Number(s.commission_rate) : 5,
      status: s.status, proposal_date: s.proposal_date || "",
      closing_date: s.closing_date || "", notes: s.notes || "",
    });
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const commissionValue = (form.sale_value * form.commission_rate) / 100;
    const payload = {
      buyer_name: form.buyer_name || null, buyer_email: form.buyer_email || null,
      buyer_phone: form.buyer_phone || null, buyer_cpf: form.buyer_cpf || null,
      sale_value: form.sale_value || null, commission_rate: form.commission_rate,
      commission_value: commissionValue, status: form.status,
      proposal_date: form.proposal_date || null, closing_date: form.closing_date || null,
      notes: form.notes || null, user_id: user.id,
    };

    if (editingSale) {
      const { error } = await adminUpdate("sales", payload, { id: editingSale.id });
      if (error) { toast.error("Erro ao atualizar venda"); return; }
      toast.success("Venda atualizada!");
    } else {
      const { error } = await adminInsert("sales", payload);
      if (error) { toast.error("Erro ao criar venda"); return; }
      toast.success("Venda registrada!");
    }
    setShowForm(false);
    fetchSales();
  };

  const deleteSale = async (id: string) => {
    if (!confirm("Excluir esta venda?")) return;
    await supabase.from("sales").delete().eq("id", id);
    toast.success("Venda excluída");
    fetchSales();
  };

  const filtered = sales.filter(s => {
    if (search && !s.buyer_name?.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const totalSales = sales.filter(s => s.status === "fechado").reduce((sum, s) => sum + (Number(s.sale_value) || 0), 0);
  const totalCommission = sales.filter(s => s.status === "fechado").reduce((sum, s) => sum + (Number(s.commission_value) || 0), 0);

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  if (viewDocsSaleId) {
    return <SaleDocuments saleId={viewDocsSaleId} onClose={() => setViewDocsSaleId(null)} />;
  }

  if (showForm) {
    return (
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-2xl">
        <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
          <div className="gradient-primary px-6 py-5 flex items-center justify-between">
            <div>
              <h2 className="font-display text-lg font-bold text-primary-foreground">{editingSale ? "Editar Venda" : "Nova Venda"}</h2>
              <p className="text-primary-foreground/60 text-xs">Registre os dados da negociação</p>
            </div>
            <button onClick={() => setShowForm(false)} className="text-primary-foreground/60 hover:text-primary-foreground"><X size={20} /></button>
          </div>
          <form onSubmit={handleSubmit} className="p-6 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Comprador *</label>
                <input required value={form.buyer_name} onChange={e => setForm({ ...form, buyer_name: e.target.value })} className={inputClass} placeholder="Nome do comprador" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">E-mail</label>
                <input type="email" value={form.buyer_email} onChange={e => setForm({ ...form, buyer_email: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Telefone</label>
                <input value={form.buyer_phone} onChange={e => setForm({ ...form, buyer_phone: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">CPF</label>
                <input value={form.buyer_cpf} onChange={e => setForm({ ...form, buyer_cpf: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Valor da Venda (R$)</label>
                <input type="number" value={form.sale_value || ""} onChange={e => setForm({ ...form, sale_value: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Comissão (%)</label>
                <input type="number" step="0.1" value={form.commission_rate} onChange={e => setForm({ ...form, commission_rate: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Status</label>
                <select value={form.status} onChange={e => setForm({ ...form, status: e.target.value })} className={inputClass}>
                  {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Data Proposta</label>
                <input type="date" value={form.proposal_date} onChange={e => setForm({ ...form, proposal_date: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Data Fechamento</label>
                <input type="date" value={form.closing_date} onChange={e => setForm({ ...form, closing_date: e.target.value })} className={inputClass} />
              </div>
            </div>
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Observações</label>
              <textarea rows={3} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={`${inputClass} resize-none`} />
            </div>
            {form.sale_value > 0 && (
              <div className="bg-primary/5 rounded-xl p-4 border border-primary/20">
                <p className="text-sm text-foreground">Comissão estimada: <span className="font-bold text-primary">{((form.sale_value * form.commission_rate) / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</span></p>
              </div>
            )}
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
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-2xl font-bold text-foreground">{sales.length}</p>
          <p className="text-xs text-muted-foreground">Total Vendas</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-2xl font-bold text-green-600">{sales.filter(s => s.status === "fechado").length}</p>
          <p className="text-xs text-muted-foreground">Fechadas</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-lg font-bold text-primary">{totalSales.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
          <p className="text-xs text-muted-foreground">Vol. Vendas</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-lg font-bold text-accent">{totalCommission.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
          <p className="text-xs text-muted-foreground">Comissões</p>
        </div>
      </div>

      <div className="flex items-center justify-between gap-4">
        <div className="flex-1 relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar vendas..." className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-secondary/30 border border-input text-sm text-foreground focus:ring-2 focus:ring-primary/30 outline-none" />
        </div>
        <button onClick={openNewForm} className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 shadow-lg shadow-primary/20">
          <Plus size={16} /> Nova Venda
        </button>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <TrendingUp size={48} className="mx-auto mb-4 opacity-30" />
          <p>Nenhuma venda registrada.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((sale, i) => {
            const statusInfo = STATUS_LABELS[sale.status] || { label: sale.status, color: "bg-muted" };
            return (
              <motion.div key={sale.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.03 }}
                className="bg-card rounded-xl border border-border hover:border-primary/20 hover:shadow-md transition-all p-4 flex items-center gap-4">
                <div className={`w-2 h-12 rounded-full ${statusInfo.color}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-semibold text-sm text-foreground">{sale.buyer_name || "Sem comprador"}</span>
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${statusInfo.color} text-white`}>{statusInfo.label}</span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    {sale.sale_value && <span className="flex items-center gap-1 text-primary font-bold"><DollarSign size={11} /> {Number(sale.sale_value).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</span>}
                    {sale.closing_date && <span className="flex items-center gap-1"><Calendar size={11} /> {new Date(sale.closing_date).toLocaleDateString("pt-BR")}</span>}
                    {sale.commission_value && <span className="text-accent font-medium">Comissão: {Number(sale.commission_value).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</span>}
                  </div>
                </div>
                <div className="flex items-center gap-1.5">
                  <button onClick={() => setViewDocsSaleId(sale.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-blue-600 hover:border-blue-400 transition-all" title="Documentos"><FileText size={14} /></button>
                  <button onClick={() => openEditForm(sale)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Edit size={14} /></button>
                  <button onClick={() => deleteSale(sale.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default SalesTab;
