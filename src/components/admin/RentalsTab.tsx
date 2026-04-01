import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminInsert, adminUpdate, adminDelete, adminSelect, adminStorageUpload, adminStorageDelete, adminStorageSignedUrl } from "@/lib/adminCrud";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { Plus, Search, Home, Calendar, DollarSign, Edit, Trash2, X, Save, Upload, FileText, Eye, Download } from "lucide-react";

type RentalContract = {
  id: string; property_id: string | null; tenant_id: string | null;
  start_date: string; end_date: string; monthly_rent: number;
  deposit_amount: number | null; payment_day: number; status: string;
  notes: string | null; late_fee_percentage: number | null;
  adjustment_index: string | null; created_at: string; user_id: string;
  commission_rate: number | null; commission_value: number | null;
};

type ContractDoc = {
  id: string; contract_id: string; file_path: string; file_name: string;
  file_type: string; document_type: string; notes: string | null; created_at: string;
};

type Tenant = { id: string; name: string };
type Property = { id: string; title: string };

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  ativo: { label: "Ativo", color: "bg-green-500" },
  pendente: { label: "Pendente", color: "bg-amber-500" },
  encerrado: { label: "Encerrado", color: "bg-muted-foreground" },
  cancelado: { label: "Cancelado", color: "bg-destructive" },
};

const DOC_TYPES = [
  { value: "contrato", label: "Contrato" },
  { value: "foto", label: "Foto" },
  { value: "documento", label: "Documento" },
  { value: "laudo", label: "Laudo" },
  { value: "comprovante", label: "Comprovante" },
  { value: "outro", label: "Outro" },
];

