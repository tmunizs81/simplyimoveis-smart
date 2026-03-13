import { Link, useNavigate, useLocation } from "react-router-dom";
import { Instagram, Phone, Mail } from "lucide-react";
import logo from "@/assets/logo.png";

const Footer = () => {
  const navigate = useNavigate();
  const location = useLocation();

  const scrollToSection = (id: string) => {
    if (location.pathname !== "/") {
      navigate("/");
      setTimeout(() => {
        document.getElementById(id)?.scrollIntoView({ behavior: "smooth" });
      }, 300);
    } else {
      document.getElementById(id)?.scrollIntoView({ behavior: "smooth" });
    }
  };
  return (
    <footer className="gradient-navy text-accent-foreground section-padding">
      <div className="container-custom">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-12">
          <div>
            <div className="flex items-center gap-3 mb-4">
              <img src={logo} alt="SimplyImóveis" className="h-11 w-11 object-contain" />
              <div className="flex flex-col leading-tight">
                <span className="font-display text-xl font-bold">
                  <span className="text-accent-foreground">simply</span>
                  <span className="text-primary">Imóveis</span>
                </span>
                <span className="text-accent-foreground/50 text-[10px] tracking-widest">— by Talita Muniz —</span>
              </div>
            </div>
            <p className="text-accent-foreground/70 text-sm leading-relaxed">
              Sua imobiliária de confiança em Fortaleza. Encontre o imóvel perfeito com atendimento personalizado.
            </p>
          </div>
          <div>
            <h4 className="font-semibold mb-4">Links Rápidos</h4>
            <div className="space-y-2">
              <Link to="/" className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Início</Link>
              <Link to="/imoveis" className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Imóveis</Link>
              <button onClick={() => scrollToSection("sobre")} className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Sobre</button>
              <button onClick={() => scrollToSection("contato")} className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Contato</button>
            </div>
          </div>
          <div>
            <h4 className="font-semibold mb-4">Redes Sociais</h4>
            <div className="flex gap-4">
              <a href="#" className="text-accent-foreground/70 hover:text-terracotta-light transition-colors">
                <Instagram size={20} />
              </a>
              <a href="tel:+5585999990000" className="text-accent-foreground/70 hover:text-terracotta-light transition-colors">
                <Phone size={20} />
              </a>
              <a href="mailto:contato@simplyimoveis.com.br" className="text-accent-foreground/70 hover:text-terracotta-light transition-colors">
                <Mail size={20} />
              </a>
            </div>
          </div>
        </div>
        <div className="border-t border-accent-foreground/20 mt-12 pt-8 text-center text-accent-foreground/50 text-sm">
          © {new Date().getFullYear()} Simply Imóveis. Todos os direitos reservados. | CRECI: XXXXX
        </div>
      </div>
    </footer>
  );
};

export default Footer;
