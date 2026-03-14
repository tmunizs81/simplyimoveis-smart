import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { motion } from "framer-motion";
import {
  Building2, Users, TrendingUp, DollarSign, Home, ClipboardCheck,
  ArrowUpRight, ArrowDownRight, Calendar, FileText, AlertCircle
} from "lucide-react";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend
} from "recharts";

type Stats = {
  totalProperties: number;
  activeProperties: number;
  forSale: number;
  forRent: number;
  totalLeads: number;
  newLeads: number;
  convertedLeads: number;
  lostLeads: number;
  totalTenants: number;
  activeContracts: number;
  pendingInspections: number;
  totalRevenue: number;
  totalExpenses: number;
  pendingPayments: number;
  overduePayments: number;
  recentLeads: { id: string; name: string; status: string; source: string; created_at: string }[];
  recentTransactions: { id: string; description: string; amount: number; type: string; status: string; date: string }[];
  monthlyData: { month: string; receitas: number; despesas: number; lucro: number }[];
};

const STATUS_COLORS: Record<string, string> = {
  novo: "bg-blue-500",
  contato_feito: "bg-cyan-500",
  visita_agendada: "bg-amber-500",
  proposta: "bg-purple-500",
  negociacao: "bg-orange-500",
  fechado_ganho: "bg-green-500",
  fechado_perdido: "bg-red-500",
};

const STATUS_LABELS: Record<string, string> = {
  novo: "Novo",
  contato_feito: "Contato Feito",
  visita_agendada: "Visita Agendada",
  proposta: "Proposta",
  negociacao: "Negociação",
  fechado_ganho: "Fechado (Ganho)",
  fechado_perdido: "Fechado (Perdido)",
};

const INVOICE_LABELS: Record<string, string> = {
  pendente: "Pendente",
  pago: "Pago",
  atrasado: "Atrasado",
  cancelado: "Cancelado",
};

const formatCurrency = (v: number) =>
  v.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

