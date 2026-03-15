import { useState } from "react";
import { motion } from "framer-motion";
import {
  BookOpen, ChevronDown, ChevronRight, Home, Building2, Users, DollarSign,
  FileText, ClipboardCheck, MessageSquare, BarChart3, Shield, Settings,
  Search, Eye, Plus, Edit, Trash2, Upload, Download, Brain, Target,
  Calendar, Phone, Mail, MapPin, Key, UserPlus, Database,
  Layers, TrendingUp, Bot, Briefcase, HardHat, Zap
} from "lucide-react";

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

const ManualTab = () => {
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
                <li><strong>Barra de Busca</strong> — Filtro por tipo de imóvel e finalidade</li>
                <li><strong>Seção de Confiança</strong> — Estatísticas e diferenciais</li>
                <li><strong>Imóveis em Destaque</strong> — Cards dos imóveis marcados como destaque</li>
                <li><strong>Oportunidades</strong> — Imóveis com condições especiais</li>
                <li><strong>Sobre a Corretora</strong> — Perfil profissional</li>
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
              <p>Página com todos os imóveis ativos:</p>
              <ul className="space-y-1">
                <li>🔍 <strong>Busca por texto</strong> — Título, endereço ou bairro</li>
                <li>🏷️ <strong>Filtros</strong> — Tipo, status, faixa de preço, quartos</li>
                <li>📐 <strong>Ordenação</strong> — Por preço, data ou relevância</li>
                <li>📸 <strong>Galeria</strong> — Fotos e vídeos de cada imóvel</li>
              </ul>
            </>
          ),
        },
        {
          id: "detalhe-imovel",
          title: "Detalhe do Imóvel",
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
                <li>🏠 Contagem de imóveis ativos</li>
                <li>👥 Leads recentes e status</li>
                <li>📊 Gráfico de evolução mensal</li>
                <li>⚠️ Alertas de pagamentos atrasados</li>
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
                <Step number={1} title="Cadastrar Imóvel" description="Preencha título, endereço, bairro, cidade, preço, tipo, status, quartos, suítes, banheiros, garagem, área, piscina e descrição." />
                <Step number={2} title="Upload de Fotos" description="Arraste ou selecione fotos e vídeos. Reordene arrastando." />
                <Step number={3} title="Marcar como Destaque" description="Ative 'Destaque' para exibir o imóvel na home." />
                <Step number={4} title="Código Automático" description="O sistema gera automaticamente um código (V-0001 para venda, A-0001 para aluguel)." />
              </div>
              <Tip>Proximidades: adicione pontos de referência para melhorar o atendimento da IA.</Tip>
            </>
          ),
        },
        {
          id: "leads-admin",
          title: "Gestão de Leads (CRM)",
          content: (
            <>
              <p>Pipeline completo de gestão de prospects:</p>
              <ul className="space-y-1">
                <li><strong>Status do funil:</strong> Novo → Contato Feito → Visita Agendada → Proposta → Negociação → Fechado</li>
                <li><strong>Dados:</strong> Nome, telefone, email, fonte, interesse, faixa de orçamento</li>
                <li><strong>Follow-up:</strong> Data do próximo contato, notas</li>
                <li><strong>Vinculação:</strong> Associe um lead a um imóvel específico</li>
              </ul>
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
                <li>📎 Upload de documentos</li>
              </ul>
            </>
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
                <li>📅 Data início/fim, índice de reajuste</li>
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
              <p>Registro detalhado de vistorias:</p>
              <ul className="space-y-1">
                <li>🏠 Vincule ao imóvel, contrato e inquilino</li>
                <li>🔑 Quantidade de chaves entregues</li>
                <li>⚡ Leituras de medidores (água, luz, gás)</li>
                <li>🔧 Condição de: pintura, piso, elétrica, hidráulica</li>
                <li>📸 Upload de fotos/vídeos por categoria</li>
                <li>📄 Geração automática de PDF</li>
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
                <li><strong>Categorias:</strong> Aluguel, Venda, Comissão, Manutenção, Condomínio, IPTU, Seguro, Taxa Admin, Reparo</li>
                <li><strong>Status:</strong> Pendente, Pago, Atrasado, Cancelado</li>
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
            <li>🥧 <strong>Fontes de Leads</strong> — Gráfico pizza donut por canal</li>
            <li>🏠 <strong>Tipos de Imóveis</strong> — Distribuição por tipo</li>
            <li>📍 <strong>Top Bairros</strong> — Ranking com preço médio</li>
            <li>💰 <strong>Faixa de Preço</strong> — Distribuição venda vs aluguel</li>
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
            <li>⚠️ Pontos de atenção</li>
            <li>💡 Recomendações estratégicas personalizadas</li>
          </ul>
          <div className="space-y-3 mt-3">
            <Step number={1} title="Acesse Insights IA" description="No menu lateral, clique em 'Insights IA'." />
            <Step number={2} title="Gerar Insights" description="Clique no botão 'Gerar Insights'. A IA analisará todos os dados." />
            <Step number={3} title="Analise o Relatório" description="O relatório é exibido com cards de métricas e análise detalhada." />
          </div>
          <Tip>Quanto mais dados no sistema, mais precisos serão os insights.</Tip>
        </>
      ),
    },
    {
      id: "luma-ia",
      title: "6. Luma — Assistente Virtual (Chat IA)",
      icon: Bot,
      content: (
        <>
          <p>A <strong>Luma</strong> é a assistente virtual da Simply Imóveis. Atende clientes 24/7 pelo widget de chat.</p>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Capacidades:</h4>
          <ul className="space-y-1">
            <li>🏠 Consulta de imóveis do portfólio</li>
            <li>📅 Agendamento de visitas automático</li>
            <li>💰 Orientação sobre financiamento</li>
            <li>📍 Informações sobre bairros de Fortaleza</li>
            <li>📱 Coleta de contato automática</li>
            <li>📲 Notificação Telegram ao corretor</li>
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
            <li>👑 <strong>Admin</strong> — Acesso total ao painel</li>
            <li>👤 <strong>Moderator</strong> — Acesso intermediário</li>
            <li>👤 <strong>User</strong> — Acesso básico</li>
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
          <div className="space-y-3">
            <Step number={1} title="Crie um bot" description="Fale com @BotFather no Telegram e crie um bot." />
            <Step number={2} title="Obtenha o chat ID" description="Envie uma mensagem ao bot e acesse a API para pegar o chat_id." />
            <Step number={3} title="Configure no .env" description="Adicione TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID no .env." />
          </div>
        </>
      ),
    },
    {
      id: "infraestrutura",
      title: "9. Infraestrutura e Deploy",
      icon: HardHat,
      content: (
        <>
          <p>O sistema roda 100% self-hosted via Docker Compose em qualquer VPS.</p>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Componentes:</h4>
          <ul className="space-y-1">
            <li>🗄️ <strong>PostgreSQL</strong> — Banco de dados principal</li>
            <li>🔐 <strong>GoTrue</strong> — Autenticação (signup, login, JWT)</li>
            <li>🌐 <strong>PostgREST</strong> — API REST automática</li>
            <li>📦 <strong>Storage</strong> — Armazenamento de arquivos</li>
            <li>🦍 <strong>Kong</strong> — API Gateway</li>
            <li>⚡ <strong>Edge Functions</strong> — Serverless (Deno)</li>
            <li>🖥️ <strong>Nginx</strong> — Reverse proxy + SSL</li>
          </ul>
          <h4 className="font-semibold text-foreground mt-4 mb-2">Scripts principais:</h4>
          <ul className="space-y-1">
            <li><code>install.sh</code> — Instalação completa interativa</li>
            <li><code>create-admin.sh</code> — Criar usuário admin</li>
            <li><code>update.sh</code> — Atualizar sistema</li>
            <li><code>backup.sh</code> — Backup completo</li>
            <li><code>restore.sh</code> — Restaurar backup</li>
            <li><code>status.sh</code> — Verificar status dos serviços</li>
            <li><code>logs.sh</code> — Ver logs em tempo real</li>
          </ul>
        </>
      ),
    },
    {
      id: "boas-praticas",
      title: "10. Boas Práticas",
      icon: Target,
      content: (
        <>
          <ul className="space-y-2">
            <li>✅ <strong>Fotos de qualidade</strong> — Use fotos horizontais, bem iluminadas, mínimo 1200x800px</li>
            <li>✅ <strong>Descrições completas</strong> — Quanto mais detalhes, melhor a IA atende</li>
            <li>✅ <strong>Proximidades</strong> — Preencha sempre para a Luma orientar clientes</li>
            <li>✅ <strong>Follow-up de leads</strong> — Acompanhe a data de próximo contato</li>
            <li>✅ <strong>Backups regulares</strong> — Configure backup automático semanal</li>
            <li>✅ <strong>SSL ativo</strong> — Mantenha o certificado HTTPS atualizado</li>
            <li>✅ <strong>Senhas fortes</strong> — Mínimo 8 caracteres com letras e números</li>
          </ul>
        </>
      ),
    },
  ];

  return (
    <div>
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="mb-8"
      >
        <div className="flex items-center gap-4 mb-4">
          <div className="w-14 h-14 rounded-2xl gradient-primary flex items-center justify-center">
            <BookOpen size={28} className="text-primary-foreground" />
          </div>
          <div>
            <h1 className="font-display text-2xl font-bold text-foreground">Manual do Sistema</h1>
            <p className="text-sm text-muted-foreground">Guia completo de todas as funcionalidades do Simply Imóveis</p>
          </div>
        </div>
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
                document.getElementById(`manual-${s.id}`)?.scrollIntoView({ behavior: "smooth", block: "center" });
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
            id={`manual-${section.id}`}
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
  );
};

export default ManualTab;
