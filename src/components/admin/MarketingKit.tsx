import { useState, useEffect } from "react";
import { 
  X, Download, Share2, MapPin, BedDouble, Bath, Maximize2, 
  Car, ImageIcon, Sparkles, Copy, Check, Instagram, MessageSquare, 
  Send, FileText, Loader2, RefreshCw
} from "lucide-react";
import { getMediaUrl } from "@/lib/mediaUrl";
import { motion, AnimatePresence } from "framer-motion";
import { adminAiGenerate } from "@/lib/adminCrud";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card } from "@/components/ui/card";

interface MarketingKitProps {
  property: any;
  onClose: () => void;
}

const MarketingKit = ({ property, onClose }: MarketingKitProps) => {
  const [activeTab, setActiveTab] = useState("flyer");
  const [isGenerating, setIsGenerating] = useState(false);
  const [copiedField, setCopiedField] = useState<string | null>(null);
  const [aiContent, setAiContent] = useState<{
    instagramPost?: string;
    whatsappMessage?: string;
    salesPitch?: string;
    hashtags?: string;
  }>({});

  const propertyContext = `
    Imóvel: ${property.title}
    Tipo: ${property.type}
    Status: ${property.status}
    Preço: ${Number(property.price).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
    Localização: ${property.neighborhood}, ${property.city}
    Quartos: ${property.bedrooms}
    Banheiros: ${property.bathrooms}
    Área: ${property.area}m²
    Vagas: ${property.garage_spots || 0}
    Código: ${property.short_code || 'N/A'}
    Destaque: ${property.featured ? 'Sim' : 'Não'}
  `;

  const generateAIContent = async () => {
    setIsGenerating(true);
    try {
      const prompt = `
        Gere um kit de marketing imobiliário para o seguinte imóvel:
        ${propertyContext}

        O kit deve conter:
        1. Legenda para Instagram (atraente, com emojis, focada em benefícios).
        2. Mensagem para WhatsApp (curta, direta, pronta para encaminhar).
        3. Pitch de Vendas (argumentos matadores para o corretor usar na visita).
        4. Melhores hashtags para o nicho imobiliário dessa região.

        Responda em formato JSON válido com as chaves: "instagramPost", "whatsappMessage", "salesPitch", "hashtags".
        Responda APENAS o JSON, sem textos adicionais.
      `;

      const result = await adminAiGenerate(prompt, {
        systemPrompt: "Você é um copywriter sênior especializado no mercado imobiliário de alto padrão. Seu objetivo é criar desejo e urgência.",
        temperature: 0.8,
        model: "deepseek-chat"
      });

      if (result.error) throw new Error(result.error.message);

      // Limpar o JSON caso a IA retorne markdown
      const jsonStr = result.data?.replace(/```json|```/g, "").trim();
      const content = JSON.parse(jsonStr || "{}");
      setAiContent(content);
      toast.success("Conteúdo gerado com sucesso!");
    } catch (error: any) {
      console.error("AI Generation error:", error);
      toast.error("Erro ao gerar conteúdo: " + error.message);
    } finally {
      setIsGenerating(false);
    }
  };

  const copyToClipboard = (text: string, field: string) => {
    navigator.clipboard.writeText(text);
    setCopiedField(field);
    toast.success("Copiado para a área de transferência");
    setTimeout(() => setCopiedField(null), 2000);
  };

  const handlePrint = () => {
    window.print();
  };

  return (
    <div className="fixed inset-0 z-[100] bg-background/95 backdrop-blur-md flex items-center justify-center p-4 print:p-0 print:bg-white overflow-hidden">
      <motion.div 
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="bg-card border border-border w-full max-w-5xl h-[90vh] overflow-hidden rounded-3xl shadow-2xl flex flex-col print:h-auto print:shadow-none print:border-none print:rounded-none"
      >
        {/* Header */}
        <div className="px-8 py-5 border-b border-border flex items-center justify-between bg-muted/30 print:hidden">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-2xl bg-primary/10 flex items-center justify-center text-primary">
              <Sparkles size={24} />
            </div>
            <div>
              <h2 className="font-display text-xl font-bold text-foreground">Marketing Kit AI</h2>
              <p className="text-xs text-muted-foreground">Material automatizado por IA</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <Button 
              variant="outline" 
              size="sm" 
              onClick={generateAIContent}
              disabled={isGenerating}
              className="gap-2 rounded-xl"
            >
              {isGenerating ? <Loader2 size={16} className="animate-spin" /> : <RefreshCw size={16} />}
              {Object.keys(aiContent).length > 0 ? "Regerar" : "Gerar com IA"}
            </Button>
            <Button 
              size="sm" 
              onClick={handlePrint}
              className="gap-2 rounded-xl bg-primary hover:bg-primary/90"
            >
              <Download size={16} /> Imprimir PDF
            </Button>
            <button 
              onClick={onClose} 
              className="p-2.5 hover:bg-secondary rounded-xl transition-colors border border-border ml-2"
            >
              <X size={20} />
            </button>
          </div>
        </div>

        {/* Layout Principal */}
        <div className="flex-1 flex overflow-hidden print:block">
          {/* Sidebar Tabs */}
          <div className="w-64 border-r border-border bg-muted/10 p-4 flex flex-col gap-2 print:hidden">
            <button 
              onClick={() => setActiveTab("flyer")}
              className={`flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-medium transition-all ${activeTab === 'flyer' ? 'bg-primary text-primary-foreground shadow-lg shadow-primary/20' : 'hover:bg-secondary'}`}
            >
              <FileText size={18} /> Panfleto Digital
            </button>
            <button 
              onClick={() => setActiveTab("instagram")}
              className={`flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-medium transition-all ${activeTab === 'instagram' ? 'bg-primary text-primary-foreground shadow-lg shadow-primary/20' : 'hover:bg-secondary'}`}
            >
              <Instagram size={18} /> Instagram (Legenda)
            </button>
            <button 
              onClick={() => setActiveTab("whatsapp")}
              className={`flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-medium transition-all ${activeTab === 'whatsapp' ? 'bg-primary text-primary-foreground shadow-lg shadow-primary/20' : 'hover:bg-secondary'}`}
            >
              <MessageSquare size={18} /> WhatsApp
            </button>
            <button 
              onClick={() => setActiveTab("pitch")}
              className={`flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-medium transition-all ${activeTab === 'pitch' ? 'bg-primary text-primary-foreground shadow-lg shadow-primary/20' : 'hover:bg-secondary'}`}
            >
              <Send size={18} /> Pitch de Vendas
            </button>

            <div className="mt-auto p-4 bg-primary/5 rounded-2xl border border-primary/10">
              <p className="text-[10px] uppercase font-bold text-primary mb-1">Dica de Especialista</p>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Use a IA para criar descrições que focam no estilo de vida, não apenas no número de quartos.
              </p>
            </div>
          </div>

          {/* Main Content Area */}
          <div className="flex-1 overflow-y-auto p-8 bg-secondary/5 print:p-0 print:bg-white">
            <AnimatePresence mode="wait">
              {activeTab === "flyer" && (
                <motion.div 
                  key="flyer"
                  initial={{ opacity: 0, x: 20 }}
                  animate={{ opacity: 1, x: 0 }}
                  exit={{ opacity: 0, x: -20 }}
                  className="flex flex-col items-center"
                >
                  <div id="marketing-flyer" className="bg-white text-slate-900 w-full aspect-[4/5] max-w-[500px] shadow-2xl flex flex-col relative rounded-sm overflow-hidden print:shadow-none print:max-w-none">
                    {/* Header Image */}
                    <div className="h-2/5 relative overflow-hidden">
                      {property.media?.[0] ? (
                        <img 
                          src={getMediaUrl(property.media[0].file_path)} 
                          alt={property.title}
                          className="w-full h-full object-cover"
                        />
                      ) : (
                        <div className="w-full h-full bg-slate-200 flex items-center justify-center">
                          <ImageIcon size={48} className="text-slate-400" />
                        </div>
                      )}
                      <div className="absolute top-6 left-6 bg-primary text-white px-4 py-1.5 rounded-full text-xs font-bold uppercase tracking-widest shadow-lg">
                        {property.status === 'venda' ? 'À Venda' : 'Aluguel'}
                      </div>
                      <div className="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent flex items-end p-8">
                        <div>
                          <p className="text-white/80 text-xs font-bold uppercase tracking-wider mb-1">{property.type}</p>
                          <h1 className="text-2xl font-black text-white leading-tight">
                            {property.title}
                          </h1>
                        </div>
                      </div>
                    </div>

                    {/* Content Body */}
                    <div className="flex-1 p-8 flex flex-col bg-slate-50">
                      <p className="text-slate-500 text-sm flex items-center gap-2 mb-8 font-medium">
                        <MapPin size={16} className="text-primary" /> {property.neighborhood}, {property.city}
                      </p>

                      <div className="grid grid-cols-2 gap-y-6 gap-x-10 mb-8">
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 rounded-xl bg-white shadow-sm flex items-center justify-center text-primary border border-slate-100">
                            <BedDouble size={20} />
                          </div>
                          <div>
                            <p className="text-[10px] text-slate-400 uppercase font-bold tracking-wider">Quartos</p>
                            <p className="text-base font-black text-slate-800">{property.bedrooms}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 rounded-xl bg-white shadow-sm flex items-center justify-center text-primary border border-slate-100">
                            <Maximize2 size={20} />
                          </div>
                          <div>
                            <p className="text-[10px] text-slate-400 uppercase font-bold tracking-wider">Área</p>
                            <p className="text-base font-black text-slate-800">{property.area} m²</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 rounded-xl bg-white shadow-sm flex items-center justify-center text-primary border border-slate-100">
                            <Bath size={20} />
                          </div>
                          <div>
                            <p className="text-[10px] text-slate-400 uppercase font-bold tracking-wider">Banheiros</p>
                            <p className="text-base font-black text-slate-800">{property.bathrooms}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-4">
                          <div className="w-10 h-10 rounded-xl bg-white shadow-sm flex items-center justify-center text-primary border border-slate-100">
                            <Car size={20} />
                          </div>
                          <div>
                            <p className="text-[10px] text-slate-400 uppercase font-bold tracking-wider">Vagas</p>
                            <p className="text-base font-black text-slate-800">{property.garage_spots || 0}</p>
                          </div>
                        </div>
                      </div>

                      <div className="mt-auto p-6 bg-white rounded-2xl shadow-sm border border-slate-100 flex items-center justify-between">
                        <div>
                          <p className="text-[10px] text-slate-400 uppercase font-bold mb-1 tracking-widest">Valor do Investimento</p>
                          <p className="text-3xl font-black text-primary">
                            {Number(property.price).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
                          </p>
                        </div>
                        <div className="text-right">
                           <p className="text-[10px] text-slate-400 uppercase font-bold mb-1 tracking-widest">Cód. Imóvel</p>
                           <p className="text-sm font-black text-slate-800">{property.short_code || '—'}</p>
                        </div>
                      </div>
                    </div>

                    {/* Footer / Contact */}
                    <div className="bg-slate-900 text-white p-8 flex items-center justify-between">
                      <div className="flex items-center gap-4">
                        <div className="w-12 h-12 bg-white/10 rounded-xl flex items-center justify-center">
                           <MessageSquare className="text-primary" />
                        </div>
                        <div>
                          <p className="text-xs text-slate-400 font-medium">Agende sua visita agora</p>
                          <p className="text-lg font-black tracking-tight">(85) 98432-6253</p>
                        </div>
                      </div>
                      <div className="w-14 h-14 bg-white rounded-xl flex flex-col items-center justify-center text-slate-900 font-black text-[8px] p-2 text-center shadow-lg uppercase leading-none border-b-4 border-slate-200">
                        <span className="mb-1 text-[10px]">VER</span>
                        FOTOS
                      </div>
                    </div>
                  </div>
                </motion.div>
              )}

              {activeTab !== "flyer" && (
                <motion.div 
                  key="ai-content"
                  initial={{ opacity: 0, scale: 0.98 }}
                  animate={{ opacity: 1, scale: 1 }}
                  className="max-w-2xl mx-auto space-y-6"
                >
                  {isGenerating ? (
                    <div className="flex flex-col items-center justify-center py-20 gap-4">
                      <div className="relative">
                        <div className="w-16 h-16 rounded-full border-4 border-primary/20 border-t-primary animate-spin" />
                        <Sparkles className="absolute inset-0 m-auto text-primary animate-pulse" size={24} />
                      </div>
                      <div className="text-center">
                        <h3 className="font-bold text-lg">IA está pensando...</h3>
                        <p className="text-sm text-muted-foreground">Criando copy persuasiva para seu imóvel.</p>
                      </div>
                    </div>
                  ) : Object.keys(aiContent).length > 0 ? (
                    <div className="space-y-6">
                      <Card className="p-6 rounded-3xl border-border bg-card/50 backdrop-blur-sm relative group">
                        <div className="flex items-center justify-between mb-4">
                          <h3 className="font-bold text-lg flex items-center gap-2">
                            {activeTab === 'instagram' ? <Instagram className="text-pink-500" /> : 
                             activeTab === 'whatsapp' ? <MessageSquare className="text-green-500" /> : 
                             <Send className="text-blue-500" />}
                            {activeTab === 'instagram' ? 'Legenda Instagram' : 
                             activeTab === 'whatsapp' ? 'Mensagem WhatsApp' : 
                             'Pitch de Vendas'}
                          </h3>
                          <Button 
                            variant="ghost" 
                            size="sm" 
                            className="rounded-xl gap-2 hover:bg-primary/10 hover:text-primary transition-all"
                            onClick={() => {
                              const text = activeTab === 'instagram' ? aiContent.instagramPost : 
                                         activeTab === 'whatsapp' ? aiContent.whatsappMessage : 
                                         aiContent.salesPitch;
                              copyToClipboard(text || "", activeTab);
                            }}
                          >
                            {copiedField === activeTab ? <Check size={16} /> : <Copy size={16} />}
                            {copiedField === activeTab ? 'Copiado' : 'Copiar'}
                          </Button>
                        </div>
                        <div className="bg-muted/30 p-5 rounded-2xl text-sm leading-relaxed whitespace-pre-wrap font-medium text-foreground/80 border border-border/50">
                          {activeTab === 'instagram' ? aiContent.instagramPost : 
                           activeTab === 'whatsapp' ? aiContent.whatsappMessage : 
                           aiContent.salesPitch}
                        </div>
                        {activeTab === 'instagram' && aiContent.hashtags && (
                          <div className="mt-4">
                            <p className="text-[10px] uppercase font-bold text-muted-foreground mb-2">Hashtags Recomendadas</p>
                            <div className="text-xs text-primary font-medium flex flex-wrap gap-2">
                              {aiContent.hashtags.split(' ').map((tag, i) => (
                                <span key={i} className="bg-primary/5 px-2 py-1 rounded-md border border-primary/10">{tag}</span>
                              ))}
                            </div>
                          </div>
                        )}
                      </Card>

                      <div className="grid grid-cols-2 gap-4">
                         <Card className="p-4 rounded-2xl border-dashed border-2 border-border flex flex-col items-center justify-center text-center group hover:border-primary/50 transition-all cursor-pointer">
                            <div className="w-10 h-10 rounded-full bg-secondary flex items-center justify-center mb-2 group-hover:bg-primary/10 transition-colors">
                              <Share2 size={18} className="group-hover:text-primary" />
                            </div>
                            <p className="text-xs font-bold">Enviar Direto</p>
                         </Card>
                         <Card className="p-4 rounded-2xl border-dashed border-2 border-border flex flex-col items-center justify-center text-center group hover:border-primary/50 transition-all cursor-pointer">
                            <div className="w-10 h-10 rounded-full bg-secondary flex items-center justify-center mb-2 group-hover:bg-primary/10 transition-colors">
                              <Sparkles size={18} className="group-hover:text-primary" />
                            </div>
                            <p className="text-xs font-bold">Variar Tom</p>
                         </Card>
                      </div>
                    </div>
                  ) : (
                    <div className="flex flex-col items-center justify-center py-20 text-center gap-6">
                      <div className="w-20 h-20 rounded-3xl bg-primary/10 flex items-center justify-center text-primary">
                        <Sparkles size={40} />
                      </div>
                      <div>
                        <h3 className="font-bold text-xl mb-2">IA pronta para trabalhar</h3>
                        <p className="text-sm text-muted-foreground max-w-sm">
                          Clique no botão abaixo para gerar conteúdo persuasivo usando os dados deste imóvel.
                        </p>
                      </div>
                      <Button onClick={generateAIContent} size="lg" className="rounded-2xl gap-2 font-bold px-8 h-14">
                        <Sparkles size={20} /> Começar Geração
                      </Button>
                    </div>
                  )}
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </motion.div>
    </div>
  );
};

export default MarketingKit;