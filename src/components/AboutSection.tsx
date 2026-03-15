import { motion } from "framer-motion";
import { Award, Users, Home, Heart } from "lucide-react";
import { HardHat, Briefcase, Target } from "lucide-react";
import talitaImg from "@/assets/talita-portrait.png";

const stats = [
  { icon: Home, value: "30+", label: "Imóveis Vendidos" },
  { icon: Users, value: "100+", label: "Clientes Satisfeitos" },
  { icon: Award, value: "5+", label: "Anos de Experiência" },
  { icon: Heart, value: "100%", label: "Dedicação" },
];

const pillars = [
  {
    icon: HardHat,
    title: "Visão de Construtora",
    description: "Avaliação criteriosa da qualidade estrutural, acabamento e potencial de valorização de cada imóvel.",
  },
  {
    icon: Briefcase,
    title: "Inteligência e Foco",
    description: "Negociações pautadas na transparência, ética e profissionalismo para proteger o seu investimento do início ao fim.",
  },
  {
    icon: Target,
    title: "Experiência Exclusiva",
    description: "Escuta ativa e dedicação total para conectar você ao endereço perfeito que reflete o seu sucesso.",
  },
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
            <div className="relative w-64 sm:w-80 mx-auto lg:mx-0">
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
            <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2 mb-2">
              Talita Muniz
            </h2>
            <p className="text-primary font-medium text-lg mb-6 italic">
              A expertise de quem constrói. O compromisso com o seu estilo de vida.
            </p>
            <p className="text-muted-foreground leading-relaxed mb-4">
              Cearense apaixonada por Fortaleza, Talita Muniz combina a visão estratégica da Administração de Empresas com a vivência prática de quem atua na construção civil de médio e alto padrão. Essa visão 360º do mercado imobiliário permite que ela ofereça uma assessoria técnica incomparável, avaliando cada propriedade com o olhar rigoroso de quem entende do processo do alicerce ao acabamento.
            </p>
            <p className="text-muted-foreground leading-relaxed mb-8">
              Movida pela paixão por vendas e com um perfil altamente focado e entusiasmado, Talita transforma a busca por um imóvel em uma jornada segura, transparente e empolgante. Sua missão é clara: guiar você na conquista de um patrimônio sólido — seja nos endereços mais cobiçados da capital ou em polos de alta valorização, como no Eusébio —, garantindo a chave de um lar que entregue verdadeira qualidade de vida, conforto e segurança.
            </p>

            <h3 className="font-display text-lg font-semibold text-foreground mb-4">
              Os pilares da sua assessoria:
            </h3>
            <div className="space-y-4 mb-8">
              {pillars.map((pillar) => (
                <div key={pillar.title} className="flex items-start gap-3">
                  <div className="mt-1 p-2 rounded-lg bg-primary/10">
                    <pillar.icon className="text-primary" size={20} />
                  </div>
                  <div>
                    <p className="font-semibold text-foreground">{pillar.title}</p>
                    <p className="text-muted-foreground text-sm">{pillar.description}</p>
                  </div>
                </div>
              ))}
            </div>

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
