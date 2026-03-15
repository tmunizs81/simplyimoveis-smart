import { useState, useEffect } from "react";
import { adminSelect } from "@/lib/adminCrud";
import { BarChart3, TrendingUp, TrendingDown, DollarSign, Home, Users, FileText, Calendar } from "lucide-react";

type MonthlyData = { month: string; receitas: number; despesas: number };

const ReportsTab = () => {
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    totalProperties: 0, activeProperties: 0, totalLeads: 0,
    openLeads: 0, activeContracts: 0, totalTenants: 0,
    totalSales: 0, closedSales: 0,
    totalReceitas: 0, totalDespesas: 0, pendentes: 0,
    atrasados: 0, monthlyRent: 0,
  });
  const [monthlyData, setMonthlyData] = useState<MonthlyData[]>([]);
  const [categoryBreakdown, setCategoryBreakdown] = useState<{ category: string; amount: number }[]>([]);

  useEffect(() => {
    const fetchAll = async () => {
      const [
        { data: properties }, { data: leads }, { data: contracts },
        { data: tenants }, { data: sales }, { data: transactions },
      ] = await Promise.all([
        supabase.from("properties").select("id, active"),
        supabase.from("leads").select("id, status"),
        supabase.from("rental_contracts").select("id, status, monthly_rent"),
        supabase.from("tenants").select("id"),
        supabase.from("sales").select("id, status, sale_value, commission_value"),
        supabase.from("financial_transactions").select("*"),
      ]);

      const txs = (transactions || []) as any[];
      const totalReceitas = txs.filter(t => t.type === "receita" && t.status === "pago").reduce((s: number, t: any) => s + Number(t.amount), 0);
      const totalDespesas = txs.filter(t => t.type === "despesa" && t.status === "pago").reduce((s: number, t: any) => s + Number(t.amount), 0);
      const pendentes = txs.filter(t => t.status === "pendente").reduce((s: number, t: any) => s + Number(t.amount), 0);
      const atrasados = txs.filter(t => t.status === "atrasado").length;
      const activeContracts = ((contracts || []) as any[]).filter(c => c.status === "ativo");
      const monthlyRent = activeContracts.reduce((s: number, c: any) => s + Number(c.monthly_rent), 0);

      setStats({
        totalProperties: (properties || []).length,
        activeProperties: ((properties || []) as any[]).filter(p => p.active).length,
        totalLeads: (leads || []).length,
        openLeads: ((leads || []) as any[]).filter(l => !["fechado_ganho", "fechado_perdido"].includes(l.status)).length,
        activeContracts: activeContracts.length,
        totalTenants: (tenants || []).length,
        totalSales: (sales || []).length,
        closedSales: ((sales || []) as any[]).filter(s => s.status === "fechado").length,
        totalReceitas, totalDespesas, pendentes, atrasados, monthlyRent,
      });

      // Monthly breakdown
      const monthMap = new Map<string, { receitas: number; despesas: number }>();
      txs.forEach(t => {
        const month = t.date?.slice(0, 7);
        if (!month) return;
        const entry = monthMap.get(month) || { receitas: 0, despesas: 0 };
        if (t.type === "receita" && t.status === "pago") entry.receitas += Number(t.amount);
        if (t.type === "despesa" && t.status === "pago") entry.despesas += Number(t.amount);
        monthMap.set(month, entry);
      });
      const monthly = Array.from(monthMap.entries())
        .sort((a, b) => a[0].localeCompare(b[0]))
        .slice(-12)
        .map(([month, data]) => ({ month, ...data }));
      setMonthlyData(monthly);

      // Category breakdown
      const catMap = new Map<string, number>();
      txs.filter(t => t.type === "despesa" && t.status === "pago").forEach(t => {
        catMap.set(t.category, (catMap.get(t.category) || 0) + Number(t.amount));
      });
      setCategoryBreakdown(Array.from(catMap.entries()).map(([category, amount]) => ({ category, amount })).sort((a, b) => b.amount - a.amount));

      setLoading(false);
    };
    fetchAll();
  }, []);

  const CATEGORY_LABELS: Record<string, string> = {
    aluguel: "Aluguel", venda: "Venda", comissao: "Comissão",
    manutencao: "Manutenção", condominio: "Condomínio", iptu: "IPTU",
    seguro: "Seguro", taxa_administracao: "Taxa Admin", reparo: "Reparo", outro: "Outro",
  };

  if (loading) return <div className="flex items-center justify-center py-20"><div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" /></div>;

  const maxMonthly = Math.max(...monthlyData.map(m => Math.max(m.receitas, m.despesas)), 1);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Relatórios & Dashboard</h2>
        <p className="text-muted-foreground text-sm">Visão geral do seu negócio imobiliário</p>
      </div>

      {/* Overview cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { icon: Home, label: "Imóveis Ativos", value: `${stats.activeProperties}/${stats.totalProperties}`, color: "text-primary" },
          { icon: Users, label: "Leads Abertos", value: `${stats.openLeads}/${stats.totalLeads}`, color: "text-blue-500" },
          { icon: FileText, label: "Contratos Ativos", value: stats.activeContracts, color: "text-green-600" },
          { icon: TrendingUp, label: "Vendas Fechadas", value: `${stats.closedSales}/${stats.totalSales}`, color: "text-purple-500" },
        ].map((card, i) => (
          <div key={i} className="bg-card rounded-xl border border-border p-4">
            <div className="flex items-center gap-2 mb-2">
              <card.icon size={16} className={card.color} />
              <span className="text-xs text-muted-foreground">{card.label}</span>
            </div>
            <p className={`font-display text-2xl font-bold ${card.color}`}>{card.value}</p>
          </div>
        ))}
      </div>

      {/* Financial summary */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <div className="bg-card rounded-xl border border-border p-5">
          <div className="flex items-center gap-2 mb-3">
            <TrendingUp size={18} className="text-green-500" />
            <span className="font-semibold text-foreground">Receitas</span>
          </div>
          <p className="font-display text-2xl font-bold text-green-600">{stats.totalReceitas.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
          <p className="text-xs text-muted-foreground mt-1">Receita mensal de aluguéis: {stats.monthlyRent.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
        </div>
        <div className="bg-card rounded-xl border border-border p-5">
          <div className="flex items-center gap-2 mb-3">
            <TrendingDown size={18} className="text-destructive" />
            <span className="font-semibold text-foreground">Despesas</span>
          </div>
          <p className="font-display text-2xl font-bold text-destructive">{stats.totalDespesas.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
          {stats.atrasados > 0 && <p className="text-xs text-destructive mt-1">{stats.atrasados} pagamento{stats.atrasados > 1 ? "s" : ""} atrasado{stats.atrasados > 1 ? "s" : ""}</p>}
        </div>
        <div className="bg-card rounded-xl border border-border p-5">
          <div className="flex items-center gap-2 mb-3">
            <DollarSign size={18} className="text-primary" />
            <span className="font-semibold text-foreground">Resultado</span>
          </div>
          <p className={`font-display text-2xl font-bold ${stats.totalReceitas - stats.totalDespesas >= 0 ? "text-green-600" : "text-destructive"}`}>
            {(stats.totalReceitas - stats.totalDespesas).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
          </p>
          <p className="text-xs text-muted-foreground mt-1">Pendentes: {stats.pendentes.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</p>
        </div>
      </div>

      {/* Charts section */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Monthly chart */}
        <div className="bg-card rounded-xl border border-border p-5">
          <h3 className="font-semibold text-foreground mb-4 flex items-center gap-2"><BarChart3 size={16} className="text-primary" /> Receitas vs Despesas (últimos 12 meses)</h3>
          {monthlyData.length === 0 ? (
            <p className="text-center text-muted-foreground py-8 text-sm">Sem dados financeiros ainda.</p>
          ) : (
            <div className="space-y-3">
              {monthlyData.map(m => {
                const monthLabel = new Date(m.month + "-01").toLocaleDateString("pt-BR", { month: "short", year: "2-digit" });
                return (
                  <div key={m.month} className="space-y-1">
                    <div className="flex items-center justify-between text-xs">
                      <span className="text-muted-foreground font-medium w-16">{monthLabel}</span>
                      <div className="flex gap-4 text-[10px]">
                        <span className="text-green-600">+{m.receitas.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</span>
                        <span className="text-destructive">-{m.despesas.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}</span>
                      </div>
                    </div>
                    <div className="flex gap-1 h-4">
                      <div className="bg-green-500/80 rounded-sm transition-all" style={{ width: `${(m.receitas / maxMonthly) * 100}%` }} />
                      <div className="bg-destructive/80 rounded-sm transition-all" style={{ width: `${(m.despesas / maxMonthly) * 100}%` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Category breakdown */}
        <div className="bg-card rounded-xl border border-border p-5">
          <h3 className="font-semibold text-foreground mb-4 flex items-center gap-2"><DollarSign size={16} className="text-primary" /> Despesas por Categoria</h3>
          {categoryBreakdown.length === 0 ? (
            <p className="text-center text-muted-foreground py-8 text-sm">Sem despesas registradas.</p>
          ) : (
            <div className="space-y-3">
              {categoryBreakdown.map((cat, i) => {
                const total = categoryBreakdown.reduce((s, c) => s + c.amount, 0);
                const pct = total > 0 ? (cat.amount / total) * 100 : 0;
                return (
                  <div key={cat.category}>
                    <div className="flex items-center justify-between text-sm mb-1">
                      <span className="text-foreground font-medium">{CATEGORY_LABELS[cat.category] || cat.category}</span>
                      <span className="text-muted-foreground">{cat.amount.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })} ({pct.toFixed(1)}%)</span>
                    </div>
                    <div className="h-2 bg-secondary rounded-full overflow-hidden">
                      <div className="h-full bg-primary rounded-full transition-all" style={{ width: `${pct}%` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Tenants summary */}
      <div className="bg-card rounded-xl border border-border p-5">
        <h3 className="font-semibold text-foreground mb-2 flex items-center gap-2"><Users size={16} className="text-primary" /> Resumo de Inquilinos</h3>
        <p className="text-muted-foreground text-sm">{stats.totalTenants} inquilino{stats.totalTenants !== 1 ? "s" : ""} cadastrado{stats.totalTenants !== 1 ? "s" : ""} • {stats.activeContracts} contrato{stats.activeContracts !== 1 ? "s" : ""} ativo{stats.activeContracts !== 1 ? "s" : ""}</p>
      </div>
    </div>
  );
};

export default ReportsTab;
