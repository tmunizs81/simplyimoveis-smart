import { Building2, KeyRound, UserPlus, LogOut, LayoutDashboard, MessageSquare } from "lucide-react";

type AdminTab = "properties" | "contacts" | "password" | "users";

interface AdminSidebarProps {
  activeTab: AdminTab;
  onTabChange: (tab: AdminTab) => void;
  userEmail: string;
  onLogout: () => void;
}

const tabs = [
  { id: "properties" as AdminTab, label: "Imóveis", icon: Building2, description: "Gerenciar listagens" },
  { id: "contacts" as AdminTab, label: "Contatos", icon: MessageSquare, description: "Solicitações recebidas" },
  { id: "password" as AdminTab, label: "Senha", icon: KeyRound, description: "Alterar credenciais" },
  { id: "users" as AdminTab, label: "Usuários", icon: UserPlus, description: "Cadastrar acessos" },
];

const AdminSidebar = ({ activeTab, onTabChange, userEmail, onLogout }: AdminSidebarProps) => {
  return (
    <aside className="w-72 bg-card border-r border-border min-h-[calc(100vh-80px)] flex flex-col">
      {/* Brand header */}
      <div className="p-6 border-b border-border">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl gradient-primary flex items-center justify-center">
            <LayoutDashboard size={20} className="text-primary-foreground" />
          </div>
          <div>
            <h2 className="font-display font-bold text-sm text-foreground">Painel Admin</h2>
            <p className="text-xs text-muted-foreground truncate max-w-[160px]">{userEmail}</p>
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-4 space-y-1">
        <p className="text-[10px] font-bold text-muted-foreground/60 uppercase tracking-widest px-3 mb-3">Menu</p>
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={`w-full flex items-center gap-3 px-3 py-3 rounded-xl text-left transition-all duration-200 group ${
                isActive
                  ? "bg-primary/10 text-primary border border-primary/20"
                  : "text-muted-foreground hover:bg-secondary hover:text-foreground"
              }`}
            >
              <div className={`w-8 h-8 rounded-lg flex items-center justify-center transition-colors ${
                isActive ? "bg-primary text-primary-foreground" : "bg-secondary group-hover:bg-muted"
              }`}>
                <Icon size={16} />
              </div>
              <div>
                <p className="text-sm font-semibold">{tab.label}</p>
                <p className={`text-[11px] ${isActive ? "text-primary/60" : "text-muted-foreground/60"}`}>
                  {tab.description}
                </p>
              </div>
            </button>
          );
        })}
      </nav>

      {/* Logout */}
      <div className="p-4 border-t border-border">
        <button
          onClick={onLogout}
          className="w-full flex items-center gap-3 px-3 py-3 rounded-xl text-muted-foreground hover:bg-destructive/10 hover:text-destructive transition-all"
        >
          <LogOut size={16} />
          <span className="text-sm font-medium">Sair</span>
        </button>
      </div>
    </aside>
  );
};

export default AdminSidebar;
