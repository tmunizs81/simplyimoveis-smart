import { useCallback, useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { Save, X, Upload, Video, Image, Trash2, Star, MapPin, DollarSign, Maximize2, BedDouble, Bath, Home, FileText, Tag, Car, DoorOpen, Waves, Navigation, CheckCircle2, AlertCircle, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { deletePropertyMediaItem, savePropertyWithMedia, type PropertyFormValues } from "@/lib/propertyFormService";
import { getMediaUrl } from "@/lib/mediaUrl";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];

const PROPERTY_TYPES = ["Apartamento", "Casa", "Cobertura", "Terreno", "Sala Comercial"] as const;

interface PropertyFormProps {
  editingProperty?: (Property & { media: MediaRow[] }) | null;
  userId: string;
  onSaved: () => void;
  onCancel: () => void;
}

type PendingMediaItem = {
  id: string;
  file: File;
  fileType: "image" | "video";
  previewUrl: string | null;
  uploadStatus?: "pending" | "uploading" | "registering" | "done" | "error";
};

const buildInitialForm = (
  editingProperty?: (Property & { media: MediaRow[] }) | null
): PropertyFormValues => ({
  title: editingProperty?.title || "",
  address: editingProperty?.address || "",
  neighborhood: editingProperty?.neighborhood || "",
  city: editingProperty?.city || "Fortaleza",
  price: editingProperty ? Number(editingProperty.price) : 0,
  bedrooms: editingProperty?.bedrooms ?? 1,
  suites: editingProperty?.suites ?? 0,
  bathrooms: editingProperty?.bathrooms ?? 1,
  garage_spots: editingProperty?.garage_spots ?? 0,
  area: editingProperty ? Number(editingProperty.area) : 0,
  pool_size: editingProperty?.pool_size ? Number(editingProperty.pool_size) : 0,
  nearby_points: editingProperty?.nearby_points || "",
  type: editingProperty?.type || "Apartamento",
  status: editingProperty?.status || "venda",
  description: editingProperty?.description || "",
  featured: editingProperty?.featured ?? false,
  active: editingProperty?.active ?? true,
});

const revokePendingMediaItem = (item: PendingMediaItem) => {
  if (item.previewUrl) {
    URL.revokeObjectURL(item.previewUrl);
  }
};

const createPendingMediaItem = (file: File): PendingMediaItem | null => {
  if (!file.type.startsWith("image/") && !file.type.startsWith("video/")) {
    return null;
  }

  return {
    id: crypto.randomUUID(),
    file,
    fileType: file.type.startsWith("video/") ? "video" : "image",
    previewUrl: file.type.startsWith("image/") ? URL.createObjectURL(file) : null,
  };
};

const PropertyForm = ({ editingProperty, userId, onSaved, onCancel }: PropertyFormProps) => {
  const [saving, setSaving] = useState(false);
  const [deletingMediaId, setDeletingMediaId] = useState<string | null>(null);
  const [pendingMedia, setPendingMedia] = useState<PendingMediaItem[]>([]);
  const [existingMedia, setExistingMedia] = useState<MediaRow[]>(editingProperty?.media || []);
  const [form, setForm] = useState<PropertyFormValues>(() => buildInitialForm(editingProperty));
  const [uploadProgress, setUploadProgress] = useState<{ current: number; total: number } | null>(null);
  const pendingMediaRef = useRef<PendingMediaItem[]>([]);

  useEffect(() => {
    pendingMediaRef.current = pendingMedia;
  }, [pendingMedia]);

  useEffect(() => {
    return () => {
      pendingMediaRef.current.forEach(revokePendingMediaItem);
    };
  }, []);

  const getMediaUrl = (filePath: string) => {
    const { data } = supabase.storage.from("property-media").getPublicUrl(filePath);
    return data.publicUrl;
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    const nextItems = files
      .map(createPendingMediaItem)
      .filter((item): item is PendingMediaItem => Boolean(item));

    if (nextItems.length !== files.length) {
      toast.error("Alguns arquivos foram ignorados. Envie apenas imagens ou vídeos válidos.");
    }

    if (nextItems.length > 0) {
      setPendingMedia((current) => [...current, ...nextItems]);
    }

    e.target.value = "";
  };

  const removeNewFile = (id: string) => {
    setPendingMedia((current) => {
      const item = current.find((entry) => entry.id === id);
      if (item) {
        revokePendingMediaItem(item);
      }

      return current.filter((entry) => entry.id !== id);
    });
  };

  const deleteExistingMedia = async (media: MediaRow) => {
    setDeletingMediaId(media.id);

    try {
      await deletePropertyMediaItem(media);
      setExistingMedia((current) => current.filter((entry) => entry.id !== media.id));
      toast.success("Mídia removida!");
    } catch (err: any) {
      toast.error(err.message || "Erro ao remover mídia");
    } finally {
      setDeletingMediaId(null);
    }
  };

  const handleFileProgress = useCallback((index: number, status: "uploading" | "registering" | "done" | "error", _fileName: string) => {
    setPendingMedia((current) =>
      current.map((item, i) => (i === index ? { ...item, uploadStatus: status } : item))
    );
    if (status === "uploading") {
      setUploadProgress((prev) => ({ current: index + 1, total: prev?.total ?? 0 }));
    }
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setUploadProgress(pendingMedia.length > 0 ? { current: 0, total: pendingMedia.length } : null);
    setPendingMedia((current) => current.map((item) => ({ ...item, uploadStatus: "pending" })));

    try {
      await savePropertyWithMedia({
        editingProperty,
        userId,
        form,
        mediaFiles: pendingMedia.map((item) => item.file),
        existingMediaCount: existingMedia.length,
        onFileProgress: handleFileProgress,
      });

      pendingMediaRef.current.forEach(revokePendingMediaItem);
      pendingMediaRef.current = [];
      setPendingMedia([]);
      setUploadProgress(null);
      toast.success(editingProperty ? "Imóvel atualizado!" : "Imóvel cadastrado!");
      onSaved();
    } catch (err: any) {
      toast.error(err.message || "Erro ao salvar");
    } finally {
      setSaving(false);
      setUploadProgress(null);
    }
  };

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";
  const labelClass = "flex items-center gap-1.5 text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5";

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -20 }}
      className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden"
    >
      {/* Form header */}
      <div className="gradient-primary px-6 py-5 flex items-center justify-between">
        <div>
          <h2 className="font-display text-lg font-bold text-primary-foreground">
            {editingProperty ? "Editar Imóvel" : "Novo Imóvel"}
          </h2>
          <p className="text-primary-foreground/60 text-xs">Preencha todos os campos obrigatórios</p>
        </div>
        <button onClick={onCancel} className="text-primary-foreground/60 hover:text-primary-foreground transition-colors">
          <X size={20} />
        </button>
      </div>

      <form onSubmit={handleSubmit} className="p-6 space-y-6">
        {/* Section: Basic info */}
        <div className="space-y-4">
          <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
            <Home size={16} className="text-primary" /> Informações Básicas
          </h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="md:col-span-2">
              <label className={labelClass}><FileText size={12} /> Título *</label>
              <input placeholder="Ex: Apartamento de Luxo em Porto das Dunas" required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} className={inputClass} />
            </div>
            <div className="md:col-span-2">
              <label className={labelClass}><MapPin size={12} /> Endereço *</label>
              <input placeholder="Ex: Rua das Palmeiras, 123 - Porto das Dunas" required value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><MapPin size={12} /> Bairro</label>
              <input placeholder="Ex: Porto das Dunas" value={form.neighborhood} onChange={(e) => setForm({ ...form, neighborhood: e.target.value })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><MapPin size={12} /> Cidade</label>
              <input placeholder="Ex: Fortaleza" value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><Tag size={12} /> Tipo</label>
              <select value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as any })} className={inputClass}>
                {PROPERTY_TYPES.map((t) => <option key={t}>{t}</option>)}
              </select>
            </div>
            <div>
              <label className={labelClass}><Tag size={12} /> Finalidade</label>
              <div className="flex gap-2">
                {(["venda", "aluguel"] as const).map((s) => (
                  <button
                    key={s}
                    type="button"
                    onClick={() => setForm({ ...form, status: s })}
                    className={`flex-1 py-3 rounded-xl text-sm font-semibold transition-all border ${
                      form.status === s
                        ? "gradient-primary text-primary-foreground border-transparent"
                        : "bg-secondary/30 text-muted-foreground border-input hover:border-primary/30"
                    }`}
                  >
                    {s === "venda" ? "Venda" : "Aluguel"}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Section: Details */}
        <div className="space-y-4">
          <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
            <Maximize2 size={16} className="text-primary" /> Detalhes do Imóvel
          </h3>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            <div>
              <label className={labelClass}><DollarSign size={12} /> Preço (R$) *</label>
              <input type="number" placeholder="0" required min={0} value={form.price || ""} onChange={(e) => setForm({ ...form, price: Number(e.target.value) })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><Maximize2 size={12} /> Área (m²) *</label>
              <input type="number" placeholder="0" required min={0} value={form.area || ""} onChange={(e) => setForm({ ...form, area: Number(e.target.value) })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><BedDouble size={12} /> Quartos</label>
              <input type="number" min={0} value={form.bedrooms} onChange={(e) => setForm({ ...form, bedrooms: Number(e.target.value) })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><DoorOpen size={12} /> Suítes</label>
              <input type="number" min={0} value={form.suites} onChange={(e) => setForm({ ...form, suites: Number(e.target.value) })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><Bath size={12} /> Banheiros</label>
              <input type="number" min={0} value={form.bathrooms} onChange={(e) => setForm({ ...form, bathrooms: Number(e.target.value) })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><Car size={12} /> Vagas Garagem</label>
              <input type="number" min={0} value={form.garage_spots} onChange={(e) => setForm({ ...form, garage_spots: Number(e.target.value) })} className={inputClass} />
            </div>
            <div>
              <label className={labelClass}><Waves size={12} /> Piscina (m²)</label>
              <input type="number" min={0} step="0.1" placeholder="0 = sem piscina" value={form.pool_size || ""} onChange={(e) => setForm({ ...form, pool_size: Number(e.target.value) })} className={inputClass} />
            </div>
          </div>
        </div>

        {/* Section: Location & Points of Interest */}
        <div className="space-y-4">
          <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
            <Navigation size={16} className="text-primary" /> Localização e Pontos de Interesse
          </h3>
          <textarea
            placeholder="Ex: Próximo ao Beach Park (5 min), Shopping Porto das Dunas (2 min), Farmácia, Supermercado, Escolas, Praia a 200m..."
            rows={3}
            value={form.nearby_points}
            onChange={(e) => setForm({ ...form, nearby_points: e.target.value })}
            className={`${inputClass} resize-none`}
          />
          <p className="text-[10px] text-muted-foreground">Descreva pontos de referência, comércios, lazer e facilidades próximas. A Luma usará essas informações para recomendar o imóvel.</p>
        </div>

        {/* Section: Description */}
        <div className="space-y-4">
          <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
            <FileText size={16} className="text-primary" /> Descrição
          </h3>
          <textarea
            placeholder="Descreva o imóvel com detalhes: características, diferenciais, localização..."
            rows={4}
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
            className={`${inputClass} resize-none`}
          />
        </div>

        {/* Section: Options */}
        <div className="space-y-4">
          <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
            <Star size={16} className="text-primary" /> Opções de Exibição
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label className={`flex items-center gap-3 p-4 rounded-xl border cursor-pointer transition-all ${
              form.featured ? "border-primary bg-primary/5" : "border-input bg-secondary/20 hover:border-primary/30"
            }`}>
              <input type="checkbox" checked={form.featured} onChange={(e) => setForm({ ...form, featured: e.target.checked })} className="sr-only" />
              <div className={`w-5 h-5 rounded-md border-2 flex items-center justify-center transition-all ${
                form.featured ? "bg-primary border-primary" : "border-muted-foreground/30"
              }`}>
                {form.featured && <Star size={12} className="text-primary-foreground fill-primary-foreground" />}
              </div>
              <div>
                <p className="text-sm font-semibold text-foreground">Destaque</p>
                <p className="text-xs text-muted-foreground">Aparece na seção de destaques</p>
              </div>
            </label>

            <label className={`flex items-center gap-3 p-4 rounded-xl border cursor-pointer transition-all ${
              form.active ? "border-green-500 bg-green-500/5" : "border-input bg-secondary/20 hover:border-primary/30"
            }`}>
              <input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} className="sr-only" />
              <div className={`w-5 h-5 rounded-md border-2 flex items-center justify-center transition-all ${
                form.active ? "bg-green-500 border-green-500" : "border-muted-foreground/30"
              }`}>
                {form.active && <div className="w-2 h-2 bg-primary-foreground rounded-sm" />}
              </div>
              <div>
                <p className="text-sm font-semibold text-foreground">Ativo</p>
                <p className="text-xs text-muted-foreground">Visível no site público</p>
              </div>
            </label>
          </div>
        </div>

        {/* Section: Media */}
        <div className="space-y-4">
          <h3 className="font-display text-sm font-bold text-foreground flex items-center gap-2 pb-2 border-b border-border">
            <Image size={16} className="text-primary" /> Fotos e Vídeos
          </h3>

          {/* Existing media */}
          {existingMedia.length > 0 && (
            <div>
              <p className="text-xs font-medium text-muted-foreground mb-2">Mídias atuais ({existingMedia.length})</p>
              <div className="grid grid-cols-4 sm:grid-cols-6 gap-3">
                {existingMedia.map((m) => (
                  <div key={m.id} className="relative group aspect-square">
                    {m.file_type === "image" ? (
                      <img src={getMediaUrl(m.file_path)} alt="Mídia já cadastrada do imóvel" className="w-full h-full object-cover rounded-xl border border-border" />
                    ) : (
                      <div className="w-full h-full bg-secondary rounded-xl border border-border flex items-center justify-center">
                        <Video size={24} className="text-muted-foreground" />
                      </div>
                    )}
                    <button
                      type="button"
                      disabled={saving || deletingMediaId === m.id}
                      onClick={() => deleteExistingMedia(m)}
                      className="absolute inset-0 bg-destructive/80 rounded-xl flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all disabled:cursor-not-allowed disabled:opacity-100"
                    >
                      {deletingMediaId === m.id ? (
                        <div className="w-4 h-4 border-2 border-destructive-foreground/40 border-t-destructive-foreground rounded-full animate-spin" />
                      ) : (
                        <Trash2 size={16} className="text-destructive-foreground" />
                      )}
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* New file previews */}
          {pendingMedia.length > 0 && (
            <div>
              <p className="text-xs font-medium text-muted-foreground mb-2">Novos arquivos ({pendingMedia.length})</p>
              {/* Upload progress bar */}
              {uploadProgress && (
                <div className="mb-3 space-y-1.5">
                  <div className="flex items-center justify-between text-xs text-muted-foreground">
                    <span>Enviando {uploadProgress.current} de {uploadProgress.total}</span>
                    <span>{Math.round((uploadProgress.current / uploadProgress.total) * 100)}%</span>
                  </div>
                  <div className="w-full h-2 bg-secondary rounded-full overflow-hidden">
                    <div
                      className="h-full bg-primary rounded-full transition-all duration-300"
                      style={{ width: `${(uploadProgress.current / uploadProgress.total) * 100}%` }}
                    />
                  </div>
                </div>
              )}
              <div className="grid grid-cols-4 sm:grid-cols-6 gap-3">
                {pendingMedia.map((item) => (
                  <div key={item.id} className="relative group aspect-square" title={item.file.name}>
                    {item.fileType === "video" ? (
                      <div className="w-full h-full bg-secondary rounded-xl border border-border flex items-center justify-center">
                        <Video size={24} className="text-muted-foreground" />
                      </div>
                    ) : (
                      <img src={item.previewUrl || ""} alt="Nova mídia selecionada" className="w-full h-full object-cover rounded-xl border border-border" />
                    )}
                    {/* Upload status overlay */}
                    {item.uploadStatus && item.uploadStatus !== "pending" && (
                      <div className={`absolute inset-0 rounded-xl flex flex-col items-center justify-center gap-1 text-[10px] font-bold ${
                        item.uploadStatus === "done"
                          ? "bg-green-500/80 text-white"
                          : item.uploadStatus === "error"
                            ? "bg-destructive/80 text-white"
                            : "bg-black/60 text-white"
                      }`}>
                        {item.uploadStatus === "uploading" && <><Loader2 size={16} className="animate-spin" /> Enviando</>}
                        {item.uploadStatus === "registering" && <><Loader2 size={16} className="animate-spin" /> Registrando</>}
                        {item.uploadStatus === "done" && <><CheckCircle2 size={16} /> OK</>}
                        {item.uploadStatus === "error" && <><AlertCircle size={16} /> Erro</>}
                      </div>
                    )}
                    <button
                      type="button"
                      disabled={saving}
                      onClick={() => removeNewFile(item.id)}
                      className={`absolute inset-0 bg-destructive/80 rounded-xl flex items-center justify-center transition-all ${
                        item.uploadStatus && item.uploadStatus !== "pending" ? "hidden" : "opacity-0 group-hover:opacity-100"
                      }`}
                    >
                      <Trash2 size={16} className="text-destructive-foreground" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Upload button */}
          <label className="flex flex-col items-center justify-center gap-2 p-8 rounded-xl border-2 border-dashed border-input hover:border-primary/50 bg-secondary/20 hover:bg-primary/5 cursor-pointer transition-all group">
            <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center group-hover:bg-primary/20 transition-colors">
              <Upload size={20} className="text-primary" />
            </div>
            <div className="text-center">
              <p className="text-sm font-semibold text-foreground">Clique para enviar</p>
              <p className="text-xs text-muted-foreground">Fotos e vídeos são enviados junto com o salvamento do imóvel</p>
            </div>
            <input type="file" multiple accept="image/*,video/*" onChange={handleFileSelect} className="sr-only" disabled={saving} />
          </label>
        </div>

        {/* Actions */}
        <div className="flex gap-3 pt-4 border-t border-border">
          <button
            type="submit"
            disabled={saving}
            className="flex-1 gradient-primary text-primary-foreground py-3.5 rounded-xl font-bold text-sm uppercase tracking-wider hover:opacity-90 disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-primary/20 transition-all"
          >
            {saving ? (
              <div className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
            ) : (
              <>
                <Save size={16} />
                {editingProperty ? "Salvar Alterações" : "Cadastrar Imóvel"}
              </>
            )}
          </button>
          <button
            type="button"
            onClick={onCancel}
            className="px-6 py-3.5 rounded-xl border border-border text-muted-foreground hover:bg-secondary font-medium text-sm transition-all"
          >
            Cancelar
          </button>
        </div>
      </form>
    </motion.div>
  );
};

export default PropertyForm;
