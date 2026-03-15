import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminInsert, adminUpdate, adminDelete } from "@/lib/adminCrud";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { Plus, Search, DollarSign, TrendingUp, TrendingDown, ArrowUpRight, ArrowDownRight, Edit, Trash2, X, Save, Calendar, Filter } from "lucide-react";

type Transaction = {
  id: string; type: string; category: string; description: string;
  amount: number; date: string; property_id: string | null;
  contract_id: string | null; tenant_id: string | null;
  status: string; due_date: string | null; paid_date: string | null;
  payment_method: string | null; receipt_path: string | null;
  notes: string | null; created_at: string; user_id: string;
};

const CATEGORY_LABELS: Record<string, string> = {
  aluguel: "Aluguel", venda: "Venda", comissao: "Comissão",
  manutencao: "Manutenção", condominio: "Condomínio", iptu: "IPTU",
  seguro: "Seguro", taxa_administracao: "Taxa Admin", reparo: "Reparo", outro: "Outro",
};

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  pendente: { label: "Pendente", color: "bg-amber-500" },
  pago: { label: "Pago", color: "bg-green-500" },
  atrasado: { label: "Atrasado", color: "bg-destructive" },
  cancelado: { label: "Cancelado", color: "bg-muted-foreground" },
};

const FinancialTab = () => {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Transaction | null>(null);
  const [search, setSearch] = useState("");
  const [filterType, setFilterType] = useState<string>("all");
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [form, setForm] = useState({
    type: "receita" as string, category: "aluguel" as string, description: "",
    amount: 0, date: new Date().toISOString().slice(0, 10), status: "pendente" as string,
    due_date: "", paid_date: "", payment_method: "", notes: "",
  });

  const fetchTransactions = async () => {
    const { data, error } = await supabase.from("financial_transactions").select("*").order("date", { ascending: false });
    if (error) toast.error("Erro ao carregar transações");
    else setTransactions((data as Transaction[]) || []);
    setLoading(false);
  };

  useEffect(() => { fetchTransactions(); }, []);

  const openNew = (type: string = "receita") => {
    setEditing(null);
    setForm({ type, category: type === "receita" ? "aluguel" : "manutencao", description: "", amount: 0, date: new Date().toISOString().slice(0, 10), status: "pendente", due_date: "", paid_date: "", payment_method: "", notes: "" });
    setShowForm(true);
  };

  const openEdit = (t: Transaction) => {
    setEditing(t);
    setForm({
      type: t.type, category: t.category, description: t.description,
      amount: Number(t.amount), date: t.date, status: t.status,
      due_date: t.due_date || "", paid_date: t.paid_date || "",
      payment_method: t.payment_method || "", notes: t.notes || "",
    });
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const payload = {
      type: form.type as any, category: form.category as any, description: form.description,
      amount: form.amount, date: form.date, status: form.status as any,
      due_date: form.due_date || null, paid_date: form.paid_date || null,
      payment_method: form.payment_method || null, notes: form.notes || null,
      user_id: user.id,
    };

    if (editing) {
      const { error } = await adminUpdate("financial_transactions", payload, { id: editing.id });
      if (error) { toast.error("Erro ao atualizar"); return; }
      toast.success("Transação atualizada!");
    } else {
      const { error } = await adminInsert("financial_transactions", payload);
      if (error) { toast.error("Erro ao registrar"); return; }
      toast.success("Transação registrada!");
    }
    setShowForm(false);
    fetchTransactions();
  };

  const deleteTransaction = async (id: string) => {
    if (!confirm("Excluir esta transação?")) return;
    await supabase.from("financial_transactions").delete().eq("id", id);
    toast.success("Transação excluída");
    fetchTransactions();
  };

  const markAsPaid = async (id: string) => {
    await supabase.from("financial_transactions").update({
      status: "pago" as any, paid_date: new Date().toISOString().slice(0, 10),
    } as any).eq("id", id);
    toast.success("Marcado como pago!");
    fetchTransactions();
  };

  const filtered = transactions.filter(t => {
    if (filterType !== "all" && t.type !== filterType) return false;
    if (filterStatus !== "all" && t.status !== filterStatus) return false;
    if (search && !t.description.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const totalReceitas = transactions.filter(t => t.type === "receita" && t.status === "pago").reduce((s, t) => s + Number(t.amount), 0);
  const totalDespesas = transactions.filter(t => t.type === "despesa" && t.status === "pago").reduce((s, t) => s + Number(t.amount), 0);
  const pendentes = transactions.filter(t => t.status === "pendente").reduce((s, t) => s + Number(t.amount), 0);
  const atrasados = transactions.filter(t => t.status === "atrasado").length;

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  if (showForm) {
    return (
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-2xl">
        <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
          <div className={`px-6 py-5 flex items-center justify-between ${form.type === "receita" ? "bg-green-600" : "bg-destructive"}`}>
            <div>
              <h2 className="font-display text-lg font-bold text-white">{editing ? "Editar" : "Nova"} {form.type === "receita" ? "Receita" : "Despesa"}</h2>
              <p className="text-white/60 text-xs">Registrar transação financeira</p>
            </div>
            <button onClick={() => setShowForm(false)} className="text-white/60 hover:text-white"><X size={20} /></button>
          </div>
          <form onSubmit={handleSubmit} className="p-6 space-y-4">
            <div className="flex gap-2 mb-2">
              <button type="button" onClick={() => setForm({ ...form, type: "receita" })} className={`flex-1 py-2 rounded-xl text-sm font-bold transition-all ${form.type === "receita" ? "bg-green-600 text-white" : "bg-secondary text-muted-foreground"}`}>
                <ArrowUpRight size={14} className="inline mr-1" /> Receita
              </button>
              <button type="button" onClick={() => setForm({ ...form, type: "despesa" })} className={`flex-1 py-2 rounded-xl text-sm font-bold transition-all ${form.type === "despesa" ? "bg-destructive text-white" : "bg-secondary text-muted-foreground"}`}>
                <ArrowDownRight size={14} className="inline mr-1" /> Despesa
              </button>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Descrição *</label>
                <input required value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} className={inputClass} placeholder="Descrição da transação" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Categoria</label>
                <select value={form.category} onChange={e => setForm({ ...form, category: e.target.value })} className={inputClass}>
                  {Object.entries(CATEGORY_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Valor (R$) *</label>
                <input type="number" required min={0} step="0.01" value={form.amount || ""} onChange={e => setForm({ ...form, amount: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Data</label>
                <input type="date" value={form.date} onChange={e => setForm({ ...form, date: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Vencimento</label>
                <input type="date" value={form.due_date} onChange={e => setForm({ ...form, due_date: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Status</label>
                <select value={form.status} onChange={e => setForm({ ...form, status: e.target.value })} className={inputClass}>
                  {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Forma Pagamento</label>
                <select value={form.payment_method} onChange={e => setForm({ ...form, payment_method: e.target.value })} className={inputClass}>
                  <option value="">—</option>
                  <option value="pix">PIX</option>
                  <option value="boleto">Boleto</option>
                  <option value="cartao">Cartão</option>
                  <option value="transferencia">Transferência</option>
                  <option value="dinheiro">Dinheiro</option>
                  <option value="cheque">Cheque</option>
                </select>
              </div>
              {form.status === "pago" && (
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Data Pagamento</label>
                  <input type="date" value={form.paid_date} onChange={e => setForm({ ...form, paid_date: e.target.value })} className={inputClass} />
                </div>
              )}
            </div>
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Observações</label>
              <textarea rows={2} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={`${inputClass} resize-none`} />
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
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div className="bg-card rounded-xl border border-border p-4">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-8 h-8 rounded-lg bg-green-500/10 flex items-center justify-center"><TrendingUp size={16} className="text-green-500" /></div>
            <p className="text-xs text-muted-foreground">Receitas</p>
          </div>
          <p className="font-display text-lg font-bold text-green-600">{totalReceitas.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-8 h-8 rounded-lg bg-destructive/10 flex items-center justify-center"><TrendingDown size={16} className="text-destructive" /></div>
            <p className="text-xs text-muted-foreground">Despesas</p>
          </div>
          <p className="font-display text-lg font-bold text-destructive">{totalDespesas.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center"><DollarSign size={16} className="text-primary" /></div>
            <p className="text-xs text-muted-foreground">Saldo</p>
          </div>
          <p className={`font-display text-lg font-bold ${totalReceitas - totalDespesas >= 0 ? "text-green-600" : "text-destructive"}`}>
            {(totalReceitas - totalDespesas).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
          </p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4">
          <div className="flex items-center gap-2 mb-2">
            <div className="w-8 h-8 rounded-lg bg-amber-500/10 flex items-center justify-center"><Calendar size={16} className="text-amber-500" /></div>
            <p className="text-xs text-muted-foreground">Pendentes</p>
          </div>
          <p className="font-display text-lg font-bold text-amber-500">{pendentes.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
          {atrasados > 0 && <p className="text-xs text-destructive font-medium">{atrasados} atrasado{atrasados > 1 ? "s" : ""}</p>}
        </div>
      </div>

      {/* Controls */}
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 relative min-w-[200px]">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar..." className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-secondary/30 border border-input text-sm text-foreground focus:ring-2 focus:ring-primary/30 outline-none" />
        </div>
        <div className="flex gap-2">
          {[{ k: "all", l: "Todos" }, { k: "receita", l: "Receitas" }, { k: "despesa", l: "Despesas" }].map(f => (
            <button key={f.k} onClick={() => setFilterType(f.k)} className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${filterType === f.k ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground"}`}>{f.l}</button>
          ))}
        </div>
        <div className="flex gap-2">
          {[{ k: "all", l: "Todos" }, { k: "pendente", l: "Pendentes" }, { k: "pago", l: "Pagos" }, { k: "atrasado", l: "Atrasados" }].map(f => (
            <button key={f.k} onClick={() => setFilterStatus(f.k)} className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors ${filterStatus === f.k ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground"}`}>{f.l}</button>
          ))}
        </div>
        <div className="flex gap-2">
          <button onClick={() => openNew("receita")} className="bg-green-600 text-white px-4 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2">
            <ArrowUpRight size={16} /> Receita
          </button>
          <button onClick={() => openNew("despesa")} className="bg-destructive text-white px-4 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2">
            <ArrowDownRight size={16} /> Despesa
          </button>
        </div>
      </div>

      {/* List */}
      {filtered.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <DollarSign size={48} className="mx-auto mb-4 opacity-30" />
          <p>Nenhuma transação encontrada.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((t, i) => {
            const statusInfo = STATUS_LABELS[t.status] || { label: t.status, color: "bg-muted" };
            const isReceita = t.type === "receita";
            return (
              <motion.div key={t.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.02 }}
                className="bg-card rounded-xl border border-border hover:border-primary/20 transition-all p-4 flex items-center gap-4">
                <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${isReceita ? "bg-green-500/10" : "bg-destructive/10"}`}>
                  {isReceita ? <ArrowUpRight size={18} className="text-green-500" /> : <ArrowDownRight size={18} className="text-destructive" />}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <span className="font-semibold text-sm text-foreground truncate">{t.description}</span>
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${statusInfo.color} text-white`}>{statusInfo.label}</span>
                    <span className="text-[10px] px-2 py-0.5 rounded-full bg-secondary text-muted-foreground">{CATEGORY_LABELS[t.category] || t.category}</span>
                  </div>
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <span>{new Date(t.date).toLocaleDateString("pt-BR")}</span>
                    {t.due_date && <span>Venc: {new Date(t.due_date).toLocaleDateString("pt-BR")}</span>}
                    {t.payment_method && <span className="capitalize">{t.payment_method}</span>}
                  </div>
                </div>
                <p className={`font-display font-bold text-base ${isReceita ? "text-green-600" : "text-destructive"}`}>
                  {isReceita ? "+" : "-"}{Number(t.amount).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
                </p>
                <div className="flex items-center gap-1.5">
                  {t.status === "pendente" && (
                    <button onClick={() => markAsPaid(t.id)} title="Marcar como pago" className="p-2 rounded-lg border border-green-500/30 text-green-500 hover:bg-green-500/10 transition-all text-xs font-bold">Pago</button>
                  )}
                  <button onClick={() => openEdit(t)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Edit size={14} /></button>
                  <button onClick={() => deleteTransaction(t.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default FinancialTab;
