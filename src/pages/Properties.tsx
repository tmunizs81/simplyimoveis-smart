import { useState, useEffect, useMemo } from "react";
import { motion } from "framer-motion";
import { Search, SlidersHorizontal, Bed, Bath, Maximize, MapPin, Car, X, ChevronDown } from "lucide-react";
import { Link } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { getMediaUrl } from "@/lib/mediaUrl";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];
type PropertyWithMedia = Property & { media: MediaRow[] };

const propertyTypes = ["Todos", "Apartamento", "Casa", "Cobertura", "Terreno", "Sala Comercial"];
const statusOptions = ["Todos", "venda", "aluguel"];
const bedroomOptions = ["Todos", "1", "2", "3", "4+"];
const priceRanges = [
  { label: "Qualquer preço", min: 0, max: Infinity },
  { label: "Até R$ 200 mil", min: 0, max: 200000 },
  { label: "R$ 200 mil – R$ 500 mil", min: 200000, max: 500000 },
  { label: "R$ 500 mil – R$ 1 milhão", min: 500000, max: 1000000 },
  { label: "Acima de R$ 1 milhão", min: 1000000, max: Infinity },
];

const formatPrice = (price: number, status: string) => {
  const formatted = price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  return status === "aluguel" ? `${formatted}/mês` : formatted;
};

