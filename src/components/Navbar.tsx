import { useState, useEffect } from "react";
import { Link, useLocation } from "react-router-dom";
import { Menu, X, Phone } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import logo from "@/assets/logo.png";

const navLinks = [
  { label: "Início", href: "/" },
  { label: "Imóveis", href: "/imoveis" },
  { label: "Sobre", href: "/#sobre" },
  { label: "Contato", href: "/#contato" },
];

const Navbar = () => {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const location = useLocation();

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 50);
    window.addEventListener("scroll", handleScroll);
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-500 ${
        scrolled
          ? "bg-background/95 backdrop-blur-xl shadow-lg border-b border-border/50"
          : "bg-transparent"
      }`}
    >
      <div className="container mx-auto flex items-center justify-between h-20 px-4 sm:px-6 lg:px-8">
        {/* Logo */}
        <Link to="/" className="flex items-center gap-3 group">
          <img src={logo} alt="SimplyImoveis" className="h-11 w-11 object-contain group-hover:scale-105 transition-transform" />
          <span className="font-display text-xl font-bold">
            <span className={scrolled ? "text-foreground" : "text-white"}>Simply</span>
            <span className="text-primary">Imóveis</span>
          </span>
        </Link>

        {/* Desktop nav */}
        <div className="hidden md:flex items-center gap-1">
          {navLinks.map((link) => {
            const isActive = location.pathname === link.href;
            return (
              <Link
                key={link.href}
                to={link.href}
                className={`relative px-4 py-2 text-xs font-bold uppercase tracking-[0.15em] transition-colors rounded-lg ${
                  isActive
                    ? "text-primary"
                    : scrolled
                    ? "text-muted-foreground hover:text-primary"
                    : "text-white/80 hover:text-white"
                }`}
              >
                {link.label}
                {isActive && (
                  <motion.span
                    layoutId="nav-indicator"
                    className="absolute bottom-0 left-4 right-4 h-0.5 bg-primary rounded-full"
                  />
                )}
              </Link>
            );
          })}

          {/* CTA */}
          <a
            href="tel:+5585999990000"
            className="ml-4 gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl text-xs font-bold uppercase tracking-wider hover:opacity-90 transition-all flex items-center gap-2 shadow-lg shadow-primary/20"
          >
            <Phone size={14} />
            Ligar Agora
          </a>
        </div>

        {/* Mobile toggle */}
        <button
          className={`md:hidden transition-colors ${scrolled ? "text-foreground" : "text-white"}`}
          onClick={() => setOpen(!open)}
        >
          {open ? <X size={24} /> : <Menu size={24} />}
        </button>
      </div>

      {/* Mobile menu */}
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="md:hidden bg-background/98 backdrop-blur-xl border-t border-border overflow-hidden"
          >
            <div className="px-6 py-6 space-y-1">
              {navLinks.map((link) => (
                <Link
                  key={link.href}
                  to={link.href}
                  className="block px-4 py-3 text-sm font-bold uppercase tracking-wider text-muted-foreground hover:text-primary hover:bg-primary/5 rounded-xl transition-all"
                  onClick={() => setOpen(false)}
                >
                  {link.label}
                </Link>
              ))}
              <a
                href="tel:+5585999990000"
                className="block gradient-primary text-primary-foreground px-4 py-3 rounded-xl text-sm font-bold text-center uppercase tracking-wider mt-4"
                onClick={() => setOpen(false)}
              >
                <Phone size={14} className="inline mr-2" />
                Ligar Agora
              </a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};

export default Navbar;
