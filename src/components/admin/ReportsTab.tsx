import { useState, useEffect, useMemo } from "react";
import { adminSelect } from "@/lib/adminCrud";
import { motion } from "framer-motion";
import {
  BarChart3, TrendingUp, TrendingDown, DollarSign, Home, Users, FileText, Calendar,
  MapPin, Target, Percent, Clock, ArrowUpRight, ArrowDownRight, Filter,
  PieChart as PieChartIcon, Activity, Layers, Eye, Building2, Zap
} from "lucide-react";
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
  PieChart, Pie, Cell, AreaChart, Area, LineChart, Line, RadialBarChart, RadialBar,
  FunnelChart, Funnel, LabelList
} from "recharts";

const formatCurrency = (v: number) =>
  v.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

const formatCompact = (v: number) => {
  if (v >= 1_000_000) return `R$${(v / 1_000_000).toFixed(1)}M`;
  if (v >= 1_000) return `R$${(v / 1_000).toFixed(0)}k`;
  return formatCurrency(v);
};

const COLORS = [
  "hsl(var(--primary))", "hsl(142,71%,45%)", "hsl(217,91%,60%)", "hsl(280,67%,55%)",
  "hsl(35,92%,55%)", "hsl(0,84%,60%)", "hsl(190,80%,50%)", "hsl(330,65%,55%)",
  "hsl(160,60%,50%)", "hsl(50,95%,55%)",
];

const CATEGORY_LABELS: Record<string, string> = {
  aluguel: "Aluguel", venda: "Venda", comissao: "Comissão",
  manutencao: "Manutenção", condominio: "Condomínio", iptu: "IPTU",
  seguro: "Seguro", taxa_administracao: "Taxa Admin", reparo: "Reparo", outro: "Outro",
};

const STATUS_LABELS: Record<string, string> = {
  novo: "Novo", contato_feito: "Contato", visita_agendada: "Visita",
  proposta: "Proposta", negociacao: "Negociação", fechado_ganho: "Ganho", fechado_perdido: "Perdido",
};

const SOURCE_LABELS: Record<string, string> = {
  site: "Site", whatsapp: "WhatsApp", indicacao: "Indicação", portal: "Portal",
  placa: "Placa", telefone: "Telefone", chat: "Chat IA", outro: "Outro",
};

type Period = "7d" | "30d" | "90d" | "365d" | "all";

