import { useState, useEffect } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { Menu, X, Settings } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import logo from "@/assets/logo-simply-clean.png";

const navLinks = [
  { label: "Início", href: "/", hash: "" },
  { label: "Imóveis", href: "/imoveis", hash: "" },
  { label: "Sobre", href: "/", hash: "sobre" },
  { label: "Contato", href: "/", hash: "contato" },
];

const Navbar = () => {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();

  const handleNavClick = (link: typeof navLinks[0]) => {
    if (link.hash) {
      if (location.pathname !== "/") {
        navigate("/");
        setTimeout(() => {
          document.getElementById(link.hash)?.scrollIntoView({ behavior: "smooth" });
        }, 300);
      } else {
        document.getElementById(link.hash)?.scrollIntoView({ behavior: "smooth" });
      }
    } else {
      navigate(link.href);
    }
  };

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
        <Link to="/" className="flex items-center group">
          <img 
            src={logo} 
            alt="SimplyImóveis by Talita Muniz" 
            className={`h-14 object-contain group-hover:scale-105 transition-transform ${
              scrolled ? "" : "brightness-0 invert"
            }`} 
          />
        </Link>

        {/* Desktop nav */}
        <div className="hidden md:flex items-center gap-1">
          {navLinks.map((link) => {
            const isActive = !link.hash && location.pathname === link.href;
            return (
              <button
                key={link.label}
                onClick={() => handleNavClick(link)}
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
              </button>
            );
          })}

          {/* Admin link */}
          <Link
            to="/admin"
            className={`ml-4 px-4 py-2 rounded-xl text-xs font-bold uppercase tracking-wider transition-all flex items-center gap-2 border ${
              scrolled
                ? "text-muted-foreground hover:text-primary border-border hover:border-primary/30"
                : "text-white/80 hover:text-white border-white/20 hover:border-white/40"
            }`}
          >
            <Settings size={14} />
            Área Admin
          </Link>
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
                <button
                  key={link.label}
                  onClick={() => { handleNavClick(link); setOpen(false); }}
                  className="block w-full text-left px-4 py-3 text-sm font-bold uppercase tracking-wider text-muted-foreground hover:text-primary hover:bg-primary/5 rounded-xl transition-all"
                >
                  {link.label}
                </button>
              ))}
              <Link
                to="/admin"
                className="block border border-border text-muted-foreground hover:text-primary px-4 py-3 rounded-xl text-sm font-bold text-center uppercase tracking-wider mt-4"
                onClick={() => setOpen(false)}
              >
                <Settings size={14} className="inline mr-2" />
                Área Admin
              </Link>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </nav>
  );
};

export default Navbar;
