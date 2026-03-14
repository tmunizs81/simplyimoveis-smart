import { useState, useEffect } from "react";
import { useParams, Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { ArrowLeft, Bed, Bath, Maximize, MapPin, Phone, Mail, ChevronLeft, ChevronRight, Car, DoorOpen, Share2, Heart, Calendar, X, MessageCircle, Home, Shield, Star, Waves, Navigation } from "lucide-react";
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
  const [lightboxOpen, setLightboxOpen] = useState(false);
  const [liked, setLiked] = useState(false);

  useEffect(() => {
    const fetchData = async () => {
      if (!id) return;
      const { data } = await supabase.from("properties").select("*").eq("id", id).single();
      if (data) {
        setProperty(data);
        const { data: mediaData } = await supabase.from("property_media").select("*").eq("property_id", id).order("sort_order");
        setMedia(mediaData || []);
      }
      setLoading(false);
    };
    fetchData();
  }, [id]);

  if (loading) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="pt-28 section-padding text-center">
          <div className="w-12 h-12 border-3 border-primary/20 border-t-primary rounded-full animate-spin mx-auto" />
          <p className="text-muted-foreground mt-4">Carregando imóvel...</p>
        </div>
      </div>
    );
  }

  if (!property) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="pt-28 section-padding text-center">
          <div className="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
            <Home size={32} className="text-primary" />
          </div>
          <h1 className="font-display text-2xl font-bold text-foreground">Imóvel não encontrado</h1>
          <p className="text-muted-foreground mt-2 mb-6">O imóvel que você procura não existe ou foi removido.</p>
          <Link to="/imoveis" className="inline-flex items-center gap-2 gradient-primary text-primary-foreground px-6 py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity">
            <ArrowLeft size={16} /> Ver todos os imóveis
          </Link>
        </div>
        <Footer />
      </div>
    );
  }

  const images = media.filter((m) => m.file_type === "image");
  const videos = media.filter((m) => m.file_type === "video");

  const handleShare = () => {
    if (navigator.share) {
      navigator.share({ title: property.title, url: window.location.href });
    } else {
      navigator.clipboard.writeText(window.location.href);
    }
  };

  return (
    <div className="min-h-screen bg-background">
      <Navbar />

      {/* Lightbox */}
      <AnimatePresence>
        {lightboxOpen && images.length > 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[60] bg-black/95 flex items-center justify-center"
            onClick={() => setLightboxOpen(false)}
          >
            <button onClick={() => setLightboxOpen(false)} className="absolute top-6 right-6 text-white/70 hover:text-white z-10">
              <X size={28} />
            </button>
            <button
              onClick={(e) => { e.stopPropagation(); setCurrentImage((p) => (p - 1 + images.length) % images.length); }}
              className="absolute left-4 top-1/2 -translate-y-1/2 bg-white/10 hover:bg-white/20 text-white p-3 rounded-full transition-colors z-10"
            >
              <ChevronLeft size={24} />
            </button>
            <button
              onClick={(e) => { e.stopPropagation(); setCurrentImage((p) => (p + 1) % images.length); }}
              className="absolute right-4 top-1/2 -translate-y-1/2 bg-white/10 hover:bg-white/20 text-white p-3 rounded-full transition-colors z-10"
            >
              <ChevronRight size={24} />
            </button>
            <img
              src={getMediaUrl(images[currentImage].file_path)}
              alt={property.title}
              className="max-w-[90vw] max-h-[85vh] object-contain rounded-lg"
              onClick={(e) => e.stopPropagation()}
            />
            <div className="absolute bottom-6 left-1/2 -translate-x-1/2 text-white/60 text-sm font-medium">
              {currentImage + 1} / {images.length}
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <div className="pt-24">
        {/* Breadcrumb bar */}
        <div className="bg-secondary/30 border-b border-border">
          <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-3 flex items-center justify-between">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <Link to="/" className="hover:text-primary transition-colors">Início</Link>
              <span>/</span>
              <Link to="/imoveis" className="hover:text-primary transition-colors">Imóveis</Link>
              <span>/</span>
              <span className="text-foreground font-medium truncate max-w-[200px]">{property.title}</span>
            </div>
            <div className="flex items-center gap-2">
              <button onClick={() => setLiked(!liked)} className={`p-2 rounded-lg border transition-all ${liked ? "border-red-400 bg-red-50 text-red-500" : "border-border text-muted-foreground hover:text-primary hover:border-primary"}`}>
                <Heart size={16} className={liked ? "fill-current" : ""} />
              </button>
              <button onClick={handleShare} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all">
                <Share2 size={16} />
              </button>
            </div>
          </div>
        </div>

        {/* Gallery Section - Full Width */}
        {images.length > 0 ? (
          <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-6">
            {images.length === 1 ? (
              <div className="rounded-2xl overflow-hidden cursor-pointer" onClick={() => setLightboxOpen(true)}>
                <img src={getMediaUrl(images[0].file_path)} alt={property.title} className="w-full max-h-[500px] object-contain bg-secondary rounded-2xl" />
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-4 gap-3 max-h-[500px]">
                {/* Main image */}
                <div
                  className="md:col-span-2 md:row-span-2 rounded-2xl overflow-hidden cursor-pointer relative group"
                  onClick={() => { setCurrentImage(0); setLightboxOpen(true); }}
                >
                  <img src={getMediaUrl(images[0].file_path)} alt={property.title} className="w-full h-full min-h-[300px] max-h-[500px] object-cover group-hover:scale-105 transition-transform duration-500" />
                  <div className="absolute inset-0 bg-black/0 group-hover:bg-black/10 transition-colors" />
                </div>
                {/* Side images */}
                {images.slice(1, 5).map((img, i) => (
                  <div
                    key={img.id}
                    className="hidden md:block rounded-xl overflow-hidden cursor-pointer relative group h-[245px]"
                    onClick={() => { setCurrentImage(i + 1); setLightboxOpen(true); }}
                  >
                    <img src={getMediaUrl(img.file_path)} alt="" className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" />
                    <div className="absolute inset-0 bg-black/0 group-hover:bg-black/10 transition-colors" />
                    {i === 3 && images.length > 5 && (
                      <div className="absolute inset-0 bg-black/50 flex items-center justify-center">
                        <span className="text-white font-bold text-lg">+{images.length - 5} fotos</span>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}

            {/* Thumbnails strip for mobile */}
            {images.length > 1 && (
              <div className="flex gap-2 mt-4 overflow-x-auto pb-2 md:hidden">
                {images.map((img, i) => (
                  <button
                    key={img.id}
                    onClick={() => { setCurrentImage(i); setLightboxOpen(true); }}
                    className={`shrink-0 w-16 h-16 rounded-lg overflow-hidden border-2 transition-colors ${i === currentImage ? "border-primary" : "border-border"}`}
                  >
                    <img src={getMediaUrl(img.file_path)} alt="" className="w-full h-full object-cover" />
                  </button>
                ))}
              </div>
            )}
          </div>
        ) : (
          <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <div className="rounded-2xl bg-secondary h-[300px] flex items-center justify-center text-muted-foreground">Sem fotos disponíveis</div>
          </div>
        )}

        {/* Main Content */}
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 pb-16">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            {/* Left Content */}
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="lg:col-span-2 space-y-8">
              {/* Title & Tags */}
              <div>
                <div className="flex flex-wrap gap-2 mb-3">
                  <span className="gradient-primary text-primary-foreground text-xs font-bold px-4 py-1.5 rounded-full uppercase tracking-wider">{property.status}</span>
                  <span className="bg-secondary text-foreground text-xs font-bold px-4 py-1.5 rounded-full">{property.type}</span>
                  {property.featured && (
                    <span className="bg-accent text-accent-foreground text-xs font-bold px-4 py-1.5 rounded-full flex items-center gap-1">
                      <Star size={12} className="fill-current" /> Destaque
                    </span>
                  )}
                </div>
                <h1 className="font-display text-2xl sm:text-3xl lg:text-4xl font-bold text-foreground mb-2">{property.title}</h1>
                <p className="text-muted-foreground flex items-center gap-2 text-base">
                  <MapPin size={18} className="text-primary shrink-0" /> {property.address}
                </p>
              </div>

              {/* Price - Mobile */}
              <div className="lg:hidden">
                <div className="glass-card rounded-2xl p-5 border border-primary/20">
                  <p className="text-primary font-bold text-3xl font-display">{formatPrice(Number(property.price), property.status)}</p>
                  <p className="text-muted-foreground text-sm mt-1">{property.status === "aluguel" ? "Valor mensal" : "Valor de venda"}</p>
                </div>
              </div>

              {/* Stats Grid */}
              <div className="grid grid-cols-3 sm:grid-cols-5 gap-3">
                {[
                  { icon: Bed, value: property.bedrooms, label: "Quartos", color: "blue" },
                  { icon: DoorOpen, value: (property as any).suites || 0, label: "Suítes", color: "purple" },
                  { icon: Bath, value: property.bathrooms, label: "Banheiros", color: "cyan" },
                  { icon: Car, value: (property as any).garage_spots || 0, label: "Vagas", color: "amber" },
                  { icon: Maximize, value: `${Number(property.area)}m²`, label: "Área", color: "emerald" },
                ].map((stat) => (
                  <div key={stat.label} className="glass-card rounded-xl p-4 text-center hover:shadow-md transition-shadow">
                    <div className={`w-11 h-11 rounded-xl bg-${stat.color}-500/10 flex items-center justify-center mx-auto mb-2`}>
                      <stat.icon className={`text-${stat.color}-500`} size={22} />
                    </div>
                    <p className="font-bold text-foreground text-lg leading-tight">{stat.value}</p>
                    <p className="text-muted-foreground text-xs mt-0.5">{stat.label}</p>
                  </div>
                ))}
              </div>

              {/* Description */}
              {property.description && (
                <div className="glass-card rounded-2xl p-8 border border-border/50">
                  <h2 className="font-display text-2xl font-bold text-foreground mb-6 flex items-center gap-3">
                    <div className="w-1.5 h-8 rounded-full gradient-primary" />
                    Sobre o Imóvel
                  </h2>
                  <div className="space-y-3">
                    {property.description.split('\n').filter(line => line.trim()).map((line, i) => {
                      const cleanLine = line.replace(/^->?\s*/, '').replace(/^[-•]\s*/, '').trim();
                      if (!cleanLine) return null;
                      return (
                        <div key={i} className="flex items-start gap-3 group">
                          <div className="w-2 h-2 rounded-full gradient-primary mt-2 shrink-0 group-hover:scale-125 transition-transform" />
                          <p className="text-muted-foreground font-body text-[15px] leading-relaxed group-hover:text-foreground transition-colors">
                            {cleanLine}
                          </p>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {/* Videos */}
              {videos.length > 0 && (
                <div className="glass-card rounded-2xl p-6">
                  <h2 className="font-display text-xl font-bold text-foreground mb-4 flex items-center gap-2">
                    <div className="w-1 h-6 rounded-full gradient-primary" />
                    Vídeos do Imóvel
                  </h2>
                  <div className="space-y-4">
                    {videos.map((v) => (
                      <video key={v.id} controls className="w-full rounded-xl">
                        <source src={getMediaUrl(v.file_path)} />
                      </video>
                    ))}
                  </div>
                </div>
              )}

              {/* Trust badges */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                {[
                  { icon: Shield, title: "Imóvel Verificado", desc: "Documentação conferida" },
                  { icon: Calendar, title: "Agenda Flexível", desc: "Visitas sob agendamento" },
                  { icon: MessageCircle, title: "Atendimento Ágil", desc: "Resposta em até 1h" },
                ].map((badge) => (
                  <div key={badge.title} className="flex items-start gap-3 p-4 rounded-xl bg-secondary/30">
                    <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
                      <badge.icon size={18} className="text-primary" />
                    </div>
                    <div>
                      <p className="font-semibold text-foreground text-sm">{badge.title}</p>
                      <p className="text-muted-foreground text-xs">{badge.desc}</p>
                    </div>
                  </div>
                ))}
              </div>
            </motion.div>

            {/* Right Sidebar */}
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}>
              <div className="glass-card rounded-2xl overflow-hidden sticky top-24">
                {/* Price header */}
                <div className="hidden lg:block gradient-primary p-6">
                  <p className="text-primary-foreground font-bold text-3xl font-display">{formatPrice(Number(property.price), property.status)}</p>
                  <p className="text-primary-foreground/70 text-sm mt-1">{property.status === "aluguel" ? "Valor mensal" : "Valor de venda"}</p>
                </div>

                <div className="p-6 space-y-4">
                  {/* CTA Buttons */}
                  <a
                    href={`https://wa.me/5585999990000?text=${encodeURIComponent(`Olá! Tenho interesse no imóvel: ${property.title}`)}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="w-full bg-[#25D366] text-white py-3.5 rounded-xl font-bold hover:opacity-90 transition-opacity flex items-center justify-center gap-2 text-sm shadow-lg shadow-[#25D366]/20"
                  >
                    <MessageCircle size={18} /> Chamar no WhatsApp
                  </a>
                  <a
                    href="tel:+5585999990000"
                    className="w-full gradient-primary text-primary-foreground py-3.5 rounded-xl font-bold hover:opacity-90 transition-opacity flex items-center justify-center gap-2 text-sm"
                  >
                    <Phone size={18} /> Ligar Agora
                  </a>
                  <a
                    href="mailto:contato@simplyimoveis.com.br"
                    className="w-full border-2 border-border text-foreground py-3.5 rounded-xl font-semibold hover:border-primary hover:text-primary transition-colors flex items-center justify-center gap-2 text-sm"
                  >
                    <Mail size={18} /> Enviar E-mail
                  </a>

                  {/* Agent info */}
                  <div className="pt-4 border-t border-border">
                    <div className="flex items-center gap-3">
                      <div className="w-12 h-12 rounded-full gradient-primary flex items-center justify-center text-primary-foreground font-bold text-lg">T</div>
                      <div>
                        <p className="text-sm text-foreground font-bold">Talita Muniz</p>
                        <p className="text-xs text-muted-foreground">Corretora | CRECI XXXXX</p>
                        <p className="text-xs text-primary font-medium">Simply Imóveis</p>
                      </div>
                    </div>
                  </div>
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
