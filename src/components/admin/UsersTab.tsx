import { useState, useEffect } from "react";
import { motion } from "framer-motion";
import { UserPlus, Mail, Lock, Trash2, KeyRound, Users, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";

interface AdminUser {
  id: string;
  email: string;
  created_at: string;
  last_sign_in_at: string | null;
  role: string;
}

const UsersTab = () => {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [creating, setCreating] = useState(false);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [resetPasswordUserId, setResetPasswordUserId] = useState<string | null>(null);
  const [newPassword, setNewPassword] = useState("");
  const [resetting, setResetting] = useState(false);

  const invokeAdminUser = async (payload: Record<string, unknown>) => {
    const {
      data: { session },
    } = await supabase.auth.getSession();

    if (!session?.access_token) {
      throw new Error("Sessão expirada. Faça login novamente.");
    }

    const { data, error } = await supabase.functions.invoke("create-admin-user", {
      body: payload,
      headers: {
        Authorization: `Bearer ${session.access_token}`,
      },
    });

    if (error) throw new Error(error.message || "Falha ao executar ação de usuários");
    if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error);

    return data;
  };

  const fetchUsers = async () => {
    setLoading(true);
    try {
      const data = await invokeAdminUser({ action: "list" });
      setUsers((data as { users?: AdminUser[] }).users || []);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Erro ao listar usuários";
      toast.error(message);
    }
    setLoading(false);
  };

  useEffect(() => {
    fetchUsers();
  }, []);

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < 6) {
      toast.error("Mínimo 6 caracteres.");
      return;
    }

    setCreating(true);
    try {
      await invokeAdminUser({ action: "create", email, password });
      toast.success(`Usuário ${email} criado!`);
      setEmail("");
      setPassword("");
      fetchUsers();
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Erro ao criar usuário";
      toast.error(message);
    }
    setCreating(false);
  };

  const handleDelete = async (userId: string, userEmail: string) => {
    try {
      await invokeAdminUser({ action: "delete", userId });
      toast.success(`Usuário ${userEmail} removido!`);
      fetchUsers();
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Erro ao remover usuário";
      toast.error(message);
    }
  };

  const handleResetPassword = async () => {
    if (!resetPasswordUserId || newPassword.length < 6) {
      toast.error("Mínimo 6 caracteres.");
      return;
    }

    setResetting(true);
    try {
      await invokeAdminUser({ action: "update", userId: resetPasswordUserId, password: newPassword });
      toast.success("Senha alterada!");
      setResetPasswordUserId(null);
      setNewPassword("");
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Erro ao alterar senha";
      toast.error(message);
    }
    setResetting(false);
  };

  const inputClass =
    "w-full px-4 py-3.5 rounded-xl bg-secondary/30 border border-input text-foreground placeholder:text-muted-foreground/60 focus:ring-2 focus:ring-primary/30 focus:border-primary outline-none transition-all text-sm";

  return (
    <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="space-y-6">
      <div className="max-w-lg">
        <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
          <div className="gradient-primary px-6 py-5">
            <h2 className="font-display text-lg font-bold text-primary-foreground flex items-center gap-2">
              <UserPlus size={20} /> Cadastrar Novo Usuário
            </h2>
            <p className="text-primary-foreground/60 text-xs">Crie acessos para outros administradores</p>
          </div>
          <form onSubmit={handleCreate} className="p-6 space-y-4">
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 flex items-center gap-1">
                <Mail size={12} /> E-mail
              </label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="email@exemplo.com"
                className={inputClass}
              />
            </div>
            <div>
              <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 flex items-center gap-1">
                <Lock size={12} /> Senha
              </label>
              <input
                type="password"
                required
                minLength={6}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Mínimo 6 caracteres"
                className={inputClass}
              />
            </div>
            <button
              type="submit"
              disabled={creating}
              className="w-full gradient-primary text-primary-foreground py-3.5 rounded-xl font-bold text-sm uppercase tracking-wider hover:opacity-90 disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-primary/20"
            >
              {creating ? (
                <div className="w-5 h-5 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
              ) : (
                <>
                  <UserPlus size={16} /> Criar Usuário
                </>
              )}
            </button>
          </form>
        </div>
      </div>

      <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
        <div className="px-6 py-5 border-b border-border flex items-center justify-between">
          <h2 className="font-display text-lg font-bold text-foreground flex items-center gap-2">
            <Users size={20} /> Usuários Cadastrados
          </h2>
          <button onClick={fetchUsers} disabled={loading} className="text-muted-foreground hover:text-foreground transition-colors">
            <RefreshCw size={18} className={loading ? "animate-spin" : ""} />
          </button>
        </div>

        {loading ? (
          <div className="p-8 flex justify-center">
            <div className="w-6 h-6 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
          </div>
        ) : users.length === 0 ? (
          <div className="p-8 text-center text-muted-foreground text-sm">Nenhum usuário encontrado.</div>
        ) : (
          <div className="divide-y divide-border">
            {users.map((u) => (
              <div key={u.id} className="px-6 py-4 flex items-center justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-foreground truncate">{u.email}</p>
                  <p className="text-xs text-muted-foreground">
                    Criado: {new Date(u.created_at).toLocaleDateString("pt-BR")}
                    {u.last_sign_in_at && (
                      <> · Último login: {new Date(u.last_sign_in_at).toLocaleDateString("pt-BR")}</>
                    )}
                  </p>
                </div>
                <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-1 rounded-full bg-primary/10 text-primary">
                  {u.role}
                </span>
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => {
                      setResetPasswordUserId(u.id);
                      setNewPassword("");
                    }}
                    className="p-2 rounded-lg hover:bg-secondary/50 text-muted-foreground hover:text-foreground transition-colors"
                    title="Alterar senha"
                  >
                    <KeyRound size={16} />
                  </button>

                  <AlertDialog>
                    <AlertDialogTrigger asChild>
                      <button
                        className="p-2 rounded-lg hover:bg-destructive/10 text-muted-foreground hover:text-destructive transition-colors"
                        title="Remover usuário"
                      >
                        <Trash2 size={16} />
                      </button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                      <AlertDialogHeader>
                        <AlertDialogTitle>Remover usuário?</AlertDialogTitle>
                        <AlertDialogDescription>
                          Tem certeza que deseja remover <strong>{u.email}</strong>? Esta ação não pode ser desfeita.
                        </AlertDialogDescription>
                      </AlertDialogHeader>
                      <AlertDialogFooter>
                        <AlertDialogCancel>Cancelar</AlertDialogCancel>
                        <AlertDialogAction
                          onClick={() => handleDelete(u.id, u.email)}
                          className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
                        >
                          Remover
                        </AlertDialogAction>
                      </AlertDialogFooter>
                    </AlertDialogContent>
                  </AlertDialog>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <AlertDialog
        open={!!resetPasswordUserId}
        onOpenChange={(open) => {
          if (!open) setResetPasswordUserId(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Alterar Senha</AlertDialogTitle>
            <AlertDialogDescription>
              Digite a nova senha para {users.find((u) => u.id === resetPasswordUserId)?.email}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <input
            type="password"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            placeholder="Nova senha (mínimo 6 caracteres)"
            className={inputClass}
            minLength={6}
          />
          <AlertDialogFooter>
            <AlertDialogCancel>Cancelar</AlertDialogCancel>
            <AlertDialogAction onClick={handleResetPassword} disabled={resetting || newPassword.length < 6}>
              {resetting ? "Alterando..." : "Alterar Senha"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </motion.div>
  );
};

export default UsersTab;
