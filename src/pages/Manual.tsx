import { useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import {
  BookOpen, ChevronDown, ChevronRight, Home, Building2, Users, DollarSign,
  FileText, ClipboardCheck, MessageSquare, BarChart3, Shield, Settings,
  Search, Eye, Plus, Edit, Trash2, Upload, Download, Brain, Target,
  Calendar, Phone, Mail, MapPin, Key, UserPlus, Database, ArrowLeft,
  Layers, TrendingUp, Bot, Briefcase, HardHat, Zap
} from "lucide-react";
import Navbar from "@/components/Navbar";
import Footer from "@/components/Footer";

type Section = {
  id: string;
  title: string;
  icon: any;
  content: React.ReactNode;
  subsections?: { id: string; title: string; content: React.ReactNode }[];
};

const ManualSection = ({ section, isOpen, onToggle }: { section: Section; isOpen: boolean; onToggle: () => void }) => {
  const [openSubs, setOpenSubs] = useState<string[]>([]);
  const Icon = section.icon;

  return (
    <div className="bg-card border border-border rounded-2xl overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full flex items-center gap-3 px-6 py-4 text-left hover:bg-secondary/50 transition-colors"
      >
        <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
          <Icon size={20} className="text-primary" />
        </div>
        <div className="flex-1">
          <h2 className="font-display font-bold text-foreground">{section.title}</h2>
        </div>
        {isOpen ? <ChevronDown size={20} className="text-muted-foreground" /> : <ChevronRight size={20} className="text-muted-foreground" />}
      </button>

      {isOpen && (
        <motion.div
          initial={{ height: 0, opacity: 0 }}
          animate={{ height: "auto", opacity: 1 }}
          className="px-6 pb-6"
        >
          <div className="prose prose-sm dark:prose-invert max-w-none text-muted-foreground leading-relaxed">
            {section.content}
          </div>

          {section.subsections?.map((sub) => (
            <div key={sub.id} className="mt-4 border-t border-border pt-4">
              <button
                onClick={() => setOpenSubs(prev => prev.includes(sub.id) ? prev.filter(s => s !== sub.id) : [...prev, sub.id])}
                className="flex items-center gap-2 text-sm font-semibold text-foreground hover:text-primary transition-colors"
              >
                {openSubs.includes(sub.id) ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
                {sub.title}
              </button>
              {openSubs.includes(sub.id) && (
                <div className="mt-3 pl-6 prose prose-sm dark:prose-invert max-w-none text-muted-foreground leading-relaxed">
                  {sub.content}
                </div>
              )}
            </div>
          ))}
        </motion.div>
      )}
    </div>
  );
};

const Step = ({ number, title, description }: { number: number; title: string; description: string }) => (
  <div className="flex gap-3 items-start">
    <div className="w-7 h-7 rounded-full gradient-primary flex items-center justify-center flex-shrink-0 text-xs font-bold text-primary-foreground">
      {number}
    </div>
    <div>
      <p className="font-semibold text-foreground text-sm">{title}</p>
      <p className="text-muted-foreground text-sm">{description}</p>
    </div>
  </div>
);

const Tip = ({ children }: { children: React.ReactNode }) => (
  <div className="bg-primary/5 border border-primary/20 rounded-xl p-3 text-sm flex items-start gap-2 my-3">
    <Zap size={16} className="text-primary flex-shrink-0 mt-0.5" />
    <span className="text-foreground">{children}</span>
  </div>
);

const Manual = () => {
  const [openSections, setOpenSections] = useState<string[]>(["visao-geral"]);

  const toggleSection = (id: string) => {
    setOpenSections(prev => prev.includes(id) ? prev.filter(s => s !== id) : [...prev, id]);
  };

  const sections: Section[] = [
    {
      id: "visao-geral",
      title: "1. Visão Geral do Sistema",
      icon: BookOpen,
      content: (
        <>
          <p>O <strong>Simply Imóveis</strong> é um sistema completo de gestão imobiliária desenvolvido para corretores e imobiliárias. Ele combina um site institucional moderno com um painel administrativo poderoso, inteligência artificial e ferramentas de Business Intelligence.</p>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Principais módulos:</h4>
          <ul className="space-y-1">
            <li>🏠 <strong>Site Público</strong> — Vitrine de imóveis com busca e filtros</li>
            <li>📋 <strong>Painel Administrativo</strong> — Gestão completa do negócio</li>
            <li>🤖 <strong>Luma (IA)</strong> — Assistente virtual para atendimento</li>
            <li>📊 <strong>Power BI</strong> — Dashboards e relatórios avançados</li>
            <li>🧠 <strong>Insights IA</strong> — Análise inteligente de dados</li>
            <li>💬 <strong>Integração WhatsApp</strong> — Contato direto com clientes</li>
            <li>📱 <strong>Notificações Telegram</strong> — Alertas em tempo real</li>
          </ul>
        </>
      ),
    },
    {
      id: "site-publico",
      title: "2. Site Público",
      icon: Home,
      content: (
        <p>O site público é a vitrine digital da sua imobiliária. Responsivo e otimizado para SEO, apresenta os imóveis de forma profissional.</p>
      ),
      subsections: [
        {
          id: "pagina-inicial",
          title: "Página Inicial",
          content: (
            <>
              <p>A página inicial contém:</p>
              <ul className="space-y-1">
                <li><strong>Hero com Carrossel</strong> — Imagens rotativas de destaque com busca rápida</li>
                <li><strong>Barra de Busca</strong> — Filtro por tipo de imóvel e finalidade (compra/aluguel)</li>
                <li><strong>Seção de Confiança</strong> — Estatísticas e diferenciais</li>
                <li><strong>Imóveis em Destaque</strong> — Cards dos imóveis marcados como destaque</li>
                <li><strong>Oportunidades</strong> — Imóveis com condições especiais</li>
                <li><strong>Sobre a Corretora</strong> — Perfil profissional e pilares de atuação</li>
                <li><strong>Formulário de Contato</strong> — Envio direto para o banco de dados</li>
              </ul>
            </>
          ),
        },
        {
          id: "listagem-imoveis",
          title: "Listagem de Imóveis (/imoveis)",
          content: (
            <>
              <p>Página com todos os imóveis ativos. Funcionalidades:</p>
              <ul className="space-y-1">
                <li>🔍 <strong>Busca por texto</strong> — Título, endereço ou bairro</li>
                <li>🏷️ <strong>Filtros</strong> — Tipo, status (venda/aluguel), faixa de preço, quartos</li>
                <li>📐 <strong>Ordenação</strong> — Por preço, data ou relevância</li>
                <li>📸 <strong>Galeria</strong> — Fotos e vídeos de cada imóvel</li>
                <li>📍 <strong>Localização</strong> — Bairro e cidade visíveis</li>
              </ul>
            </>
          ),
        },
        {
          id: "detalhe-imovel",
          title: "Detalhe do Imóvel (/imoveis/:id)",
          content: (
            <>
              <p>Página individual com todas as informações:</p>
              <ul className="space-y-1">
                <li>📸 Galeria de fotos em carrossel</li>
                <li>📋 Descrição completa, código do imóvel</li>
                <li>🛏️ Quartos, suítes, banheiros, garagem, área, piscina</li>
                <li>📍 Endereço, bairro, proximidades</li>
                <li>💰 Preço e status (venda/aluguel)</li>
                <li>📧 Formulário de contato/interesse</li>
                <li>📅 Botão para agendar visita via Chat IA</li>
              </ul>
            </>
          ),
        },
        {
          id: "servicos",
          title: "Página de Serviços (/servicos)",
          content: (
            <p>Apresenta os serviços oferecidos pela imobiliária: assessoria na compra, venda, aluguel, administração de imóveis, e consultoria de investimento. O botão "Fale Conosco" abre automaticamente o chat da Luma.</p>
          ),
        },
      ],
    },
    {
      id: "painel-admin",
      title: "3. Painel Administrativo (/admin)",
      icon: Settings,
      content: (
        <>
          <p>O painel admin é acessado em <code>/admin</code>. Requer autenticação com email e senha de um usuário com role <strong>admin</strong>.</p>
          <Tip>Para criar o primeiro admin, use o script <code>create-admin.sh</code> no servidor.</Tip>
        </>
      ),
      subsections: [
        {
          id: "dashboard",
          title: "Dashboard",
          content: (
            <>
              <p>Visão geral instantânea do negócio:</p>
              <ul className="space-y-1">
                <li>💰 Resumo financeiro (receitas, despesas, lucro)</li>
                <li>🏠 Contagem de imóveis ativos (venda vs aluguel)</li>
                <li>👥 Leads recentes e status</li>
                <li>📊 Gráfico de evolução mensal (Recharts)</li>
                <li>⚠️ Alertas de pagamentos atrasados</li>
                <li>📋 Últimas transações financeiras</li>
              </ul>
            </>
          ),
        },
        {
          id: "imoveis-admin",
          title: "Gestão de Imóveis",
          content: (
            <>
              <p>Módulo completo de CRUD de imóveis:</p>
              <div className="space-y-3 mt-3">
                <Step number={1} title="Cadastrar Imóvel" description="Preencha título, endereço, bairro, cidade, preço, tipo (Apartamento/Casa/Cobertura/Terreno/Sala Comercial), status (venda/aluguel), quartos, suítes, banheiros, garagem, área, piscina e descrição." />
                <Step number={2} title="Upload de Fotos" description="Arraste ou selecione fotos e vídeos. Reordene arrastando. Formatos aceitos: JPG, PNG, WebP, MP4." />
                <Step number={3} title="Marcar como Destaque" description="Ative 'Destaque' para exibir o imóvel na home. Ative/desative a visibilidade com 'Ativo'." />
                <Step number={4} title="Código Automático" description="O sistema gera automaticamente um código (V-0001 para venda, A-0001 para aluguel)." />
              </div>
              <Tip>Proximidades: adicione pontos de referência (ex: "Shopping Iguatemi 5min, Praia 800m") para melhorar o atendimento da IA.</Tip>
            </>
          ),
        },
        {
          id: "contatos-admin",
          title: "Contatos",
          content: (
            <p>Lista todas as solicitações recebidas via formulário do site e conversas com a Luma (chat IA). Cada contato mostra nome, email, telefone, assunto, mensagem, data, fonte (site/chat) e a transcrição completa da conversa quando originado do chat. Marque como lido ou exclua.</p>
          ),
        },
        {
          id: "leads-admin",
          title: "Gestão de Leads (CRM)",
          content: (
            <>
              <p>Pipeline completo de gestão de prospects:</p>
              <ul className="space-y-1">
                <li><strong>Status do funil:</strong> Novo → Contato Feito → Visita Agendada → Proposta → Negociação → Fechado (Ganho/Perdido)</li>
                <li><strong>Dados:</strong> Nome, telefone, email, fonte, interesse, faixa de orçamento</li>
                <li><strong>Follow-up:</strong> Data do próximo contato, notas</li>
                <li><strong>Vinculação:</strong> Associe um lead a um imóvel específico</li>
              </ul>
              <Tip>Leads vindos do chat da Luma são registrados automaticamente com a fonte "chat".</Tip>
            </>
          ),
        },
        {
          id: "vendas-admin",
          title: "Pipeline de Vendas",
          content: (
            <>
              <p>Gerencie todo o processo de venda:</p>
              <ul className="space-y-1">
                <li>📋 Vincule a um imóvel e lead existente</li>
                <li>👤 Dados do comprador (nome, CPF, email, telefone)</li>
                <li>💰 Valor da venda, comissão (taxa e valor)</li>
                <li>📅 Data da proposta e fechamento</li>
                <li>📎 Upload de documentos (contratos, escrituras, etc.)</li>
                <li>📝 Status: Em andamento, Proposta, Fechado, Cancelado</li>
              </ul>
            </>
          ),
        },
        {
          id: "inquilinos-admin",
          title: "Cadastro de Inquilinos",
          content: (
            <p>Cadastre inquilinos com dados completos: nome, CPF/CNPJ, RG, telefone, email, endereço e observações. Upload de documentos pessoais (RG, CPF, comprovante de renda, etc.) vinculados ao inquilino.</p>
          ),
        },
        {
          id: "alugueis-admin",
          title: "Contratos de Aluguel",
          content: (
            <>
              <p>Gestão completa de contratos de locação:</p>
              <ul className="space-y-1">
                <li>📋 Vincule imóvel e inquilino</li>
                <li>💰 Valor do aluguel, caução, dia de pagamento</li>
                <li>📅 Data início/fim, índice de reajuste (IGPM, IPCA)</li>
                <li>% Comissão e taxa de multa</li>
                <li>📎 Upload de documentos do contrato</li>
                <li>📊 Status: Ativo, Pendente, Encerrado, Cancelado</li>
              </ul>
            </>
          ),
        },
        {
          id: "vistorias-admin",
          title: "Vistorias de Imóveis",
          content: (
            <>
              <p>Registro detalhado de vistorias de entrada e saída:</p>
              <ul className="space-y-1">
                <li>🏠 Vincule ao imóvel, contrato e inquilino</li>
                <li>👤 Nome do vistoriador, data da vistoria</li>
                <li>🔑 Quantidade de chaves entregues</li>
                <li>⚡ Leituras de medidores (água, luz, gás)</li>
                <li>🔧 Condição de: pintura, piso, elétrica, hidráulica, cômodos</li>
                <li>📸 Upload de fotos/vídeos por categoria</li>
                <li>📄 Geração automática de PDF da vistoria</li>
              </ul>
            </>
          ),
        },
        {
          id: "financeiro-admin",
          title: "Gestão Financeira",
          content: (
            <>
              <p>Controle completo de receitas e despesas:</p>
              <ul className="space-y-1">
                <li><strong>Tipos:</strong> Receita ou Despesa</li>
                <li><strong>Categorias:</strong> Aluguel, Venda, Comissão, Manutenção, Condomínio, IPTU, Seguro, Taxa Admin, Reparo, Outro</li>
                <li><strong>Status:</strong> Pendente, Pago, Atrasado, Cancelado</li>
                <li>💳 Método de pagamento, data de vencimento e pagamento</li>
                <li>📎 Upload de comprovantes</li>
                <li>🔗 Vincule a imóvel, contrato ou inquilino</li>
              </ul>
            </>
          ),
        },
      ],
    },
    {
      id: "power-bi",
      title: "4. Power BI — Relatórios e Dashboards",
      icon: BarChart3,
      content: (
        <>
          <p>Central de Business Intelligence com gráficos interativos e métricas em tempo real.</p>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Dashboards disponíveis:</h4>
          <ul className="space-y-1">
            <li>📈 <strong>Evolução Mensal</strong> — Gráfico de área com receitas, despesas e lucro</li>
            <li>🎯 <strong>Taxas de Performance</strong> — Gauges radiais de conversão e ocupação</li>
            <li>🔽 <strong>Funil de Leads</strong> — Visualização do pipeline por etapa</li>
            <li>🥧 <strong>Fontes de Leads</strong> — Gráfico pizza donut por canal de origem</li>
            <li>🏠 <strong>Tipos de Imóveis</strong> — Distribuição por tipo (apartamento, casa, etc.)</li>
            <li>👥 <strong>Volume de Leads & Contatos</strong> — Barras por mês</li>
            <li>📍 <strong>Top Bairros</strong> — Ranking com preço médio</li>
            <li>💰 <strong>Faixa de Preço</strong> — Distribuição venda vs aluguel</li>
            <li>🥧 <strong>Despesas por Categoria</strong> — Donut com breakdown</li>
            <li>📊 <strong>Resumo de Atendimentos</strong> — Chat IA vs Formulário</li>
          </ul>
          <Tip>Use o filtro de período (7d, 30d, 90d, 1 ano, Tudo) para analisar intervalos específicos.</Tip>
        </>
      ),
    },
    {
      id: "insights-ia",
      title: "5. Insights IA — Inteligência Artificial",
      icon: Brain,
      content: (
        <>
          <p>A central de inteligência usa IA para analisar automaticamente todos os dados do negócio e gerar relatórios estratégicos.</p>
          <h4 className="font-semibold text-foreground mt-4 mb-2">O relatório inclui:</h4>
          <ul className="space-y-1">
            <li>📊 Resumo executivo do momento atual</li>
            <li>🎯 Insights sobre padrões de comportamento</li>
            <li>📍 Análise de localização e bairros mais procurados</li>
            <li>🏠 Preferências de imóveis dos clientes</li>
            <li>📈 Análise do funil de vendas e gargalos</li>
            <li>⚠️ Pontos de atenção (desistências, leads sem follow-up)</li>
            <li>💡 Recomendações estratégicas personalizadas</li>
            <li>📋 Tabela de métricas-chave (KPIs)</li>
          </ul>
          <div className="space-y-3 mt-3">
            <Step number={1} title="Acesse Insights IA" description="No menu lateral do painel admin, clique em 'Insights IA'." />
            <Step number={2} title="Gerar Insights" description="Clique no botão 'Gerar Insights'. A IA analisará leads, conversas, vendas e imóveis." />
            <Step number={3} title="Analise o Relatório" description="O relatório é exibido em formato rico com cards de métricas e análise detalhada." />
          </div>
          <Tip>Quanto mais dados no sistema, mais precisos e relevantes serão os insights gerados.</Tip>
        </>
      ),
    },
    {
      id: "luma-ia",
      title: "6. Luma — Assistente Virtual (Chat IA)",
      icon: Bot,
      content: (
        <>
          <p>A <strong>Luma</strong> é a assistente virtual da Simply Imóveis. Ela atende clientes 24/7 pelo widget de chat presente em todas as páginas.</p>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Capacidades:</h4>
          <ul className="space-y-1">
            <li>🏠 <strong>Consulta de imóveis</strong> — Busca e apresenta imóveis do portfólio com dados reais</li>
            <li>📅 <strong>Agendamento de visitas</strong> — Coleta dados e cria a visita automaticamente</li>
            <li>💰 <strong>Financiamento</strong> — Orienta sobre opções e documentação</li>
            <li>📍 <strong>Bairros</strong> — Informações sobre regiões de Fortaleza</li>
            <li>📱 <strong>Coleta de contato</strong> — Registra nome e telefone automaticamente</li>
            <li>📲 <strong>Notificação Telegram</strong> — Envia alerta ao corretor quando visita é agendada</li>
          </ul>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Como funciona:</h4>
          <ul className="space-y-1">
            <li>O widget de chat aparece no canto inferior direito de todas as páginas</li>
            <li>Na página de detalhe do imóvel, a Luma já tem contexto do imóvel sendo visualizado</li>
            <li>O botão "Fale Conosco" na página de Serviços também abre o chat da Luma</li>
            <li>Todas as conversas são salvas no banco de dados com transcrição completa</li>
          </ul>
        </>
      ),
    },
    {
      id: "usuarios",
      title: "7. Gestão de Usuários e Segurança",
      icon: Shield,
      content: (
        <>
          <p>O sistema utiliza autenticação segura com roles para controle de acesso.</p>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Roles disponíveis:</h4>
          <ul className="space-y-1">
            <li>👑 <strong>Admin</strong> — Acesso total ao painel e todas as funcionalidades</li>
            <li>👤 <strong>Moderator</strong> — Acesso intermediário (configurável)</li>
            <li>👤 <strong>User</strong> — Acesso básico</li>
          </ul>
          <h4 className="font-semibold text-foreground mt-4 mb-2">No painel admin:</h4>
          <ul className="space-y-1">
            <li><strong>Aba Usuários:</strong> Crie novos usuários admin com email e senha</li>
            <li><strong>Aba Senha:</strong> Altere sua própria senha</li>
            <li><strong>Segurança RLS:</strong> Todas as tabelas possuem Row Level Security</li>
          </ul>
          <Tip>O primeiro admin deve ser criado via script no servidor: <code>sudo bash create-admin.sh</code></Tip>
        </>
      ),
    },
    {
      id: "notificacoes",
      title: "8. Notificações (Telegram)",
      icon: Phone,
      content: (
        <>
          <p>O sistema envia notificações automáticas via Telegram quando:</p>
          <ul className="space-y-1">
            <li>📅 Uma visita é agendada pelo chat da Luma</li>
            <li>👤 Um novo contato é registrado</li>
          </ul>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Configuração:</h4>
          <div className="space-y-3 mt-3">
            <Step number={1} title="Crie um bot no Telegram" description="Fale com @BotFather no Telegram e crie um novo bot. Copie o token." />
            <Step number={2} title="Obtenha seu Chat ID" description="Envie uma mensagem ao bot e use a API para descobrir seu chat_id." />
            <Step number={3} title="Configure os secrets" description="Adicione TELEGRAM_API_KEY e TELEGRAM_CHAT_ID nas configurações do servidor." />
          </div>
        </>
      ),
    },
    {
      id: "deploy",
      title: "9. Deploy e Infraestrutura (VPS)",
      icon: Database,
      content: (
        <>
          <p>O sistema é auto-hospedado via Docker em VPS com os seguintes serviços:</p>
          <ul className="space-y-1">
            <li>🐘 <strong>PostgreSQL</strong> — Banco de dados principal</li>
            <li>🔐 <strong>GoTrue</strong> — Autenticação (signup, login, JWT)</li>
            <li>🌐 <strong>PostgREST</strong> — API REST automática</li>
            <li>📦 <strong>Storage</strong> — Armazenamento de arquivos (S3-compatible)</li>
            <li>🦍 <strong>Kong</strong> — API Gateway</li>
            <li>⚡ <strong>Deno Functions</strong> — Edge functions (chat, notificações, etc.)</li>
            <li>🌐 <strong>Nginx</strong> — Reverse proxy com SSL</li>
          </ul>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Scripts disponíveis:</h4>
          <table className="w-full text-sm border-collapse mt-2">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left py-2 font-semibold text-foreground">Script</th>
                <th className="text-left py-2 font-semibold text-foreground">Função</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              <tr><td className="py-2"><code>install.sh</code></td><td className="py-2">Instalação completa interativa</td></tr>
              <tr><td className="py-2"><code>create-admin.sh</code></td><td className="py-2">Criar primeiro usuário admin</td></tr>
              <tr><td className="py-2"><code>quick-update.sh</code></td><td className="py-2">Atualizar frontend do GitHub</td></tr>
              <tr><td className="py-2"><code>update.sh</code></td><td className="py-2">Atualização completa</td></tr>
              <tr><td className="py-2"><code>backup.sh</code></td><td className="py-2">Backup do banco de dados</td></tr>
              <tr><td className="py-2"><code>restore.sh</code></td><td className="py-2">Restaurar backup</td></tr>
              <tr><td className="py-2"><code>setup-ssl.sh</code></td><td className="py-2">Configurar certificado SSL</td></tr>
              <tr><td className="py-2"><code>status.sh</code></td><td className="py-2">Ver status dos containers</td></tr>
              <tr><td className="py-2"><code>logs.sh</code></td><td className="py-2">Ver logs do sistema</td></tr>
              <tr><td className="py-2"><code>validate.sh</code></td><td className="py-2">Validar configuração</td></tr>
            </tbody>
          </table>
        </>
      ),
    },
    {
      id: "dicas",
      title: "10. Dicas e Boas Práticas",
      icon: Target,
      content: (
        <>
          <ul className="space-y-3">
            <li>
              <strong>📸 Fotos de qualidade</strong>
              <p>Use fotos em alta resolução (mín. 1200x800px). A primeira foto é a capa do imóvel.</p>
            </li>
            <li>
              <strong>📝 Descrições detalhadas</strong>
              <p>Quanto mais detalhada a descrição, melhor a Luma responde aos clientes sobre o imóvel.</p>
            </li>
            <li>
              <strong>📍 Proximidades</strong>
              <p>Preencha o campo "Proximidades" com pontos de referência. A Luma usa essas informações.</p>
            </li>
            <li>
              <strong>⭐ Destaques</strong>
              <p>Marque de 3 a 6 imóveis como destaque para a página inicial.</p>
            </li>
            <li>
              <strong>📊 Insights regulares</strong>
              <p>Gere insights com IA semanalmente para acompanhar tendências do mercado.</p>
            </li>
            <li>
              <strong>👥 Follow-up de leads</strong>
              <p>Use o CRM para não perder nenhum prospect. A IA identifica leads sem follow-up.</p>
            </li>
            <li>
              <strong>💰 Financeiro em dia</strong>
              <p>Registre todas as transações para ter relatórios precisos no Power BI.</p>
            </li>
            <li>
              <strong>🔒 Backups regulares</strong>
              <p>Faça backup do banco pelo menos semanalmente usando o script <code>backup.sh</code>.</p>
            </li>
          </ul>
        </>
      ),
    },
  ];

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <div className="pt-24 pb-16">
        <div className="container mx-auto px-4 sm:px-6 lg:px-8 max-w-4xl">
          {/* Header */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-center mb-10"
          >
            <Link to="/" className="inline-flex items-center gap-2 text-sm text-primary hover:underline mb-4">
              <ArrowLeft size={14} /> Voltar ao site
            </Link>
            <div className="w-16 h-16 rounded-2xl gradient-primary flex items-center justify-center mx-auto mb-4">
              <BookOpen size={32} className="text-primary-foreground" />
            </div>
            <h1 className="font-display text-3xl sm:text-4xl font-bold text-foreground mb-3">
              Manual do Sistema
            </h1>
            <p className="text-muted-foreground max-w-xl mx-auto">
              Guia completo de todas as funcionalidades do Simply Imóveis.
              Clique em cada seção para expandir.
            </p>
          </motion.div>

          {/* Quick nav */}
          <div className="bg-card border border-border rounded-2xl p-4 mb-8">
            <p className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-3">Navegação rápida</p>
            <div className="flex flex-wrap gap-2">
              {sections.map((s) => (
                <button
                  key={s.id}
                  onClick={() => {
                    if (!openSections.includes(s.id)) toggleSection(s.id);
                    document.getElementById(s.id)?.scrollIntoView({ behavior: "smooth", block: "center" });
                  }}
                  className="text-xs bg-secondary hover:bg-primary/10 hover:text-primary text-muted-foreground px-3 py-1.5 rounded-lg transition-colors"
                >
                  {s.title.split(". ")[1]}
                </button>
              ))}
            </div>
          </div>

          {/* Sections */}
          <div className="space-y-4">
            {sections.map((section, i) => (
              <motion.div
                key={section.id}
                id={section.id}
                initial={{ opacity: 0, y: 15 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.03 * i }}
              >
                <ManualSection
                  section={section}
                  isOpen={openSections.includes(section.id)}
                  onToggle={() => toggleSection(section.id)}
                />
              </motion.div>
            ))}
          </div>

          {/* Footer note */}
          <div className="mt-12 text-center">
            <p className="text-sm text-muted-foreground">
              Simply Imóveis — Software por T2 Systems LTDA.
            </p>
            <p className="text-xs text-muted-foreground/60 mt-1">
              Versão 1.0 • Última atualização: {new Date().toLocaleDateString("pt-BR")}
            </p>
          </div>
        </div>
      </div>
      <Footer />
    </div>
  );
};

export default Manual;
