import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Search, SlidersHorizontal, Bed, Bath, Maximize, MapPin } from "lucide-react";
import { Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];
type PropertyWithMedia = Property & { media: MediaRow[] };

const propertyTypes = ["Todos", "Apartamento", "Casa", "Cobertura", "Terreno", "Sala Comercial"];
const statusOptions = ["Todos", "venda", "aluguel"];

const formatPrice = (price: number, status: string) => {
  const formatted = price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  return status === "aluguel" ? `${formatted}/mês` : formatted;
};

const getMediaUrl = (filePath: string) => {
  const { data } = supabase.storage.from("property-media").getPublicUrl(filePath);
  return data.publicUrl;
};

const Properties = () => {
  const [search, setSearch] = useState("");
  const [type, setType] = useState("Todos");
  const [status, setStatus] = useState("Todos");
  const [properties, setProperties] = useState<PropertyWithMedia[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchProperties = async () => {
      const { data } = await supabase
        .from("properties")
        .select("*")
        .eq("active", true)
        .order("featured", { ascending: false })
        .order("created_at", { ascending: false });

      if (!data) { setLoading(false); return; }

      const withMedia = await Promise.all(
        data.map(async (p) => {
          const { data: media } = await supabase
            .from("property_media")
            .select("*")
            .eq("property_id", p.id)
            .order("sort_order");
          return { ...p, media: media || [] };
        })
      );
      setProperties(withMedia);
      setLoading(false);
    };
    fetchProperties();
  }, []);

  const filtered = properties.filter((p) => {
    const matchSearch =
      p.title.toLowerCase().includes(search.toLowerCase()) ||
      p.address.toLowerCase().includes(search.toLowerCase());
    const matchType = type === "Todos" || p.type === type;
    const matchStatus = status === "Todos" || p.status === status;
    return matchSearch && matchType && matchStatus;
  });

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="pt-24 section-padding">
        <div className="container-custom">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="text-center mb-12">
            <h1 className="font-display text-3xl sm:text-4xl font-bold text-foreground">Nossos Imóveis</h1>
            <p className="text-muted-foreground mt-3">Encontre o imóvel ideal para você em Fortaleza e região.</p>
          </motion.div>

          <div className="glass-card rounded-xl p-4 mb-10 flex flex-col sm:flex-row gap-4 items-center">
            <div className="relative flex-1 w-full">
              <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input type="text" placeholder="Buscar por nome ou localização..." value={search} onChange={(e) => setSearch(e.target.value)} className="w-full pl-9 pr-4 py-2.5 rounded-lg bg-background border border-input text-sm text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
            </div>
            <select value={type} onChange={(e) => setType(e.target.value)} className="px-4 py-2.5 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none">
              {propertyTypes.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
            <select value={status} onChange={(e) => setStatus(e.target.value)} className="px-4 py-2.5 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none capitalize">
              {statusOptions.map((s) => <option key={s} value={s}>{s === "Todos" ? "Todos" : s === "venda" ? "Venda" : "Aluguel"}</option>)}
            </select>
          </div>

          {loading ? (
            <div className="text-center py-20">
              <p className="text-muted-foreground animate-pulse">Carregando imóveis...</p>
            </div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-20">
              <SlidersHorizontal className="mx-auto text-muted-foreground mb-4" size={48} />
              <p className="text-muted-foreground">Nenhum imóvel encontrado.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
              {filtered.map((property, i) => (
                <motion.div
                  key={property.id}
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: i * 0.1 }}
                >
                  <Link to={`/imoveis/${property.id}`} className="block group hover-lift rounded-xl overflow-hidden glass-card">
                    <div className="relative h-64 overflow-hidden bg-secondary">
                      {property.media[0] ? (
                        <img src={getMediaUrl(property.media[0].file_path)} alt={property.title} className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500" />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-muted-foreground">Sem foto</div>
                      )}
                      <div className="absolute top-3 left-3 flex gap-2">
                        <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">{property.status}</span>
                        <span className="bg-accent text-accent-foreground text-xs font-semibold px-3 py-1 rounded-full">{property.type}</span>
                      </div>
                    </div>
                    <div className="p-5">
                      <p className="text-primary font-bold text-xl mb-1">{formatPrice(Number(property.price), property.status)}</p>
                      <h3 className="font-display text-lg font-semibold text-foreground mb-1">{property.title}</h3>
                      <p className="text-muted-foreground text-sm flex items-center gap-1 mb-4"><MapPin size={14} /> {property.address}</p>
                      <div className="flex items-center gap-5 text-foreground text-sm font-medium border-t border-border pt-4">
                        <span className="flex items-center gap-2"><Bed size={18} className="text-primary" /> {property.bedrooms}</span>
                        <span className="flex items-center gap-2"><Bath size={18} className="text-primary" /> {property.bathrooms}</span>
                        <span className="flex items-center gap-2"><Maximize size={18} className="text-primary" /> {Number(property.area)}m²</span>
                      </div>
                    </div>
                  </Link>
                </motion.div>
              ))}
            </div>
          )}
        </div>
      </div>
      <Footer />
      <ChatWidget />
    </div>
  );
};

export default Properties;
