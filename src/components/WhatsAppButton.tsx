import { MessageCircle } from "lucide-react";

const WhatsAppButton = () => {
  const phoneNumber = "5585999990000"; // Substitua pelo número real
  const message = encodeURIComponent("Olá! Gostaria de mais informações sobre imóveis.");
  const url = `https://wa.me/${phoneNumber}?text=${message}`;

  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      aria-label="Fale pelo WhatsApp"
      className="fixed bottom-6 right-6 z-50 group"
    >
      {/* Pulse ring */}
      <span className="absolute inset-0 rounded-full bg-green-500 animate-ping opacity-30" />

      {/* Button */}
      <div className="relative w-14 h-14 rounded-full bg-green-500 hover:bg-green-600 shadow-2xl shadow-green-500/40 flex items-center justify-center transition-all duration-300 group-hover:scale-110">
        <MessageCircle size={26} className="text-white fill-white" />
      </div>

      {/* Tooltip */}
      <span className="absolute right-full mr-3 top-1/2 -translate-y-1/2 bg-foreground text-background text-xs font-semibold px-3 py-2 rounded-lg whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none shadow-lg">
        Fale no WhatsApp
      </span>
    </a>
  );
};

export default WhatsAppButton;
