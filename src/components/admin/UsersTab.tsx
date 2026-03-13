import { useState } from "react";
import { motion } from "framer-motion";
import { UserPlus, Mail, Lock } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";

const UsersTab = () => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [creating, setCreating] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < 6) { toast.error("Mínimo 6 caracteres."); return; }
    setCreating(true);
    try {
      const { data, error } = await supabase.functions.invoke("create-admin-user", {
        body: { email, password },
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      toast.success(`Usuário ${email} criado!`);
      setEmail(""); setPassword("");
    } catch (err: any) {
      toast.error(err.message || "Erro ao criar usuário");
    }
    setCreating(false);
  };

  const inputClass = "w-full px-4 py-3.5 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-lg">
      <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
        <div className="gradient-primary px-6 py-5">
          <h2 className="font-display text-lg font-bold text-primary-foreground flex items-center gap-2">
            <UserPlus size={20} /> Cadastrar Novo Usuário
          </h2>
          <p className="text-primary-foreground/60 text-xs">Crie acessos para outros administradores</p>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 flex items-center gap-1"><Mail size={12} /> E-mail</label>
            <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="email@exemplo.com" className={inputClass} />
          </div>
          <div>
            <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 flex items-center gap-1"><Lock size={12} /> Senha</label>
            <input type="password" required minLength={6} value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Mínimo 6 caracteres" className={inputClass} />
          </div>
          <button type="submit" disabled={creating} className="w-full gradient-primary text-primary-foreground py-3.5 rounded-xl font-bold text-sm uppercase tracking-wider hover:opacity-90 disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-primary/20">
            {creating ? <div className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" /> : <><UserPlus size={16} /> Criar Usuário</>}
          </button>
        </form>
      </div>
    </motion.div>
  );
};

export default UsersTab;
