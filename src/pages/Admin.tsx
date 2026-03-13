import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Trash2, Edit, LogIn, Eye, EyeOff } from "lucide-react";
import { toast } from "sonner";
import Navbar from "@/components/Navbar";

interface AdminProperty {
  id: string;
  title: string;
  address: string;
  price: number;
  bedrooms: number;
  bathrooms: number;
  area: number;
  type: string;
  status: "venda" | "aluguel";
  description: string;
}

const Admin = () => {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [properties, setProperties] = useState<AdminProperty[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [form, setForm] = useState<Omit<AdminProperty, "id">>({
    title: "",
    address: "",
    price: 0,
    bedrooms: 1,
    bathrooms: 1,
    area: 0,
    type: "Apartamento",
    status: "venda",
    description: "",
  });

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault();
    // Placeholder - will use Supabase auth later
    if (email && password) {
      setIsLoggedIn(true);
      toast.success("Login realizado com sucesso!");
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (editingId) {
      setProperties((prev) =>
        prev.map((p) => (p.id === editingId ? { ...p, ...form } : p))
      );
      toast.success("Imóvel atualizado!");
    } else {
      setProperties((prev) => [...prev, { id: crypto.randomUUID(), ...form }]);
      toast.success("Imóvel cadastrado!");
    }
    resetForm();
  };

  const resetForm = () => {
    setForm({ title: "", address: "", price: 0, bedrooms: 1, bathrooms: 1, area: 0, type: "Apartamento", status: "venda", description: "" });
    setEditingId(null);
    setShowForm(false);
  };

  const editProperty = (p: AdminProperty) => {
    setForm({ title: p.title, address: p.address, price: p.price, bedrooms: p.bedrooms, bathrooms: p.bathrooms, area: p.area, type: p.type, status: p.status, description: p.description });
    setEditingId(p.id);
    setShowForm(true);
  };

  const deleteProperty = (id: string) => {
    setProperties((prev) => prev.filter((p) => p.id !== id));
    toast.success("Imóvel removido!");
  };

  if (!isLoggedIn) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="pt-24 section-padding flex items-center justify-center">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="glass-card rounded-2xl p-8 w-full max-w-md"
          >
            <h1 className="font-display text-2xl font-bold text-foreground text-center mb-2">Área Administrativa</h1>
            <p className="text-muted-foreground text-sm text-center mb-6">Simply Imóveis</p>
            <form onSubmit={handleLogin} className="space-y-4">
              <input
                type="email"
                placeholder="E-mail"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none"
              />
              <div className="relative">
                <input
                  type={showPassword ? "text" : "password"}
                  placeholder="Senha"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none pr-10"
                />
                <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
                  {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
              <button type="submit" className="w-full gradient-primary text-primary-foreground py-3 rounded-lg font-semibold hover:opacity-90 flex items-center justify-center gap-2">
                <LogIn size={16} /> Entrar
              </button>
            </form>
          </motion.div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="pt-24 section-padding">
        <div className="container-custom">
          <div className="flex items-center justify-between mb-8">
            <div>
              <h1 className="font-display text-3xl font-bold text-foreground">Painel Admin</h1>
              <p className="text-muted-foreground text-sm">Gerencie seus imóveis</p>
            </div>
            <button
              onClick={() => { resetForm(); setShowForm(true); }}
              className="gradient-primary text-primary-foreground px-6 py-3 rounded-xl font-semibold hover:opacity-90 flex items-center gap-2"
            >
              <Plus size={18} /> Novo Imóvel
            </button>
          </div>

          {showForm && (
            <motion.form
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              onSubmit={handleSubmit}
              className="glass-card rounded-2xl p-6 mb-8 space-y-4"
            >
              <h2 className="font-display text-xl font-semibold text-foreground">
                {editingId ? "Editar Imóvel" : "Novo Imóvel"}
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <input placeholder="Título" required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                <input placeholder="Endereço" required value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                <input type="number" placeholder="Preço" required value={form.price || ""} onChange={(e) => setForm({ ...form, price: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                <input type="number" placeholder="Área (m²)" required value={form.area || ""} onChange={(e) => setForm({ ...form, area: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                <input type="number" placeholder="Quartos" required min={0} value={form.bedrooms} onChange={(e) => setForm({ ...form, bedrooms: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                <input type="number" placeholder="Banheiros" required min={0} value={form.bathrooms} onChange={(e) => setForm({ ...form, bathrooms: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                <select value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground focus:ring-2 focus:ring-ring outline-none">
                  <option>Apartamento</option>
                  <option>Casa</option>
                  <option>Cobertura</option>
                  <option>Terreno</option>
                  <option>Sala Comercial</option>
                </select>
                <select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value as "venda" | "aluguel" })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground focus:ring-2 focus:ring-ring outline-none">
                  <option value="venda">Venda</option>
                  <option value="aluguel">Aluguel</option>
                </select>
              </div>
              <textarea placeholder="Descrição do imóvel" rows={3} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none resize-none" />
              
              <p className="text-muted-foreground text-xs">📷 Upload de fotos e vídeos será habilitado com o banco de dados.</p>

              <div className="flex gap-3">
                <button type="submit" className="gradient-primary text-primary-foreground px-6 py-2.5 rounded-lg font-semibold hover:opacity-90">
                  {editingId ? "Salvar Alterações" : "Cadastrar Imóvel"}
                </button>
                <button type="button" onClick={resetForm} className="border border-border text-muted-foreground px-6 py-2.5 rounded-lg hover:bg-secondary">
                  Cancelar
                </button>
              </div>
            </motion.form>
          )}

          {properties.length === 0 && !showForm ? (
            <div className="text-center py-20 glass-card rounded-2xl">
              <p className="text-muted-foreground text-lg mb-2">Nenhum imóvel cadastrado ainda.</p>
              <p className="text-muted-foreground text-sm">Clique em "Novo Imóvel" para começar.</p>
            </div>
          ) : (
            <div className="space-y-4">
              {properties.map((p) => (
                <div key={p.id} className="glass-card rounded-xl p-4 flex items-center justify-between">
                  <div>
                    <h3 className="font-semibold text-foreground">{p.title}</h3>
                    <p className="text-muted-foreground text-sm">{p.address} • {p.type} • {p.status}</p>
                    <p className="text-primary font-bold text-sm mt-1">
                      {p.price.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
                    </p>
                  </div>
                  <div className="flex gap-2">
                    <button onClick={() => editProperty(p)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-colors">
                      <Edit size={16} />
                    </button>
                    <button onClick={() => deleteProperty(p.id)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-colors">
                      <Trash2 size={16} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default Admin;
