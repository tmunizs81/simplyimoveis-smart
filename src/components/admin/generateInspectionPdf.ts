import jsPDF from "jspdf";
import { supabase } from "@/integrations/supabase/client";

type InspectionData = {
  id: string;
  property_title: string;
  property_address: string;
  tenant_name: string;
  inspection_type: string;
  inspection_date: string;
  inspector_name: string | null;
  status: string;
  general_notes: string | null;
  rooms_condition: string | null;
  electrical_condition: string | null;
  plumbing_condition: string | null;
  painting_condition: string | null;
  floor_condition: string | null;
  keys_delivered: number | null;
  meter_reading_water: string | null;
  meter_reading_electricity: string | null;
  meter_reading_gas: string | null;
};

type MediaItem = {
  file_path: string;
  file_name: string;
  file_type: string;
  media_category: string;
};

const CATEGORY_LABELS: Record<string, string> = {
  geral: "Geral", sala: "Sala", quarto: "Quarto", cozinha: "Cozinha",
  banheiro: "Banheiro", area_externa: "Área Externa", garagem: "Garagem",
  fachada: "Fachada", termo_vistoria: "Termo de Vistoria", outro: "Outro",
};

const TYPE_LABELS: Record<string, string> = {
  entrada: "Entrada", saida: "Saída", periodica: "Periódica",
};

const STATUS_LABELS: Record<string, string> = {
  pendente: "Pendente", em_andamento: "Em Andamento", concluida: "Concluída",
};

