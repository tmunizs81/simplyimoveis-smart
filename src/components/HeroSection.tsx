import { useState, useEffect, useCallback, useRef } from "react";
import { Link } from "react-router-dom";
import { motion, AnimatePresence } from "framer-motion";
import { Search, ArrowRight, ChevronLeft, ChevronRight, MapPin, Home, Building2 } from "lucide-react";
import heroBg from "@/assets/hero-bg.jpg";
import heroDay from "@/assets/hero-day.jpg";
import heroPortoDunas from "@/assets/hero-porto-dunas.jpg";
import heroSunset from "@/assets/hero-sunset.jpg";

const slides = [
  { image: heroBg, alt: "Orla de Fortaleza à noite", location: "Fortaleza, CE" },
  { image: heroDay, alt: "Orla de Fortaleza de dia", location: "Meireles, Fortaleza" },
  { image: heroPortoDunas, alt: "Porto das Dunas, Ceará", location: "Porto das Dunas" },
  { image: heroSunset, alt: "Pôr do sol em Fortaleza", location: "Praia do Futuro" },
];

const AnimatedCounter = ({ target, suffix = "" }: { target: number; suffix?: string }) => {
  const [count, setCount] = useState(0);
  const ref = useRef<HTMLSpanElement>(null);
  const [started, setStarted] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting && !started) setStarted(true);
    });
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, [started]);

  useEffect(() => {
    if (!started) return;
    const duration = 2000;
    const steps = 60;
    const increment = target / steps;
    let current = 0;
    const timer = setInterval(() => {
      current += increment;
      if (current >= target) { setCount(target); clearInterval(timer); }
      else setCount(Math.floor(current));
    }, duration / steps);
    return () => clearInterval(timer);
  }, [started, target]);

  return <span ref={ref}>{count}{suffix}</span>;
};

