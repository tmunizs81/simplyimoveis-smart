import { useState } from "react";
import { motion } from "framer-motion";
import { KeyRound, Shield } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";

const PasswordTab = () => {
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [changing, setChanging] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword.length < 6) { toast.error("Mínimo 6 caracteres."); return; }
    if (newPassword !== confirmPassword) { toast.error("As senhas não coincidem."); return; }
    setChanging(true);
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    if (error) { toast.error(error.message); }
    else { toast.success("Senha alterada com sucesso!"); setNewPassword(""); setConfirmPassword(""); }
    setChanging(false);
  };

  const inputClass = "w-full px-4 py-3.5 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="max-w-lg">
      <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
        <div className="gradient-primary px-6 py-5">
          <h2 className="font-display text-lg font-bold text-primary-foreground flex items-center gap-2">
            <Shield size={20} /> Alterar Senha
          </h2>
          <p className="text-primary-foreground/60 text-xs">Use uma senha forte com letras, números e símbolos</p>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Nova senha</label>
            <input type="password" required minLength={6} value={newPassword} onChange={(e) => setNewPassword(e.target.value)} placeholder="Mínimo 6 caracteres" className={inputClass} />
          </div>
          <div>
            <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Confirmar nova senha</label>
            <input type="password" required minLength={6} value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} placeholder="Repita a nova senha" className={inputClass} />
          </div>
          <button type="submit" disabled={changing} className="w-full gradient-primary text-primary-foreground py-3.5 rounded-xl font-bold text-sm uppercase tracking-wider hover:opacity-90 disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-primary/20">
            {changing ? <div className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" /> : <><KeyRound size={16} /> Alterar Senha</>}
          </button>
        </form>
      </div>
    </motion.div>
  );
};

export default PasswordTab;
