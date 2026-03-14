import { useState } from "react";
import { motion } from "framer-motion";
import { Save, X, Upload, Video, Image, Trash2, Star, MapPin, DollarSign, Maximize2, BedDouble, Bath, Home, FileText, Tag, Car, DoorOpen, Waves, Navigation } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
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

const PropertyForm = ({ editingProperty, userId, onSaved, onCancel }: PropertyFormProps) => {
  const [saving, setSaving] = useState(false);
  const [mediaFiles, setMediaFiles] = useState<File[]>([]);
  const [mediaPreviews, setMediaPreviews] = useState<string[]>([]);
  const [existingMedia, setExistingMedia] = useState<MediaRow[]>(editingProperty?.media || []);
  const [form, setForm] = useState({
    title: editingProperty?.title || "",
    address: editingProperty?.address || "",
    neighborhood: (editingProperty as any)?.neighborhood || "",
    city: (editingProperty as any)?.city || "Fortaleza",
    price: editingProperty ? Number(editingProperty.price) : 0,
    bedrooms: editingProperty?.bedrooms ?? 1,
    suites: (editingProperty as any)?.suites ?? 0,
    bathrooms: editingProperty?.bathrooms ?? 1,
    garage_spots: (editingProperty as any)?.garage_spots ?? 0,
    area: editingProperty ? Number(editingProperty.area) : 0,
    pool_size: (editingProperty as any)?.pool_size ? Number((editingProperty as any).pool_size) : 0,
    nearby_points: (editingProperty as any)?.nearby_points || "",
    type: (editingProperty?.type || "Apartamento") as typeof PROPERTY_TYPES[number],
    status: (editingProperty?.status || "venda") as "venda" | "aluguel",
    description: editingProperty?.description || "",
    featured: editingProperty?.featured ?? false,
    active: editingProperty?.active ?? true,
  });

  const getMediaUrl = (filePath: string) => {
    const { data } = supabase.storage.from("property-media").getPublicUrl(filePath);
    return data.publicUrl;
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    setMediaFiles((prev) => [...prev, ...files]);
    files.forEach((f) => {
      if (f.type.startsWith("image")) {
        const reader = new FileReader();
        reader.onload = (ev) => setMediaPreviews((p) => [...p, ev.target?.result as string]);
        reader.readAsDataURL(f);
      } else {
        setMediaPreviews((p) => [...p, "video"]);
      }
    });
  };

  const removeNewFile = (index: number) => {
    setMediaFiles((prev) => prev.filter((_, i) => i !== index));
    setMediaPreviews((prev) => prev.filter((_, i) => i !== index));
  };

  const deleteExistingMedia = async (media: MediaRow) => {
    await supabase.storage.from("property-media").remove([media.file_path]);
    await supabase.from("property_media").delete().eq("id", media.id);
    setExistingMedia((prev) => prev.filter((m) => m.id !== media.id));
    toast.success("Mídia removida!");
  };

  const uploadMedia = async (propertyId: string) => {
    for (let i = 0; i < mediaFiles.length; i++) {
      const file = mediaFiles[i];
      const ext = file.name.split(".").pop();
      const path = `${userId}/${propertyId}/${crypto.randomUUID()}.${ext}`;
      const { error } = await supabase.storage.from("property-media").upload(path, file);
      if (error) { toast.error(`Erro ao enviar ${file.name}`); continue; }
      const fileType = file.type.startsWith("video") ? "video" : "image";
      await supabase.from("property_media").insert({
        property_id: propertyId, file_path: path, file_type: fileType,
        sort_order: existingMedia.length + i,
      });
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      if (editingProperty) {
        const { error } = await supabase.from("properties").update({
          title: form.title, address: form.address,
          neighborhood: form.neighborhood || null, city: form.city || null,
          price: form.price, bedrooms: form.bedrooms, suites: form.suites,
          bathrooms: form.bathrooms, garage_spots: form.garage_spots, area: form.area,
          pool_size: form.pool_size, nearby_points: form.nearby_points || null,
          type: form.type, status: form.status, description: form.description,
          featured: form.featured, active: form.active,
        } as any).eq("id", editingProperty.id);
        if (error) throw error;
        if (mediaFiles.length) await uploadMedia(editingProperty.id);
        toast.success("Imóvel atualizado!");
      } else {
        const { data, error } = await supabase.from("properties").insert({
          user_id: userId, title: form.title, address: form.address,
          neighborhood: form.neighborhood || null, city: form.city || null,
          price: form.price, bedrooms: form.bedrooms, suites: form.suites,
          bathrooms: form.bathrooms, garage_spots: form.garage_spots,
          area: form.area, pool_size: form.pool_size, nearby_points: form.nearby_points || null,
          type: form.type, status: form.status,
          description: form.description, featured: form.featured, active: form.active,
        } as any).select().single();
        if (error) throw error;
        if (mediaFiles.length && data) await uploadMedia(data.id);
        toast.success("Imóvel cadastrado!");
      }
      onSaved();
    } catch (err: any) {
      toast.error(err.message || "Erro ao salvar");
    } finally {
      setSaving(false);
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
                      <img src={getMediaUrl(m.file_path)} alt="" className="w-full h-full object-cover rounded-xl border border-border" />
                    ) : (
                      <div className="w-full h-full bg-secondary rounded-xl border border-border flex items-center justify-center">
                        <Video size={24} className="text-muted-foreground" />
                      </div>
                    )}
                    <button
                      type="button"
                      onClick={() => deleteExistingMedia(m)}
                      className="absolute inset-0 bg-destructive/80 rounded-xl flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all"
                    >
                      <Trash2 size={16} className="text-destructive-foreground" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* New file previews */}
          {mediaPreviews.length > 0 && (
            <div>
              <p className="text-xs font-medium text-muted-foreground mb-2">Novos arquivos ({mediaPreviews.length})</p>
              <div className="grid grid-cols-4 sm:grid-cols-6 gap-3">
                {mediaPreviews.map((preview, i) => (
                  <div key={i} className="relative group aspect-square">
                    {preview === "video" ? (
                      <div className="w-full h-full bg-secondary rounded-xl border border-border flex items-center justify-center">
                        <Video size={24} className="text-muted-foreground" />
                      </div>
                    ) : (
                      <img src={preview} alt="" className="w-full h-full object-cover rounded-xl border border-border" />
                    )}
                    <button
                      type="button"
                      onClick={() => removeNewFile(i)}
                      className="absolute inset-0 bg-destructive/80 rounded-xl flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all"
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
              <p className="text-xs text-muted-foreground">Fotos (JPG, PNG) ou Vídeos (MP4)</p>
            </div>
            <input type="file" multiple accept="image/*,video/*" onChange={handleFileSelect} className="sr-only" />
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
