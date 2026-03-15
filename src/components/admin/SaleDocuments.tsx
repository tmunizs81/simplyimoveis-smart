import { useState, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { adminInsert, adminDelete } from "@/lib/adminCrud";
import { toast } from "sonner";
import { Upload, Trash2, FileText, Download, X, Eye } from "lucide-react";

const DOC_CATEGORIES: Record<string, string> = {
  documento_imovel: "Documento do Imóvel",
  comprovante_pagamento: "Comprovante de Pagamento",
  certidao: "Certidão",
  planta: "Planta da Casa",
  contrato: "Contrato",
  procuracao: "Procuração",
  laudo: "Laudo/Vistoria",
  outro: "Outro",
};

type SaleDoc = {
  id: string;
  sale_id: string;
  document_type: string;
  file_name: string;
  file_path: string;
  file_type: string;
  notes: string | null;
  created_at: string;
};

const SaleDocuments = ({ saleId, onClose }: { saleId: string; onClose: () => void }) => {
  const [docs, setDocs] = useState<SaleDoc[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [docType, setDocType] = useState("documento_imovel");
  const [files, setFiles] = useState<File[]>([]);

  const fetchDocs = async () => {
    const { data, error } = await supabase
      .from("sales_documents")
      .select("*")
      .eq("sale_id", saleId)
      .order("created_at", { ascending: false });
    if (!error) setDocs((data as SaleDoc[]) || []);
    setLoading(false);
  };

  useEffect(() => { fetchDocs(); }, [saleId]);

  const handleUpload = async () => {
    if (files.length === 0) return;
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    setUploading(true);
    for (const file of files) {
      const ext = file.name.split(".").pop();
      const path = `${user.id}/${saleId}/${crypto.randomUUID()}.${ext}`;
      const { error: uploadErr } = await supabase.storage.from("sales-documents").upload(path, file);
      if (uploadErr) { toast.error(`Erro ao enviar ${file.name}`); continue; }

      await supabase.from("sales_documents").insert({
        sale_id: saleId,
        user_id: user.id,
        document_type: docType,
        file_name: file.name,
        file_path: path,
        file_type: file.type || "application/octet-stream",
      } as any);
    }
    toast.success("Documentos enviados!");
    setFiles([]);
    setUploading(false);
    fetchDocs();
  };

  const handleDelete = async (doc: SaleDoc) => {
    if (!confirm(`Excluir "${doc.file_name}"?`)) return;
    await supabase.storage.from("sales-documents").remove([doc.file_path]);
    await supabase.from("sales_documents").delete().eq("id", doc.id);
    toast.success("Documento excluído");
    fetchDocs();
  };

  const handleView = async (doc: SaleDoc) => {
    const { data } = await supabase.storage.from("sales-documents").createSignedUrl(doc.file_path, 300);
    if (data?.signedUrl) window.open(data.signedUrl, "_blank");
    else toast.error("Erro ao gerar link");
  };

  const inputClass = "w-full px-4 py-3 rounded-xl bg-secondary/30 border border-input text-foreground text-sm focus:ring-2 focus:ring-primary/30 outline-none transition-all";

  return (
    <div className="max-w-2xl">
      <div className="bg-card rounded-2xl border border-border shadow-xl overflow-hidden">
        <div className="gradient-primary px-6 py-5 flex items-center justify-between">
          <div>
            <h2 className="font-display text-lg font-bold text-primary-foreground">Documentos da Venda</h2>
            <p className="text-primary-foreground/60 text-xs">Gerencie documentos, certidões e comprovantes</p>
          </div>
          <button onClick={onClose} className="text-primary-foreground/60 hover:text-primary-foreground"><X size={20} /></button>
        </div>

        <div className="p-6 space-y-5">
          {/* Upload area */}
          <div className="space-y-3 bg-secondary/20 rounded-xl p-4 border border-border">
            <h3 className="text-sm font-bold text-foreground">Enviar Documentos</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Categoria</label>
                <select value={docType} onChange={e => setDocType(e.target.value)} className={inputClass}>
                  {Object.entries(DOC_CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs font-bold text-muted-foreground uppercase tracking-wider mb-1.5 block">Arquivos</label>
                <input
                  type="file"
                  multiple
                  onChange={e => setFiles(Array.from(e.target.files || []))}
                  className={inputClass}
                />
              </div>
            </div>
            {files.length > 0 && (
              <div className="space-y-1">
                {files.map((f, i) => (
                  <div key={i} className="text-xs text-muted-foreground flex items-center gap-2">
                    <FileText size={12} /> {f.name}
                  </div>
                ))}
              </div>
            )}
            <button
              onClick={handleUpload}
              disabled={files.length === 0 || uploading}
              className="gradient-primary text-primary-foreground px-5 py-2.5 rounded-xl font-bold text-sm hover:opacity-90 flex items-center gap-2 disabled:opacity-50"
            >
              <Upload size={14} /> {uploading ? "Enviando..." : "Enviar"}
            </button>
          </div>

          {/* Document list */}
          {loading ? (
            <div className="flex justify-center py-8"><div className="w-6 h-6 border-2 border-primary/30 border-t-primary rounded-full animate-spin" /></div>
          ) : docs.length === 0 ? (
            <p className="text-center text-muted-foreground text-sm py-8">Nenhum documento enviado.</p>
          ) : (
            <div className="space-y-2">
              {docs.map(doc => (
                <div key={doc.id} className="flex items-center gap-3 bg-secondary/10 rounded-xl border border-border p-3 hover:border-primary/20 transition-all">
                  <FileText size={18} className="text-primary shrink-0" />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-foreground truncate">{doc.file_name}</p>
                    <p className="text-xs text-muted-foreground">
                      {DOC_CATEGORIES[doc.document_type] || doc.document_type} • {new Date(doc.created_at).toLocaleDateString("pt-BR")}
                    </p>
                  </div>
                  <div className="flex gap-1.5">
                    <button onClick={() => handleView(doc)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-primary hover:border-primary transition-all" title="Visualizar">
                      <Eye size={14} />
                    </button>
                    <button onClick={() => handleDelete(doc)} className="p-2 rounded-lg border border-border text-muted-foreground hover:text-destructive hover:border-destructive transition-all" title="Excluir">
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default SaleDocuments;
