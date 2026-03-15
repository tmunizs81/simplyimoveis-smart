import { Building2, KeyRound, UserPlus, LogOut, LayoutDashboard, MessageSquare, Users, TrendingUp, Home, FileText, DollarSign, BarChart3, ChevronDown, ChevronRight, Handshake, ClipboardCheck, DatabaseBackup, Brain, BookOpen, Menu, X } from "lucide-react";
import { useState } from "react";
import { useIsMobile } from "@/hooks/use-mobile";

type AdminTab = "dashboard" | "properties" | "contacts" | "password" | "users" | "leads" | "sales" | "tenants" | "rentals" | "inspections" | "financial" | "reports" | "backup" | "insights" | "manual";

interface AdminSidebarProps {
  activeTab: AdminTab;
  onTabChange: (tab: AdminTab) => void;
  userEmail: string;
  onLogout: () => void;
}

const mainTabs = [
  { id: "dashboard" as AdminTab, label: "Dashboard", icon: LayoutDashboard, description: "Visão geral" },
  { id: "properties" as AdminTab, label: "Imóveis", icon: Building2, description: "Gerenciar listagens" },
  { id: "contacts" as AdminTab, label: "Contatos", icon: MessageSquare, description: "Solicitações recebidas" },
];

const realEstateTabs = [
  { id: "leads" as AdminTab, label: "Leads", icon: Users, description: "Gestão de prospects" },
  { id: "sales" as AdminTab, label: "Vendas", icon: TrendingUp, description: "Pipeline de vendas" },
  { id: "tenants" as AdminTab, label: "Inquilinos", icon: Users, description: "Cadastro de clientes" },
  { id: "rentals" as AdminTab, label: "Aluguéis", icon: Home, description: "Contratos e gestão" },
  { id: "inspections" as AdminTab, label: "Vistorias", icon: ClipboardCheck, description: "Vistorias de imóveis" },
  { id: "financial" as AdminTab, label: "Financeiro", icon: DollarSign, description: "Transações e cobranças" },
  { id: "reports" as AdminTab, label: "Relatórios", icon: BarChart3, description: "Dashboards e análises" },
  { id: "insights" as AdminTab, label: "Insights IA", icon: Brain, description: "Inteligência artificial" },
];

const settingsTabs = [
  { id: "password" as AdminTab, label: "Senha", icon: KeyRound, description: "Alterar credenciais" },
  { id: "users" as AdminTab, label: "Usuários", icon: UserPlus, description: "Cadastrar acessos" },
  { id: "backup" as AdminTab, label: "Backup", icon: DatabaseBackup, description: "Backup e restauração" },
  { id: "manual" as AdminTab, label: "Manual", icon: BookOpen, description: "Documentação do sistema" },
];

const AdminSidebar = ({ activeTab, onTabChange, userEmail, onLogout }: AdminSidebarProps) => {
  const isMobile = useIsMobile();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [realEstateOpen, setRealEstateOpen] = useState(
    realEstateTabs.some(t => t.id === activeTab)
  );

  const handleTabChange = (tab: AdminTab) => {
    onTabChange(tab);
    if (isMobile) setMobileOpen(false);
  };

  const renderTab = (tab: typeof mainTabs[0]) => {
    const Icon = tab.icon;
    const isActive = activeTab === tab.id;
    return (
      <button
        key={tab.id}
        onClick={() => handleTabChange(tab.id)}
        className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-left transition-all duration-200 group ${
          isActive
            ? "bg-primary/10 text-primary border border-primary/20"
            : "text-muted-foreground hover:bg-secondary hover:text-foreground"
        }`}
      >
        <div className={`w-8 h-8 rounded-lg flex items-center justify-center transition-colors shrink-0 ${
          isActive ? "bg-primary text-primary-foreground" : "bg-secondary group-hover:bg-muted"
        }`}>
          <Icon size={15} />
        </div>
        <div className="min-w-0">
          <p className="text-sm font-semibold">{tab.label}</p>
          <p className={`text-[10px] truncate ${isActive ? "text-primary/60" : "text-muted-foreground/60"}`}>
            {tab.description}
          </p>
        </div>
      </button>
    );
  };

  const sidebarContent = (
    <>
      {/* Brand header */}
      <div className="p-5 border-b border-border">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl gradient-primary flex items-center justify-center shrink-0">
            <LayoutDashboard size={20} className="text-primary-foreground" />
          </div>
          <div className="min-w-0">
            <h2 className="font-display font-bold text-sm text-foreground">Painel Admin</h2>
            <p className="text-xs text-muted-foreground truncate">{userEmail}</p>
          </div>
          {isMobile && (
            <button onClick={() => setMobileOpen(false)} className="ml-auto text-muted-foreground hover:text-foreground">
              <X size={20} />
            </button>
          )}
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 p-3 space-y-1 overflow-y-auto">
        <p className="text-[10px] font-bold text-muted-foreground/60 uppercase tracking-widest px-3 mb-2">Geral</p>
        {mainTabs.map(renderTab)}

        {/* Imobiliária section */}
        <div className="pt-3">
          <button
            onClick={() => setRealEstateOpen(!realEstateOpen)}
            className="w-full flex items-center justify-between px-3 py-2 text-left"
          >
            <div className="flex items-center gap-2">
              <Handshake size={12} className="text-primary" />
              <p className="text-[10px] font-bold text-muted-foreground/60 uppercase tracking-widest">Imobiliária</p>
            </div>
            {realEstateOpen ? <ChevronDown size={14} className="text-muted-foreground/40" /> : <ChevronRight size={14} className="text-muted-foreground/40" />}
          </button>
          {realEstateOpen && (
            <div className="space-y-1 mt-1">
              {realEstateTabs.map(renderTab)}
            </div>
          )}
        </div>

        <div className="pt-3">
          <p className="text-[10px] font-bold text-muted-foreground/60 uppercase tracking-widest px-3 mb-2">Config</p>
          {settingsTabs.map(renderTab)}
        </div>
      </nav>

      {/* Logout */}
      <div className="p-3 border-t border-border">
        <button
          onClick={onLogout}
          className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-muted-foreground hover:bg-destructive/10 hover:text-destructive transition-all"
        >
          <LogOut size={16} />
          <span className="text-sm font-medium">Sair</span>
        </button>
      </div>
    </>
  );

  // Mobile: floating trigger + overlay drawer
  if (isMobile) {
    return (
      <>
        {/* Floating trigger button */}
        <button
          onClick={() => setMobileOpen(true)}
          className="fixed top-24 left-3 z-40 w-10 h-10 rounded-xl bg-primary text-primary-foreground shadow-lg flex items-center justify-center hover:opacity-90 transition-opacity"
          aria-label="Abrir menu"
        >
          <Menu size={18} />
        </button>

        {/* Overlay */}
        {mobileOpen && (
          <div className="fixed inset-0 z-50 flex">
            <div
              className="absolute inset-0 bg-black/50 backdrop-blur-sm"
              onClick={() => setMobileOpen(false)}
            />
            <aside className="relative w-72 max-w-[85vw] bg-card border-r border-border flex flex-col h-full overflow-hidden animate-in slide-in-from-left duration-300">
              {sidebarContent}
            </aside>
          </div>
        )}
      </>
    );
  }

  // Desktop: fixed sidebar
  return (
    <aside className="w-72 bg-card border-r border-border min-h-[calc(100vh-80px)] flex flex-col shrink-0">
      {sidebarContent}
    </aside>
  );
};

export default AdminSidebar;
