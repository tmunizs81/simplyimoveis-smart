import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { motion } from "framer-motion";
import { Plus, Search, ClipboardCheck, Calendar, Home, Edit, Trash2, X, Save, Upload, FileText, Eye, Camera, Video, File } from "lucide-react";

type Inspection = {
  id: string; property_id: string; contract_id: string | null;
  tenant_id: string | null; inspection_type: string; inspection_date: string;
  inspector_name: string | null; status: string; general_notes: string | null;
  rooms_condition: string | null; electrical_condition: string | null;
  plumbing_condition: string | null; painting_condition: string | null;
  floor_condition: string | null; keys_delivered: number | null;
  meter_reading_water: string | null; meter_reading_electricity: string | null;
  meter_reading_gas: string | null; created_at: string; user_id: string;
};

type InspectionMedia = {
  id: string; inspection_id: string; file_path: string; file_name: string;
  file_type: string; media_category: string; notes: string | null; created_at: string;
};

type Property = { id: string; title: string; address: string };
type Tenant = { id: string; name: string };
type Contract = { id: string; property_id: string | null; tenant_id: string | null };

const CONDITION_OPTIONS = ["Ótimo", "Bom", "Regular", "Ruim", "Não se aplica"];
const MEDIA_CATEGORIES = [
  { value: "geral", label: "Geral" },
  { value: "sala", label: "Sala" },
  { value: "quarto", label: "Quarto" },
  { value: "cozinha", label: "Cozinha" },
  { value: "banheiro", label: "Banheiro" },
  { value: "area_externa", label: "Área Externa" },
  { value: "garagem", label: "Garagem" },
  { value: "fachada", label: "Fachada" },
  { value: "termo_vistoria", label: "Termo de Vistoria" },
  { value: "outro", label: "Outro" },
];

const STATUS_LABELS: Record<string, { label: string; color: string }> = {
  pendente: { label: "Pendente", color: "bg-amber-500" },
  em_andamento: { label: "Em Andamento", color: "bg-blue-500" },
  concluida: { label: "Concluída", color: "bg-green-500" },
};

