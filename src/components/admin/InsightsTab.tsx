import { useState } from "react";
import { Brain, RefreshCw, TrendingUp, Users, MessageSquare, Home, BarChart3, Sparkles } from "lucide-react";
import { toast } from "sonner";
import ReactMarkdown from "react-markdown";
import { supabase } from "@/integrations/supabase/client";

interface Metrics {
  totalLeads: number;
  leadsNovos: number;
  leadsFechados: number;
  leadsPerdidos: number;
  totalContacts: number;
  totalSales: number;
  totalProperties: number;
  chatContacts: number;
  fontes: [string, number][];
}

const InsightsTab = () => {
  const [insights, setInsights] = useState<string | null>(null);
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [loading, setLoading] = useState(false);
  const [generatedAt, setGeneratedAt] = useState<string | null>(null);

  const generateInsights = async () => {
    setLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        toast.error("Sessão expirada. Faça login novamente.");
        return;
      }

      const envBase = (import.meta.env.VITE_SUPABASE_URL || "").replace(/\/$/, "");
      const hostname = window.location.hostname;
      const isLovableHost = hostname.includes("lovable.app") || hostname.includes("lovableproject.com");
      const baseUrl = isLovableHost ? envBase : `${window.location.origin}/api`;
      const url = `${baseUrl}/functions/v1/ai-insights`;

      const resp = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
          apikey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
        },
      });

      if (!resp.ok) {
        const err = await resp.json().catch(() => ({ error: "Erro desconhecido" }));
        throw new Error(err.error || `Erro ${resp.status}`);
      }

      const data = await resp.json();
      setInsights(data.insights);
      setMetrics(data.metrics);
      setGeneratedAt(data.generatedAt);
      toast.success("Insights gerados com sucesso!");
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Erro ao gerar insights";
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  const metricCards = metrics
    ? [
        { icon: Users, label: "Total de Leads", value: metrics.totalLeads, color: "text-blue-500" },
        { icon: TrendingUp, label: "Leads Convertidos", value: metrics.leadsFechados, color: "text-green-500" },
        { icon: MessageSquare, label: "Conversas Chat", value: metrics.chatContacts, color: "text-purple-500" },
        { icon: Home, label: "Imóveis Ativos", value: metrics.totalProperties, color: "text-primary" },
        { icon: BarChart3, label: "Total Vendas", value: metrics.totalSales, color: "text-emerald-500" },
        { icon: Users, label: "Leads Novos", value: metrics.leadsNovos, color: "text-amber-500" },
      ]
    : [];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl gradient-primary flex items-center justify-center">
            <Brain size={24} className="text-primary-foreground" />
          </div>
          <div>
            <h1 className="font-display text-2xl font-bold text-foreground">Insights IA</h1>
            <p className="text-sm text-muted-foreground">Central de inteligência e BI powered by AI</p>
          </div>
        </div>
        <button
          onClick={generateInsights}
          disabled={loading}
          className="flex items-center gap-2 gradient-primary text-primary-foreground px-6 py-3 rounded-xl font-semibold hover:opacity-90 transition-opacity disabled:opacity-50"
        >
          {loading ? (
            <>
              <RefreshCw size={18} className="animate-spin" />
              Analisando...
            </>
          ) : (
            <>
              <Sparkles size={18} />
              Gerar Insights
            </>
          )}
        </button>
      </div>

      {/* Initial state */}
      {!insights && !loading && (
        <div className="bg-card border border-border rounded-2xl p-12 text-center">
          <div className="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6">
            <Brain size={40} className="text-primary" />
          </div>
          <h2 className="font-display text-xl font-bold text-foreground mb-3">
            Central de Inteligência
          </h2>
          <p className="text-muted-foreground max-w-md mx-auto mb-6">
            Clique em "Gerar Insights" para que a IA analise todos os seus leads, conversas com clientes,
            vendas e imóveis, gerando um relatório completo de Business Intelligence.
          </p>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 max-w-lg mx-auto">
            {[
              { icon: Users, label: "Leads" },
              { icon: MessageSquare, label: "Conversas" },
              { icon: TrendingUp, label: "Vendas" },
              { icon: Home, label: "Imóveis" },
            ].map((item) => (
              <div key={item.label} className="bg-secondary/50 rounded-xl p-3 text-center">
                <item.icon size={20} className="text-primary mx-auto mb-1" />
                <p className="text-xs text-muted-foreground">{item.label}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Loading state */}
      {loading && (
        <div className="bg-card border border-border rounded-2xl p-12 text-center">
          <div className="w-20 h-20 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-6 animate-pulse">
            <Brain size={40} className="text-primary" />
          </div>
          <h2 className="font-display text-xl font-bold text-foreground mb-3">
            Analisando seus dados...
          </h2>
          <p className="text-muted-foreground max-w-md mx-auto">
            A IA está processando leads, conversas, vendas e imóveis para gerar insights estratégicos.
            Isso pode levar alguns segundos.
          </p>
          <div className="flex justify-center gap-1 mt-6">
            <span className="w-3 h-3 bg-primary rounded-full animate-bounce [animation-delay:0ms]" />
            <span className="w-3 h-3 bg-primary rounded-full animate-bounce [animation-delay:150ms]" />
            <span className="w-3 h-3 bg-primary rounded-full animate-bounce [animation-delay:300ms]" />
          </div>
        </div>
      )}

      {/* Metrics cards */}
      {metrics && !loading && (
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
          {metricCards.map((card) => (
            <div key={card.label} className="bg-card border border-border rounded-xl p-4">
              <card.icon size={20} className={card.color} />
              <p className="font-display text-2xl font-bold text-foreground mt-2">{card.value}</p>
              <p className="text-xs text-muted-foreground">{card.label}</p>
            </div>
          ))}
        </div>
      )}

      {/* AI Insights */}
      {insights && !loading && (
        <div className="bg-card border border-border rounded-2xl overflow-hidden">
          <div className="bg-gradient-to-r from-primary/10 to-primary/5 px-6 py-4 border-b border-border flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Sparkles size={18} className="text-primary" />
              <h2 className="font-display font-bold text-foreground">Relatório de Insights</h2>
            </div>
            {generatedAt && (
              <p className="text-xs text-muted-foreground">
                Gerado em {new Date(generatedAt).toLocaleString("pt-BR")}
              </p>
            )}
          </div>
          <div className="p-6">
            <div className="prose prose-sm dark:prose-invert max-w-none
              [&>h3]:text-lg [&>h3]:font-display [&>h3]:font-bold [&>h3]:mt-8 [&>h3]:mb-3 [&>h3]:text-foreground
              [&>h4]:text-base [&>h4]:font-semibold [&>h4]:mt-6 [&>h4]:mb-2
              [&>ul]:space-y-1 [&>ol]:space-y-1
              [&>p]:text-muted-foreground [&>p]:leading-relaxed
              [&>table]:w-full [&>table]:border-collapse
              [&>table>thead>tr>th]:bg-secondary [&>table>thead>tr>th]:px-3 [&>table>thead>tr>th]:py-2 [&>table>thead>tr>th]:text-left [&>table>thead>tr>th]:text-sm [&>table>thead>tr>th]:font-semibold
              [&>table>tbody>tr>td]:px-3 [&>table>tbody>tr>td]:py-2 [&>table>tbody>tr>td]:border-t [&>table>tbody>tr>td]:border-border [&>table>tbody>tr>td]:text-sm
            ">
              <ReactMarkdown>{insights}</ReactMarkdown>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default InsightsTab;
