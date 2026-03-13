import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { Search, ArrowRight } from "lucide-react";
import heroBg from "@/assets/hero-bg.jpg";

const HeroSection = () => {
  return (
    <section className="relative min-h-[90vh] flex items-center justify-center overflow-hidden">
      <div
        className="absolute inset-0 bg-cover bg-center"
        style={{ backgroundImage: `url(${heroBg})` }}
      >
        <div className="absolute inset-0 bg-gradient-to-r from-foreground/80 via-foreground/50 to-transparent" />
      </div>

      <div className="relative z-10 container-custom px-4 sm:px-6 lg:px-8 w-full">
        <motion.div
          initial={{ opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, ease: "easeOut" }}
          className="max-w-2xl"
        >
          <span className="inline-block gradient-primary text-primary-foreground text-xs font-semibold px-3 py-1 rounded-full mb-6 uppercase tracking-wider">
            Simply Imóveis — Fortaleza, CE
          </span>
          <h1 className="font-display text-4xl sm:text-5xl lg:text-6xl font-bold text-primary-foreground leading-tight mb-6">
            Encontre o imóvel dos seus{" "}
            <span className="text-gradient">sonhos</span>
          </h1>
          <p className="text-primary-foreground/80 text-lg sm:text-xl mb-8 font-light leading-relaxed">
            Com Talita Muniz, sua corretora de confiança. Atendimento personalizado e os melhores imóveis de Fortaleza.
          </p>
          <div className="flex flex-col sm:flex-row gap-4">
            <Link
              to="/imoveis"
              className="gradient-primary text-primary-foreground px-8 py-4 rounded-xl text-base font-semibold hover:opacity-90 transition-opacity flex items-center justify-center gap-2"
            >
              <Search size={18} />
              Ver Imóveis
            </Link>
            <a
              href="#contato"
              className="border border-primary-foreground/30 text-primary-foreground px-8 py-4 rounded-xl text-base font-semibold hover:bg-primary-foreground/10 transition-colors flex items-center justify-center gap-2"
            >
              Fale Conosco
              <ArrowRight size={18} />
            </a>
          </div>
        </motion.div>
      </div>
    </section>
  );
};

export default HeroSection;
