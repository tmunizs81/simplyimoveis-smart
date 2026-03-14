import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Bed, Bath, Maximize, MapPin, ArrowRight, Tag, Car, DoorOpen } from "lucide-react";
import { Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];
type PropertyWithMedia = Property & { media: MediaRow[] };

const formatPrice = (price: number, status: string) => {
  const formatted = price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  return status === "aluguel" ? `${formatted}/mês` : formatted;
};

const getMediaUrl = (filePath: string) => {
  const { data } = supabase.storage.from("property-media").getPublicUrl(filePath);
  return data.publicUrl;
};

const OpportunitiesSection = () => {
  const [properties, setProperties] = useState<PropertyWithMedia[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchOpportunities = async () => {
      // Fetch non-featured active properties as "oportunidades"
      const { data } = await supabase
        .from("properties")
        .select("*")
        .eq("active", true)
        .eq("featured", false)
        .order("created_at", { ascending: false })
        .limit(4);

      if (data && data.length > 0) {
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
    fetchOpportunities();
  }, []);

  if (loading || properties.length === 0) return null;

  return (
    <section className="section-padding bg-secondary/40">
      <div className="container-custom">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-12"
        >
          <span className="text-primary text-sm font-semibold uppercase tracking-widest">🔥 Oportunidades</span>
          <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2">
            Oportunidades Imperdíveis
          </h2>
          <p className="text-muted-foreground mt-2 max-w-lg mx-auto">
            Imóveis com condições especiais que você não pode perder. Aproveite!
          </p>
        </motion.div>

        <div className="space-y-6">
          {properties.map((property, i) => (
            <motion.div
              key={property.id}
              initial={{ opacity: 0, x: i % 2 === 0 ? -30 : 30 }}
              whileInView={{ opacity: 1, x: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5, delay: i * 0.1 }}
            >
              <Link
                to={`/imoveis/${property.id}`}
                className="block group glass-card rounded-2xl overflow-hidden hover-lift"
              >
                <div className="flex flex-col md:flex-row">
                  {/* Image */}
                  <div className="relative md:w-2/5 h-64 md:h-auto overflow-hidden bg-secondary">
                    {property.media[0] ? (
                      <img
                        src={getMediaUrl(property.media[0].file_path)}
                        alt={property.title}
                        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-muted-foreground min-h-[200px]">Sem foto</div>
                    )}
                    <div className="absolute top-4 left-4">
                      <span className="bg-destructive text-destructive-foreground text-xs font-bold px-3 py-1.5 rounded-full flex items-center gap-1 uppercase">
                        <Tag size={12} /> Oportunidade
                      </span>
                    </div>
                  </div>

                  {/* Content */}
                  <div className="md:w-3/5 p-6 md:p-8 flex flex-col justify-between">
                    <div>
                      <div className="flex items-center gap-3 mb-3">
                        <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">{property.status}</span>
                        <span className="bg-accent text-accent-foreground text-xs font-semibold px-3 py-1 rounded-full">{property.type}</span>
                      </div>

                      <h3 className="font-display text-xl md:text-2xl font-bold text-foreground mb-2 group-hover:text-primary transition-colors">
                        {property.title}
                      </h3>

                      <p className="text-muted-foreground text-sm flex items-center gap-1 mb-4">
                        <MapPin size={14} /> {property.address}
                      </p>

                      {property.description && (
                        <p className="text-muted-foreground text-sm leading-relaxed line-clamp-3 mb-4">
                          {property.description}
                        </p>
                      )}

                      <div className="flex items-center gap-5 text-muted-foreground text-sm">
                        <span className="flex items-center gap-1.5"><Bed size={15} /> {property.bedrooms} quartos</span>
                        <span className="flex items-center gap-1.5"><Bath size={15} /> {property.bathrooms} banheiros</span>
                        <span className="flex items-center gap-1.5"><Maximize size={15} /> {Number(property.area)}m²</span>
                      </div>
                    </div>

                    <div className="flex items-center justify-between mt-6 pt-4 border-t border-border">
                      <p className="text-primary font-bold text-2xl font-display">
                        {formatPrice(Number(property.price), property.status)}
                      </p>
                      <span className="text-primary font-semibold text-sm flex items-center gap-1 group-hover:gap-2 transition-all">
                        Ver detalhes <ArrowRight size={16} />
                      </span>
                    </div>
                  </div>
                </div>
              </Link>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default OpportunitiesSection;