const InspectionsTab = () => {
  const [inspections, setInspections] = useState<Inspection[]>([]);
  const [properties, setProperties] = useState<Property[]>([]);
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [contracts, setContracts] = useState<Contract[]>([]);
  const [media, setMedia] = useState<InspectionMedia[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Inspection | null>(null);
  const [viewingMedia, setViewingMedia] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [uploadFiles, setUploadFiles] = useState<File[]>([]);
  const [uploadCategory, setUploadCategory] = useState("geral");
  const [form, setForm] = useState({
    property_id: "", contract_id: "", tenant_id: "",
    inspection_type: "entrada", inspection_date: new Date().toISOString().slice(0, 10),
    inspector_name: "", status: "pendente",
    general_notes: "", rooms_condition: "Bom", electrical_condition: "Bom",
    plumbing_condition: "Bom", painting_condition: "Bom", floor_condition: "Bom",
    keys_delivered: 0, meter_reading_water: "", meter_reading_electricity: "", meter_reading_gas: "",
  });

  const fetchAll = async () => {
    const [{ data: ins }, { data: props }, { data: ten }, { data: con }] = await Promise.all([
      supabase.from("property_inspections").select("*").order("inspection_date", { ascending: false }),
      supabase.from("properties").select("id, title, address").order("title"),
      supabase.from("tenants").select("id, name").order("name"),
      supabase.from("rental_contracts").select("id, property_id, tenant_id"),
    ]);
    setInspections((ins as Inspection[]) || []);
    setProperties((props as Property[]) || []);
    setTenants((ten as Tenant[]) || []);
    setContracts((con as Contract[]) || []);
    setLoading(false);
  };

  const fetchMedia = async (inspectionId: string) => {
    const { data } = await supabase.from("inspection_media").select("*").eq("inspection_id", inspectionId).order("created_at", { ascending: false });
    setMedia((data as InspectionMedia[]) || []);
  };

  useEffect(() => { fetchAll(); }, []);

  const openNew = () => {
    setEditing(null);
    setForm({
      property_id: "", contract_id: "", tenant_id: "",
      inspection_type: "entrada", inspection_date: new Date().toISOString().slice(0, 10),
      inspector_name: "", status: "pendente",
      general_notes: "", rooms_condition: "Bom", electrical_condition: "Bom",
      plumbing_condition: "Bom", painting_condition: "Bom", floor_condition: "Bom",
      keys_delivered: 0, meter_reading_water: "", meter_reading_electricity: "", meter_reading_gas: "",
    });
    setShowForm(true);
  };

  const openEdit = (ins: Inspection) => {
    setEditing(ins);
    setForm({
      property_id: ins.property_id, contract_id: ins.contract_id || "",
      tenant_id: ins.tenant_id || "", inspection_type: ins.inspection_type,
      inspection_date: ins.inspection_date, inspector_name: ins.inspector_name || "",
      status: ins.status, general_notes: ins.general_notes || "",
      rooms_condition: ins.rooms_condition || "Bom",
      electrical_condition: ins.electrical_condition || "Bom",
      plumbing_condition: ins.plumbing_condition || "Bom",
      painting_condition: ins.painting_condition || "Bom",
      floor_condition: ins.floor_condition || "Bom",
      keys_delivered: ins.keys_delivered || 0,
      meter_reading_water: ins.meter_reading_water || "",
      meter_reading_electricity: ins.meter_reading_electricity || "",
      meter_reading_gas: ins.meter_reading_gas || "",
    });
    setShowForm(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const payload = {
      property_id: form.property_id, contract_id: form.contract_id || null,
      tenant_id: form.tenant_id || null, inspection_type: form.inspection_type,
      inspection_date: form.inspection_date, inspector_name: form.inspector_name || null,
      status: form.status, general_notes: form.general_notes || null,
      rooms_condition: form.rooms_condition, electrical_condition: form.electrical_condition,
      plumbing_condition: form.plumbing_condition, painting_condition: form.painting_condition,
      floor_condition: form.floor_condition, keys_delivered: form.keys_delivered,
      meter_reading_water: form.meter_reading_water || null,
      meter_reading_electricity: form.meter_reading_electricity || null,
      meter_reading_gas: form.meter_reading_gas || null, user_id: user.id,
    };

    if (editing) {
      const { error } = await supabase.from("property_inspections").update(payload as any).eq("id", editing.id);
      if (error) { toast.error("Erro ao atualizar vistoria"); return; }
      toast.success("Vistoria atualizada!");
    } else {
      const { error } = await supabase.from("property_inspections").insert(payload as any);
      if (error) { toast.error("Erro ao criar vistoria"); return; }
      toast.success("Vistoria criada!");
    }
    setShowForm(false);
    fetchAll();
  };

  const deleteInspection = async (id: string) => {
    if (!confirm("Excluir esta vistoria e todas as mídias?")) return;
    await supabase.from("property_inspections").delete().eq("id", id);
    toast.success("Vistoria excluída");
    fetchAll();
  };

  const uploadMedia = async (inspectionId: string) => {
    if (uploadFiles.length === 0) return;
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    for (const file of uploadFiles) {
      const ext = file.name.split(".").pop();
      const path = `${user.id}/${inspectionId}/${crypto.randomUUID()}.${ext}`;
      const { error } = await supabase.storage.from("inspection-media").upload(path, file);
      if (error) { toast.error(`Erro: ${file.name}`); continue; }
      await supabase.from("inspection_media").insert({
        inspection_id: inspectionId, file_path: path, file_name: file.name,
        file_type: file.type, media_category: uploadCategory, user_id: user.id,
      } as any);
    }
    toast.success("Mídias enviadas!");
    setUploadFiles([]);
    fetchMedia(inspectionId);
  };

  const deleteMediaItem = async (item: InspectionMedia) => {
    await supabase.storage.from("inspection-media").remove([item.file_path]);
    await supabase.from("inspection_media").delete().eq("id", item.id);
    toast.success("Mídia removida");
    if (viewingMedia) fetchMedia(viewingMedia);
  };

  const viewFile = async (filePath: string) => {
    const { data } = await supabase.storage.from("inspection-media").createSignedUrl(filePath, 3600);
    if (data?.signedUrl) window.open(data.signedUrl, "_blank");
  };

  const getPropertyTitle = (id: string | null) => properties.find(p => p.id === id)?.title || "—";
  const getTenantName = (id: string | null) => tenants.find(t => t.id === id)?.name || "—";

  const getFileIcon = (fileType: string) => {
    if (fileType.startsWith("image")) return <Camera size={18} className="text-blue-500" />;
    if (fileType.startsWith("video")) return <Video size={18} className="text-purple-500" />;
    if (fileType.includes("pdf")) return <File size={18} className="text-destructive" />;
    return <FileText size={18} className="text-primary" />;
  };

  const filtered = inspections.filter(ins => {
    if (search) {
      const propTitle = getPropertyTitle(ins.property_id).toLowerCase();
      const tenantName = getTenantName(ins.tenant_id).toLowerCase();
      if (!propTitle.includes(search.toLowerCase()) && !tenantName.includes(search.toLowerCase())) return false;
    }
    return true;
  });

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";
  const selectClass = inputClass;

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  // Media viewer
  if (viewingMedia) {
    const inspection = inspections.find(i => i.id === viewingMedia);
    return (
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}>
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-xl font-bold text-foreground">Mídias da Vistoria</h2>
            <p className="text-sm text-muted-foreground">
              {getPropertyTitle(inspection?.property_id || null)} •
              {inspection?.inspection_type === "entrada" ? " Entrada" : " Saída"} •
              {inspection?.inspection_date ? ` ${new Date(inspection.inspection_date).toLocaleDateString("pt-BR")}` : ""}
            </p>
          </div>
          <button onClick={() => setViewingMedia(null)} className="px-4 py-2 rounded-xl border border-input text-sm text-muted-foreground hover:bg-secondary">
            <X size={16} className="inline mr-1" /> Voltar
          </button>
        </div>

        {/* Upload area */}
        <div className="bg-card rounded-xl border border-border p-4 mb-6">
          <h3 className="text-sm font-semibold text-foreground mb-3 flex items-center gap-2"><Upload size={16} className="text-primary" /> Enviar Fotos, Vídeos e PDFs</h3>
          <div className="flex items-center gap-4 flex-wrap">
            <select value={uploadCategory} onChange={e => setUploadCategory(e.target.value)} className="px-3 py-2 rounded-lg bg-secondary/30 border border-input text-sm">
              {MEDIA_CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
            </select>
            <label className="flex-1 min-w-[200px] flex items-center gap-2 px-4 py-3 rounded-xl border-2 border-dashed border-primary/30 cursor-pointer hover:bg-primary/5 transition-all">
              <Upload size={16} className="text-primary" />
              <span className="text-sm text-muted-foreground">{uploadFiles.length > 0 ? `${uploadFiles.length} arquivo(s)` : "Fotos, vídeos ou PDFs"}</span>
              <input type="file" multiple accept="image/*,video/*,.pdf" className="hidden" onChange={e => setUploadFiles(Array.from(e.target.files || []))} />
            </label>
            {uploadFiles.length > 0 && (
              <button onClick={() => uploadMedia(viewingMedia)} className="gradient-primary text-primary-foreground px-4 py-2 rounded-xl font-bold text-sm">Enviar</button>
            )}
          </div>
          <p className="text-[10px] text-muted-foreground mt-2">Aceita: JPG, PNG, MP4, MOV, PDF (fotos, vídeos, termos de vistoria)</p>
        </div>

        {/* Media grid */}
        {media.length === 0 ? (
          <div className="text-center py-16 text-muted-foreground">
            <Camera size={48} className="mx-auto mb-4 opacity-30" />
            <p>Nenhuma mídia enviada para esta vistoria.</p>
          </div>
        ) : (
          <div>
            {/* Group by category */}
            {MEDIA_CATEGORIES.filter(cat => media.some(m => m.media_category === cat.value)).map(cat => (
              <div key={cat.value} className="mb-6">
                <h4 className="text-sm font-semibold text-foreground mb-3 flex items-center gap-2 pb-2 border-b border-border">
                  {cat.label} <span className="text-muted-foreground font-normal">({media.filter(m => m.media_category === cat.value).length})</span>
                </h4>
                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
                  {media.filter(m => m.media_category === cat.value).map(item => (
                    <div key={item.id} className="bg-card rounded-xl border border-border overflow-hidden group relative">
                      <div className="aspect-square bg-secondary flex items-center justify-center">
                        {item.file_type.startsWith("image") ? (
                          <div className="w-full h-full bg-muted flex items-center justify-center text-muted-foreground text-xs">
                            {getFileIcon(item.file_type)}
                            <span className="ml-1">Imagem</span>
                          </div>
                        ) : (
                          <div className="flex flex-col items-center gap-1">
                            {getFileIcon(item.file_type)}
                            <span className="text-[10px] text-muted-foreground truncate max-w-full px-2">{item.file_name}</span>
                          </div>
                        )}
                      </div>
                      <div className="p-2">
                        <p className="text-[10px] text-muted-foreground truncate">{item.file_name}</p>
                      </div>
                      <div className="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-all flex items-center justify-center gap-2">
                        <button onClick={() => viewFile(item.file_path)} className="p-2 rounded-lg bg-white/20 text-white hover:bg-white/30"><Eye size={16} /></button>
                        <button onClick={() => deleteMediaItem(item)} className="p-2 rounded-lg bg-white/20 text-white hover:bg-destructive/80"><Trash2 size={16} /></button>
                      </div>
                    </div>
                  ))}
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
      <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-3xl">
        <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
          <div className="gradient-primary px-6 py-5 flex items-center justify-between">
            <div>
              <h2 className="font-display text-lg font-bold text-primary-foreground">{editing ? "Editar Vistoria" : "Nova Vistoria"}</h2>
              <p className="text-primary-foreground/60 text-xs">Registro completo da vistoria do imóvel</p>
            </div>
            <button onClick={() => setShowForm(false)} className="text-primary-foreground/60 hover:text-primary-foreground"><X size={20} /></button>
          </div>
          <form onSubmit={handleSubmit} className="p-6 space-y-6">
            {/* Basic info */}
            <div className="space-y-4">
              <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
                <Home size={16} className="text-primary" /> Dados da Vistoria
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Imóvel *</label>
                  <select required value={form.property_id} onChange={e => setForm({ ...form, property_id: e.target.value })} className={selectClass}>
                    <option value="">Selecione o imóvel...</option>
                    {properties.map(p => <option key={p.id} value={p.id}>{p.title} - {p.address}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Inquilino</label>
                  <select value={form.tenant_id} onChange={e => setForm({ ...form, tenant_id: e.target.value })} className={selectClass}>
                    <option value="">Selecione...</option>
                    {tenants.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Contrato</label>
                  <select value={form.contract_id} onChange={e => setForm({ ...form, contract_id: e.target.value })} className={selectClass}>
                    <option value="">Nenhum</option>
                    {contracts.map(c => <option key={c.id} value={c.id}>{getPropertyTitle(c.property_id)} - {getTenantName(c.tenant_id)}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Tipo</label>
                  <select value={form.inspection_type} onChange={e => setForm({ ...form, inspection_type: e.target.value })} className={selectClass}>
                    <option value="entrada">Entrada</option>
                    <option value="saida">Saída</option>
                    <option value="periodica">Periódica</option>
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Data *</label>
                  <input type="date" required value={form.inspection_date} onChange={e => setForm({ ...form, inspection_date: e.target.value })} className={inputClass} />
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Vistoriador</label>
                  <input value={form.inspector_name} onChange={e => setForm({ ...form, inspector_name: e.target.value })} className={inputClass} placeholder="Nome do vistoriador" />
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Status</label>
                  <select value={form.status} onChange={e => setForm({ ...form, status: e.target.value })} className={selectClass}>
                    {Object.entries(STATUS_LABELS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Chaves Entregues</label>
                  <input type="number" min={0} value={form.keys_delivered} onChange={e => setForm({ ...form, keys_delivered: Number(e.target.value) })} className={inputClass} />
                </div>
              </div>
            </div>

            {/* Conditions */}
            <div className="space-y-4">
              <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
                <ClipboardCheck size={16} className="text-primary" /> Condições do Imóvel
              </h3>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                {[
                  { key: "rooms_condition", label: "Cômodos" },
                  { key: "electrical_condition", label: "Elétrica" },
                  { key: "plumbing_condition", label: "Hidráulica" },
                  { key: "painting_condition", label: "Pintura" },
                  { key: "floor_condition", label: "Pisos" },
                ].map(field => (
                  <div key={field.key}>
                    <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">{field.label}</label>
                    <select value={(form as any)[field.key]} onChange={e => setForm({ ...form, [field.key]: e.target.value })} className={selectClass}>
                      {CONDITION_OPTIONS.map(o => <option key={o} value={o}>{o}</option>)}
                    </select>
                  </div>
                ))}
              </div>
            </div>

            {/* Meter readings */}
            <div className="space-y-4">
              <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
                📊 Leituras de Medidores
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Água</label>
                  <input value={form.meter_reading_water} onChange={e => setForm({ ...form, meter_reading_water: e.target.value })} className={inputClass} placeholder="Leitura" />
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Energia</label>
                  <input value={form.meter_reading_electricity} onChange={e => setForm({ ...form, meter_reading_electricity: e.target.value })} className={inputClass} placeholder="Leitura" />
                </div>
                <div>
                  <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Gás</label>
                  <input value={form.meter_reading_gas} onChange={e => setForm({ ...form, meter_reading_gas: e.target.value })} className={inputClass} placeholder="Leitura" />
                </div>
              </div>
            </div>

            {/* Notes */}
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Observações Gerais</label>
              <textarea rows={4} value={form.general_notes} onChange={e => setForm({ ...form, general_notes: e.target.value })} className={`${inputClass} resize-none`} placeholder="Descreva o estado geral do imóvel, danos, pendências..." />
            </div>

            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowForm(false)} className="flex-1 py-3 rounded-xl border border-input text-muted-foreground font-semibold text-sm hover:bg-secondary transition-all">Cancelar</button>
              <button type="submit" className="flex-1 gradient-primary text-primary-foreground py-3 rounded-xl font-bold text-sm hover:opacity-90 flex items-center justify-center gap-2">
                <Save size={16} /> Salvar Vistoria
              </button>
            </div>
          </form>
        </div>
      </motion.div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-2xl font-bold text-foreground">{inspections.length}</p>
          <p className="text-xs text-muted-foreground">Total Vistorias</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-2xl font-bold text-green-600">{inspections.filter(i => i.status === "concluida").length}</p>
          <p className="text-xs text-muted-foreground">Concluídas</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-4 text-center">
          <p className="font-display text-2xl font-bold text-amber-500">{inspections.filter(i => i.status === "pendente").length}</p>
          <p className="text-xs text-muted-foreground">Pendentes</p>
        </div>
      </div>

      <div className="flex items-center justify-between gap-4">
        <div className="flex-1 relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar por imóvel ou inquilino..." className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-secondary/30 border border-input text-sm text-foreground focus:ring-2 focus:ring-primary/30 outline-none" />
        </div>
        <button onClick={openNew} className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 shadow-lg shadow-primary/20">
          <Plus size={16} /> Nova Vistoria
        </button>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <ClipboardCheck size={48} className="mx-auto mb-4 opacity-30" />
          <p>Nenhuma vistoria registrada.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((ins, i) => {
            const statusInfo = STATUS_LABELS[ins.status] || { label: ins.status, color: "bg-muted" };
            return (
              <motion.div key={ins.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.03 }}
                className="bg-card rounded-xl border border-border hover:border-primary/20 hover:shadow-md transition-all p-4 flex items-center gap-4">
                <div className={`w-2 h-12 rounded-full ${statusInfo.color}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-semibold text-sm text-foreground">{getPropertyTitle(ins.property_id)}</span>
                    <span className={`text-[10px] font-bold uppercase px-2 py-0.5 rounded-full ${statusInfo.color} text-white`}>{statusInfo.label}</span>
                    <span className="text-[10px] px-2 py-0.5 rounded-full bg-secondary text-muted-foreground font-medium capitalize">{ins.inspection_type}</span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-muted-foreground">
                    <span className="flex items-center gap-1"><Calendar size={11} /> {new Date(ins.inspection_date).toLocaleDateString("pt-BR")}</span>
                    {ins.tenant_id && <span>Inquilino: {getTenantName(ins.tenant_id)}</span>}
                    {ins.inspector_name && <span>Vistoriador: {ins.inspector_name}</span>}
                  </div>
                </div>
                <div className="flex items-center gap-1.5">
                  <button onClick={() => { setViewingMedia(ins.id); fetchMedia(ins.id); }} title="Fotos e Documentos" className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Camera size={14} /></button>
                  <button onClick={() => openEdit(ins)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all"><Edit size={14} /></button>
                  <button onClick={() => deleteInspection(ins.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all"><Trash2 size={14} /></button>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default InspectionsTab;
