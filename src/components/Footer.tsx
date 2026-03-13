import { Link, useNavigate, useLocation } from "react-router-dom";
import { Instagram, Phone, Mail } from "lucide-react";

const Footer = () => {
  return (
    <footer className="gradient-navy text-accent-foreground section-padding">
      <div className="container-custom">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-12">
          <div>
            <h3 className="font-display text-2xl font-bold mb-4">
              Simply<span className="text-terracotta-light">Imóveis</span>
            </h3>
            <p className="text-accent-foreground/70 text-sm leading-relaxed">
              Sua imobiliária de confiança em Fortaleza. Encontre o imóvel perfeito com atendimento personalizado.
            </p>
          </div>
          <div>
            <h4 className="font-semibold mb-4">Links Rápidos</h4>
            <div className="space-y-2">
              <Link to="/" className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Início</Link>
              <Link to="/imoveis" className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Imóveis</Link>
              <a href="/#sobre" className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Sobre</a>
              <a href="/#contato" className="block text-accent-foreground/70 text-sm hover:text-terracotta-light transition-colors">Contato</a>
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
