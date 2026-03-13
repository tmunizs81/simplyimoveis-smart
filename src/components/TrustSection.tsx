import { motion } from "framer-motion";
import { Shield, Award, CheckCircle, Star } from "lucide-react";

const badges = [
  { icon: Shield, label: "CRECI Ativo", desc: "Registro profissional verificado" },
  { icon: Award, label: "Top Corretor", desc: "Reconhecimento de excelência" },
  { icon: CheckCircle, label: "Contratos Seguros", desc: "Assessoria jurídica completa" },
  { icon: Star, label: "5 Estrelas", desc: "Avaliação dos clientes" },
];

const TrustSection = () => {
  return (
    <section className="py-16 bg-secondary/40 border-y border-border/50">
      <div className="container mx-auto px-4">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-10"
        >
          <p className="text-primary text-xs font-bold uppercase tracking-[0.2em] mb-2">
            Por que nos escolher
          </p>
          <h2 className="font-display text-2xl sm:text-3xl font-bold text-foreground">
            Confiança e Credibilidade
          </h2>
        </motion.div>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 md:gap-6">
          {badges.map((badge, i) => {
            const Icon = badge.icon;
            return (
              <motion.div
                key={badge.label}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.1 }}
                className="bg-card rounded-2xl border border-border p-6 text-center hover:shadow-xl hover:shadow-primary/5 hover:border-primary/20 transition-all duration-300 group"
              >
                <div className="w-14 h-14 rounded-2xl bg-primary/10 group-hover:bg-primary/20 flex items-center justify-center mx-auto mb-4 transition-colors">
                  <Icon size={24} className="text-primary" />
                </div>
                <p className="font-display font-bold text-sm text-foreground mb-1">{badge.label}</p>
                <p className="text-muted-foreground text-xs leading-relaxed">{badge.desc}</p>
              </motion.div>
            );
          })}
        </div>

        {/* CRECI bar */}
        <motion.div
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          className="mt-10 flex flex-wrap items-center justify-center gap-6 text-muted-foreground/60 text-xs uppercase tracking-widest font-medium"
        >
          <span>CRECI/CE • Registro Ativo</span>
          <span className="hidden sm:inline">•</span>
          <span>Atendimento Personalizado</span>
          <span className="hidden sm:inline">•</span>
          <span>Fortaleza e Região Metropolitana</span>
        </motion.div>
      </div>
    </section>
  );
};

export default TrustSection;