const ReportsTab = () => {
  const [loading, setLoading] = useState(true);
  const [period, setPeriod] = useState<Period>("all");
  const [rawData, setRawData] = useState<{
    properties: any[]; leads: any[]; contacts: any[];
    sales: any[]; contracts: any[]; tenants: any[];
    transactions: any[]; inspections: any[];
  }>({ properties: [], leads: [], contacts: [], sales: [], contracts: [], tenants: [], transactions: [], inspections: [] });

  useEffect(() => {
    const fetchAll = async () => {
      const [props, leads, contacts, sales, contracts, tenants, txs, inspections] = await Promise.all([
        adminSelect("properties"),
        adminSelect("leads", { order: { column: "created_at", ascending: false } }),
        adminSelect("contact_submissions", { order: { column: "created_at", ascending: false } }),
        adminSelect("sales", { order: { column: "created_at", ascending: false } }),
        adminSelect("rental_contracts"),
        adminSelect("tenants"),
        adminSelect("financial_transactions", { order: { column: "date", ascending: false } }),
        adminSelect("property_inspections"),
      ]);
      setRawData({
        properties: (props.data || []) as any[],
        leads: (leads.data || []) as any[],
        contacts: (contacts.data || []) as any[],
        sales: (sales.data || []) as any[],
        contracts: (contracts.data || []) as any[],
        tenants: (tenants.data || []) as any[],
        transactions: (txs.data || []) as any[],
        inspections: (inspections.data || []) as any[],
      });
      setLoading(false);
    };
    fetchAll();
  }, []);

  const filterByPeriod = (items: any[], dateField = "created_at") => {
    if (period === "all") return items;
    const days = { "7d": 7, "30d": 30, "90d": 90, "365d": 365 }[period];
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - days);
    return items.filter(i => new Date(i[dateField]) >= cutoff);
  };

  const data = useMemo(() => {
    const leads = filterByPeriod(rawData.leads);
    const contacts = filterByPeriod(rawData.contacts);
    const sales = filterByPeriod(rawData.sales);
    const txs = filterByPeriod(rawData.transactions, "date");
    const properties = rawData.properties;
    const contracts = rawData.contracts;
    const tenants = rawData.tenants;

    // KPIs
    const totalReceitas = txs.filter(t => t.type === "receita" && t.status === "pago").reduce((s, t) => s + Number(t.amount), 0);
    const totalDespesas = txs.filter(t => t.type === "despesa" && t.status === "pago").reduce((s, t) => s + Number(t.amount), 0);
    const pendentes = txs.filter(t => t.status === "pendente").reduce((s, t) => s + Number(t.amount), 0);
    const atrasados = txs.filter(t => t.status === "atrasado").length;
    const activeContracts = contracts.filter((c: any) => c.status === "ativo");
    const monthlyRent = activeContracts.reduce((s, c: any) => s + Number(c.monthly_rent), 0);
    const convertedLeads = leads.filter(l => l.status === "fechado_ganho").length;
    const lostLeads = leads.filter(l => l.status === "fechado_perdido").length;
    const conversionRate = leads.length > 0 ? (convertedLeads / leads.length) * 100 : 0;
    const avgTicket = sales.filter(s => s.sale_value).length > 0
      ? sales.filter(s => s.sale_value).reduce((s, sale) => s + Number(sale.sale_value), 0) / sales.filter(s => s.sale_value).length
      : 0;
    const totalCommission = sales.reduce((s, sale) => s + Number(sale.commission_value || 0), 0);

    // Lead funnel
    const funnelOrder = ["novo", "contato_feito", "visita_agendada", "proposta", "negociacao", "fechado_ganho"];
    const statusCounts: Record<string, number> = {};
    leads.forEach(l => { statusCounts[l.status] = (statusCounts[l.status] || 0) + 1; });
    const funnelData = funnelOrder.map(status => ({
      name: STATUS_LABELS[status] || status,
      value: statusCounts[status] || 0,
      fill: COLORS[funnelOrder.indexOf(status) % COLORS.length],
    }));

    // Lead sources
    const sourceMap: Record<string, number> = {};
    leads.forEach(l => { sourceMap[l.source] = (sourceMap[l.source] || 0) + 1; });
    const leadSources = Object.entries(sourceMap)
      .map(([source, count]) => ({ name: SOURCE_LABELS[source] || source, value: count }))
      .sort((a, b) => b.value - a.value);

    // Property types
    const typeMap: Record<string, number> = {};
    properties.filter(p => p.active).forEach(p => { typeMap[p.type] = (typeMap[p.type] || 0) + 1; });
    const propertyTypes = Object.entries(typeMap).map(([type, count]) => ({ name: type, value: count }));

    // Property by status
    const forSale = properties.filter(p => p.active && p.status === "venda").length;
    const forRent = properties.filter(p => p.active && p.status === "aluguel").length;

    // Neighborhood analysis
    const neighborhoodMap: Record<string, { count: number; totalPrice: number }> = {};
    properties.filter(p => p.active && p.neighborhood).forEach(p => {
      const n = p.neighborhood;
      if (!neighborhoodMap[n]) neighborhoodMap[n] = { count: 0, totalPrice: 0 };
      neighborhoodMap[n].count++;
      neighborhoodMap[n].totalPrice += Number(p.price);
    });
    const neighborhoods = Object.entries(neighborhoodMap)
      .map(([name, data]) => ({ name, count: data.count, avgPrice: data.totalPrice / data.count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10);

    // Monthly revenue evolution
    const monthlyMap = new Map<string, { receitas: number; despesas: number; leads: number; contacts: number }>();
    const now = new Date();
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      monthlyMap.set(key, { receitas: 0, despesas: 0, leads: 0, contacts: 0 });
    }
    txs.forEach(t => {
      const key = (t.date || t.created_at)?.substring(0, 7);
      if (key && monthlyMap.has(key)) {
        const entry = monthlyMap.get(key)!;
        if (t.type === "receita" && t.status === "pago") entry.receitas += Number(t.amount);
        if (t.type === "despesa" && t.status === "pago") entry.despesas += Number(t.amount);
      }
    });
    rawData.leads.forEach(l => {
      const key = l.created_at?.substring(0, 7);
      if (key && monthlyMap.has(key)) monthlyMap.get(key)!.leads++;
    });
    rawData.contacts.forEach(c => {
      const key = c.created_at?.substring(0, 7);
      if (key && monthlyMap.has(key)) monthlyMap.get(key)!.contacts++;
    });
    const MONTH_NAMES = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
    const monthlyEvolution = Array.from(monthlyMap.entries()).map(([key, val]) => {
      const [, m] = key.split("-");
      return { month: MONTH_NAMES[parseInt(m) - 1], ...val, lucro: val.receitas - val.despesas };
    });

    // Category breakdown
    const catMap: Record<string, number> = {};
    txs.filter(t => t.status === "pago").forEach(t => {
      const cat = t.category || "outro";
      catMap[cat] = (catMap[cat] || 0) + Number(t.amount) * (t.type === "despesa" ? -1 : 1);
    });
    const expenseCategories = Object.entries(catMap)
      .filter(([, v]) => v < 0)
      .map(([cat, amount]) => ({ name: CATEGORY_LABELS[cat] || cat, value: Math.abs(amount) }))
      .sort((a, b) => b.value - a.value);

    // Sales pipeline
    const saleStatusMap: Record<string, number> = {};
    sales.forEach(s => { saleStatusMap[s.status] = (saleStatusMap[s.status] || 0) + 1; });
    const salesPipeline = Object.entries(saleStatusMap).map(([status, count]) => ({ name: status, value: count }));

    // Price range distribution
    const priceRanges = [
      { range: "< 200k", min: 0, max: 200000 },
      { range: "200-500k", min: 200000, max: 500000 },
      { range: "500k-1M", min: 500000, max: 1000000 },
      { range: "1-2M", min: 1000000, max: 2000000 },
      { range: "> 2M", min: 2000000, max: Infinity },
    ];
    const priceDistribution = priceRanges.map(r => ({
      name: r.range,
      venda: properties.filter(p => p.active && p.status === "venda" && p.price >= r.min && p.price < r.max).length,
      aluguel: properties.filter(p => p.active && p.status === "aluguel" && p.price >= r.min && p.price < r.max).length,
    }));

    // Chat analytics
    const chatContacts = contacts.filter(c => c.source?.includes("chat"));
    const formContacts = contacts.filter(c => c.source === "form");

    // Conversion gauges
    const gauges = [
      { name: "Conversão Leads", value: Math.round(conversionRate), fill: "hsl(142,71%,45%)" },
      { name: "Taxa Ocupação", value: activeContracts.length > 0 && forRent > 0 ? Math.round((activeContracts.length / (forRent + activeContracts.length)) * 100) : 0, fill: "hsl(217,91%,60%)" },
    ];

    return {
      totalReceitas, totalDespesas, pendentes, atrasados, monthlyRent, convertedLeads,
      lostLeads, conversionRate, avgTicket, totalCommission,
      leads, contacts, sales, properties, contracts, tenants,
      activeContracts, forSale, forRent,
      funnelData, leadSources, propertyTypes, neighborhoods, monthlyEvolution,
      expenseCategories, salesPipeline, priceDistribution, chatContacts, formContacts,
      gauges,
    };
  }, [rawData, period]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="w-8 h-8 border-3 border-primary/30 border-t-primary rounded-full animate-spin" />
      </div>
    );
  }

  const kpis = [
    { icon: DollarSign, label: "Receita Total", value: formatCompact(data.totalReceitas), sub: "pagos", color: "text-green-500", bg: "bg-green-500/10", trend: "up" as const },
    { icon: TrendingDown, label: "Despesa Total", value: formatCompact(data.totalDespesas), sub: "pagos", color: "text-red-500", bg: "bg-red-500/10", trend: "down" as const },
    { icon: Zap, label: "Lucro Líquido", value: formatCompact(data.totalReceitas - data.totalDespesas), sub: "resultado", color: data.totalReceitas - data.totalDespesas >= 0 ? "text-primary" : "text-red-500", bg: data.totalReceitas - data.totalDespesas >= 0 ? "bg-primary/10" : "bg-red-500/10", trend: data.totalReceitas - data.totalDespesas >= 0 ? "up" as const : "down" as const },
    { icon: Home, label: "Receita Aluguel/mês", value: formatCompact(data.monthlyRent), sub: `${data.activeContracts.length} contratos`, color: "text-blue-500", bg: "bg-blue-500/10", trend: "up" as const },
    { icon: Users, label: "Total Leads", value: data.leads.length.toString(), sub: `${data.convertedLeads} convertidos`, color: "text-purple-500", bg: "bg-purple-500/10", trend: "up" as const },
    { icon: Percent, label: "Taxa Conversão", value: `${data.conversionRate.toFixed(1)}%`, sub: `${data.lostLeads} perdidos`, color: "text-amber-500", bg: "bg-amber-500/10", trend: data.conversionRate > 10 ? "up" as const : "down" as const },
    { icon: Target, label: "Ticket Médio", value: formatCompact(data.avgTicket), sub: "vendas", color: "text-emerald-500", bg: "bg-emerald-500/10", trend: "up" as const },
    { icon: DollarSign, label: "Comissões", value: formatCompact(data.totalCommission), sub: `${data.sales.length} vendas`, color: "text-primary", bg: "bg-primary/10", trend: "up" as const },
  ];

  const CustomTooltip = ({ active, payload, label }: any) => {
    if (!active || !payload) return null;
    return (
      <div className="bg-card border border-border rounded-xl p-3 shadow-xl text-xs">
        <p className="font-bold text-foreground mb-1">{label}</p>
        {payload.map((entry: any, i: number) => (
          <div key={i} className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full" style={{ backgroundColor: entry.color }} />
            <span className="text-muted-foreground">{entry.name}:</span>
            <span className="font-semibold text-foreground">
              {typeof entry.value === "number" && entry.value > 100 ? formatCurrency(entry.value) : entry.value}
            </span>
          </div>
        ))}
      </div>
    );
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl gradient-primary flex items-center justify-center">
            <BarChart3 size={24} className="text-primary-foreground" />
          </div>
          <div>
            <h1 className="font-display text-2xl font-bold text-foreground">Power BI</h1>
            <p className="text-sm text-muted-foreground">Central de inteligência do seu negócio imobiliário</p>
          </div>
        </div>
        <div className="flex items-center gap-2 bg-card border border-border rounded-xl p-1">
          {([
            { value: "7d", label: "7 dias" },
            { value: "30d", label: "30 dias" },
            { value: "90d", label: "90 dias" },
            { value: "365d", label: "1 ano" },
            { value: "all", label: "Tudo" },
          ] as { value: Period; label: string }[]).map(p => (
            <button
              key={p.value}
              onClick={() => setPeriod(p.value)}
              className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                period === p.value
                  ? "gradient-primary text-primary-foreground"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {kpis.map((kpi, i) => (
          <motion.div
            key={kpi.label}
            initial={{ opacity: 0, y: 15 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.03 * i }}
            className="bg-card rounded-xl border border-border p-4 hover:shadow-lg transition-shadow relative overflow-hidden group"
          >
            <div className={`absolute top-0 right-0 w-16 h-16 ${kpi.bg} rounded-full -translate-y-6 translate-x-6 opacity-50 group-hover:opacity-100 transition-opacity`} />
            <div className="flex items-center gap-2 mb-2">
              <div className={`w-8 h-8 rounded-lg ${kpi.bg} flex items-center justify-center`}>
                <kpi.icon size={14} className={kpi.color} />
              </div>
              {kpi.trend === "up" ? (
                <ArrowUpRight size={14} className="text-green-500" />
              ) : (
                <ArrowDownRight size={14} className="text-red-500" />
              )}
            </div>
            <p className={`font-display text-xl font-bold ${kpi.color}`}>{kpi.value}</p>
            <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-wider mt-0.5">{kpi.label}</p>
            <p className="text-[10px] text-muted-foreground">{kpi.sub}</p>
          </motion.div>
        ))}
      </div>

      {/* Row 1: Monthly Evolution + Conversion Gauges */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
          className="lg:col-span-2 bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <Activity size={16} className="text-primary" /> Evolução Mensal — Receitas vs Despesas
          </h3>
          <ResponsiveContainer width="100%" height={300}>
            <AreaChart data={data.monthlyEvolution}>
              <defs>
                <linearGradient id="gradReceitas" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="hsl(142,71%,45%)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="hsl(142,71%,45%)" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="gradDespesas" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="hsl(0,84%,60%)" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="hsl(0,84%,60%)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis dataKey="month" tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} />
              <YAxis tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} tickFormatter={(v) => formatCompact(v)} />
              <Tooltip content={<CustomTooltip />} />
              <Legend wrapperStyle={{ fontSize: "12px" }} />
              <Area type="monotone" dataKey="receitas" name="Receitas" stroke="hsl(142,71%,45%)" fill="url(#gradReceitas)" strokeWidth={2} />
              <Area type="monotone" dataKey="despesas" name="Despesas" stroke="hsl(0,84%,60%)" fill="url(#gradDespesas)" strokeWidth={2} />
              <Line type="monotone" dataKey="lucro" name="Lucro" stroke="hsl(var(--primary))" strokeWidth={2} strokeDasharray="5 5" dot={false} />
            </AreaChart>
          </ResponsiveContainer>
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.15 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <Target size={16} className="text-primary" /> Taxas de Performance
          </h3>
          <div className="space-y-6">
            {data.gauges.map((gauge) => (
              <div key={gauge.name} className="text-center">
                <ResponsiveContainer width="100%" height={120}>
                  <RadialBarChart cx="50%" cy="50%" innerRadius="60%" outerRadius="90%" startAngle={180} endAngle={0}
                    data={[{ value: gauge.value, fill: gauge.fill }]}
                  >
                    <RadialBar dataKey="value" cornerRadius={10} background={{ fill: "hsl(var(--secondary))" }} />
                  </RadialBarChart>
                </ResponsiveContainer>
                <p className="font-display text-2xl font-bold text-foreground -mt-8">{gauge.value}%</p>
                <p className="text-xs text-muted-foreground mt-1">{gauge.name}</p>
              </div>
            ))}
          </div>
        </motion.div>
      </div>

      {/* Row 2: Lead Funnel + Lead Sources + Property Types */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <Layers size={16} className="text-primary" /> Funil de Leads
          </h3>
          {data.funnelData.every(d => d.value === 0) ? (
            <p className="text-center text-muted-foreground py-8 text-sm">Sem leads ainda</p>
          ) : (
            <div className="space-y-2">
              {data.funnelData.map((item, i) => {
                const maxVal = Math.max(...data.funnelData.map(d => d.value), 1);
                const pct = (item.value / maxVal) * 100;
                return (
                  <div key={item.name} className="group">
                    <div className="flex items-center justify-between text-xs mb-1">
                      <span className="font-medium text-foreground">{item.name}</span>
                      <span className="font-bold text-foreground">{item.value}</span>
                    </div>
                    <div className="h-6 bg-secondary rounded-lg overflow-hidden">
                      <motion.div
                        initial={{ width: 0 }}
                        animate={{ width: `${pct}%` }}
                        transition={{ duration: 0.8, delay: 0.1 * i }}
                        className="h-full rounded-lg transition-all"
                        style={{ backgroundColor: COLORS[i % COLORS.length], minWidth: item.value > 0 ? "8px" : "0px" }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.25 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <PieChartIcon size={16} className="text-primary" /> Fontes de Leads
          </h3>
          {data.leadSources.length === 0 ? (
            <p className="text-center text-muted-foreground py-8 text-sm">Sem dados</p>
          ) : (
            <>
              <ResponsiveContainer width="100%" height={180}>
                <PieChart>
                  <Pie data={data.leadSources} cx="50%" cy="50%" innerRadius={45} outerRadius={75} paddingAngle={3} dataKey="value">
                    {data.leadSources.map((_, i) => (
                      <Cell key={i} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip content={<CustomTooltip />} />
                </PieChart>
              </ResponsiveContainer>
              <div className="grid grid-cols-2 gap-1 mt-2">
                {data.leadSources.map((source, i) => (
                  <div key={source.name} className="flex items-center gap-1.5 text-[10px]">
                    <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: COLORS[i % COLORS.length] }} />
                    <span className="text-muted-foreground truncate">{source.name}</span>
                    <span className="font-bold text-foreground ml-auto">{source.value}</span>
                  </div>
                ))}
              </div>
            </>
          )}
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <Building2 size={16} className="text-primary" /> Tipos de Imóveis
          </h3>
          {data.propertyTypes.length === 0 ? (
            <p className="text-center text-muted-foreground py-8 text-sm">Sem imóveis</p>
          ) : (
            <>
              <ResponsiveContainer width="100%" height={180}>
                <PieChart>
                  <Pie data={data.propertyTypes} cx="50%" cy="50%" outerRadius={75} dataKey="value" label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}>
                    {data.propertyTypes.map((_, i) => (
                      <Cell key={i} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip content={<CustomTooltip />} />
                </PieChart>
              </ResponsiveContainer>
              <div className="flex items-center justify-center gap-4 mt-2 text-xs">
                <div className="flex items-center gap-1">
                  <span className="w-3 h-3 rounded bg-primary" />
                  <span className="text-muted-foreground">Venda: {data.forSale}</span>
                </div>
                <div className="flex items-center gap-1">
                  <span className="w-3 h-3 rounded bg-blue-500" />
                  <span className="text-muted-foreground">Aluguel: {data.forRent}</span>
                </div>
              </div>
            </>
          )}
        </motion.div>
      </div>

      {/* Row 3: Leads + Contacts evolution */}
      <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.35 }}
        className="bg-card rounded-2xl border border-border p-5">
        <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
          <Users size={16} className="text-primary" /> Volume de Leads & Contatos por Mês
        </h3>
        <ResponsiveContainer width="100%" height={260}>
          <BarChart data={data.monthlyEvolution}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis dataKey="month" tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} />
            <YAxis tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} />
            <Tooltip content={<CustomTooltip />} />
            <Legend wrapperStyle={{ fontSize: "12px" }} />
            <Bar dataKey="leads" name="Leads" fill="hsl(280,67%,55%)" radius={[4, 4, 0, 0]} />
            <Bar dataKey="contacts" name="Contatos" fill="hsl(190,80%,50%)" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </motion.div>

      {/* Row 4: Neighborhoods + Price Distribution + Expense Categories */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.4 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <MapPin size={16} className="text-primary" /> Top Bairros — Imóveis Ativos
          </h3>
          {data.neighborhoods.length === 0 ? (
            <p className="text-center text-muted-foreground py-8 text-sm">Sem dados de bairro</p>
          ) : (
            <div className="space-y-3">
              {data.neighborhoods.map((n, i) => {
                const maxCount = data.neighborhoods[0]?.count || 1;
                return (
                  <div key={n.name}>
                    <div className="flex items-center justify-between text-xs mb-1">
                      <span className="font-medium text-foreground flex items-center gap-1">
                        <span className="text-muted-foreground font-mono">#{i + 1}</span> {n.name}
                      </span>
                      <span className="text-muted-foreground">{n.count} imóveis • Média {formatCompact(n.avgPrice)}</span>
                    </div>
                    <div className="h-3 bg-secondary rounded-full overflow-hidden">
                      <motion.div
                        initial={{ width: 0 }}
                        animate={{ width: `${(n.count / maxCount) * 100}%` }}
                        transition={{ duration: 0.6, delay: 0.05 * i }}
                        className="h-full rounded-full"
                        style={{ backgroundColor: COLORS[i % COLORS.length] }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.45 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <DollarSign size={16} className="text-primary" /> Distribuição por Faixa de Preço
          </h3>
          <ResponsiveContainer width="100%" height={250}>
            <BarChart data={data.priceDistribution}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis dataKey="name" tick={{ fontSize: 10, fill: "hsl(var(--muted-foreground))" }} />
              <YAxis tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }} />
              <Tooltip content={<CustomTooltip />} />
              <Legend wrapperStyle={{ fontSize: "12px" }} />
              <Bar dataKey="venda" name="Venda" fill="hsl(var(--primary))" radius={[4, 4, 0, 0]} />
              <Bar dataKey="aluguel" name="Aluguel" fill="hsl(217,91%,60%)" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </motion.div>
      </div>

      {/* Row 5: Expense Categories + Chat Analytics */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.5 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <PieChartIcon size={16} className="text-primary" /> Despesas por Categoria
          </h3>
          {data.expenseCategories.length === 0 ? (
            <p className="text-center text-muted-foreground py-8 text-sm">Sem despesas registradas</p>
          ) : (
            <div className="flex items-center gap-6">
              <ResponsiveContainer width="50%" height={200}>
                <PieChart>
                  <Pie data={data.expenseCategories} cx="50%" cy="50%" innerRadius={40} outerRadius={70} paddingAngle={2} dataKey="value">
                    {data.expenseCategories.map((_, i) => (
                      <Cell key={i} fill={COLORS[i % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip content={<CustomTooltip />} />
                </PieChart>
              </ResponsiveContainer>
              <div className="flex-1 space-y-2">
                {data.expenseCategories.slice(0, 6).map((cat, i) => (
                  <div key={cat.name} className="flex items-center gap-2 text-xs">
                    <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ backgroundColor: COLORS[i % COLORS.length] }} />
                    <span className="text-muted-foreground flex-1 truncate">{cat.name}</span>
                    <span className="font-bold text-foreground">{formatCompact(cat.value)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.55 }}
          className="bg-card rounded-2xl border border-border p-5">
          <h3 className="font-display font-bold text-sm text-foreground mb-4 flex items-center gap-2">
            <Eye size={16} className="text-primary" /> Resumo de Atendimentos
          </h3>
          <div className="grid grid-cols-2 gap-4">
            <div className="bg-secondary/50 rounded-xl p-4 text-center">
              <p className="font-display text-3xl font-bold text-foreground">{data.contacts.length}</p>
              <p className="text-xs text-muted-foreground font-semibold">Total Contatos</p>
            </div>
            <div className="bg-secondary/50 rounded-xl p-4 text-center">
              <p className="font-display text-3xl font-bold text-purple-500">{data.chatContacts.length}</p>
              <p className="text-xs text-muted-foreground font-semibold">Via Chat IA</p>
            </div>
            <div className="bg-secondary/50 rounded-xl p-4 text-center">
              <p className="font-display text-3xl font-bold text-blue-500">{data.formContacts.length}</p>
              <p className="text-xs text-muted-foreground font-semibold">Via Formulário</p>
            </div>
            <div className="bg-secondary/50 rounded-xl p-4 text-center">
              <p className="font-display text-3xl font-bold text-amber-500">{data.atrasados}</p>
              <p className="text-xs text-muted-foreground font-semibold">Pgtos Atrasados</p>
            </div>
          </div>
          <div className="mt-4 bg-secondary/30 rounded-xl p-3">
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground">Pendentes a receber</span>
              <span className="font-bold text-amber-500">{formatCurrency(data.pendentes)}</span>
            </div>
            <div className="flex items-center justify-between text-xs mt-1">
              <span className="text-muted-foreground">Imóveis ativos</span>
              <span className="font-bold text-foreground">{data.properties.filter(p => p.active).length}</span>
            </div>
            <div className="flex items-center justify-between text-xs mt-1">
              <span className="text-muted-foreground">Inquilinos cadastrados</span>
              <span className="font-bold text-foreground">{data.tenants.length}</span>
            </div>
          </div>
        </motion.div>
      </div>
    </div>
  );
};

export default ReportsTab;
