import { motion } from "framer-motion";
import cidadeAlpha1 from "@/assets/cidade-alpha-1.jpg";
import cidadeAlpha2 from "@/assets/cidade-alpha-2.jpg";
import { MapPin, Shield, Trees, Home } from "lucide-react";

const features = [
  { icon: Shield, label: "Segurança 24h", desc: "Portaria blindada e monitoramento" },
  { icon: Trees, label: "Área Verde", desc: "Paisagismo tropical exuberante" },
  { icon: Home, label: "Alto Padrão", desc: "Casas com arquitetura moderna" },
  { icon: MapPin, label: "Localização", desc: "Eusébio, região metropolitana" },
];

const CidadeAlphaSection = () => {
  return (
    <section className="py-20 bg-accent text-accent-foreground overflow-hidden">
      <div className="container mx-auto px-4">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center mb-12"
        >
          <p className="text-sm font-bold uppercase tracking-[0.2em] text-primary mb-3">
            Condomínio Premium
          </p>
          <h2 className="font-display text-3xl md:text-5xl font-bold mb-4">
            Cidade Alpha — Eusébio, CE
          </h2>
          <p className="text-accent-foreground/60 max-w-2xl mx-auto font-body text-lg">
            O maior e mais completo condomínio fechado do Ceará. Viva com exclusividade,
            segurança e qualidade de vida incomparáveis.
          </p>
        </motion.div>

        {/* Images grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-14">
          <motion.div
            initial={{ opacity: 0, x: -40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.7 }}
            className="relative group rounded-2xl overflow-hidden shadow-2xl"
          >
            <img
              src={cidadeAlpha1}
              alt="Vista aérea do Cidade Alpha, Eusébio - Ceará"
              className="w-full h-[350px] lg:h-[420px] object-cover group-hover:scale-105 transition-transform duration-700"
            />
            <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent" />
            <div className="absolute bottom-6 left-6">
              <span className="bg-primary text-primary-foreground text-xs font-bold uppercase tracking-wider px-3 py-1.5 rounded-full">
                Vista Aérea
              </span>
              <p className="text-white font-display font-bold text-xl mt-2">
                Infraestrutura Completa
              </p>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, x: 40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.7, delay: 0.15 }}
            className="relative group rounded-2xl overflow-hidden shadow-2xl"
          >
            <img
              src={cidadeAlpha2}
              alt="Entrada do Cidade Alpha, Eusébio - Ceará"
              className="w-full h-[350px] lg:h-[420px] object-cover group-hover:scale-105 transition-transform duration-700"
            />
            <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent" />
            <div className="absolute bottom-6 left-6">
              <span className="bg-primary text-primary-foreground text-xs font-bold uppercase tracking-wider px-3 py-1.5 rounded-full">
                Entrada Principal
              </span>
              <p className="text-white font-display font-bold text-xl mt-2">
                Portaria de Alto Padrão
              </p>
            </div>
          </motion.div>
        </div>

        {/* Features */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {features.map((feat, i) => {
            const Icon = feat.icon;
            return (
              <motion.div
                key={feat.label}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.1 }}
                className="bg-accent-foreground/5 border border-accent-foreground/10 rounded-xl p-5 text-center hover:bg-accent-foreground/10 transition-colors"
              >
                <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center mx-auto mb-3">
                  <Icon size={20} className="text-primary" />
                </div>
                <p className="font-display font-bold text-sm text-accent-foreground">{feat.label}</p>
                <p className="text-accent-foreground/50 text-xs mt-1">{feat.desc}</p>
              </motion.div>
            );
          })}
        </div>
      </div>
    </section>
  );
};

export default CidadeAlphaSection;
