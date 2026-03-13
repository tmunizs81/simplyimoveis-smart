import { motion } from "framer-motion";
import { Bed, Bath, Maximize, MapPin } from "lucide-react";
import { Link } from "react-router-dom";
import property1 from "@/assets/property-1.jpg";
import property2 from "@/assets/property-2.jpg";
import property3 from "@/assets/property-3.jpg";

export interface Property {
  id: string;
  title: string;
  address: string;
  price: number;
  bedrooms: number;
  bathrooms: number;
  area: number;
  image: string;
  type: string;
  status: "venda" | "aluguel";
}

const featuredProperties: Property[] = [
  {
    id: "1",
    title: "Apartamento Vista Mar",
    address: "Meireles, Fortaleza",
    price: 850000,
    bedrooms: 3,
    bathrooms: 2,
    area: 120,
    image: property1,
    type: "Apartamento",
    status: "venda",
  },
  {
    id: "2",
    title: "Casa com Piscina",
    address: "Eusébio, CE",
    price: 1200000,
    bedrooms: 4,
    bathrooms: 3,
    area: 250,
    image: property2,
    type: "Casa",
    status: "venda",
  },
  {
    id: "3",
    title: "Cobertura Panorâmica",
    address: "Aldeota, Fortaleza",
    price: 5500,
    bedrooms: 2,
    bathrooms: 2,
    area: 95,
    image: property3,
    type: "Cobertura",
    status: "aluguel",
  },
];

const formatPrice = (price: number, status: string) => {
  const formatted = price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  return status === "aluguel" ? `${formatted}/mês` : formatted;
};

const PropertyCard = ({ property, index }: { property: Property; index: number }) => (
  <motion.div
    initial={{ opacity: 0, y: 30 }}
    whileInView={{ opacity: 1, y: 0 }}
    viewport={{ once: true }}
    transition={{ duration: 0.5, delay: index * 0.15 }}
  >
    <Link to={`/imoveis/${property.id}`} className="block group hover-lift rounded-xl overflow-hidden glass-card">
      <div className="relative h-64 overflow-hidden">
        <img
          src={property.image}
          alt={property.title}
          className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
        />
        <div className="absolute top-3 left-3 flex gap-2">
          <span className="gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full uppercase">
            {property.status}
          </span>
          <span className="bg-accent text-accent-foreground text-xs font-semibold px-3 py-1 rounded-full">
            {property.type}
          </span>
        </div>
      </div>
      <div className="p-5">
        <p className="text-primary font-bold text-xl mb-1">
          {formatPrice(property.price, property.status)}
        </p>
        <h3 className="font-display text-lg font-semibold text-foreground mb-1">
          {property.title}
        </h3>
        <p className="text-muted-foreground text-sm flex items-center gap-1 mb-4">
          <MapPin size={14} /> {property.address}
        </p>
        <div className="flex items-center gap-4 text-muted-foreground text-sm border-t border-border pt-4">
          <span className="flex items-center gap-1"><Bed size={14} /> {property.bedrooms} quartos</span>
          <span className="flex items-center gap-1"><Bath size={14} /> {property.bathrooms} banheiros</span>
          <span className="flex items-center gap-1"><Maximize size={14} /> {property.area}m²</span>
        </div>
      </div>
    </Link>
  </motion.div>
);

const FeaturedProperties = () => {
  return (
    <section className="section-padding bg-secondary/30">
      <div className="container-custom">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-12"
        >
          <span className="text-primary text-sm font-semibold uppercase tracking-wider">Destaques</span>
          <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2">
            Imóveis em Destaque
          </h2>
          <p className="text-muted-foreground mt-3 max-w-lg mx-auto">
            Seleção especial dos melhores imóveis disponíveis em Fortaleza e região.
          </p>
        </motion.div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
          {featuredProperties.map((property, i) => (
            <PropertyCard key={property.id} property={property} index={i} />
          ))}
        </div>

        <div className="text-center mt-12">
          <Link
            to="/imoveis"
            className="inline-block border-2 border-primary text-primary px-8 py-3 rounded-xl font-semibold hover:bg-primary hover:text-primary-foreground transition-colors"
          >
            Ver Todos os Imóveis
          </Link>
        </div>
      </div>
    </section>
  );
};

export default FeaturedProperties;
export { featuredProperties, formatPrice, PropertyCard };