const RentalsTab = () => {
  const [contracts, setContracts] = useState<RentalContract[]>([]);
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [properties, setProperties] = useState<Property[]>([]);
  const [documents, setDocuments] = useState<ContractDoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<RentalContract | null>(null);
  const [viewingDocs, setViewingDocs] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [uploadFiles, setUploadFiles] = useState<File[]>([]);
  const [uploadDocType, setUploadDocType] = useState("contrato");
  const [form, setForm] = useState({
    property_id: "", tenant_id: "", start_date: "", end_date: "",
    monthly_rent: 0, deposit_amount: 0, payment_day: 5, status: "ativo",
    late_fee_percentage: 2, adjustment_index: "IGPM", notes: "",
    commission_rate: 10,
  });

  const fetchAll = async () => {
    const [{ data: c }, { data: t }, { data: p }] = await Promise.all([
      adminSelect("rental_contracts", { order: { column: "created_at", ascending: false } }),
      adminSelect("tenants", { select: "id, name", order: { column: "name", ascending: true } }),
      adminSelect("properties", { select: "id, title", order: { column: "title", ascending: true } }),
    ]);
    setContracts((c as RentalContract[]) || []);
    setTenants((t as Tenant[]) || []);
    setProperties((p as Property[]) || []);
    setLoading(false);
  };

  const fetchDocs = async (contractId: string) => {
    const { data } = await adminSelect("contract_documents", { match: { contract_id: contractId }, order: { column: "created_at", ascending: false } });
    setDocuments((data as ContractDoc[]) || []);
  };

  useEffect(() => { fetchAll(); }, []);

  const openNew = () => {
    setEditing(null);
    setForm({ property_id: "", tenant_id: "", start_date: "", end_date: "", monthly_rent: 0, deposit_amount: 0, payment_day: 5, status: "ativo", late_fee_percentage: 2, adjustment_index: "IGPM", notes: "", commission_rate: 10 });
    setShowForm(true);
  };

  const openEdit = (c: RentalContract) => {
    setEditing(c);
    setForm({
      property_id: c.property_id || "", tenant_id: c.tenant_id || "",
      start_date: c.start_date, end_date: c.end_date,
      monthly_rent: Number(c.monthly_rent), deposit_amount: Number(c.deposit_amount) || 0,
      payment_day: c.payment_day, status: c.status,
      late_fee_percentage: Number(c.late_fee_percentage) || 2,
      adjustment_index: c.adjustment_index || "IGPM", notes: c.notes || "",
      commission_rate: Number(c.commission_rate) || 10,
    });
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const commissionValue = (form.monthly_rent * form.commission_rate) / 100;
    const payload = {
      property_id: form.property_id || null, tenant_id: form.tenant_id || null,
      start_date: form.start_date, end_date: form.end_date,
      monthly_rent: form.monthly_rent, deposit_amount: form.deposit_amount || null,
      payment_day: form.payment_day, status: form.status as any,
      late_fee_percentage: form.late_fee_percentage,
      adjustment_index: form.adjustment_index || null, notes: form.notes || null,
      user_id: user.id,
      commission_rate: form.commission_rate,
      commission_value: commissionValue,
    };

    if (editing) {
      const { error } = await adminUpdate("rental_contracts", payload, { id: editing.id });
      if (error) { toast.error("Erro ao atualizar contrato"); return; }
      toast.success("Contrato atualizado!");
    } else {
      const { error } = await adminInsert("rental_contracts", payload);
      if (error) { toast.error("Erro ao criar contrato"); return; }
      toast.success("Contrato criado!");
    }
    setShowForm(false);
    fetchAll();
  };

  const deleteContract = async (id: string) => {
    if (!confirm("Excluir este contrato e todos os documentos?")) return;

    // 1) Remove contract docs (storage + table)
    const { data: docs, error: docsError } = await adminSelect("contract_documents", { match: { contract_id: id } });
    if (docsError) {
      toast.error(docsError.message || "Erro ao buscar documentos do contrato");
      return;
    }

    if (Array.isArray(docs) && docs.length > 0) {
      const paths = docs
        .map((d) => (d as ContractDoc).file_path)
        .filter(Boolean);

      if (paths.length > 0) {
        const { error: storageError } = await supabase.storage.from("contract-documents").remove(paths);
        if (storageError) {
          toast.error(storageError.message || "Erro ao remover arquivos do contrato");
          return;
        }
      }

      const { error: docsDeleteError } = await adminDelete("contract_documents", { contract_id: id });
      if (docsDeleteError) {
        toast.error(docsDeleteError.message || "Erro ao remover documentos do contrato");
        return;
      }
    }

    // 2) Unlink dependent rows that reference this contract
    const unlinkOps = await Promise.all([
      adminUpdate("financial_transactions", { contract_id: null }, { contract_id: id }),
      adminUpdate("property_inspections", { contract_id: null }, { contract_id: id }),
    ]);

    const unlinkError = unlinkOps.find((op) => op.error)?.error;
    if (unlinkError) {
      toast.error(unlinkError.message || "Erro ao desvincular dependências do contrato");
      return;
    }

    // 3) Delete contract
    const { error } = await adminDelete("rental_contracts", { id });
    if (error) {
      toast.error(error.message || "Erro ao excluir contrato");
      return;
    }

    toast.success("Contrato excluído");
    fetchAll();
  };

  const uploadDocument = async (contractId: string) => {
    if (uploadFiles.length === 0) return;
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    for (const file of uploadFiles) {
      const ext = file.name.split(".").pop();
      const path = `${user.id}/${contractId}/${crypto.randomUUID()}.${ext}`;
      const { error: uploadError } = await supabase.storage.from("contract-documents").upload(path, file);
      if (uploadError) { toast.error(`Erro ao enviar ${file.name}`); continue; }
      await adminInsert("contract_documents", {
        contract_id: contractId, file_path: path, file_name: file.name,
        file_type: file.type, document_type: uploadDocType, user_id: user.id,
      });
    }
    toast.success("Documentos enviados!");
    setUploadFiles([]);
    fetchDocs(contractId);
  };

  const deleteDoc = async (doc: ContractDoc) => {
    await supabase.storage.from("contract-documents").remove([doc.file_path]);
    await adminDelete("contract_documents", { id: doc.id });
    toast.success("Documento removido");
    if (viewingDocs) fetchDocs(viewingDocs);
  };

  const getDocUrl = async (filePath: string) => {
    const { data } = await supabase.storage.from("contract-documents").createSignedUrl(filePath, 3600);
    if (data?.signedUrl) window.open(data.signedUrl, "_blank");
  };

  const getTenantName = (id: string | null) => tenants.find(t => t.id === id)?.name || "—";
  const getPropertyTitle = (id: string | null) => properties.find(p => p.id === id)?.title || "—";

  const filtered = contracts.filter(c => {
    if (search) {
      const tenantName = getTenantName(c.tenant_id).toLowerCase();
      const propTitle = getPropertyTitle(c.property_id).toLowerCase();
      if (!tenantName.includes(search.toLowerCase()) && !propTitle.includes(search.toLowerCase())) return false;
    }
    return true;
  });

  const totalMonthly = contracts.filter(c => c.status === "ativo").reduce((s, c) => s + Number(c.monthly_rent), 0);
  const totalCommission = contracts.filter(c => c.status === "ativo").reduce((s, c) => s + (Number(c.commission_value) || 0), 0);
  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  // Document viewer
  if (viewingDocs) {
    const contract = contracts.find(c => c.id === viewingDocs);
    return (
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-xl font-bold text-foreground">Documentos do Contrato</h2>
            <p className="text-sm text-muted-foreground">Inquilino: {getTenantName(contract?.tenant_id || null)} • Imóvel: {getPropertyTitle(contract?.property_id || null)}</p>
          </div>
          <button onClick={() => setViewingDocs(null)} className="px-4 py-2 rounded-xl border border-input text-sm text-muted-foreground hover:bg-secondary"><X size={16} className="inline mr-1" /> Voltar</button>
        </div>

        {/* Upload area */}
        <div className="bg-card rounded-xl border border-border p-4 mb-6">
          <div className="flex items-center gap-4">
            <select value={uploadDocType} onChange={e => setUploadDocType(e.target.value)} className="px-3 py-2 rounded-lg bg-secondary/30 border border-input text-sm">
              {DOC_TYPES.map(d => <option key={d.value} value={d.value}>{d.label}</option>)}
            </select>
            <label className="flex-1 flex items-center gap-2 px-4 py-3 rounded-xl border-2 border-dashed border-primary/30 cursor-pointer hover:bg-primary/5 transition-all">
              <Upload size={16} className="text-primary" />
              <span className="text-sm text-muted-foreground">{uploadFiles.length > 0 ? `${uploadFiles.length} arquivo(s) selecionado(s)` : "Selecionar arquivos"}</span>
              <input type="file" multiple className="hidden" onChange={e => setUploadFiles(Array.from(e.target.files || []))} />
            </label>
            {uploadFiles.length > 0 && (
              <button onClick={() => uploadDocument(viewingDocs)} className="gradient-primary text-primary-foreground px-4 py-2 rounded-xl font-bold text-sm">Enviar</button>
            )}
          </div>
        </div>

        {/* Document list */}
        {documents.length === 0 ? (
          <div className="text-center py-16 text-muted-foreground">
            <FileText size={48} className="mx-auto mb-4 opacity-30" />
            <p>Nenhum documento enviado.</p>
          </div>
        ) : (
          <div className="space-y-2">
            {documents.map(doc => (
              <div key={doc.id} className="bg-card rounded-xl border border-border p-4 flex items-center gap-4">
                <div className="w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center">
                  <FileText size={18} className="text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-foreground truncate">{doc.file_name}</p>
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <span className="px-2 py-0.5 rounded-full bg-secondary font-medium">{DOC_TYPES.find(d => d.value === doc.document_type)?.label || doc.document_type}</span>
                    <span>{new Date(doc.created_at).toLocaleDateString("pt-BR")}</span>
                  </div>
                </div>
                <div className="flex gap-1.5">
                  <button onClick={() => getDocUrl(doc.file_path)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Eye size={14} /></button>
                  <button onClick={() => deleteDoc(doc)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
                </div>
              </div>
            ))}
          </div>
        )}
      </motion.div>
    );
  }

  if (showForm) {
    return (
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-2xl">
        <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
          <div className="gradient-primary px-6 py-5 flex items-center justify-between">
            <div>
              <h2 className="font-display text-lg font-bold text-primary-foreground">{editing ? "Editar Contrato" : "Novo Contrato"}</h2>
              <p className="text-primary-foreground/60 text-xs">Dados do contrato de aluguel</p>
            </div>
            <button onClick={() => setShowForm(false)} className="text-primary-foreground/60 hover:text-primary-foreground"><X size={20} /></button>
          </div>
          <form onSubmit={handleSubmit} className="p-6 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Imóvel</label>
                <select value={form.property_id} onChange={e => setForm({ ...form, property_id: e.target.value })} className={inputClass}>
                  <option value="">Selecione...</option>
                  {properties.map(p => <option key={p.id} value={p.id}>{p.title}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Inquilino</label>
                <select value={form.tenant_id} onChange={e => setForm({ ...form, tenant_id: e.target.value })} className={inputClass}>
                  <option value="">Selecione...</option>
                  {tenants.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Data Início *</label>
                <input type="date" required value={form.start_date} onChange={e => setForm({ ...form, start_date: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Data Fim *</label>
                <input type="date" required value={form.end_date} onChange={e => setForm({ ...form, end_date: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Aluguel Mensal (R$) *</label>
                <input type="number" required min={0} value={form.monthly_rent || ""} onChange={e => setForm({ ...form, monthly_rent: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Caução (R$)</label>
                <input type="number" min={0} value={form.deposit_amount || ""} onChange={e => setForm({ ...form, deposit_amount: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Dia Vencimento</label>
                <input type="number" min={1} max={31} value={form.payment_day} onChange={e => setForm({ ...form, payment_day: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Multa Atraso (%)</label>
                <input type="number" step="0.1" min={0} value={form.late_fee_percentage} onChange={e => setForm({ ...form, late_fee_percentage: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Comissão (%)</label>
                <input type="number" step="0.1" min={0} value={form.commission_rate} onChange={e => setForm({ ...form, commission_rate: Number(e.target.value) })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Índice Reajuste</label>
                <select value={form.adjustment_index} onChange={e => setForm({ ...form, adjustment_index: e.target.value })} className={inputClass}>
                  <option value="IGPM">IGP-M</option>
                  <option value="IPCA">IPCA</option>
                  <option value="INPC">INPC</option>
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Status</label>
                <select value={form.status} onChange={e => setForm({ ...form, status: e.target.value })} className={inputClass}>
                  {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                </select>
              </div>
            </div>
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Observações</label>
              <textarea rows={3} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={`${inputClass} resize-none`} />
            </div>
            {form.monthly_rent > 0 && (
              <div className="bg-primary/5 rounded-xl p-4 border border-primary/20">
                <p className="text-sm text-foreground">Comissão mensal estimada: <span className="font-bold text-primary">{((form.monthly_rent * form.commission_rate) / 100).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</span></p>
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
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-2xl font-bold text-foreground">{contracts.length}</p>
          <p className="text-xs text-muted-foreground">Total Contratos</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-2xl font-bold text-green-600">{contracts.filter(c => c.status === "ativo").length}</p>
          <p className="text-xs text-muted-foreground">Ativos</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-lg font-bold text-primary">{totalMonthly.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
          <p className="text-xs text-muted-foreground">Receita Mensal</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-lg font-bold text-accent">{totalCommission.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
          <p className="text-xs text-muted-foreground">Comissão Mensal</p>
        </div>
      </div>

      <div className="flex items-center justify-between gap-4">
        <div className="flex-1 relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar contratos..." className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-secondary/30 border border-input text-sm text-foreground focus:ring-2 focus:ring-primary/30 outline-none" />
        </div>
        <button onClick={openNew} className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 shadow-lg shadow-primary/20">
          <Plus size={16} /> Novo Contrato
        </button>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <Home size={48} className="mx-auto mb-4 opacity-30" />
          <p>Nenhum contrato encontrado.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((c, i) => {
            const statusInfo = STATUS_LABELS[c.status] || { label: c.status, color: "bg-muted" };
            return (
              <motion.div key={c.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.03 }}
                className="bg-card rounded-xl border border-border hover:border-primary/20 hover:shadow-md transition-all p-4 flex items-center gap-4">
                <div className={`w-2 h-12 rounded-full ${statusInfo.color}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-semibold text-sm text-foreground">{getPropertyTitle(c.property_id)}</span>
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${statusInfo.color} text-white`}>{statusInfo.label}</span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    <span>Inquilino: {getTenantName(c.tenant_id)}</span>
                    <span className="flex items-center gap-1"><Calendar size={11} /> {new Date(c.start_date).toLocaleDateString("pt-BR")} - {new Date(c.end_date).toLocaleDateString("pt-BR")}</span>
                    <span className="text-primary font-bold flex items-center gap-1"><DollarSign size={11} /> {Number(c.monthly_rent).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}/mês</span>
                    {c.commission_value ? <span className="text-accent font-medium">Comissão: {Number(c.commission_value).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</span> : null}
                    <span>Venc. dia {c.payment_day}</span>
                  </div>
                </div>
                <div className="flex items-center gap-1.5">
                  <button onClick={() => { setViewingDocs(c.id); fetchDocs(c.id); }} title="Documentos" className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><FileText size={14} /></button>
                  <button onClick={() => openEdit(c)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Edit size={14} /></button>
                  <button onClick={() => deleteContract(c.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default RentalsTab;
