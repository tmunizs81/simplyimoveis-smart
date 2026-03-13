import { motion } from "framer-motion";
import { Award, Users, Home, Heart } from "lucide-react";
import talitaImg from "@/assets/talita-portrait.png";

const stats = [
  { icon: Home, value: "200+", label: "Imóveis Vendidos" },
  { icon: Users, value: "500+", label: "Clientes Satisfeitos" },
  { icon: Award, value: "5+", label: "Anos de Experiência" },
  { icon: Heart, value: "100%", label: "Dedicação" },
];

const AboutSection = () => {
  return (
    <section id="sobre" className="section-padding">
      <div className="container-custom">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
          <motion.div
            initial={{ opacity: 0, x: -40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6 }}
            className="relative"
          >
            <div className="relative w-80 mx-auto lg:mx-0">
              <div className="absolute -inset-4 gradient-primary rounded-2xl rotate-3 opacity-20" />
              <img
                src={talitaImg}
                alt="Talita Muniz - Corretora"
                className="relative rounded-2xl w-full object-cover shadow-2xl"
              />
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, x: 40 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6 }}
          >
            <span className="text-primary text-sm font-semibold uppercase tracking-wider">Sobre</span>
            <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2 mb-6">
              Talita Muniz
            </h2>
            <p className="text-muted-foreground leading-relaxed mb-4">
              Cearense apaixonada pelo mercado imobiliário, Talita Muniz fundou a <strong className="text-foreground">Simply Imóveis</strong> com a missão de transformar a experiência de compra e venda de imóveis em Fortaleza.
            </p>
            <p className="text-muted-foreground leading-relaxed mb-8">
              Com atendimento personalizado e transparente, ela ajuda seus clientes a encontrarem não apenas um imóvel, mas um verdadeiro lar. Sua jovialidade e energia contagiam todos ao redor, tornando cada negociação uma experiência única.
            </p>

            <div className="grid grid-cols-2 gap-6">
              {stats.map((stat) => (
                <div key={stat.label} className="glass-card rounded-xl p-4 text-center">
                  <stat.icon className="mx-auto text-primary mb-2" size={24} />
                  <p className="font-display text-2xl font-bold text-foreground">{stat.value}</p>
                  <p className="text-muted-foreground text-xs">{stat.label}</p>
                </div>
              ))}
            </div>
          </motion.div>
        </div>
      </div>
    </section>
  );
};

export default AboutSection;
