import { useState, useEffect, useCallback } from "react";
import { motion } from "framer-motion";
import { Plus, Trash2, Edit, LogIn, Eye, EyeOff, Upload, X, Image, Video, LogOut, KeyRound, UserPlus, Settings } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import Navbar from "@/components/Navbar";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];

const PROPERTY_TYPES = ["Apartamento", "Casa", "Cobertura", "Terreno", "Sala Comercial"] as const;

type AdminTab = "properties" | "password" | "users";

const Admin = () => {
  const [user, setUser] = useState<any>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [properties, setProperties] = useState<(Property & { media: MediaRow[] })[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [mediaFiles, setMediaFiles] = useState<File[]>([]);
  const [existingMedia, setExistingMedia] = useState<MediaRow[]>([]);
  const [activeTab, setActiveTab] = useState<AdminTab>("properties");

  // Password change state
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [changingPassword, setChangingPassword] = useState(false);

  // User creation state
  const [newUserEmail, setNewUserEmail] = useState("");
  const [newUserPassword, setNewUserPassword] = useState("");
  const [creatingUser, setCreatingUser] = useState(false);

  const [form, setForm] = useState({
    title: "", address: "", price: 0, bedrooms: 1, bathrooms: 1,
    area: 0, type: "Apartamento" as typeof PROPERTY_TYPES[number],
    status: "venda" as "venda" | "aluguel", description: "", featured: false,
  });

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      setAuthLoading(false);
    });
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      setAuthLoading(false);
    });
    return () => subscription.unsubscribe();
  }, []);

  const fetchProperties = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from("properties")
      .select("*")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false });

    if (!data) return;

    const withMedia = await Promise.all(
      data.map(async (p) => {
        const { data: media } = await supabase
          .from("property_media")
          .select("*")
          .eq("property_id", p.id)
          .order("sort_order");
        return { ...p, media: media || [] };
      })
    );
    setProperties(withMedia);
  }, [user]);

  useEffect(() => { fetchProperties(); }, [fetchProperties]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      if (error.message.includes("Invalid login")) {
        toast.error("E-mail ou senha incorretos.");
      } else {
        toast.error(error.message);
      }
    } else {
      toast.success("Login realizado!");
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
    toast.success("Logout realizado.");
  };

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword.length < 6) {
      toast.error("A senha deve ter no mínimo 6 caracteres.");
      return;
    }
    if (newPassword !== confirmPassword) {
      toast.error("As senhas não coincidem.");
      return;
    }
    setChangingPassword(true);
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    if (error) {
      toast.error(error.message);
    } else {
      toast.success("Senha alterada com sucesso!");
      setNewPassword("");
      setConfirmPassword("");
    }
    setChangingPassword(false);
  };

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newUserPassword.length < 6) {
      toast.error("A senha deve ter no mínimo 6 caracteres.");
      return;
    }
    setCreatingUser(true);
    try {
      const { data, error } = await supabase.functions.invoke("create-admin-user", {
        body: { email: newUserEmail, password: newUserPassword },
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      toast.success(`Usuário ${newUserEmail} criado com sucesso!`);
      setNewUserEmail("");
      setNewUserPassword("");
    } catch (err: any) {
      toast.error(err.message || "Erro ao criar usuário");
    }
    setCreatingUser(false);
  };

  const getMediaUrl = (filePath: string) => {
    const { data } = supabase.storage.from("property-media").getPublicUrl(filePath);
    return data.publicUrl;
  };

  const uploadMedia = async (propertyId: string) => {
    for (let i = 0; i < mediaFiles.length; i++) {
      const file = mediaFiles[i];
      const ext = file.name.split(".").pop();
      const path = `${user.id}/${propertyId}/${crypto.randomUUID()}.${ext}`;
      const { error: uploadError } = await supabase.storage
        .from("property-media")
        .upload(path, file);
      if (uploadError) { toast.error(`Erro ao enviar ${file.name}`); continue; }

      const fileType = file.type.startsWith("video") ? "video" : "image";
      await supabase.from("property_media").insert({
        property_id: propertyId,
        file_path: path,
        file_type: fileType,
        sort_order: i,
      });
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    setSaving(true);

    try {
      if (editingId) {
        const { error } = await supabase.from("properties").update({
          title: form.title, address: form.address, price: form.price,
          bedrooms: form.bedrooms, bathrooms: form.bathrooms, area: form.area,
          type: form.type, status: form.status, description: form.description,
          featured: form.featured,
        }).eq("id", editingId);
        if (error) throw error;
        if (mediaFiles.length) await uploadMedia(editingId);
        toast.success("Imóvel atualizado!");
      } else {
        const { data, error } = await supabase.from("properties").insert({
          user_id: user.id, title: form.title, address: form.address,
          price: form.price, bedrooms: form.bedrooms, bathrooms: form.bathrooms,
          area: form.area, type: form.type, status: form.status,
          description: form.description, featured: form.featured,
        }).select().single();
        if (error) throw error;
        if (mediaFiles.length && data) await uploadMedia(data.id);
        toast.success("Imóvel cadastrado!");
      }
      resetForm();
      fetchProperties();
    } catch (err: any) {
      toast.error(err.message || "Erro ao salvar");
    } finally {
      setSaving(false);
    }
  };

  const resetForm = () => {
    setForm({ title: "", address: "", price: 0, bedrooms: 1, bathrooms: 1, area: 0, type: "Apartamento", status: "venda", description: "", featured: false });
    setEditingId(null);
    setShowForm(false);
    setMediaFiles([]);
    setExistingMedia([]);
  };

  const editProperty = (p: Property & { media: MediaRow[] }) => {
    setForm({
      title: p.title, address: p.address, price: Number(p.price),
      bedrooms: p.bedrooms, bathrooms: p.bathrooms, area: Number(p.area),
      type: p.type, status: p.status, description: p.description || "",
      featured: p.featured,
    });
    setEditingId(p.id);
    setExistingMedia(p.media);
    setMediaFiles([]);
    setShowForm(true);
    setActiveTab("properties");
  };

  const deleteProperty = async (id: string) => {
    if (!confirm("Tem certeza que deseja remover este imóvel?")) return;
    const prop = properties.find((p) => p.id === id);
    if (prop) {
      for (const m of prop.media) {
        await supabase.storage.from("property-media").remove([m.file_path]);
      }
    }
    await supabase.from("properties").delete().eq("id", id);
    toast.success("Imóvel removido!");
    fetchProperties();
  };

  const deleteMedia = async (media: MediaRow) => {
    await supabase.storage.from("property-media").remove([media.file_path]);
    await supabase.from("property_media").delete().eq("id", media.id);
    setExistingMedia((prev) => prev.filter((m) => m.id !== media.id));
    toast.success("Mídia removida!");
  };

  if (authLoading) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="pt-24 section-padding flex items-center justify-center">
          <p className="text-muted-foreground">Carregando...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="min-h-screen bg-background">
        <Navbar />
        <div className="pt-24 section-padding flex items-center justify-center">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="glass-card rounded-2xl p-8 w-full max-w-md">
            <h1 className="font-display text-2xl font-bold text-foreground text-center mb-2">Área Administrativa</h1>
            <p className="text-muted-foreground text-sm text-center mb-6">Simply Imóveis</p>
            <form onSubmit={handleLogin} className="space-y-4">
              <input type="email" placeholder="E-mail" required value={email} onChange={(e) => setEmail(e.target.value)} className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
              <div className="relative">
                <input type={showPassword ? "text" : "password"} placeholder="Senha" required value={password} onChange={(e) => setPassword(e.target.value)} className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none pr-10" />
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

  const tabs: { id: AdminTab; label: string; icon: React.ReactNode }[] = [
    { id: "properties", label: "Imóveis", icon: <Edit size={16} /> },
    { id: "password", label: "Alterar Senha", icon: <KeyRound size={16} /> },
    { id: "users", label: "Usuários", icon: <UserPlus size={16} /> },
  ];

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="pt-24 section-padding">
        <div className="container-custom">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h1 className="font-display text-3xl font-bold text-foreground">Painel Admin</h1>
              <p className="text-muted-foreground text-sm">Gerencie seus imóveis • {user.email}</p>
            </div>
            <button onClick={handleLogout} className="border border-border text-muted-foreground px-4 py-3 rounded-xl hover:bg-secondary flex items-center gap-2">
              <LogOut size={16} /> Sair
            </button>
          </div>

          {/* Tabs */}
          <div className="flex gap-2 mb-8 border-b border-border pb-2">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-2 px-4 py-2.5 rounded-t-lg text-sm font-medium transition-colors ${
                  activeTab === tab.id
                    ? "bg-primary text-primary-foreground"
                    : "text-muted-foreground hover:text-foreground hover:bg-secondary"
                }`}
              >
                {tab.icon} {tab.label}
              </button>
            ))}
          </div>

          {/* Properties Tab */}
          {activeTab === "properties" && (
            <>
              <div className="flex justify-end mb-4">
                <button onClick={() => { resetForm(); setShowForm(true); }} className="gradient-primary text-primary-foreground px-6 py-3 rounded-xl font-semibold hover:opacity-90 flex items-center gap-2">
                  <Plus size={18} /> Novo Imóvel
                </button>
              </div>

              {showForm && (
                <motion.form initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} onSubmit={handleSubmit} className="glass-card rounded-2xl p-6 mb-8 space-y-4">
                  <h2 className="font-display text-xl font-semibold text-foreground">{editingId ? "Editar Imóvel" : "Novo Imóvel"}</h2>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <input placeholder="Título" required value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                    <input placeholder="Endereço" required value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                    <input type="number" placeholder="Preço" required value={form.price || ""} onChange={(e) => setForm({ ...form, price: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                    <input type="number" placeholder="Área (m²)" required value={form.area || ""} onChange={(e) => setForm({ ...form, area: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                    <input type="number" placeholder="Quartos" required min={0} value={form.bedrooms} onChange={(e) => setForm({ ...form, bedrooms: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                    <input type="number" placeholder="Banheiros" required min={0} value={form.bathrooms} onChange={(e) => setForm({ ...form, bathrooms: Number(e.target.value) })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                    <select value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as any })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground focus:ring-2 focus:ring-ring outline-none">
                      {PROPERTY_TYPES.map((t) => <option key={t}>{t}</option>)}
                    </select>
                    <select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value as "venda" | "aluguel" })} className="px-4 py-3 rounded-lg bg-background border border-input text-foreground focus:ring-2 focus:ring-ring outline-none">
                      <option value="venda">Venda</option>
                      <option value="aluguel">Aluguel</option>
                    </select>
                  </div>
                  <textarea placeholder="Descrição do imóvel" rows={3} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none resize-none" />

                  <div className="flex items-center gap-2">
                    <input type="checkbox" id="featured" checked={form.featured} onChange={(e) => setForm({ ...form, featured: e.target.checked })} className="rounded border-input" />
                    <label htmlFor="featured" className="text-sm text-foreground">Destacar na página inicial</label>
                  </div>

                  {existingMedia.length > 0 && (
                    <div>
                      <p className="text-sm font-medium text-foreground mb-2">Mídias existentes:</p>
                      <div className="flex flex-wrap gap-3">
                        {existingMedia.map((m) => (
                          <div key={m.id} className="relative group">
                            {m.file_type === "image" ? (
                              <img src={getMediaUrl(m.file_path)} alt="" className="w-24 h-24 object-cover rounded-lg border border-border" />
                            ) : (
                              <div className="w-24 h-24 bg-secondary rounded-lg border border-border flex items-center justify-center">
                                <Video size={24} className="text-muted-foreground" />
                              </div>
                            )}
                            <button type="button" onClick={() => deleteMedia(m)} className="absolute -top-2 -right-2 bg-destructive text-destructive-foreground rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity">
                              <X size={12} />
                            </button>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  <div>
                    <label className="block text-sm font-medium text-foreground mb-2">
                      <Upload size={14} className="inline mr-1" /> Adicionar fotos e vídeos:
                    </label>
                    <input type="file" multiple accept="image/*,video/*" onChange={(e) => setMediaFiles(Array.from(e.target.files || []))} className="text-sm text-muted-foreground file:mr-3 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-primary file:text-primary-foreground hover:file:opacity-90" />
                    {mediaFiles.length > 0 && (
                      <div className="flex flex-wrap gap-2 mt-2">
                        {mediaFiles.map((f, i) => (
                          <span key={i} className="inline-flex items-center gap-1 bg-secondary text-secondary-foreground text-xs px-2 py-1 rounded">
                            {f.type.startsWith("video") ? <Video size={12} /> : <Image size={12} />}
                            {f.name.slice(0, 20)}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>

                  <div className="flex gap-3">
                    <button type="submit" disabled={saving} className="gradient-primary text-primary-foreground px-6 py-2.5 rounded-lg font-semibold hover:opacity-90 disabled:opacity-50">
                      {saving ? "Salvando..." : editingId ? "Salvar Alterações" : "Cadastrar Imóvel"}
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
                    <div key={p.id} className="glass-card rounded-xl p-4 flex items-center gap-4">
                      {p.media[0] && (
                        <img src={getMediaUrl(p.media[0].file_path)} alt="" className="w-20 h-20 object-cover rounded-lg shrink-0" />
                      )}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <h3 className="font-semibold text-foreground truncate">{p.title}</h3>
                          {p.featured && <span className="text-xs gradient-primary text-primary-foreground px-2 py-0.5 rounded-full">Destaque</span>}
                        </div>
                        <p className="text-muted-foreground text-sm">{p.address} • {p.type} • {p.status}</p>
                        <p className="text-primary font-bold text-sm mt-1">
                          {Number(p.price).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
                        </p>
                        <p className="text-muted-foreground text-xs">{p.media.length} mídia(s)</p>
                      </div>
                      <div className="flex gap-2 shrink-0">
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
            </>
          )}

          {/* Password Tab */}
          {activeTab === "password" && (
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="glass-card rounded-2xl p-6 max-w-md">
              <h2 className="font-display text-xl font-semibold text-foreground mb-4 flex items-center gap-2">
                <KeyRound size={20} /> Alterar Senha
              </h2>
              <form onSubmit={handleChangePassword} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-foreground mb-1">Nova senha</label>
                  <input type="password" required minLength={6} value={newPassword} onChange={(e) => setNewPassword(e.target.value)} placeholder="Mínimo 6 caracteres" className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-foreground mb-1">Confirmar nova senha</label>
                  <input type="password" required minLength={6} value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} placeholder="Repita a nova senha" className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                </div>
                <button type="submit" disabled={changingPassword} className="gradient-primary text-primary-foreground px-6 py-2.5 rounded-lg font-semibold hover:opacity-90 disabled:opacity-50">
                  {changingPassword ? "Alterando..." : "Alterar Senha"}
                </button>
              </form>
            </motion.div>
          )}

          {/* Users Tab */}
          {activeTab === "users" && (
            <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="glass-card rounded-2xl p-6 max-w-md">
              <h2 className="font-display text-xl font-semibold text-foreground mb-4 flex items-center gap-2">
                <UserPlus size={20} /> Cadastrar Novo Usuário
              </h2>
              <form onSubmit={handleCreateUser} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-foreground mb-1">E-mail</label>
                  <input type="email" required value={newUserEmail} onChange={(e) => setNewUserEmail(e.target.value)} placeholder="email@exemplo.com" className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                </div>
                <div>
                  <label className="block text-sm font-medium text-foreground mb-1">Senha</label>
                  <input type="password" required minLength={6} value={newUserPassword} onChange={(e) => setNewUserPassword(e.target.value)} placeholder="Mínimo 6 caracteres" className="w-full px-4 py-3 rounded-lg bg-background border border-input text-foreground placeholder:text-muted-foreground focus:ring-2 focus:ring-ring outline-none" />
                </div>
                <button type="submit" disabled={creatingUser} className="gradient-primary text-primary-foreground px-6 py-2.5 rounded-lg font-semibold hover:opacity-90 disabled:opacity-50">
                  {creatingUser ? "Criando..." : "Criar Usuário"}
                </button>
              </form>
            </motion.div>
          )}
        </div>
      </div>
    </div>
  );
};

export default Admin;
