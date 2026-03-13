import { useParams, Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ArrowLeft, Bed, Bath, Maximize, MapPin, Phone, Mail } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";
import { featuredProperties, formatPrice } from "@/components/FeaturedProperties";

const PropertyDetail = () => {
  const { id } = useParams();
  const property = featuredProperties.find((p) => p.id === id);

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

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="pt-24 section-padding">
        <div className="container-custom">
          <Link to="/imoveis" className="inline-flex items-center gap-2 text-muted-foreground hover:text-primary mb-6 text-sm">
            <ArrowLeft size={16} /> Voltar aos imóveis
          </Link>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="lg:col-span-2"
            >
              <div className="rounded-2xl overflow-hidden mb-6">
                <img src={property.image} alt={property.title} className="w-full h-[400px] object-cover" />
              </div>

              <div className="flex flex-wrap gap-2 mb-4">
                <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">
                  {property.status}
                </span>
                <span className="bg-accent text-accent-foreground text-xs font-semibold px-3 py-1 rounded-full">
                  {property.type}
                </span>
              </div>

              <h1 className="font-display text-3xl font-bold text-foreground mb-2">{property.title}</h1>
              <p className="text-muted-foreground flex items-center gap-1 mb-6">
                <MapPin size={16} /> {property.address}
              </p>

              <div className="grid grid-cols-3 gap-4 mb-8">
                <div className="glass-card rounded-xl p-4 text-center">
                  <Bed className="mx-auto text-primary mb-1" size={20} />
                  <p className="font-semibold text-foreground">{property.bedrooms}</p>
                  <p className="text-muted-foreground text-xs">Quartos</p>
                </div>
                <div className="glass-card rounded-xl p-4 text-center">
                  <Bath className="mx-auto text-primary mb-1" size={20} />
                  <p className="font-semibold text-foreground">{property.bathrooms}</p>
                  <p className="text-muted-foreground text-xs">Banheiros</p>
                </div>
                <div className="glass-card rounded-xl p-4 text-center">
                  <Maximize className="mx-auto text-primary mb-1" size={20} />
                  <p className="font-semibold text-foreground">{property.area}m²</p>
                  <p className="text-muted-foreground text-xs">Área</p>
                </div>
              </div>

              <h2 className="font-display text-xl font-semibold text-foreground mb-3">Descrição</h2>
              <p className="text-muted-foreground leading-relaxed">
                Imóvel excepcional localizado em {property.address}. Com {property.bedrooms} quartos, {property.bathrooms} banheiros e {property.area}m² de área total, este {property.type.toLowerCase()} oferece o melhor em conforto e qualidade de vida. Agende uma visita e conheça pessoalmente!
              </p>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.2 }}
            >
              <div className="glass-card rounded-2xl p-6 sticky top-24">
                <p className="text-primary font-bold text-3xl font-display mb-1">
                  {formatPrice(property.price, property.status)}
                </p>
                <p className="text-muted-foreground text-sm mb-6">
                  {property.status === "aluguel" ? "Valor mensal" : "Valor de venda"}
                </p>

                <div className="space-y-3">
                  <a
                    href="tel:+5585999990000"
                    className="w-full gradient-primary text-primary-foreground py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity flex items-center justify-center gap-2"
                  >
                    <Phone size={16} /> Ligar Agora
                  </a>
                  <a
                    href={`https://wa.me/5585999990000?text=Olá! Tenho interesse no imóvel: ${property.title}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="w-full bg-[#25D366] text-primary-foreground py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity flex items-center justify-center gap-2"
                  >
                    WhatsApp
                  </a>
                  <a
                    href="mailto:contato@simplyimoveis.com.br"
                    className="w-full border-2 border-primary text-primary py-3 rounded-xl font-semibold hover:bg-primary hover:text-primary-foreground transition-colors flex items-center justify-center gap-2"
                  >
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
      <ChatWidget />
    </div>
  );
};

export default PropertyDetail;
