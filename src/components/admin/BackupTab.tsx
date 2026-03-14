import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "sonner";
import { Download, Upload, Shield, AlertTriangle, CheckCircle2, Loader2 } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";

const BACKUP_TABLES = [
  "properties",
  "property_media",
  "contact_submissions",
  "leads",
  "sales",
  "sales_documents",
  "tenants",
  "tenant_documents",
  "rental_contracts",
  "contract_documents",
  "financial_transactions",
  "property_inspections",
  "inspection_media",
  "scheduled_visits",
] as const;

interface BackupData {
  version: string;
  created_at: string;
  tables: Record<string, any[]>;
}

const BackupTab = () => {
  const [exporting, setExporting] = useState(false);
  const [importing, setImporting] = useState(false);
  const [importProgress, setImportProgress] = useState("");
  const [lastBackupInfo, setLastBackupInfo] = useState<string | null>(null);

  const handleExport = async () => {
    setExporting(true);
    try {
      const backup: BackupData = {
        version: "1.0",
        created_at: new Date().toISOString(),
        tables: {},
      };

      for (const table of BACKUP_TABLES) {
        const { data, error } = await supabase.from(table).select("*");
        if (error) {
          console.error(`Erro ao exportar ${table}:`, error.message);
          backup.tables[table] = [];
        } else {
          backup.tables[table] = data || [];
        }
      }

      const blob = new Blob([JSON.stringify(backup, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      const date = new Date().toISOString().slice(0, 10);
      a.href = url;
      a.download = `simply-backup-${date}.json`;
      a.click();
      URL.revokeObjectURL(url);

      const totalRecords = Object.values(backup.tables).reduce((sum, arr) => sum + arr.length, 0);
      setLastBackupInfo(`${totalRecords} registros em ${Object.keys(backup.tables).length} tabelas`);
      toast.success("Backup exportado com sucesso!");
    } catch (err) {
      console.error("Erro no backup:", err);
      toast.error("Erro ao gerar backup.");
    } finally {
      setExporting(false);
    }
  };

  const handleImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const confirmed = window.confirm(
      "⚠️ ATENÇÃO: A restauração substituirá TODOS os dados atuais pelas informações do backup.\n\nTem certeza que deseja continuar?"
    );
    if (!confirmed) {
      e.target.value = "";
      return;
    }

    setImporting(true);
    try {
      const text = await file.text();
      const backup: BackupData = JSON.parse(text);

      if (!backup.version || !backup.tables) {
        throw new Error("Arquivo de backup inválido.");
      }

      // Restore order matters due to foreign keys — delete in reverse, insert in order
      const deleteOrder = [...BACKUP_TABLES].reverse();

      for (const table of deleteOrder) {
        setImportProgress(`Limpando ${table}...`);
        const { error } = await supabase.from(table).delete().neq("id", "00000000-0000-0000-0000-000000000000");
        if (error) console.warn(`Aviso ao limpar ${table}:`, error.message);
      }

      for (const table of BACKUP_TABLES) {
        const rows = backup.tables[table];
        if (!rows || rows.length === 0) continue;

        setImportProgress(`Restaurando ${table} (${rows.length} registros)...`);

        // Insert in batches of 100
        for (let i = 0; i < rows.length; i += 100) {
          const batch = rows.slice(i, i + 100);
          const { error } = await supabase.from(table).insert(batch as any);
          if (error) {
            console.error(`Erro ao restaurar ${table}:`, error.message);
            toast.error(`Erro ao restaurar ${table}: ${error.message}`);
          }
        }
      }

      toast.success("Restauração concluída com sucesso!");
      setImportProgress("");
    } catch (err: any) {
      console.error("Erro na restauração:", err);
      toast.error(err.message || "Erro ao restaurar backup.");
      setImportProgress("");
    } finally {
      setImporting(false);
      e.target.value = "";
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-display font-bold text-foreground">Backup & Restauração</h1>
        <p className="text-muted-foreground mt-1">Exporte e restaure todos os dados do sistema</p>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        {/* Export Card */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Download size={20} className="text-primary" />
              Exportar Backup
            </CardTitle>
            <CardDescription>
              Gera um arquivo JSON com todos os dados: imóveis, contratos, inquilinos, financeiro, leads, contatos e vistorias.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button onClick={handleExport} disabled={exporting} className="w-full">
              {exporting ? (
                <><Loader2 size={16} className="animate-spin mr-2" /> Exportando...</>
              ) : (
                <><Download size={16} className="mr-2" /> Gerar Backup</>
              )}
            </Button>
            {lastBackupInfo && (
              <div className="flex items-center gap-2 text-sm text-green-600">
                <CheckCircle2 size={14} />
                Último backup: {lastBackupInfo}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Import Card */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Upload size={20} className="text-orange-500" />
              Restaurar Backup
            </CardTitle>
            <CardDescription>
              Restaura os dados a partir de um arquivo de backup JSON gerado anteriormente.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <label className="block">
              <input
                type="file"
                accept=".json"
                onChange={handleImport}
                disabled={importing}
                className="hidden"
                id="backup-file"
              />
              <Button
                variant="outline"
                className="w-full border-orange-300 text-orange-600 hover:bg-orange-50"
                disabled={importing}
                onClick={() => document.getElementById("backup-file")?.click()}
              >
                {importing ? (
                  <><Loader2 size={16} className="animate-spin mr-2" /> Restaurando...</>
                ) : (
                  <><Upload size={16} className="mr-2" /> Selecionar Arquivo</>
                )}
              </Button>
            </label>
            {importProgress && (
              <p className="text-sm text-muted-foreground animate-pulse">{importProgress}</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Info Alerts */}
      <Alert>
        <Shield size={16} />
        <AlertDescription>
          <strong>Tabelas incluídas no backup:</strong> Imóveis, Mídias, Contatos, Leads, Vendas, Documentos de venda, Inquilinos, Documentos de inquilinos, Contratos, Documentos de contratos, Transações financeiras, Vistorias, Mídias de vistorias e Visitas agendadas.
        </AlertDescription>
      </Alert>

      <Alert variant="destructive">
        <AlertTriangle size={16} />
        <AlertDescription>
          <strong>Atenção:</strong> A restauração <u>substituirá todos os dados atuais</u>. Faça um backup antes de restaurar para evitar perda de dados.
        </AlertDescription>
      </Alert>
    </div>
  );
};

export default BackupTab;
