import { motion } from "framer-motion";
import { Star, Quote } from "lucide-react";

const testimonials = [
  {
    name: "Mariana Costa",
    role: "Compradora — Meireles",
    text: "A Talita foi excepcional do início ao fim. Encontrou o apartamento perfeito para nossa família e nos guiou em cada etapa da negociação com muita transparência e profissionalismo.",
    rating: 5,
  },
  {
    name: "Ricardo Oliveira",
    role: "Investidor — Eusébio",
    text: "Como investidor, preciso de uma corretora que entenda o mercado. A Talita tem uma visão estratégica impressionante e me ajudou a encontrar oportunidades com alto potencial de valorização.",
    rating: 5,
  },
  {
    name: "Ana Paula Souza",
    role: "Locatária — Porto das Dunas",
    text: "Processo de locação foi rápido e sem estresse. A equipe cuidou de toda a documentação e me entregou as chaves no prazo combinado. Recomendo demais!",
    rating: 5,
  },
  {
    name: "Carlos Henrique",
    role: "Comprador — Cidade Alpha",
    text: "O conhecimento técnico da Talita sobre construção civil fez toda a diferença na avaliação do imóvel. Compramos com total segurança sabendo que fizemos um excelente negócio.",
    rating: 5,
  },
];

const TestimonialsSection = () => {
  return (
    <section className="section-padding bg-secondary/30">
      <div className="container-custom">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-12"
        >
          <span className="text-primary text-sm font-semibold uppercase tracking-widest">Depoimentos</span>
          <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2">
            O que nossos clientes dizem
          </h2>
          <p className="text-muted-foreground mt-3 max-w-lg mx-auto">
            A satisfação de quem confiou na Simply Imóveis para realizar seus sonhos.
          </p>
        </motion.div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {testimonials.map((t, i) => (
            <motion.div
              key={t.name}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5, delay: i * 0.1 }}
              className="glass-card rounded-2xl p-6 relative group hover:shadow-xl hover:shadow-primary/5 transition-all duration-300"
            >
              <Quote size={32} className="text-primary/10 absolute top-4 right-4" />

              <div className="flex gap-1 mb-4">
                {Array.from({ length: t.rating }).map((_, j) => (
                  <Star key={j} size={14} className="text-primary fill-primary" />
                ))}
              </div>

              <p className="text-foreground text-sm leading-relaxed mb-6 italic">
                "{t.text}"
              </p>

              <div className="flex items-center gap-3 border-t border-border pt-4">
                <div className="w-10 h-10 rounded-full gradient-primary flex items-center justify-center text-primary-foreground font-bold text-sm">
                  {t.name.split(" ").map(w => w[0]).join("").slice(0, 2)}
                </div>
                <div>
                  <p className="font-semibold text-sm text-foreground">{t.name}</p>
                  <p className="text-xs text-muted-foreground">{t.role}</p>
                </div>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default TestimonialsSection;
