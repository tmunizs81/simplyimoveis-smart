import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminInsert, adminUpdate, adminDelete, adminSelect, adminStorageUpload, adminStorageDelete, adminStorageSignedUrl } from "@/lib/adminCrud";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { Plus, Search, Users, Phone, Mail, Edit, Trash2, X, Save, FileText, Upload, Eye, FolderOpen } from "lucide-react";

type Tenant = {
  id: string; name: string; email: string | null; phone: string | null;
  cpf_cnpj: string | null; rg: string | null; address: string | null;
  notes: string | null; created_at: string; user_id: string;
};

type TenantDoc = {
  id: string; tenant_id: string; file_path: string; file_name: string;
  file_type: string; document_type: string; notes: string | null; created_at: string;
};

const DOC_TYPES = [
  { value: "rg", label: "RG" },
  { value: "cpf", label: "CPF" },
  { value: "comprovante_residencia", label: "Comprovante Residência" },
  { value: "comprovante_renda", label: "Comprovante Renda" },
  { value: "contrato_trabalho", label: "Contrato Trabalho" },
  { value: "certidao", label: "Certidão" },
  { value: "procuracao", label: "Procuração" },
  { value: "outro", label: "Outro" },
];

const TenantsTab = () => {
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Tenant | null>(null);
  const [search, setSearch] = useState("");
  const [viewingDocs, setViewingDocs] = useState<string | null>(null);
  const [documents, setDocuments] = useState<TenantDoc[]>([]);
  const [uploadFiles, setUploadFiles] = useState<File[]>([]);
  const [uploadDocType, setUploadDocType] = useState("rg");
  const [formFiles, setFormFiles] = useState<{ file: File; docType: string }[]>([]);
  const [formDocType, setFormDocType] = useState("rg");
  const [form, setForm] = useState({
    name: "", email: "", phone: "", cpf_cnpj: "", rg: "", address: "", notes: "",
  });

  const fetchTenants = async () => {
    const { data, error } = await adminSelect("tenants", { order: { column: "name", ascending: true } });
    if (error) toast.error("Erro ao carregar inquilinos");
    else setTenants((data as Tenant[]) || []);
    setLoading(false);
  };

  const fetchDocs = async (tenantId: string) => {
    const { data } = await adminSelect("tenant_documents", { match: { tenant_id: tenantId }, order: { column: "created_at", ascending: false } });
    setDocuments((data as TenantDoc[]) || []);
  };

  useEffect(() => { fetchTenants(); }, []);

  const openNew = () => {
    setEditing(null);
    setForm({ name: "", email: "", phone: "", cpf_cnpj: "", rg: "", address: "", notes: "" });
    setFormFiles([]);
    setFormDocType("rg");
    setShowForm(true);
  };

  const openEdit = (t: Tenant) => {
    setEditing(t);
    setForm({
      name: t.name, email: t.email || "", phone: t.phone || "",
      cpf_cnpj: t.cpf_cnpj || "", rg: t.rg || "", address: t.address || "", notes: t.notes || "",
    });
    setFormFiles([]);
    setFormDocType("rg");
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const payload = {
      name: form.name, email: form.email || null, phone: form.phone || null,
      cpf_cnpj: form.cpf_cnpj || null, rg: form.rg || null,
      address: form.address || null, notes: form.notes || null, user_id: user.id,
    };

    let tenantId: string;

    if (editing) {
      const { error } = await adminUpdate("tenants", payload, { id: editing.id });
      if (error) { toast.error(error.message || "Erro ao atualizar"); return; }
      tenantId = editing.id;
    } else {
      const { data: inserted, error } = await adminInsert("tenants", payload);
      if (error || !inserted?.[0]) { toast.error(error?.message || "Erro ao cadastrar"); return; }
      tenantId = inserted[0].id;
    }

    // Upload form documents
    if (formFiles.length > 0) {
      for (const { file, docType } of formFiles) {
        const ext = file.name.split(".").pop();
        const path = `${user.id}/${tenantId}/${crypto.randomUUID()}.${ext}`;
        const { error: upErr } = await adminStorageUpload("tenant-documents", path, file);
        if (upErr) { toast.error(`Erro: ${file.name}`); continue; }
        await adminInsert("tenant_documents", {
          tenant_id: tenantId, file_path: path, file_name: file.name,
          file_type: file.type, document_type: docType, user_id: user.id,
        });
      }
    }

    toast.success(editing ? "Inquilino atualizado!" : "Inquilino cadastrado!");
    setFormFiles([]);
    setShowForm(false);
    fetchTenants();
  };

  const deleteTenant = async (id: string) => {
    if (!confirm("Excluir este inquilino e todos os documentos?")) return;

    // 1) Remove tenant docs (storage + table)
    const { data: docs, error: docsError } = await adminSelect("tenant_documents", { match: { tenant_id: id } });
    if (docsError) {
      toast.error(docsError.message || "Erro ao buscar documentos do inquilino");
      return;
    }

    if (Array.isArray(docs) && docs.length > 0) {
      const paths = docs
        .map((d) => (d as TenantDoc).file_path)
        .filter(Boolean);

      if (paths.length > 0) {
        const { error: storageError } = await adminStorageDelete("tenant-documents", paths);
        if (storageError) {
          toast.error(storageError.message || "Erro ao remover arquivos do inquilino");
          return;
        }
      }

      const { error: docsDeleteError } = await adminDelete("tenant_documents", { tenant_id: id });
      if (docsDeleteError) {
        toast.error(docsDeleteError.message || "Erro ao remover documentos do inquilino");
        return;
      }
    }

    // 2) Unlink dependent rows
    const unlinkOps = await Promise.all([
      adminUpdate("rental_contracts", { tenant_id: null }, { tenant_id: id }),
      adminUpdate("property_inspections", { tenant_id: null }, { tenant_id: id }),
      adminUpdate("financial_transactions", { tenant_id: null }, { tenant_id: id }),
    ]);

    const unlinkError = unlinkOps.find((op) => op.error)?.error;
    if (unlinkError) {
      toast.error(unlinkError.message || "Erro ao desvincular dependências do inquilino");
      return;
    }

    // 3) Delete tenant
    const { error } = await adminDelete("tenants", { id });
    if (error) {
      toast.error(error.message || "Erro ao excluir inquilino");
      return;
    }

    toast.success("Inquilino excluído");
    fetchTenants();
  };

  const uploadDocument = async (tenantId: string) => {
    if (uploadFiles.length === 0) return;
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    for (const file of uploadFiles) {
      const ext = file.name.split(".").pop();
      const path = `${user.id}/${tenantId}/${crypto.randomUUID()}.${ext}`;
      const { error: uploadError } = await adminStorageUpload("tenant-documents", path, file);
      if (uploadError) { toast.error(`Erro ao enviar ${file.name}`); continue; }
      await adminInsert("tenant_documents", {
        tenant_id: tenantId, file_path: path, file_name: file.name,
        file_type: file.type, document_type: uploadDocType, user_id: user.id,
      });
    }
    toast.success("Documentos enviados!");
    setUploadFiles([]);
    fetchDocs(tenantId);
  };

  const deleteDoc = async (doc: TenantDoc) => {
    await supabase.storage.from("tenant-documents").remove([doc.file_path]);
    await adminDelete("tenant_documents", { id: doc.id });
    toast.success("Documento removido");
    if (viewingDocs) fetchDocs(viewingDocs);
  };

  const viewDoc = async (filePath: string) => {
    const { data } = await supabase.storage.from("tenant-documents").createSignedUrl(filePath, 3600);
    if (data?.signedUrl) window.open(data.signedUrl, "_blank");
  };

  const filtered = tenants.filter(t => {
    if (search && !t.name.toLowerCase().includes(search.toLowerCase()) && !t.cpf_cnpj?.includes(search) && !t.email?.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  // Document viewer for tenant
  if (viewingDocs) {
    const tenant = tenants.find(t => t.id === viewingDocs);
    return (
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-xl font-bold text-foreground">Documentos do Inquilino</h2>
            <p className="text-sm text-muted-foreground">{tenant?.name} • {tenant?.cpf_cnpj || "CPF não informado"}</p>
          </div>
          <button onClick={() => setViewingDocs(null)} className="px-4 py-2 rounded-xl border border-input text-sm text-muted-foreground hover:bg-secondary">
            <X size={16} className="inline mr-1" /> Voltar
          </button>
        </div>

        {/* Upload area */}
        <div className="bg-card rounded-xl border border-border p-4 mb-6">
          <h3 className="text-sm font-semibold text-foreground mb-3 flex items-center gap-2"><Upload size={16} className="text-primary" /> Enviar Documentos</h3>
          <div className="flex items-center gap-4">
            <select value={uploadDocType} onChange={e => setUploadDocType(e.target.value)} className="px-3 py-2 rounded-lg bg-secondary/30 border border-input text-sm">
              {DOC_TYPES.map(d => <option key={d.value} value={d.value}>{d.label}</option>)}
            </select>
            <label className="flex-1 flex items-center gap-2 px-4 py-3 rounded-xl border-2 border-dashed border-primary/30 cursor-pointer hover:bg-primary/5 transition-all">
              <Upload size={16} className="text-primary" />
              <span className="text-sm text-muted-foreground">{uploadFiles.length > 0 ? `${uploadFiles.length} arquivo(s)` : "Selecionar arquivos"}</span>
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
            <FolderOpen size={48} className="mx-auto mb-4 opacity-30" />
            <p>Nenhum documento enviado para este inquilino.</p>
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
                  <button onClick={() => viewDoc(doc.file_path)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Eye size={14} /></button>
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
              <h2 className="font-display text-lg font-bold text-primary-foreground">{editing ? "Editar Inquilino" : "Novo Inquilino"}</h2>
              <p className="text-primary-foreground/60 text-xs">Dados do cliente/inquilino</p>
            </div>
            <button onClick={() => setShowForm(false)} className="text-primary-foreground/60 hover:text-primary-foreground"><X size={20} /></button>
          </div>
          <form onSubmit={handleSubmit} className="p-6 space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Nome Completo *</label>
                <input required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} className={inputClass} placeholder="Nome completo" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">CPF/CNPJ</label>
                <input value={form.cpf_cnpj} onChange={e => setForm({ ...form, cpf_cnpj: e.target.value })} className={inputClass} placeholder="000.000.000-00" />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">RG</label>
                <input value={form.rg} onChange={e => setForm({ ...form, rg: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">E-mail</label>
                <input type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} className={inputClass} />
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Telefone</label>
                <input value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} className={inputClass} placeholder="(85) 99999-9999" />
              </div>
              <div className="md:col-span-2">
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Endereço</label>
                <input value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} className={inputClass} />
              </div>
            </div>
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Observações</label>
              <textarea rows={3} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} className={`${inputClass} resize-none`} />
            </div>
            {/* Document Upload */}
            <div className="space-y-3 pt-2 border-t border-border">
              <h3 className="text-xs font-bold text-muted-foreground uppercase tracking-wider flex items-center gap-2">
                <Upload size={14} className="text-primary" /> Documentos do Inquilino
              </h3>
              <div className="flex items-center gap-3 flex-wrap">
                <select value={formDocType} onChange={e => setFormDocType(e.target.value)} className="px-3 py-2 rounded-lg bg-secondary/30 border border-input text-sm">
                  {DOC_TYPES.map(d => <option key={d.value} value={d.value}>{d.label}</option>)}
                </select>
                <label className="flex-1 min-w-[180px] flex items-center gap-2 px-4 py-3 rounded-xl border-2 border-dashed border-primary/30 cursor-pointer hover:bg-primary/5 transition-all">
                  <Upload size={16} className="text-primary" />
                  <span className="text-sm text-muted-foreground">Selecionar arquivos</span>
                  <input type="file" multiple className="hidden" onChange={e => {
                    const files = Array.from(e.target.files || []);
                    setFormFiles(prev => [...prev, ...files.map(f => ({ file: f, docType: formDocType }))]);
                    e.target.value = "";
                  }} />
                </label>
              </div>
              {formFiles.length > 0 && (
                <div className="space-y-1.5">
                  {formFiles.map((item, idx) => (
                    <div key={idx} className="flex items-center gap-3 bg-secondary/20 rounded-lg px-3 py-2 text-sm">
                      <FileText size={14} className="text-primary" />
                      <span className="flex-1 truncate text-foreground">{item.file.name}</span>
                      <span className="text-xs text-muted-foreground px-2 py-0.5 rounded-full bg-secondary">
                        {DOC_TYPES.find(d => d.value === item.docType)?.label}
                      </span>
                      <button type="button" onClick={() => setFormFiles(prev => prev.filter((_, i) => i !== idx))} className="text-muted-foreground hover:text-destructive">
                        <X size={14} />
                      </button>
                    </div>
                  ))}
                  <p className="text-xs text-muted-foreground">{formFiles.length} documento(s) serão enviados ao salvar</p>
                </div>
              )}
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
      <div className="flex items-center justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-foreground">Inquilinos</h2>
          <p className="text-muted-foreground text-sm">{tenants.length} cadastrado{tenants.length !== 1 ? "s" : ""}</p>
        </div>
        <button onClick={openNew} className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 shadow-lg shadow-primary/20">
          <Plus size={16} /> Novo Inquilino
        </button>
      </div>

      <div className="relative">
        <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar por nome, CPF ou email..." className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-secondary/30 border border-input text-sm text-foreground focus:ring-2 focus:ring-primary/30 outline-none" />
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <Users size={48} className="mx-auto mb-4 opacity-30" />
          <p>Nenhum inquilino encontrado.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((t, i) => (
            <motion.div key={t.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.03 }}
              className="bg-card rounded-xl border border-border hover:border-primary/20 hover:shadow-md transition-all p-4 flex items-center gap-4">
              <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center text-primary font-bold text-sm">
                {t.name.charAt(0).toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-sm text-foreground truncate">{t.name}</p>
                <div className="flex items-center gap-3 text-xs text-muted-foreground">
                  {t.cpf_cnpj && <span>{t.cpf_cnpj}</span>}
                  {t.email && <span className="flex items-center gap-1"><Mail size={11} /> {t.email}</span>}
                  {t.phone && <span className="flex items-center gap-1"><Phone size={11} /> {t.phone}</span>}
                </div>
              </div>
              <div className="flex items-center gap-1.5">
                <button onClick={() => { setViewingDocs(t.id); fetchDocs(t.id); }} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-blue-600 hover:border-blue-400 transition-all" title="Documentos"><FolderOpen size={14} /></button>
                <button onClick={() => openEdit(t)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Edit size={14} /></button>
                <button onClick={() => deleteTenant(t.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
              </div>
            </motion.div>
          ))}
        </div>
      )}
    </div>
  );
};

export default TenantsTab;
