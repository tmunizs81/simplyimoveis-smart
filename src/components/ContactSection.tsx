import { useState } from "react";
import { motion } from "framer-motion";
import { Send, Phone, Mail, MapPin } from "lucide-react";
import { toast } from "sonner";

const ContactSection = () => {
  const [form, setForm] = useState({ name: "", email: "", phone: "", message: "" });
  const [sending, setSending] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSending(true);
    // Simulate send
    await new Promise((r) => setTimeout(r, 1000));
    toast.success("Mensagem enviada com sucesso! Entraremos em contato em breve.");
    setForm({ name: "", email: "", phone: "", message: "" });
    setSending(false);
  };

  return (
    <section id="contato" className="section-padding bg-secondary/30">
      <div className="container-custom">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          className="text-center mb-12"
        >
          <span className="text-primary text-sm font-semibold uppercase tracking-wider">Contato</span>
          <h2 className="font-display text-3xl sm:text-4xl font-bold text-foreground mt-2">
            Fale Conosco
          </h2>
          <p className="text-muted-foreground mt-3 max-w-lg mx-auto">
            Entre em contato e encontre o imóvel perfeito para você.
          </p>
        </motion.div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12">
          <motion.div
            initial={{ opacity: 0, x: -30 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            className="space-y-6"
          >
            <div className="glass-card rounded-xl p-6 flex items-start gap-4">
              <div className="gradient-primary p-3 rounded-lg">
                <Phone className="text-primary-foreground" size={20} />
              </div>
              <div>
                <h3 className="font-semibold text-foreground">Telefone</h3>
                <p className="text-muted-foreground text-sm">(85) 99999-0000</p>
              </div>
            </div>
            <div className="glass-card rounded-xl p-6 flex items-start gap-4">
              <div className="gradient-primary p-3 rounded-lg">
                <Mail className="text-primary-foreground" size={20} />
              </div>
              <div>
                <h3 className="font-semibold text-foreground">E-mail</h3>
                <p className="text-muted-foreground text-sm">contato@simplyimoveis.com.br</p>
              </div>
            </div>
            <div className="glass-card rounded-xl p-6 flex items-start gap-4">
              <div className="gradient-primary p-3 rounded-lg">
                <MapPin className="text-primary-foreground" size={20} />
              </div>
              <div>
                <h3 className="font-semibold text-foreground">Endereço</h3>
                <p className="text-muted-foreground text-sm">Fortaleza, Ceará - Brasil</p>
              </div>
            </div>
          </motion.div>

          <motion.form
            initial={{ opacity: 0, x: 30 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            onSubmit={handleSubmit}
            className="glass-card rounded-xl p-6 space-y-4"
          >
            <input
              type="text"
              placeholder="Seu nome"
              required
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none"
            />
            <input
              type="email"
              placeholder="Seu e-mail"
              required
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none"
            />
            <input
              type="tel"
              placeholder="Seu telefone"
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
              className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none"
            />
            <textarea
              placeholder="Sua mensagem"
              required
              rows={4}
              value={form.message}
              onChange={(e) => setForm({ ...form, message: e.target.value })}
              className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none resize-none"
            />
            <button
              type="submit"
              disabled={sending}
              className="w-full gradient-primary text-primary-foreground py-3 rounded-lg font-semibold hover:opacity-90 transition-opacity flex items-center justify-center gap-2 disabled:opacity-50"
            >
              <Send size={16} />
              {sending ? "Enviando..." : "Enviar Mensagem"}
            </button>
          </motion.form>
        </div>
      </div>
    </section>
  );
};

export default ContactSection;
