import { useState, useEffect, useCallback } from "react";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { Search, ArrowRight } from "lucide-react";
import heroBg from "@/assets/hero-bg.jpg";
import heroDay from "@/assets/hero-day.jpg";
import heroPortoDunas from "@/assets/hero-porto-dunas.jpg";
import heroSunset from "@/assets/hero-sunset.jpg";

const slides = [
  { image: heroBg, alt: "Orla de Fortaleza à noite" },
  { image: heroDay, alt: "Orla de Fortaleza de dia" },
  { image: heroPortoDunas, alt: "Porto das Dunas, Ceará" },
  { image: heroSunset, alt: "Pôr do sol em Fortaleza" },
];

const HeroSection = () => {
  const [current, setCurrent] = useState(0);

  const next = useCallback(() => {
    setCurrent((prev) => (prev + 1) % slides.length);
  }, []);

  useEffect(() => {
    const timer = setInterval(next, 6000);
    return () => clearInterval(timer);
  }, [next]);

  return (
    <section className="relative min-h-[90vh] flex items-center justify-center overflow-hidden">
      {/* Background images with crossfade */}
      {slides.map((slide, i) => (
        <AnimatePresence key={i}>
          {i === current && (
            <motion.div
              initial={{ opacity: 0, scale: 1.08 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 1.5, ease: "easeInOut" }}
              className="absolute inset-0"
            >
              <img
                src={slide.image}
                alt={slide.alt}
                className="w-full h-full object-cover"
              />
            </motion.div>
          )}
        </AnimatePresence>
      ))}

      {/* Overlay */}
      <div className="absolute inset-0 bg-gradient-to-r from-foreground/80 via-foreground/50 to-foreground/20 z-10" />

      {/* Content */}
      <div className="relative z-20 container-custom px-4 sm:px-6 lg:px-8 w-full">
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

      {/* Slide indicators */}
      <div className="absolute bottom-8 left-1/2 -translate-x-1/2 z-20 flex gap-2">
        {slides.map((_, i) => (
          <button
            key={i}
            onClick={() => setCurrent(i)}
            className={`h-1.5 rounded-full transition-all duration-500 ${
              i === current
                ? "w-8 bg-primary-foreground"
                : "w-3 bg-primary-foreground/40 hover:bg-primary-foreground/60"
            }`}
            aria-label={`Slide ${i + 1}`}
          />
        ))}
      </div>
    </section>
  );
};

export default HeroSection;