const HeroSection = () => {
  const [current, setCurrent] = useState(0);

  const next = useCallback(() => setCurrent((prev) => (prev + 1) % slides.length), []);
  const prev = useCallback(() => setCurrent((p) => (p - 1 + slides.length) % slides.length), []);

  useEffect(() => {
    const timer = setInterval(next, 7000);
    return () => clearInterval(timer);
  }, [next]);

  return (
    <section className="relative h-screen flex items-center justify-center overflow-hidden">
      {/* Background images */}
      {slides.map((slide, i) => (
        <AnimatePresence key={i}>
          {i === current && (
            <motion.div
              initial={{ opacity: 0, scale: 1.1 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 2, ease: "easeInOut" }}
              className="absolute inset-0"
            >
              <img src={slide.image} alt={slide.alt} className="w-full h-full object-cover" />
            </motion.div>
          )}
        </AnimatePresence>
      ))}

      {/* Gradient overlays */}
      <div className="absolute inset-0 bg-gradient-to-b from-black/70 via-black/40 to-black/70 z-10" />
      <div className="absolute inset-0 bg-gradient-to-r from-black/50 to-transparent z-10" />

      {/* Content */}
      <div className="relative z-20 container mx-auto px-4 sm:px-6 lg:px-8 w-full">
        <motion.div
          initial={{ opacity: 0, y: 50 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 1, ease: "easeOut", delay: 0.3 }}
          className="max-w-3xl"
        >
          <motion.span
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.6 }}
            className="inline-flex items-center gap-2 bg-white/10 backdrop-blur-md text-white text-xs font-bold px-4 py-2 rounded-full mb-6 uppercase tracking-[0.2em] border border-white/20"
          >
            <MapPin size={14} className="text-primary" />
            {slides[current].location}
          </motion.span>

          <h1 className="font-display text-3xl sm:text-5xl lg:text-7xl font-bold text-white leading-[1.1] mb-4 sm:mb-6">
            A excelência que o seu{" "}
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-primary to-yellow-400">
              patrimônio exige.
            </span>
          </h1>

          <p className="text-white/70 text-base sm:text-xl mb-6 sm:mb-10 font-body leading-relaxed max-w-xl">
            Comprometimento absoluto com a sua tranquilidade. Da busca inicial à entrega das chaves, garantimos uma jornada segura e impecável nos melhores endereços.
          </p>

          {/* Search bar */}
          <div className="bg-white/10 backdrop-blur-xl rounded-2xl p-2 border border-white/20 mb-10 max-w-2xl">
            <div className="flex flex-col sm:flex-row gap-2">
              <div className="flex-1 flex items-center gap-2 bg-white/10 rounded-xl px-4 py-3">
                <Home size={16} className="text-white/50" />
                <select className="bg-transparent text-white text-sm outline-none flex-1 appearance-none cursor-pointer">
                  <option value="" className="text-foreground">Tipo do Imóvel</option>
                  <option value="Apartamento" className="text-foreground">Apartamento</option>
                  <option value="Casa" className="text-foreground">Casa</option>
                  <option value="Cobertura" className="text-foreground">Cobertura</option>
                  <option value="Terreno" className="text-foreground">Terreno</option>
                </select>
              </div>
              <div className="flex-1 flex items-center gap-2 bg-white/10 rounded-xl px-4 py-3">
                <Building2 size={16} className="text-white/50" />
                <select className="bg-transparent text-white text-sm outline-none flex-1 appearance-none cursor-pointer">
                  <option value="" className="text-foreground">Finalidade</option>
                  <option value="venda" className="text-foreground">Comprar</option>
                  <option value="aluguel" className="text-foreground">Alugar</option>
                </select>
              </div>
              <Link
                to="/imoveis"
                className="gradient-primary text-primary-foreground px-8 py-3 rounded-xl text-sm font-bold uppercase tracking-wider hover:opacity-90 transition-all flex items-center justify-center gap-2 shadow-xl shadow-primary/30"
              >
                <Search size={16} />
                Buscar
              </Link>
            </div>
          </div>

          {/* Animated counters */}
          <div className="flex gap-8 sm:gap-12">
            {[
              { target: 30, suffix: "+", label: "Imóveis Vendidos" },
              { target: 100, suffix: "+", label: "Clientes Satisfeitos" },
              { target: 5, suffix: " anos", label: "De Experiência" },
            ].map((stat) => (
              <div key={stat.label}>
                <p className="font-display text-2xl sm:text-3xl font-bold text-white">
                  <AnimatedCounter target={stat.target} suffix={stat.suffix} />
                </p>
                <p className="text-white/50 text-xs uppercase tracking-wider font-medium">{stat.label}</p>
              </div>
            ))}
          </div>
        </motion.div>
      </div>

      {/* Navigation arrows */}
      <div className="absolute bottom-1/2 translate-y-1/2 left-4 z-20">
        <button onClick={prev} className="w-10 h-10 rounded-full bg-white/10 backdrop-blur-md border border-white/20 text-white hover:bg-white/20 transition-all flex items-center justify-center">
          <ChevronLeft size={20} />
        </button>
      </div>
      <div className="absolute bottom-1/2 translate-y-1/2 right-4 z-20">
        <button onClick={next} className="w-10 h-10 rounded-full bg-white/10 backdrop-blur-md border border-white/20 text-white hover:bg-white/20 transition-all flex items-center justify-center">
          <ChevronRight size={20} />
        </button>
      </div>

      {/* Slide indicators */}
      <div className="absolute bottom-8 left-1/2 -translate-x-1/2 z-20 flex gap-2">
        {slides.map((_, i) => (
          <button
            key={i}
            onClick={() => setCurrent(i)}
            className={`rounded-full transition-all duration-500 ${
              i === current
                ? "w-10 h-2 bg-primary"
                : "w-2 h-2 bg-white/30 hover:bg-white/50"
            }`}
            aria-label={`Slide ${i + 1}`}
          />
        ))}
      </div>

      {/* Scroll indicator */}
      <motion.div
        animate={{ y: [0, 8, 0] }}
        transition={{ repeat: Infinity, duration: 2 }}
        className="absolute bottom-20 left-1/2 -translate-x-1/2 z-20"
      >
        <div className="w-6 h-10 rounded-full border-2 border-white/30 flex items-start justify-center p-1.5">
          <motion.div
            animate={{ y: [0, 12, 0] }}
            transition={{ repeat: Infinity, duration: 2 }}
            className="w-1.5 h-1.5 rounded-full bg-white/60"
          />
        </div>
      </motion.div>
    </section>
  );
};

export default HeroSection;