const Properties = () => {
  const [search, setSearch] = useState("");
  const [type, setType] = useState("Todos");
  const [status, setStatus] = useState("Todos");
  const [bedrooms, setBedrooms] = useState("Todos");
  const [priceRange, setPriceRange] = useState(0);
  const [city, setCity] = useState("Todos");
  const [showFilters, setShowFilters] = useState(false);
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
            .order("sort_order")
            .limit(1);
          return { ...p, media: media || [] };
        })
      );
      setProperties(withMedia);
      setLoading(false);
    };
    fetchProperties();
  }, []);

  const cities = useMemo(() => {
    const set = new Set(properties.map(p => p.city || "Fortaleza"));
    return ["Todos", ...Array.from(set).sort()];
  }, [properties]);

  const activeFilterCount = [
    type !== "Todos",
    status !== "Todos",
    bedrooms !== "Todos",
    priceRange !== 0,
    city !== "Todos",
  ].filter(Boolean).length;

  const clearFilters = () => {
    setType("Todos");
    setStatus("Todos");
    setBedrooms("Todos");
    setPriceRange(0);
    setCity("Todos");
    setSearch("");
  };

  const filtered = properties.filter((p) => {
    const matchSearch =
      p.title.toLowerCase().includes(search.toLowerCase()) ||
      p.address.toLowerCase().includes(search.toLowerCase()) ||
      (p.neighborhood || "").toLowerCase().includes(search.toLowerCase());
    const matchType = type === "Todos" || p.type === type;
    const matchStatus = status === "Todos" || p.status === status;
    const matchBedrooms = bedrooms === "Todos" || (bedrooms === "4+" ? p.bedrooms >= 4 : p.bedrooms === parseInt(bedrooms));
    const range = priceRanges[priceRange];
    const matchPrice = Number(p.price) >= range.min && Number(p.price) <= range.max;
    const matchCity = city === "Todos" || (p.city || "Fortaleza") === city;
    return matchSearch && matchType && matchStatus && matchBedrooms && matchPrice && matchCity;
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

          {/* Search + filter toggle */}
          <div className="glass-card rounded-xl p-4 mb-4">
            <div className="flex flex-col sm:flex-row gap-3 items-center">
              <div className="relative flex-1 w-full">
                <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
                <input
                  type="text"
                  placeholder="Buscar por nome, bairro ou localização..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="w-full pl-9 pr-4 py-2.5 rounded-lg bg-background border border-input text-sm text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none"
                />
              </div>
              <button
                onClick={() => setShowFilters(!showFilters)}
                className={`flex items-center gap-2 px-4 py-2.5 rounded-lg border text-sm font-medium transition-colors shrink-0 ${
                  showFilters || activeFilterCount > 0
                    ? "border-primary bg-primary/10 text-primary"
                    : "border-input text-muted-foreground hover:text-foreground"
                }`}
              >
                <SlidersHorizontal size={16} />
                Filtros
                {activeFilterCount > 0 && (
                  <span className="w-5 h-5 rounded-full bg-primary text-primary-foreground text-xs flex items-center justify-center font-bold">
                    {activeFilterCount}
                  </span>
                )}
                <ChevronDown size={14} className={`transition-transform ${showFilters ? "rotate-180" : ""}`} />
              </button>
            </div>
          </div>

          {/* Expanded filters */}
          {showFilters && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              className="glass-card rounded-xl p-4 mb-4 overflow-hidden"
            >
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
                <div>
                  <label className="text-xs font-semibold text-muted-foreground mb-1 block">Tipo</label>
                  <select value={type} onChange={(e) => setType(e.target.value)} className="w-full px-3 py-2 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none">
                    {propertyTypes.map((t) => <option key={t} value={t}>{t}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-semibold text-muted-foreground mb-1 block">Finalidade</label>
                  <select value={status} onChange={(e) => setStatus(e.target.value)} className="w-full px-3 py-2 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none">
                    {statusOptions.map((s) => <option key={s} value={s}>{s === "Todos" ? "Todos" : s === "venda" ? "Venda" : "Aluguel"}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-semibold text-muted-foreground mb-1 block">Quartos</label>
                  <select value={bedrooms} onChange={(e) => setBedrooms(e.target.value)} className="w-full px-3 py-2 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none">
                    {bedroomOptions.map((b) => <option key={b} value={b}>{b === "Todos" ? "Todos" : b === "4+" ? "4 ou mais" : `${b} quarto${b !== "1" ? "s" : ""}`}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-semibold text-muted-foreground mb-1 block">Faixa de preço</label>
                  <select value={priceRange} onChange={(e) => setPriceRange(parseInt(e.target.value))} className="w-full px-3 py-2 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none">
                    {priceRanges.map((r, i) => <option key={i} value={i}>{r.label}</option>)}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-semibold text-muted-foreground mb-1 block">Cidade</label>
                  <select value={city} onChange={(e) => setCity(e.target.value)} className="w-full px-3 py-2 rounded-lg bg-background border border-input text-sm text-foreground focus:ring-2 focus:ring-ring outline-none">
                    {cities.map((c) => <option key={c} value={c}>{c}</option>)}
                  </select>
                </div>
              </div>
              {activeFilterCount > 0 && (
                <button onClick={clearFilters} className="mt-3 text-xs text-primary hover:underline flex items-center gap-1">
                  <X size={12} /> Limpar todos os filtros
                </button>
              )}
            </motion.div>
          )}

          {/* Results count */}
          <div className="flex items-center justify-between mb-6">
            <p className="text-sm text-muted-foreground">
              {loading ? "Carregando..." : `${filtered.length} imóve${filtered.length !== 1 ? "is" : "l"} encontrado${filtered.length !== 1 ? "s" : ""}`}
            </p>
          </div>

          {loading ? (
            <div className="text-center py-20">
              <p className="text-muted-foreground animate-pulse">Carregando imóveis...</p>
            </div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-20">
              <SlidersHorizontal className="mx-auto text-muted-foreground mb-4" size={48} />
              <p className="text-muted-foreground">Nenhum imóvel encontrado.</p>
              {activeFilterCount > 0 && (
                <button onClick={clearFilters} className="mt-3 text-primary font-medium hover:underline">
                  Limpar filtros
                </button>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
              {filtered.map((property, i) => (
                <motion.div
                  key={property.id}
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ duration: 0.5, delay: i * 0.05 }}
                >
                  <Link to={`/imoveis/${property.id}`} className="block group hover-lift rounded-xl overflow-hidden glass-card">
                    <div className="relative aspect-[4/3] overflow-hidden bg-secondary">
                      {property.media[0] ? (
                        <img
                          src={getMediaUrl(property.media[0].file_path)}
                          alt={property.title}
                          loading="lazy"
                          className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
                        />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-muted-foreground">Sem foto</div>
                      )}
                      <div className="absolute top-3 left-3 flex gap-2">
                        <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">{property.status}</span>
                        <span className="bg-accent text-accent-foreground text-xs font-semibold px-3 py-1 rounded-full">{property.type}</span>
                      </div>
                      {property.short_code && (
                        <span className="absolute top-3 right-3 bg-card/80 backdrop-blur text-foreground text-[10px] font-bold px-2 py-1 rounded-md">
                          {property.short_code}
                        </span>
                      )}
                    </div>
                    <div className="p-5">
                      <p className="text-primary font-bold text-xl mb-1">{formatPrice(Number(property.price), property.status)}</p>
                      <h3 className="font-display text-lg font-semibold text-foreground mb-1 truncate">{property.title}</h3>
                      <p className="text-muted-foreground text-sm flex items-center gap-1 mb-4"><MapPin size={14} /> {property.neighborhood ? `${property.neighborhood}, ` : ""}{property.city || "Fortaleza"}</p>
                      <div className="flex items-center gap-4 text-foreground text-sm font-semibold border-t border-border pt-4">
                        <span className="flex items-center gap-1.5" title="Quartos">
                          <span className="w-7 h-7 rounded-lg bg-blue-500/10 flex items-center justify-center"><Bed size={16} className="text-blue-500" /></span> {property.bedrooms}
                        </span>
                        <span className="flex items-center gap-1.5" title="Banheiros">
                          <span className="w-7 h-7 rounded-lg bg-cyan-500/10 flex items-center justify-center"><Bath size={16} className="text-cyan-500" /></span> {property.bathrooms}
                        </span>
                        <span className="flex items-center gap-1.5" title="Vagas">
                          <span className="w-7 h-7 rounded-lg bg-amber-500/10 flex items-center justify-center"><Car size={16} className="text-amber-500" /></span> {property.garage_spots}
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
          )}
        </div>
      </div>
      <Footer />
      <ChatWidget />
    </div>
  );
};

export default Properties;
