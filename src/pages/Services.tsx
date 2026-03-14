import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";
import WhatsAppButton from "@/components/WhatsAppButton";
import { motion } from "framer-motion";
import { Gem, TrendingUp, SearchCheck, Building, HardHat, Home } from "lucide-react";
import servicesHero from "@/assets/services-hero.jpg";

const services = [
  {
    icon: Gem,
    title: "Curadoria de Imóveis Premium",
    subtitle: "Compra e Venda",
    description:
      "Mais do que apresentar opções, realizamos uma seleção rigorosa de propriedades de médio e alto padrão nos endereços mais cobiçados. Da busca criteriosa à negociação blindada, garantimos que sua próxima aquisição seja o reflexo perfeito do seu estilo de vida, com total conforto e segurança.",
    highlight: false,
  },
  {
    icon: TrendingUp,
    title: "Consultoria de Investimentos Imobiliários",
    subtitle: "",
    description:
      "Direcionamento estratégico para quem busca proteger e multiplicar seu patrimônio. Através de uma análise de mercado apurada, identificamos as melhores oportunidades com alto potencial de rentabilidade e valorização, garantindo decisões seguras e baseadas em dados.",
    highlight: false,
  },
  {
    icon: SearchCheck,
    title: "Avaliação Técnica Especializada",
    subtitle: "O seu grande diferencial",
    description:
      "O olhar de quem constrói a favor do seu negócio. Diferente da corretagem tradicional, oferecemos uma análise detalhada da qualidade estrutural, excelência dos acabamentos e potencial real de cada imóvel. É a tranquilidade de fechar negócio sabendo exatamente o que está comprando.",
    highlight: true,
  },
  {
    icon: Building,
    title: "Lançamentos e Projetos Exclusivos",
    subtitle: "",
    description:
      "Acesso privilegiado aos empreendimentos mais aguardados e inovadores da região. Antecipe-se às tendências do mercado e garanta unidades exclusivas na planta com condições diferenciadas e assessoria completa do início ao fim da obra.",
    highlight: false,
  },
  {
    icon: HardHat,
    title: "Gestão de Obras e Reformas de Alto Padrão",
    subtitle: "",
    description:
      "Transformar o seu imóvel não precisa ser sinônimo de dor de cabeça. Unindo a expertise técnica de construtora à precisão da administração de empresas, cuidamos de cada detalhe do seu projeto. Do planejamento rigoroso à execução impecável dos acabamentos, garantimos o cumprimento de prazos, a otimização de custos e a entrega do seu espaço com a excelência que você exige.",
    highlight: false,
  },
  {
    icon: Home,
    title: "Locação Premium e Gestão Patrimonial",
    subtitle: "",
    description:
      "Rentabilidade e segurança para quem investe; conforto e exclusividade para quem mora. Realizamos uma seleção criteriosa de imóveis de médio e alto padrão para locação, conectando perfis qualificados aos melhores endereços da região. Oferecemos uma assessoria administrativa completa, garantindo tranquilidade jurídica e financeira de ponta a ponta.",
    highlight: false,
  },
];

const Services = () => {
  return (
    <div className="min-h-screen bg-background">
      <Navbar />

      {/* Hero banner */}
      <section
        className="pt-32 pb-16 text-accent-foreground text-center relative"
        style={{
          backgroundImage: `url(${servicesHero})`,
          backgroundSize: "cover",
          backgroundPosition: "center",
        }}
      >
        <div className="absolute inset-0 bg-accent/80 backdrop-blur-[2px]" />
        <div className="container-custom px-4">
          <motion.p
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-primary font-bold text-xs uppercase tracking-[0.2em] mb-4"
          >
            O que fazemos por você
          </motion.p>
          <motion.h1
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1 }}
            className="font-display text-4xl md:text-5xl font-bold mb-4"
          >
            Nossos <span className="text-gradient">Serviços</span>
          </motion.h1>
          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="text-accent-foreground/70 max-w-2xl mx-auto text-lg"
          >
            Assessoria completa, do alicerce ao acabamento, para quem busca excelência no mercado imobiliário.
          </motion.p>
        </div>
        </div>
      </section>

      {/* Services grid */}
      <section className="section-padding">
        <div className="container-custom">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {services.map((service, index) => {
              const Icon = service.icon;
              return (
                <motion.div
                  key={service.title}
                  initial={{ opacity: 0, y: 30 }}
                  whileInView={{ opacity: 1, y: 0 }}
                  viewport={{ once: true }}
                  transition={{ delay: index * 0.1 }}
                  className={`relative rounded-2xl p-8 transition-all duration-300 hover-lift group ${
                    service.highlight
                      ? "bg-primary/5 border-2 border-primary/30 ring-1 ring-primary/10"
                      : "bg-card border border-border"
                  }`}
                >
                  {/* Highlight badge */}
                  {service.highlight && (
                    <span className="absolute -top-3 left-6 bg-primary text-primary-foreground text-[10px] font-bold uppercase tracking-widest px-4 py-1 rounded-full">
                      Diferencial
                    </span>
                  )}

                  {/* Icon */}
                  <div
                    className={`w-14 h-14 rounded-xl flex items-center justify-center mb-5 transition-colors ${
                      service.highlight
                        ? "gradient-primary text-primary-foreground"
                        : "bg-secondary text-primary group-hover:bg-primary/10"
                    }`}
                  >
                    <Icon size={26} strokeWidth={1.8} />
                  </div>

                  {/* Title */}
                  <h3 className="font-display text-lg font-bold text-foreground mb-1">
                    {service.title}
                  </h3>
                  {service.subtitle && (
                    <p className="text-primary text-xs font-bold uppercase tracking-wider mb-3">
                      {service.subtitle}
                    </p>
                  )}

                  {/* Description */}
                  <p className="text-muted-foreground text-sm leading-relaxed">
                    {service.description}
                  </p>
                </motion.div>
              );
            })}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="section-padding bg-secondary/50">
        <div className="container-custom text-center">
          <motion.h2
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            className="font-display text-3xl font-bold text-foreground mb-4"
          >
            Pronto para dar o próximo passo?
          </motion.h2>
          <motion.p
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ delay: 0.1 }}
            className="text-muted-foreground mb-8 max-w-xl mx-auto"
          >
            Agende uma consulta personalizada e descubra como podemos ajudar você.
          </motion.p>
          <motion.a
            initial={{ opacity: 0, y: 20 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ delay: 0.2 }}
            href="https://wa.me/5585999990000"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 gradient-primary text-primary-foreground font-bold px-8 py-4 rounded-xl hover:opacity-90 transition-opacity"
          >
            Fale com a Talita
          </motion.a>
        </div>
      </section>

      <Footer />
      <ChatWidget />
      <WhatsAppButton />
    </div>
  );
};

export default Services;
