import { useState, useEffect, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import Navbar from "@/components/Navbar";
import AdminLogin from "@/components/admin/AdminLogin";
import AdminSidebar from "@/components/admin/AdminSidebar";
import DashboardTab from "@/components/admin/DashboardTab";
import PropertyForm from "@/components/admin/PropertyForm";
import PropertyList from "@/components/admin/PropertyList";
import PasswordTab from "@/components/admin/PasswordTab";
import UsersTab from "@/components/admin/UsersTab";
import ContactsTab from "@/components/admin/ContactsTab";
import LeadsTab from "@/components/admin/LeadsTab";
import SalesTab from "@/components/admin/SalesTab";
import TenantsTab from "@/components/admin/TenantsTab";
import RentalsTab from "@/components/admin/RentalsTab";
import FinancialTab from "@/components/admin/FinancialTab";
import ReportsTab from "@/components/admin/ReportsTab";
import InspectionsTab from "@/components/admin/InspectionsTab";
import BackupTab from "@/components/admin/BackupTab";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];
type AdminTab = "dashboard" | "properties" | "contacts" | "password" | "users" | "leads" | "sales" | "tenants" | "rentals" | "inspections" | "financial" | "reports" | "backup";

const Admin = () => {
  const [user, setUser] = useState<any>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [adminCheckLoading, setAdminCheckLoading] = useState(true);
  const [isAdmin, setIsAdmin] = useState(false);
  const [properties, setProperties] = useState<(Property & { media: MediaRow[] })[]>([]);
  const [activeTab, setActiveTab] = useState<AdminTab>("dashboard");
  const [showForm, setShowForm] = useState(false);
  const [editingProperty, setEditingProperty] = useState<(Property & { media: MediaRow[] }) | null>(null);

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

  useEffect(() => {
    let mounted = true;

    const checkAdminAccess = async () => {
      if (!user) {
        if (mounted) {
          setIsAdmin(false);
          setAdminCheckLoading(false);
        }
        return;
      }

      setAdminCheckLoading(true);
      const { data, error } = await supabase.rpc("has_role", {
        _user_id: user.id,
        _role: "admin",
      });

      if (!mounted) return;

      if (error) {
        toast.error("Falha ao validar permissões de administrador.");
        setIsAdmin(false);
      } else {
        const allowed = Boolean(data);
        setIsAdmin(allowed);
        if (!allowed) {
          toast.error("Sua conta não possui acesso de administrador.");
        }
      }

      setAdminCheckLoading(false);
    };

    checkAdminAccess();

    return () => {
      mounted = false;
    };
  }, [user]);

  const fetchProperties = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase
      .from("properties")
      .select("*")
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

  const navigate = useNavigate();

  const handleLogout = async () => {
    await supabase.auth.signOut();
    toast.success("Logout realizado.");
    navigate("/");
  };

  if (authLoading || (user && adminCheckLoading)) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" />
      </div>
    );
  }

  if (!user) return <AdminLogin />;

  if (!isAdmin) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center px-4">
        <div className="w-full max-w-md bg-card border border-border rounded-2xl p-6 text-center shadow-xl">
          <h1 className="font-display text-xl font-bold text-foreground mb-2">Acesso negado</h1>
          <p className="text-sm text-muted-foreground mb-5">
            Sua conta está autenticada, mas não possui permissão de administrador.
          </p>
          <button
            onClick={handleLogout}
            className="w-full gradient-primary text-primary-foreground py-3 rounded-xl font-semibold"
          >
            Sair
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="pt-20 flex">
        <AdminSidebar
          activeTab={activeTab}
          onTabChange={(tab) => { setActiveTab(tab); setShowForm(false); setEditingProperty(null); }}
          userEmail={user.email}
          onLogout={handleLogout}
        />

        <main className="flex-1 p-6 lg:p-8 overflow-y-auto max-h-[calc(100vh-80px)]">
          {activeTab === "dashboard" && <DashboardTab />}

          {activeTab === "properties" && !showForm && (
            <PropertyList
              properties={properties}
              onEdit={(p) => { setEditingProperty(p); setShowForm(true); }}
              onRefresh={fetchProperties}
              onNew={() => { setEditingProperty(null); setShowForm(true); }}
            />
          )}

          {activeTab === "properties" && showForm && (
            <PropertyForm
              editingProperty={editingProperty}
              userId={user.id}
              onSaved={() => { setShowForm(false); setEditingProperty(null); fetchProperties(); }}
              onCancel={() => { setShowForm(false); setEditingProperty(null); }}
            />
          )}

          {activeTab === "contacts" && <ContactsTab />}
          {activeTab === "password" && <PasswordTab />}
          {activeTab === "users" && <UsersTab />}
          {activeTab === "leads" && <LeadsTab />}
          {activeTab === "sales" && <SalesTab />}
          {activeTab === "tenants" && <TenantsTab />}
          {activeTab === "rentals" && <RentalsTab />}
          {activeTab === "inspections" && <InspectionsTab />}
          {activeTab === "financial" && <FinancialTab />}
          {activeTab === "reports" && <ReportsTab />}
          {activeTab === "backup" && <BackupTab />}
        </main>
      </div>
    </div>
  );
};

export default Admin;
