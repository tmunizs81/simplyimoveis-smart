import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Bed, Bath, Maximize, MapPin, Car, DoorOpen, Star } from "lucide-react";
import { Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { getMediaUrl } from "@/lib/mediaUrl";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];
type PropertyWithMedia = Property & { media: MediaRow[] };

const formatPrice = (price: number, status: string) => {
  const formatted = price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  return status === "aluguel" ? `${formatted}/mês` : formatted;
};

const FeaturedProperties = () => {
  const [properties, setProperties] = useState<PropertyWithMedia[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchFeatured = async () => {
      const { data } = await supabase
        .from("properties")
        .select("*")
        .eq("active", true)
        .eq("featured", true)
        .order("created_at", { ascending: false })
        .limit(6);

      if (!data || data.length === 0) {
        // Fallback: show latest properties if none are featured
        const { data: latest } = await supabase
          .from("properties")
          .select("*")
          .eq("active", true)
          .order("created_at", { ascending: false })
          .limit(3);
        if (latest) {
          const withMedia = await Promise.all(
            latest.map(async (p) => {
              const { data: media } = await supabase.from("property_media").select("*").eq("property_id", p.id).order("sort_order").limit(1);
              return { ...p, media: media || [] };
            })
          );
          setProperties(withMedia);
        }
      } else {
        const withMedia = await Promise.all(
          data.map(async (p) => {
            const { data: media } = await supabase.from("property_media").select("*").eq("property_id", p.id).order("sort_order").limit(1);
            return { ...p, media: media || [] };
          })
        );
        setProperties(withMedia);
      }
      setLoading(false);
    };
    fetchFeatured();
  }, []);

  if (loading) {
    return (
      <section className="section-padding bg-secondary/30">
        <div className="container-custom text-center">
          <p className="text-muted-foreground animate-pulse">Carregando imóveis...</p>
        </div>
      </section>
    );
  }

  if (properties.length === 0) {
    return (
      <section className="section-padding bg-secondary/30">
        <div className="container-custom text-center">
          <span className="text-primary text-sm font-semibold uppercase tracking-wider">Destaques</span>
          <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2">Imóveis em Destaque</h2>
          <p className="text-muted-foreground mt-6">Em breve novos imóveis disponíveis. Entre em contato!</p>
        </div>
      </section>
    );
  }

  return (
    <section className="section-padding bg-secondary/30">
      <div className="container-custom">
        <motion.div initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} className="text-center mb-12">
          <span className="text-primary text-sm font-semibold uppercase tracking-wider">Destaques</span>
          <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2">Imóveis em Destaque</h2>
          <p className="text-muted-foreground mt-3 max-w-lg mx-auto">Seleção especial dos melhores imóveis disponíveis em Fortaleza e região.</p>
        </motion.div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
          {properties.map((property, i) => (
            <motion.div
              key={property.id}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5, delay: i * 0.15 }}
            >
              <Link to={`/imoveis/${property.id}`} className="block group hover-lift rounded-xl overflow-hidden glass-card">
                <div className="relative h-64 overflow-hidden bg-secondary">
                  {property.media[0] ? (
                    <img src={getMediaUrl(property.media[0].file_path)} alt={property.title} className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500" />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-muted-foreground">Sem foto</div>
                  )}
                  <div className="absolute top-3 left-3 flex gap-2">
                    {(property as any).short_code && (
                      <span className="bg-black/60 backdrop-blur-sm text-white text-xs font-bold px-3 py-1 rounded-full">{(property as any).short_code}</span>
                    )}
                    <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">{property.status}</span>
                  </div>
                  {property.featured && (
                    <div className="absolute top-3 right-3">
                      <span className="bg-accent text-accent-foreground text-xs font-bold px-3 py-1 rounded-full flex items-center gap-1">
                        <Star size={12} className="fill-current" /> Destaque
                      </span>
                    </div>
                  )}
                </div>
                <div className="p-5">
                  <p className="text-primary font-bold text-xl mb-1">{formatPrice(Number(property.price), property.status)}</p>
                  <h3 className="font-display text-lg font-semibold text-foreground mb-1">{property.title}</h3>
                  <p className="text-muted-foreground text-sm flex items-center gap-1 mb-4"><MapPin size={14} /> {property.address}</p>
                  <div className="flex items-center gap-4 text-foreground text-sm font-semibold border-t border-border pt-4">
                    <span className="flex items-center gap-1.5" title="Quartos">
                      <span className="w-7 h-7 rounded-lg bg-blue-500/10 flex items-center justify-center"><Bed size={16} className="text-blue-500" /></span> {property.bedrooms}
                    </span>
                    <span className="flex items-center gap-1.5" title="Banheiros">
                      <span className="w-7 h-7 rounded-lg bg-cyan-500/10 flex items-center justify-center"><Bath size={16} className="text-cyan-500" /></span> {property.bathrooms}
                    </span>
                    <span className="flex items-center gap-1.5" title="Área">
                      <span className="w-7 h-7 rounded-lg bg-emerald-500/10 flex items-center justify-center"><Maximize size={16} className="text-emerald-500" /></span> {Number(property.area)}m²
                    </span>
                  </div>
                </div>
              </Link>
            </motion.div>
          ))}
        </div>

        <div className="text-center mt-12">
          <Link to="/imoveis" className="inline-block border-2 border-primary text-primary px-8 py-3 rounded-xl font-semibold hover:bg-primary hover:text-primary-foreground transition-colors">
            Ver Todos os Imóveis
          </Link>
        </div>
      </div>
    </section>
  );
};

export default FeaturedProperties;
