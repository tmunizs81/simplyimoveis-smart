import { useState } from "react";
import { X, Download, Share2, MapPin, BedDouble, Bath, Maximize2, Car, ImageIcon } from "lucide-react";
import { getMediaUrl } from "@/lib/mediaUrl";
import { motion, AnimatePresence } from "framer-motion";

interface MarketingKitProps {
  property: any;
  onClose: () => void;
}

const MarketingKit = ({ property, onClose }: MarketingKitProps) => {
  const [selectedTemplate, setSelectedTemplate] = useState("classic");

  const handleDownload = () => {
    window.print();
  };

  return (
    <div className="fixed inset-0 z-[100] bg-background/80 backdrop-blur-sm flex items-center justify-center p-4 print:p-0 print:bg-white">
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="bg-card border border-border w-full max-w-4xl max-h-[90vh] overflow-hidden rounded-2xl shadow-2xl flex flex-col print:max-h-none print:shadow-none print:border-none print:rounded-none"
      >
        {/* Header */}
        <div className="px-6 py-4 border-b border-border flex items-center justify-between print:hidden">
          <div>
            <h2 className="font-display text-lg font-bold text-foreground">Marketing Kit</h2>
            <p className="text-xs text-muted-foreground">Gerador de material para WhatsApp e Redes Sociais</p>
          </div>
          <div className="flex items-center gap-2">
            <button 
              onClick={handleDownload}
              className="flex items-center gap-2 bg-primary text-primary-foreground px-4 py-2 rounded-xl text-sm font-bold hover:opacity-90"
            >
              <Download size={16} /> Imprimir / PDF
            </button>
            <button onClick={onClose} className="p-2 hover:bg-secondary rounded-lg transition-colors">
              <X size={20} />
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-8 bg-secondary/20 print:p-0 print:bg-white">
          <div id="marketing-flyer" className="bg-white text-slate-900 w-full aspect-[4/5] max-w-[500px] mx-auto shadow-xl flex flex-col relative print:shadow-none">
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
              <div className="absolute top-4 left-4 bg-primary text-white px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider">
                {property.status === 'venda' ? 'À Venda' : 'Aluguel'}
              </div>
            </div>

            {/* Content Body */}
            <div className="flex-1 p-8 flex flex-col">
              <h1 className="text-2xl font-bold text-slate-900 mb-2 leading-tight">
                {property.title}
              </h1>
              <p className="text-slate-500 text-sm flex items-center gap-1 mb-6">
                <MapPin size={14} /> {property.neighborhood}, {property.city}
              </p>

              <div className="grid grid-cols-2 gap-y-4 gap-x-8 mb-8">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-slate-100 flex items-center justify-center text-primary">
                    <BedDouble size={16} />
                  </div>
                  <div>
                    <p className="text-[10px] text-slate-400 uppercase font-bold">Quartos</p>
                    <p className="text-sm font-bold">{property.bedrooms}</p>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-slate-100 flex items-center justify-center text-primary">
                    <Maximize2 size={16} />
                  </div>
                  <div>
                    <p className="text-[10px] text-slate-400 uppercase font-bold">Área</p>
                    <p className="text-sm font-bold">{property.area} m²</p>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-slate-100 flex items-center justify-center text-primary">
                    <Bath size={16} />
                  </div>
                  <div>
                    <p className="text-[10px] text-slate-400 uppercase font-bold">Banheiros</p>
                    <p className="text-sm font-bold">{property.bathrooms}</p>
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-slate-100 flex items-center justify-center text-primary">
                    <Car size={16} />
                  </div>
                  <div>
                    <p className="text-[10px] text-slate-400 uppercase font-bold">Vagas</p>
                    <p className="text-sm font-bold">{property.garage_spots || 0}</p>
                  </div>
                </div>
              </div>

              <div className="mt-auto pt-6 border-t border-slate-100 flex items-center justify-between">
                <div>
                  <p className="text-[10px] text-slate-400 uppercase font-bold mb-1">Valor</p>
                  <p className="text-2xl font-black text-primary">
                    {Number(property.price).toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
                  </p>
                </div>
                <div className="text-right">
                   <p className="text-[10px] text-slate-400 uppercase font-bold mb-1">Cód.</p>
                   <p className="text-sm font-bold">{property.short_code || '—'}</p>
                </div>
              </div>
            </div>

            {/* Footer / Contact */}
            <div className="bg-slate-900 text-white p-6 flex items-center justify-between">
              <div>
                <p className="text-xs text-slate-400">Entre em contato para agendar visita</p>
                <p className="font-bold">(85) 98432-6253</p>
              </div>
              <div className="w-12 h-12 bg-white rounded-lg flex items-center justify-center text-slate-900 font-bold text-xs p-1 text-center">
                SCAN QR
              </div>
            </div>
          </div>
        </div>
      </motion.div>
    </div>
  );
};

export default MarketingKit;
