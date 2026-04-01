import { motion } from "framer-motion";
import { Edit, Trash2, Star, Eye, EyeOff, MapPin, BedDouble, Bath, Maximize2, ImageIcon, Plus, Search, Building2, Car, DoorOpen } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { adminUpdate, adminDelete, adminStorageDelete } from "@/lib/adminCrud";
import { toast } from "sonner";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];

interface PropertyListProps {
  properties: (Property & { media: MediaRow[] })[];
  onEdit: (property: Property & { media: MediaRow[] }) => void;
  onRefresh: () => void;
  onNew: () => void;
}

const PropertyList = ({ properties, onEdit, onRefresh, onNew }: PropertyListProps) => {
  const getMediaUrl = (filePath: string) => {
    const { data } = supabase.storage.from("property-media").getPublicUrl(filePath);
    return data.publicUrl;
  };

  const deleteProperty = async (id: string) => {
    if (!confirm("Tem certeza que deseja remover este imóvel?")) return;
    const prop = properties.find((p) => p.id === id);
    if (prop) {
      for (const m of prop.media) {
        await adminStorageDelete("property-media", [m.file_path]);
      }
    }
    await adminDelete("properties", { id });
    toast.success("Imóvel removido!");
    onRefresh();
  };

  const toggleActive = async (p: Property) => {
    await adminUpdate("properties", { active: !p.active }, { id: p.id });
    toast.success(p.active ? "Imóvel desativado" : "Imóvel ativado");
    onRefresh();
  };

  const toggleFeatured = async (p: Property) => {
    await adminUpdate("properties", { featured: !p.featured }, { id: p.id });
    toast.success(p.featured ? "Removido dos destaques" : "Adicionado aos destaques");
    onRefresh();
  };

  const stats = {
    total: properties.length,
    active: properties.filter((p) => p.active).length,
    featured: properties.filter((p) => p.featured).length,
    venda: properties.filter((p) => p.status === "venda").length,
    aluguel: properties.filter((p) => p.status === "aluguel").length,
  };

  return (
    <div className="space-y-6">
      {/* Stats bar */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {[
          { label: "Total", value: stats.total, color: "text-foreground" },
          { label: "Ativos", value: stats.active, color: "text-green-600" },
          { label: "Destaques", value: stats.featured, color: "text-primary" },
          { label: "Venda", value: stats.venda, color: "text-accent" },
          { label: "Aluguel", value: stats.aluguel, color: "text-primary" },
        ].map((stat) => (
          <div key={stat.label} className="bg-card rounded-xl border border-border p-4 text-center">
            <p className={`font-display text-2xl font-bold ${stat.color}`}>{stat.value}</p>
            <p className="text-xs text-muted-foreground font-medium">{stat.label}</p>
          </div>
        ))}
      </div>

      {/* Header */}
      <div className="flex items-center justify-between">
        <h2 className="font-display text-lg font-bold text-foreground">Seus Imóveis</h2>
        <button
          onClick={onNew}
          className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 shadow-lg shadow-primary/20 transition-all"
        >
          <Plus size={16} /> Novo Imóvel
        </button>
      </div>

      {/* Empty state */}
      {properties.length === 0 ? (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          className="text-center py-20 bg-card rounded-2xl border border-border"
        >
          <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
            <Building2 size={28} className="text-primary" />
          </div>
          <p className="text-foreground font-semibold text-lg mb-1">Nenhum imóvel cadastrado</p>
          <p className="text-muted-foreground text-sm mb-6">Comece adicionando seu primeiro imóvel.</p>
          <button onClick={onNew} className="gradient-primary text-primary-foreground px-6 py-3 rounded-xl font-bold text-sm hover:opacity-90 inline-flex items-center gap-2">
            <Plus size={16} /> Cadastrar Imóvel
          </button>
        </motion.div>
      ) : (
        <div className="space-y-3">
          {properties.map((p, index) => (
            <motion.div
              key={p.id}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.05 }}
              className={`bg-card rounded-xl border border-border hover:border-primary/20 hover:shadow-lg transition-all p-4 flex gap-4 ${!p.active ? "opacity-60" : ""}`}
            >
              {/* Thumbnail */}
              <div className="w-28 h-28 rounded-xl overflow-hidden bg-secondary shrink-0">
                {p.media[0] ? (
                  <img src={getMediaUrl(p.media[0].file_path)} alt="" className="w-full h-full object-cover" />
                ) : (
                  <div className="w-full h-full flex items-center justify-center">
                    <ImageIcon size={24} className="text-muted-foreground/40" />
                  </div>
                )}
              </div>

              {/* Content */}
              <div className="flex-1 min-w-0">
                <div className="flex items-start gap-2 mb-1">
                  <h3 className="font-display font-bold text-foreground truncate text-sm">{p.title}</h3>
                  {(p as any).short_code && (
                    <span className="text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-muted text-muted-foreground border border-border shrink-0">
                      {(p as any).short_code}
                    </span>
                  )}
                  <div className="flex gap-1.5 shrink-0">
                    {p.featured && (
                      <span className="inline-flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider gradient-primary text-primary-foreground px-2 py-0.5 rounded-full">
                        <Star size={10} className="fill-current" /> Destaque
                      </span>
                    )}
                    <span className={`text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full ${
                      p.status === "venda" ? "bg-accent/10 text-accent" : "bg-primary/10 text-primary"
                    }`}>
                      {p.status}
                    </span>
                    {!p.active && (
                      <span className="text-[10px] font-bold uppercase tracking-wider bg-destructive/10 text-destructive px-2 py-0.5 rounded-full">
                        Inativo
                      </span>
                    )}
                  </div>
                </div>

                <p className="text-xs text-muted-foreground flex items-center gap-1 mb-2">
                  <MapPin size={12} /> {p.address}
                </p>

                <div className="flex items-center gap-4 text-xs text-muted-foreground mb-2">
                  <span className="flex items-center gap-1"><BedDouble size={12} className="text-blue-500" /> {p.bedrooms} quartos</span>
                  <span className="flex items-center gap-1"><DoorOpen size={12} className="text-purple-500" /> {(p as any).suites || 0} suítes</span>
                  <span className="flex items-center gap-1"><Bath size={12} className="text-cyan-500" /> {p.bathrooms} banheiros</span>
                  <span className="flex items-center gap-1"><Car size={12} className="text-amber-500" /> {(p as any).garage_spots || 0} vagas</span>
                  <span className="flex items-center gap-1"><Maximize2 size={12} className="text-emerald-500" /> {Number(p.area)} m²</span>
                  <span className="flex items-center gap-1"><ImageIcon size={12} /> {p.media.length} mídias</span>
                </div>

                <p className="text-primary font-display font-bold text-base">
                  {Number(p.price).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
                </p>
              </div>

              {/* Actions */}
              <div className="flex flex-col gap-1.5 shrink-0">
                <button
                  onClick={() => onEdit(p)}
                  title="Editar"
                  className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary hover:bg-primary/5 transition-all"
                >
                  <Edit size={14} />
                </button>
                <button
                  onClick={() => toggleFeatured(p)}
                  title={p.featured ? "Remover destaque" : "Destacar"}
                  className={`p-2 rounded-lg border transition-all ${
                    p.featured ? "border-primary text-primary bg-primary/5" : "border-border text-muted-foreground hover:text-primary hover:border-primary hover:bg-primary/5"
                  }`}
                >
                  <Star size={14} className={p.featured ? "fill-current" : ""} />
                </button>
                <button
                  onClick={() => toggleActive(p)}
                  title={p.active ? "Desativar" : "Ativar"}
                  className="p-2 rounded-lg border border-border text-muted-foreground hover:text-foreground hover:border-foreground transition-all"
                >
                  {p.active ? <Eye size={14} /> : <EyeOff size={14} />}
                </button>
                <button
                  onClick={() => deleteProperty(p.id)}
                  title="Remover"
                  className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive hover:bg-destructive/5 transition-all"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </motion.div>
          ))}
        </div>
      )}
    </div>
  );
};

export default PropertyList;