const DashboardTab = () => {
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchStats = async () => {
      const [
        { data: props },
        { data: leads },
        { data: tenants },
        { data: contracts },
        { data: inspections },
        { data: transactions },
      ] = await Promise.all([
        supabase.from("properties").select("id, status, active"),
        supabase.from("leads").select("id, name, status, source, created_at").order("created_at", { ascending: false }),
        supabase.from("tenants").select("id"),
        supabase.from("rental_contracts").select("id, status"),
        supabase.from("property_inspections").select("id, status"),
        supabase.from("financial_transactions").select("id, description, amount, type, status, date, category").order("date", { ascending: false }),
      ]);

      const allProps = props || [];
      const allLeads = leads || [];
      const allTenants = tenants || [];
      const allContracts = contracts || [];
      const allInspections = inspections || [];
      const allTx = transactions || [];

      const revenue = allTx
        .filter((t: any) => t.type === "receita" && t.status === "pago")
        .reduce((sum: number, t: any) => sum + Number(t.amount), 0);
      const expenses = allTx
        .filter((t: any) => t.type === "despesa" && t.status === "pago")
        .reduce((sum: number, t: any) => sum + Number(t.amount), 0);
      const pending = allTx.filter((t: any) => t.status === "pendente").length;
      const overdue = allTx.filter((t: any) => t.status === "atrasado").length;

      // Build monthly data for last 12 months
      const monthlyMap = new Map<string, { receitas: number; despesas: number }>();
      const now = new Date();
      for (let i = 11; i >= 0; i--) {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
        monthlyMap.set(key, { receitas: 0, despesas: 0 });
      }
      for (const t of allTx as any[]) {
        if (t.status === "cancelado") continue;
        const dateStr = t.date || t.created_at;
        const key = dateStr?.substring(0, 7);
        if (key && monthlyMap.has(key)) {
          const entry = monthlyMap.get(key)!;
          if (t.type === "receita") entry.receitas += Number(t.amount);
          else entry.despesas += Number(t.amount);
        }
      }
      const MONTH_NAMES = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
      const monthlyData = Array.from(monthlyMap.entries()).map(([key, val]) => {
        const [, m] = key.split("-");
        return {
          month: MONTH_NAMES[parseInt(m) - 1],
          receitas: val.receitas,
          despesas: val.despesas,
          lucro: val.receitas - val.despesas,
        };
      });

      setStats({
        totalProperties: allProps.length,
        activeProperties: allProps.filter((p: any) => p.active).length,
        forSale: allProps.filter((p: any) => p.status === "venda").length,
        forRent: allProps.filter((p: any) => p.status === "aluguel").length,
        totalLeads: allLeads.length,
        newLeads: allLeads.filter((l: any) => l.status === "novo").length,
        convertedLeads: allLeads.filter((l: any) => l.status === "fechado_ganho").length,
        lostLeads: allLeads.filter((l: any) => l.status === "fechado_perdido").length,
        totalTenants: allTenants.length,
        activeContracts: allContracts.filter((c: any) => c.status === "ativo").length,
        pendingInspections: allInspections.filter((i: any) => i.status === "pendente").length,
        totalRevenue: revenue,
        totalExpenses: expenses,
        pendingPayments: pending,
        overduePayments: overdue,
        recentLeads: (allLeads.slice(0, 5) as any),
        recentTransactions: (allTx.slice(0, 5) as any),
        monthlyData,
      });
      setLoading(false);
    };
    fetchStats();
  }, []);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" />
      </div>
    );
  }

  if (!stats) return null;

  const profit = stats.totalRevenue - stats.totalExpenses;

  const statCards = [
    { icon: Building2, label: "Imóveis Ativos", value: stats.activeProperties, sub: `${stats.totalProperties} total`, color: "text-primary", bg: "bg-primary/10" },
    { icon: Home, label: "Venda", value: stats.forSale, sub: "imóveis", color: "text-accent", bg: "bg-accent/10" },
    { icon: Home, label: "Aluguel", value: stats.forRent, sub: "imóveis", color: "text-blue-500", bg: "bg-blue-500/10" },
    { icon: Users, label: "Leads", value: stats.totalLeads, sub: `${stats.newLeads} novos`, color: "text-purple-500", bg: "bg-purple-500/10" },
    { icon: TrendingUp, label: "Convertidos", value: stats.convertedLeads, sub: "leads ganhos", color: "text-green-500", bg: "bg-green-500/10" },
    { icon: Users, label: "Inquilinos", value: stats.totalTenants, sub: `${stats.activeContracts} contratos`, color: "text-cyan-500", bg: "bg-cyan-500/10" },
    { icon: ClipboardCheck, label: "Vistorias Pendentes", value: stats.pendingInspections, sub: "aguardando", color: "text-amber-500", bg: "bg-amber-500/10" },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-foreground font-display">Dashboard</h1>
        <p className="text-sm text-muted-foreground">Visão geral do seu negócio imobiliário</p>
      </div>

      {/* Financial Summary */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
          className="bg-card rounded-2xl border border-border p-5 relative overflow-hidden">
          <div className="absolute top-0 right-0 w-24 h-24 bg-green-500/5 rounded-full -translate-y-8 translate-x-8" />
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 rounded-xl bg-green-500/10 flex items-center justify-center">
              <ArrowUpRight size={20} className="text-green-500" />
            </div>
            <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider">Receitas</p>
          </div>
          <p className="text-2xl font-bold text-green-600 font-display">{formatCurrency(stats.totalRevenue)}</p>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.05 }}
          className="bg-card rounded-2xl border border-border p-5 relative overflow-hidden">
          <div className="absolute top-0 right-0 w-24 h-24 bg-red-500/5 rounded-full -translate-y-8 translate-x-8" />
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 rounded-xl bg-red-500/10 flex items-center justify-center">
              <ArrowDownRight size={20} className="text-red-500" />
            </div>
            <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider">Despesas</p>
          </div>
          <p className="text-2xl font-bold text-red-600 font-display">{formatCurrency(stats.totalExpenses)}</p>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
          className="bg-card rounded-2xl border border-border p-5 relative overflow-hidden">
          <div className={`absolute top-0 right-0 w-24 h-24 ${profit >= 0 ? "bg-primary/5" : "bg-red-500/5"} rounded-full -translate-y-8 translate-x-8`} />
          <div className="flex items-center gap-3 mb-3">
            <div className={`w-10 h-10 rounded-xl ${profit >= 0 ? "bg-primary/10" : "bg-red-500/10"} flex items-center justify-center`}>
              <DollarSign size={20} className={profit >= 0 ? "text-primary" : "text-red-500"} />
            </div>
            <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider">Lucro</p>
          </div>
          <p className={`text-2xl font-bold font-display ${profit >= 0 ? "text-primary" : "text-red-600"}`}>{formatCurrency(profit)}</p>
        </motion.div>
      </div>

      {/* Alerts */}
      {(stats.overduePayments > 0 || stats.pendingPayments > 0) && (
        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.15 }}
          className="bg-amber-500/5 border border-amber-500/20 rounded-xl p-4 flex items-center gap-3">
          <AlertCircle size={20} className="text-amber-500 shrink-0" />
          <div className="text-sm">
            {stats.overduePayments > 0 && (
              <span className="text-red-600 font-semibold">{stats.overduePayments} pagamento(s) atrasado(s)</span>
            )}
            {stats.overduePayments > 0 && stats.pendingPayments > 0 && <span className="text-muted-foreground"> • </span>}
            {stats.pendingPayments > 0 && (
              <span className="text-amber-600 font-semibold">{stats.pendingPayments} pagamento(s) pendente(s)</span>
            )}
          </div>
        </motion.div>
      )}

      {/* Stat Cards Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-7 gap-3">
        {statCards.map((card, i) => (
          <motion.div key={card.label} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.05 * i }}
            className="bg-card rounded-xl border border-border p-4 text-center hover:shadow-md transition-shadow">
            <div className={`w-10 h-10 rounded-xl ${card.bg} flex items-center justify-center mx-auto mb-2`}>
              <card.icon size={18} className={card.color} />
            </div>
            <p className="text-2xl font-bold text-foreground font-display">{card.value}</p>
            <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-wider">{card.label}</p>
            <p className="text-[10px] text-muted-foreground">{card.sub}</p>
          </motion.div>
        ))}
      </div>

      {/* Bottom: Recent Leads + Recent Transactions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent Leads */}
        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}
          className="bg-card rounded-2xl border border-border overflow-hidden">
          <div className="px-5 py-4 border-b border-border flex items-center justify-between">
            <h3 className="font-display font-bold text-sm text-foreground flex items-center gap-2">
              <Users size={16} className="text-primary" /> Leads Recentes
            </h3>
            <span className="text-[10px] font-bold text-muted-foreground bg-secondary px-2 py-0.5 rounded-full">{stats.totalLeads} total</span>
          </div>
          {stats.recentLeads.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground text-sm">Nenhum lead registrado</div>
          ) : (
            <div className="divide-y divide-border">
              {stats.recentLeads.map(lead => (
                <div key={lead.id} className="px-5 py-3 flex items-center gap-3">
                  <div className={`w-2 h-8 rounded-full ${STATUS_COLORS[lead.status] || "bg-muted"}`} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-foreground truncate">{lead.name}</p>
                    <div className="flex items-center gap-2 text-[10px] text-muted-foreground">
                      <span className={`px-1.5 py-0.5 rounded-full text-white font-bold ${STATUS_COLORS[lead.status] || "bg-muted"}`}>
                        {STATUS_LABELS[lead.status] || lead.status}
                      </span>
                      <span>{lead.source}</span>
                    </div>
                  </div>
                  <span className="text-[10px] text-muted-foreground flex items-center gap-1">
                    <Calendar size={10} /> {new Date(lead.created_at).toLocaleDateString("pt-BR")}
                  </span>
                </div>
              ))}
            </div>
          )}
        </motion.div>

        {/* Recent Transactions */}
        <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.25 }}
          className="bg-card rounded-2xl border border-border overflow-hidden">
          <div className="px-5 py-4 border-b border-border flex items-center justify-between">
            <h3 className="font-display font-bold text-sm text-foreground flex items-center gap-2">
              <FileText size={16} className="text-primary" /> Transações Recentes
            </h3>
            <span className="text-[10px] font-bold text-muted-foreground bg-secondary px-2 py-0.5 rounded-full">
              {formatCurrency(stats.totalRevenue - stats.totalExpenses)}
            </span>
          </div>
          {stats.recentTransactions.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground text-sm">Nenhuma transação registrada</div>
          ) : (
            <div className="divide-y divide-border">
              {stats.recentTransactions.map(tx => (
                <div key={tx.id} className="px-5 py-3 flex items-center gap-3">
                  <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${tx.type === "receita" ? "bg-green-500/10" : "bg-red-500/10"}`}>
                    {tx.type === "receita" ? <ArrowUpRight size={14} className="text-green-500" /> : <ArrowDownRight size={14} className="text-red-500" />}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-foreground truncate">{tx.description}</p>
                    <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-bold ${
                      tx.status === "pago" ? "bg-green-500/10 text-green-600" :
                      tx.status === "atrasado" ? "bg-red-500/10 text-red-600" :
                      "bg-amber-500/10 text-amber-600"
                    }`}>{INVOICE_LABELS[tx.status] || tx.status}</span>
                  </div>
                  <div className="text-right">
                    <p className={`text-sm font-bold ${tx.type === "receita" ? "text-green-600" : "text-red-600"}`}>
                      {tx.type === "receita" ? "+" : "-"}{formatCurrency(Number(tx.amount))}
                    </p>
                    <p className="text-[10px] text-muted-foreground">{new Date(tx.date).toLocaleDateString("pt-BR")}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </motion.div>
      </div>
    </div>
  );
};

export default DashboardTab;