async function loadImageAsBase64(url: string): Promise<string | null> {
  try {
    const res = await fetch(url);
    const blob = await res.blob();
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

export async function generateInspectionPdf(
  inspection: InspectionData,
  mediaItems: MediaItem[]
) {
  const doc = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4" });
  const pageW = doc.internal.pageSize.getWidth();
  const pageH = doc.internal.pageSize.getHeight();
  const margin = 15;
  const contentW = pageW - margin * 2;
  let y = margin;

  const addPage = () => {
    doc.addPage();
    y = margin;
  };

  const checkSpace = (needed: number) => {
    if (y + needed > pageH - margin) addPage();
  };

  // --- HEADER ---
  doc.setFillColor(30, 58, 95);
  doc.rect(0, 0, pageW, 35, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFontSize(18);
  doc.setFont("helvetica", "bold");
  doc.text("TERMO DE VISTORIA", pageW / 2, 16, { align: "center" });
  doc.setFontSize(10);
  doc.setFont("helvetica", "normal");
  doc.text(
    `${TYPE_LABELS[inspection.inspection_type] || inspection.inspection_type} — ${new Date(inspection.inspection_date).toLocaleDateString("pt-BR")}`,
    pageW / 2, 25, { align: "center" }
  );
  doc.text(`Status: ${STATUS_LABELS[inspection.status] || inspection.status}`, pageW / 2, 31, { align: "center" });

  y = 42;
  doc.setTextColor(30, 30, 30);

  // --- PROPERTY & TENANT INFO ---
  const drawSection = (title: string) => {
    checkSpace(12);
    doc.setFillColor(240, 243, 247);
    doc.rect(margin, y, contentW, 8, "F");
    doc.setFont("helvetica", "bold");
    doc.setFontSize(11);
    doc.setTextColor(30, 58, 95);
    doc.text(title, margin + 3, y + 5.5);
    y += 11;
    doc.setTextColor(30, 30, 30);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(9);
  };

  const drawRow = (label: string, value: string) => {
    checkSpace(7);
    doc.setFont("helvetica", "bold");
    doc.text(`${label}:`, margin + 3, y);
    doc.setFont("helvetica", "normal");
    doc.text(value || "—", margin + 45, y);
    y += 5.5;
  };

  drawSection("Dados do Imóvel");
  drawRow("Imóvel", inspection.property_title);
  drawRow("Endereço", inspection.property_address);
  drawRow("Inquilino", inspection.tenant_name);
  drawRow("Vistoriador", inspection.inspector_name || "Não informado");
  drawRow("Data", new Date(inspection.inspection_date).toLocaleDateString("pt-BR"));
  y += 3;

  // --- CONDITIONS ---
  drawSection("Condições do Imóvel");
  const conditions = [
    ["Cômodos", inspection.rooms_condition],
    ["Elétrica", inspection.electrical_condition],
    ["Hidráulica", inspection.plumbing_condition],
    ["Pintura", inspection.painting_condition],
    ["Pisos", inspection.floor_condition],
  ];

  // Draw conditions as a table
  const colW = contentW / 5;
  checkSpace(16);
  doc.setFillColor(30, 58, 95);
  doc.rect(margin, y, contentW, 7, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(8);
  conditions.forEach(([label], idx) => {
    doc.text(label as string, margin + colW * idx + colW / 2, y + 5, { align: "center" });
  });
  y += 7;
  doc.setFillColor(250, 250, 250);
  doc.rect(margin, y, contentW, 7, "F");
  doc.setTextColor(30, 30, 30);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(9);
  conditions.forEach(([, value], idx) => {
    doc.text((value as string) || "—", margin + colW * idx + colW / 2, y + 5, { align: "center" });
  });
  y += 10;

  // --- METER READINGS ---
  drawSection("Leituras de Medidores");
  const meters = [
    ["Água", inspection.meter_reading_water],
    ["Energia", inspection.meter_reading_electricity],
    ["Gás", inspection.meter_reading_gas],
  ];
  const mColW = contentW / 3;
  checkSpace(16);
  doc.setFillColor(30, 58, 95);
  doc.rect(margin, y, contentW, 7, "F");
  doc.setTextColor(255, 255, 255);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(8);
  meters.forEach(([label], idx) => {
    doc.text(label as string, margin + mColW * idx + mColW / 2, y + 5, { align: "center" });
  });
  y += 7;
  doc.setFillColor(250, 250, 250);
  doc.rect(margin, y, contentW, 7, "F");
  doc.setTextColor(30, 30, 30);
  doc.setFont("helvetica", "normal");
  doc.setFontSize(9);
  meters.forEach(([, value], idx) => {
    doc.text((value as string) || "—", margin + mColW * idx + mColW / 2, y + 5, { align: "center" });
  });
  y += 10;

  // Keys
  drawRow("Chaves Entregues", String(inspection.keys_delivered ?? 0));
  y += 3;

  // --- NOTES ---
  if (inspection.general_notes) {
    drawSection("Observações Gerais");
    checkSpace(20);
    const lines = doc.splitTextToSize(inspection.general_notes, contentW - 6);
    lines.forEach((line: string) => {
      checkSpace(5);
      doc.text(line, margin + 3, y);
      y += 4.5;
    });
    y += 3;
  }

  // --- PHOTOS ---
  const imageMedia = mediaItems.filter(m => m.file_type.startsWith("image"));
  if (imageMedia.length > 0) {
    addPage();
    drawSection("Registro Fotográfico");
    y += 2;

    // Group by category
    const grouped: Record<string, MediaItem[]> = {};
    imageMedia.forEach(m => {
      const cat = m.media_category || "geral";
      if (!grouped[cat]) grouped[cat] = [];
      grouped[cat].push(m);
    });

    for (const [category, items] of Object.entries(grouped)) {
      checkSpace(15);
      doc.setFont("helvetica", "bold");
      doc.setFontSize(10);
      doc.setTextColor(30, 58, 95);
      doc.text(CATEGORY_LABELS[category] || category, margin + 3, y);
      y += 6;
      doc.setTextColor(30, 30, 30);

      const imgW = (contentW - 6) / 2;
      const imgH = 55;

      for (let i = 0; i < items.length; i += 2) {
        checkSpace(imgH + 12);

        for (let j = 0; j < 2 && i + j < items.length; j++) {
          const item = items[i + j];
          const xPos = margin + j * (imgW + 6);

          // Get signed URL and load image
          const { data } = await supabase.storage
            .from("inspection-media")
            .createSignedUrl(item.file_path, 300);

          if (data?.signedUrl) {
            const base64 = await loadImageAsBase64(data.signedUrl);
            if (base64) {
              try {
                doc.addImage(base64, "JPEG", xPos, y, imgW, imgH);
              } catch {
                doc.setFillColor(240, 240, 240);
                doc.rect(xPos, y, imgW, imgH, "F");
                doc.setFontSize(8);
                doc.text("Erro ao carregar imagem", xPos + imgW / 2, y + imgH / 2, { align: "center" });
              }
            }
          }

          // Caption
          doc.setFontSize(7);
          doc.setFont("helvetica", "normal");
          doc.text(item.file_name.substring(0, 40), xPos, y + imgH + 4);
        }

        y += imgH + 10;
      }
      y += 3;
    }
  }

  // --- FOOTER on each page ---
  const totalPages = doc.getNumberOfPages();
  for (let p = 1; p <= totalPages; p++) {
    doc.setPage(p);
    doc.setFontSize(7);
    doc.setTextColor(150, 150, 150);
    doc.setFont("helvetica", "normal");
    doc.text(
      `Gerado em ${new Date().toLocaleDateString("pt-BR")} às ${new Date().toLocaleTimeString("pt-BR")} — Página ${p}/${totalPages}`,
      pageW / 2, pageH - 8, { align: "center" }
    );
  }

  // --- SIGNATURE AREA on last page ---
  doc.setPage(totalPages);
  const sigY = pageH - 45;
  doc.setDrawColor(180, 180, 180);
  doc.setFontSize(8);
  doc.setTextColor(80, 80, 80);
  doc.setFont("helvetica", "normal");

  const sigW = (contentW - 10) / 2;
  doc.line(margin, sigY, margin + sigW, sigY);
  doc.text("Vistoriador", margin + sigW / 2, sigY + 5, { align: "center" });

  doc.line(margin + sigW + 10, sigY, margin + sigW * 2 + 10, sigY);
  doc.text("Inquilino / Responsável", margin + sigW + 10 + sigW / 2, sigY + 5, { align: "center" });

  doc.text(`Data: ____/____/________`, pageW / 2, sigY + 15, { align: "center" });

  // Save
  const fileName = `vistoria_${inspection.inspection_type}_${inspection.inspection_date}.pdf`;
  doc.save(fileName);
}
