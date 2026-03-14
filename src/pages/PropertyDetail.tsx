import { useState, useEffect } from "react";
import { useParams, Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Bed, Bath, Maximize, MapPin, Phone, Mail, ChevronLeft, ChevronRight, Car, DoorOpen } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];

const formatPrice = (price: number, status: string) => {
  const formatted = price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  return status === "aluguel" ? `${formatted}/mês` : formatted;
};

const getMediaUrl = (filePath: string) => {
  const { data } = supabase.storage.from("property-media").getPublicUrl(filePath);
  return data.publicUrl;
};

const PropertyDetail = () => {
  const { id } = useParams();
  const [property, setProperty] = useState<Property | null>(null);
  const [media, setMedia] = useState<MediaRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [currentImage, setCurrentImage] = useState(0);

  useEffect(() => {
    const fetch = async () => {
      if (!id) return;
      const { data } = await supabase.from("properties").select("*").eq("id", id).single();
      if (data) {
        setProperty(data);
        const { data: mediaData } = await supabase.from("property_media").select("*").eq("property_id", id).order("sort_order");
        setMedia(mediaData || []);
      }
      setLoading(false);
    };
    fetch();
  }, [id]);

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="pt-24 section-padding text-center"><p className="text-muted-foreground animate-pulse">Carregando...</p></div>
      </div>
    );
  }

  if (!property) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="pt-24 section-padding text-center">
          <h1 className="font-display text-2xl font-bold text-foreground">Imóvel não encontrado</h1>
          <Link to="/imoveis" className="text-primary mt-4 inline-block hover:underline">← Voltar aos imóveis</Link>
        </div>
        <Footer />
      </div>
    );
  }

  const images = media.filter((m) => m.file_type === "image");
  const videos = media.filter((m) => m.file_type === "video");

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="pt-24 section-padding">
        <div className="container-custom">
          <Link to="/imoveis" className="inline-flex items-center gap-2 text-muted-foreground hover:text-primary mb-6 text-sm">
            <ArrowLeft size={16} /> Voltar aos imóveis
          </Link>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="lg:col-span-2">
              {/* Image gallery */}
              {images.length > 0 ? (
                <div className="relative rounded-2xl overflow-hidden mb-6">
                  <img src={getMediaUrl(images[currentImage].file_path)} alt={property.title} className="w-full h-[400px] object-cover" />
                  {images.length > 1 && (
                    <>
                      <button onClick={() => setCurrentImage((p) => (p - 1 + images.length) % images.length)} className="absolute left-3 top-1/2 -translate-y-1/2 bg-foreground/50 text-primary-foreground p-2 rounded-full hover:bg-foreground/70">
                        <ChevronLeft size={20} />
                      </button>
                      <button onClick={() => setCurrentImage((p) => (p + 1) % images.length)} className="absolute right-3 top-1/2 -translate-y-1/2 bg-foreground/50 text-primary-foreground p-2 rounded-full hover:bg-foreground/70">
                        <ChevronRight size={20} />
                      </button>
                      <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex gap-1.5">
                        {images.map((_, i) => (
                          <button key={i} onClick={() => setCurrentImage(i)} className={`w-2 h-2 rounded-full transition-colors ${i === currentImage ? "bg-primary-foreground" : "bg-primary-foreground/40"}`} />
                        ))}
                      </div>
                    </>
                  )}
                </div>
              ) : (
                <div className="rounded-2xl bg-secondary h-[400px] flex items-center justify-center mb-6 text-muted-foreground">Sem fotos</div>
              )}

              {/* Thumbnails */}
              {images.length > 1 && (
                <div className="flex gap-2 mb-6 overflow-x-auto pb-2">
                  {images.map((img, i) => (
                    <button key={img.id} onClick={() => setCurrentImage(i)} className={`shrink-0 w-20 h-20 rounded-lg overflow-hidden border-2 transition-colors ${i === currentImage ? "border-primary" : "border-transparent"}`}>
                      <img src={getMediaUrl(img.file_path)} alt="" className="w-full h-full object-cover" />
                    </button>
                  ))}
                </div>
              )}

              {/* Videos */}
              {videos.length > 0 && (
                <div className="mb-6 space-y-4">
                  <h2 className="font-display text-xl font-semibold text-foreground">Vídeos</h2>
                  {videos.map((v) => (
                    <video key={v.id} controls className="w-full rounded-xl">
                      <source src={getMediaUrl(v.file_path)} />
                    </video>
                  ))}
                </div>
              )}

              <div className="flex flex-wrap gap-2 mb-4">
                <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">{property.status}</span>
                <span className="bg-accent text-accent-foreground text-xs font-semibold px-3 py-1 rounded-full">{property.type}</span>
              </div>

              <h1 className="font-display text-3xl font-bold text-foreground mb-2">{property.title}</h1>
              <p className="text-muted-foreground flex items-center gap-1 mb-6"><MapPin size={16} /> {property.address}</p>

              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-4 mb-8">
                <div className="glass-card rounded-xl p-4 text-center">
                  <div className="w-10 h-10 rounded-xl bg-blue-500/10 flex items-center justify-center mx-auto mb-2">
                    <Bed className="text-blue-500" size={22} />
                  </div>
                  <p className="font-bold text-foreground text-lg">{property.bedrooms}</p>
                  <p className="text-muted-foreground text-xs">Quartos</p>
                </div>
                <div className="glass-card rounded-xl p-4 text-center">
                  <div className="w-10 h-10 rounded-xl bg-purple-500/10 flex items-center justify-center mx-auto mb-2">
                    <DoorOpen className="text-purple-500" size={22} />
                  </div>
                  <p className="font-bold text-foreground text-lg">{(property as any).suites || 0}</p>
                  <p className="text-muted-foreground text-xs">Suítes</p>
                </div>
                <div className="glass-card rounded-xl p-4 text-center">
                  <div className="w-10 h-10 rounded-xl bg-cyan-500/10 flex items-center justify-center mx-auto mb-2">
                    <Bath className="text-cyan-500" size={22} />
                  </div>
                  <p className="font-bold text-foreground text-lg">{property.bathrooms}</p>
                  <p className="text-muted-foreground text-xs">Banheiros</p>
                </div>
                <div className="glass-card rounded-xl p-4 text-center">
                  <div className="w-10 h-10 rounded-xl bg-amber-500/10 flex items-center justify-center mx-auto mb-2">
                    <Car className="text-amber-500" size={22} />
                  </div>
                  <p className="font-bold text-foreground text-lg">{(property as any).garage_spots || 0}</p>
                  <p className="text-muted-foreground text-xs">Garagem</p>
                </div>
                <div className="glass-card rounded-xl p-4 text-center">
                  <div className="w-10 h-10 rounded-xl bg-emerald-500/10 flex items-center justify-center mx-auto mb-2">
                    <Maximize className="text-emerald-500" size={22} />
                  </div>
                  <p className="font-bold text-foreground text-lg">{Number(property.area)}m²</p>
                  <p className="text-muted-foreground text-xs">Área</p>
                </div>
              </div>

              {property.description && (
                <>
                  <h2 className="font-display text-xl font-semibold text-foreground mb-3">Descrição</h2>
                  <p className="text-muted-foreground leading-relaxed">{property.description}</p>
                </>
              )}
            </motion.div>

            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}>
              <div className="glass-card rounded-2xl p-6 sticky top-24">
                <p className="text-primary font-bold text-3xl font-display mb-1">{formatPrice(Number(property.price), property.status)}</p>
                <p className="text-muted-foreground text-sm mb-6">{property.status === "aluguel" ? "Valor mensal" : "Valor de venda"}</p>
                <div className="space-y-3">
                  <a href="tel:+5585999990000" className="w-full gradient-primary text-primary-foreground py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity flex items-center justify-center gap-2">
                    <Phone size={16} /> Ligar Agora
                  </a>
                  <a href={`https://wa.me/5585999990000?text=Olá! Tenho interesse no imóvel: ${property.title}`} target="_blank" rel="noopener noreferrer" className="w-full bg-[#25D366] text-primary-foreground py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity flex items-center justify-center gap-2">
                    WhatsApp
                  </a>
                  <a href="mailto:contato@simplyimoveis.com.br" className="w-full border-2 border-primary text-primary py-3 rounded-xl font-semibold hover:bg-primary hover:text-primary-foreground transition-colors flex items-center justify-center gap-2">
                    <Mail size={16} /> E-mail
                  </a>
                </div>
                <div className="mt-6 pt-6 border-t border-border">
                  <p className="text-sm text-foreground font-semibold">Talita Muniz</p>
                  <p className="text-xs text-muted-foreground">Corretora | CRECI XXXXX</p>
                  <p className="text-xs text-muted-foreground">Simply Imóveis</p>
                </div>
              </div>
            </motion.div>
          </div>
        </div>
      </div>
      <Footer />
      <ChatWidget propertyId={id} />
    </div>
  );
};

export default PropertyDetail;
