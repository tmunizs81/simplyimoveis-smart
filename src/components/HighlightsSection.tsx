import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { Bed, Bath, Maximize, MapPin, ChevronLeft, ChevronRight, Sparkles, Car } from "lucide-react";
import { Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { getMediaUrl } from "@/lib/mediaUrl";
import { Carousel, CarouselContent, CarouselItem, CarouselNext, CarouselPrevious, type CarouselApi } from "@/components/ui/carousel";

import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];
type PropertyWithMedia = Property & { media: MediaRow[] };

const formatPrice = (price: number, status: string) => {
  const formatted = price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  return status === "aluguel" ? `${formatted}/mês` : formatted;
};

const HighlightsSection = () => {
  const [properties, setProperties] = useState<PropertyWithMedia[]>([]);
  const [loading, setLoading] = useState(true);
  const [api, setApi] = useState<CarouselApi>();

  useEffect(() => {
    const fetchHighlights = async () => {
      const { data } = await supabase
        .from("properties")
        .select("*")
        .eq("active", true)
        .eq("featured", true)
        .order("created_at", { ascending: false })
        .limit(10);

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
    fetchHighlights();
  }, []);

  if (loading || properties.length === 0) return null;

  return (
    <section className="section-padding bg-background overflow-hidden">
      <div className="container-custom">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="flex items-end justify-between mb-10"
        >
          <div>
            <span className="text-primary text-sm font-semibold uppercase tracking-widest">⭐ Destaques</span>
            <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2">
              Imóveis em Destaque
            </h2>
            <p className="text-muted-foreground mt-2">Os melhores imóveis selecionados para você</p>
          </div>
          <div className="hidden sm:flex gap-2">
            <button
              onClick={() => api?.scrollPrev()}
              className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-colors"
            >
              <ChevronLeft size={20} />
            </button>
            <button
              onClick={() => api?.scrollNext()}
              className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-colors"
            >
              <ChevronRight size={20} />
            </button>
          </div>
        </motion.div>

        <Carousel
          setApi={setApi}
          opts={{
            align: "start",
            loop: true,
          }}
          className="w-full"
        >
          <CarouselContent className="-ml-4 sm:-ml-6">
            {properties.map((property) => (
              <CarouselItem key={property.id} className="pl-4 sm:pl-6 basis-[85%] sm:basis-1/2 lg:basis-1/3">
                <Link
                  to={`/imoveis/${property.id}`}
                  className="block group hover-lift rounded-xl overflow-hidden glass-card h-full"
                >
                  <div className="relative h-56 overflow-hidden bg-secondary">
                    {property.media[0] ? (
                      <img 
                        src={getMediaUrl(property.media[0].file_path)} 
                        alt={property.title} 
                        className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500" 
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-muted-foreground">Sem foto</div>
                    )}
                    <div className="absolute top-3 left-3 flex gap-2">
                      <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">{property.status}</span>
                    </div>
                    <div className="absolute top-3 right-3">
                      <span className="bg-gold text-foreground text-xs font-bold px-2 py-1 rounded-full flex items-center gap-1">
                        <Sparkles size={10} /> Destaque
                      </span>
                    </div>
                  </div>
                  <div className="p-4">
                    <p className="text-primary font-bold text-lg">{formatPrice(Number(property.price), property.status)}</p>
                    <h3 className="font-display text-base font-semibold text-foreground mt-1 truncate">{property.title}</h3>
                    <p className="text-muted-foreground text-xs flex items-center gap-1 mt-1 truncate"><MapPin size={12} /> {property.address}</p>
                    <div className="flex items-center gap-3 text-foreground text-xs font-semibold mt-3 pt-3 border-t border-border">
                      <span className="flex items-center gap-1.5 shrink-0">
                        <span className="w-6 h-6 rounded-md bg-blue-500/10 flex items-center justify-center"><Bed size={13} className="text-blue-500" /></span> {property.bedrooms}
                      </span>
                      <span className="flex items-center gap-1.5 shrink-0">
                        <span className="w-6 h-6 rounded-md bg-cyan-500/10 flex items-center justify-center"><Bath size={13} className="text-cyan-500" /></span> {property.bathrooms}
                      </span>
                      <span className="flex items-center gap-1.5 shrink-0">
                        <span className="w-6 h-6 rounded-md bg-amber-500/10 flex items-center justify-center"><Car size={13} className="text-amber-500" /></span> {(property as any).garage_spots || 0}
                      </span>
                      <span className="flex items-center gap-1.5 shrink-0">
                        <span className="w-6 h-6 rounded-md bg-emerald-500/10 flex items-center justify-center"><Maximize size={13} className="text-emerald-500" /></span> {Number(property.area)}m²
                      </span>
                    </div>
                  </div>
                </Link>
              </CarouselItem>
            ))}
          </CarouselContent>
        </Carousel>


        <div className="text-center mt-10">
          <Link to="/imoveis" className="inline-block border-2 border-primary text-primary px-8 py-3 rounded-xl font-semibold hover:bg-primary hover:text-primary-foreground transition-colors">
            Ver Todos os Imóveis
          </Link>
        </div>
      </div>
    </section>
  );
};

export default HighlightsSection;
