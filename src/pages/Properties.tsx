import { useState } from "react";
import { motion } from "framer-motion";
import { Search, SlidersHorizontal } from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";
import { featuredProperties, formatPrice, PropertyCard } from "@/components/FeaturedProperties";

const propertyTypes = ["Todos", "Apartamento", "Casa", "Cobertura", "Terreno", "Sala Comercial"];
const statusOptions = ["Todos", "venda", "aluguel"];

const Properties = () => {
  const [search, setSearch] = useState("");
  const [type, setType] = useState("Todos");
  const [status, setStatus] = useState("Todos");

  const filtered = featuredProperties.filter((p) => {
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
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-center mb-12"
          >
            <h1 className="font-display text-3xl sm:text-4xl font-bold text-foreground">
              Nossos Imóveis
            </h1>
            <p className="text-muted-foreground mt-3">
              Encontre o imóvel ideal para você em Fortaleza e região.
            </p>
          </motion.div>

          {/* Filters */}
          <div className="glass-card rounded-xl p-4 mb-10 flex flex-col sm:flex-row gap-4 items-center">
            <div className="relative flex-1 w-full">
              <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input
                type="text"
                placeholder="Buscar por nome ou localização..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full pl-9 pr-4 py-2.5 rounded-lg bg-background border border-input text-sm text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none"
              />
            </div>
            <select
              value={type}
              onChange={(e) => setType(e.target.value)}
              className="px-4 py-2.5 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none"
            >
              {propertyTypes.map((t) => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              className="px-4 py-2.5 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none capitalize"
            >
              {statusOptions.map((s) => (
                <option key={s} value={s}>{s === "Todos" ? "Todos" : s === "venda" ? "Venda" : "Aluguel"}</option>
              ))}
            </select>
          </div>

          {filtered.length === 0 ? (
            <div className="text-center py-20">
              <SlidersHorizontal className="mx-auto text-muted-foreground mb-4" size={48} />
              <p className="text-muted-foreground">Nenhum imóvel encontrado com esses filtros.</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
              {filtered.map((property, i) => (
                <PropertyCard key={property.id} property={property} index={i} />
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
