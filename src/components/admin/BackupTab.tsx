import { useState } from "react";
import { adminSelect, adminInsert, adminDelete } from "@/lib/adminCrud";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "sonner";
import { Download, Upload, Shield, AlertTriangle, CheckCircle2, Loader2, Server } from "lucide-react";
import { Alert, AlertDescription } from "@/components/ui/alert";

/**
 * Ordem topológica respeitando FKs:
 * - Tabelas-pai primeiro (insert) / tabelas-filho primeiro (delete)
 * 
 * Dependências:
 *   property_media -> properties
 *   leads -> properties
 *   rental_contracts -> properties, tenants
 *   sales -> properties, leads
 *   financial_transactions -> properties, rental_contracts, tenants
 *   property_inspections -> properties, tenants, rental_contracts
 *   inspection_media -> property_inspections
 *   contract_documents -> rental_contracts
 *   tenant_documents -> tenants
 *   sales_documents -> sales
 *   scheduled_visits -> properties
 */

// INSERT order (parents first)
const BACKUP_TABLES_INSERT_ORDER = [
  "property_code_sequences",
  "properties",
  "property_media",
  "contact_submissions",
  "tenants",
  "tenant_documents",
  "leads",
  "rental_contracts",
  "contract_documents",
  "sales",
  "sales_documents",
  "financial_transactions",
  "property_inspections",
  "inspection_media",
  "scheduled_visits",
  "user_roles",
] as const;

// DELETE order (children first — reverse of insert)
const BACKUP_TABLES_DELETE_ORDER = [...BACKUP_TABLES_INSERT_ORDER].reverse();

// Tables where PK is NOT "id"
const PK_MAP: Record<string, string> = {
  property_code_sequences: "prefix",
};

interface BackupData {
  version: string;
  created_at: string;
  tables: Record<string, any[]>;
  metadata?: {
    total_records: number;
    table_counts: Record<string, number>;
  };
}

const BackupTab = () => {
  const [exporting, setExporting] = useState(false);
  const [importing, setImporting] = useState(false);
  const [importProgress, setImportProgress] = useState("");
  const [lastBackupInfo, setLastBackupInfo] = useState<string | null>(null);
  const [importErrors, setImportErrors] = useState<string[]>([]);

  const handleExport = async () => {
    setExporting(true);
    try {
      const backup: BackupData = {
        version: "2.0",
        created_at: new Date().toISOString(),
        tables: {},
      };

      const tableCounts: Record<string, number> = {};

      for (const table of BACKUP_TABLES_INSERT_ORDER) {
        setImportProgress(`Exportando ${table}...`);
        const { data, error } = await adminSelect(table);
        if (error) {
          console.error(`Erro ao exportar ${table}:`, error.message);
          toast.error(`Erro ao exportar ${table}: ${error.message}`);
          backup.tables[table] = [];
          tableCounts[table] = 0;
        } else {
          backup.tables[table] = data || [];
          tableCounts[table] = (data || []).length;
        }
      }

      const totalRecords = Object.values(tableCounts).reduce((s, n) => s + n, 0);
      backup.metadata = { total_records: totalRecords, table_counts: tableCounts };

      // Validate backup integrity before download
      const missingTables = BACKUP_TABLES_INSERT_ORDER.filter(t => !(t in backup.tables));
      if (missingTables.length > 0) {
        toast.error(`Backup incompleto — tabelas ausentes: ${missingTables.join(", ")}`);
        setExporting(false);
        setImportProgress("");
        return;
      }

      const blob = new Blob([JSON.stringify(backup, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      const date = new Date().toISOString().slice(0, 10);
      a.href = url;
      a.download = `simply-backup-${date}.json`;
      a.click();
      URL.revokeObjectURL(url);

      setLastBackupInfo(`${totalRecords} registros em ${Object.keys(backup.tables).length} tabelas`);
      setImportProgress("");
      toast.success("Backup exportado com sucesso!");
    } catch (err) {
      console.error("Erro no backup:", err);
      toast.error("Erro ao gerar backup.");
      setImportProgress("");
    } finally {
      setExporting(false);
    }
  };

  const handleImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const confirmed = window.confirm(
      "⚠️ ATENÇÃO: A restauração substituirá TODOS os dados atuais pelas informações do backup.\n\n" +
      "Recomendação: Faça um backup ANTES de restaurar.\n\n" +
      "Tem certeza que deseja continuar?"
    );
    if (!confirmed) {
      e.target.value = "";
      return;
    }

    setImporting(true);
    setImportErrors([]);
    try {
      const text = await file.text();
      const backup: BackupData = JSON.parse(text);

      if (!backup.tables || typeof backup.tables !== "object") {
        throw new Error("Arquivo de backup inválido — campo 'tables' ausente.");
      }

      // Validate backup has expected tables
      const backupTables = Object.keys(backup.tables);
      if (backupTables.length === 0) {
        throw new Error("Backup vazio — nenhuma tabela encontrada.");
      }

      const errors: string[] = [];

      // ── PHASE 1: Delete all existing data (children first) ──
      for (const table of BACKUP_TABLES_DELETE_ORDER) {
        setImportProgress(`Limpando ${table}...`);
        const pk = PK_MAP[table] || "id";
        const { data: rows, error: selectErr } = await adminSelect(table, { select: pk });

        if (selectErr) {
          errors.push(`[select] ${table}: ${selectErr.message}`);
          continue;
        }

        if (rows && rows.length > 0) {
          for (const row of rows) {
            const matchVal = (row as any)[pk];
            if (matchVal === undefined || matchVal === null) continue;
            const { error: delErr } = await adminDelete(table, { [pk]: matchVal });
            if (delErr) {
              errors.push(`[delete] ${table}.${pk}=${matchVal}: ${delErr.message}`);
            }
          }
        }
      }

      // ── PHASE 2: Insert backup data (parents first) ──
      for (const table of BACKUP_TABLES_INSERT_ORDER) {
        const rows = backup.tables[table];
        if (!rows || rows.length === 0) continue;

        setImportProgress(`Restaurando ${table} (${rows.length} registros)...`);

        // Insert in batches of 50 (smaller batches = more reliable on VPS)
        for (let i = 0; i < rows.length; i += 50) {
          const batch = rows.slice(i, i + 50);
          const { error } = await adminInsert(table, batch);
          if (error) {
            errors.push(`[insert] ${table} (batch ${Math.floor(i / 50) + 1}): ${error.message}`);
            // Try one-by-one for failed batch
            for (const row of batch) {
              const { error: singleErr } = await adminInsert(table, row);
              if (singleErr) {
                const pk = PK_MAP[table] || "id";
                errors.push(`[insert-single] ${table}.${pk}=${row[pk]}: ${singleErr.message}`);
              }
            }
          }
        }
      }

      setImportErrors(errors);

      if (errors.length === 0) {
        toast.success("Restauração concluída com sucesso! Todos os dados foram restaurados.");
      } else {
        toast.warning(`Restauração concluída com ${errors.length} aviso(s). Verifique os detalhes abaixo.`);
      }

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
              Exportar Backup (JSON)
            </CardTitle>
            <CardDescription>
              Gera um arquivo JSON com todos os dados do painel admin. Ideal para migração ou backup rápido via navegador.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Button onClick={handleExport} disabled={exporting || importing} className="w-full">
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
            {(exporting || importing) && importProgress && (
              <p className="text-sm text-muted-foreground animate-pulse">{importProgress}</p>
            )}
          </CardContent>
        </Card>

        {/* Import Card */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Upload size={20} className="text-orange-500" />
              Restaurar Backup (JSON)
            </CardTitle>
            <CardDescription>
              Restaura os dados a partir de um arquivo JSON. Remove os dados atuais e insere os do backup.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <label className="block">
              <input
                type="file"
                accept=".json"
                onChange={handleImport}
                disabled={importing || exporting}
                className="hidden"
                id="backup-file"
              />
              <Button
                variant="outline"
                className="w-full border-orange-300 text-orange-600 hover:bg-orange-50"
                disabled={importing || exporting}
                onClick={() => document.getElementById("backup-file")?.click()}
              >
                {importing ? (
                  <><Loader2 size={16} className="animate-spin mr-2" /> Restaurando...</>
                ) : (
                  <><Upload size={16} className="mr-2" /> Selecionar Arquivo</>
                )}
              </Button>
            </label>
            {importing && importProgress && (
              <p className="text-sm text-muted-foreground animate-pulse">{importProgress}</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Import Errors */}
      {importErrors.length > 0 && (
        <Alert variant="destructive">
          <AlertTriangle size={16} />
          <AlertDescription>
            <strong>{importErrors.length} erro(s) durante a restauração:</strong>
            <ul className="mt-2 space-y-1 text-xs max-h-40 overflow-y-auto">
              {importErrors.map((err, i) => (
                <li key={i} className="font-mono">{err}</li>
              ))}
            </ul>
          </AlertDescription>
        </Alert>
      )}

      {/* VPS Backup Info */}
      <Alert>
        <Server size={16} />
        <AlertDescription>
          <strong>Backup completo via VPS (recomendado):</strong> Para backup integral incluindo arquivos de storage, use os scripts SSH:
          <pre className="mt-2 text-xs bg-secondary/50 p-3 rounded-lg overflow-x-auto font-mono">
{`# Backup completo (DB + Storage)
cd /opt/simply-imoveis/docker && bash backup.sh

# Restaurar backup
bash restore.sh /opt/simply-imoveis/backups/simply-backup-YYYY-MM-DD_HHMM.sql.gz

# Agendar backup diário (cron)
echo "0 2 * * * /opt/simply-imoveis/docker/backup.sh" | crontab -`}
          </pre>
        </AlertDescription>
      </Alert>

      {/* Info Alerts */}
      <Alert>
        <Shield size={16} />
        <AlertDescription>
          <strong>Tabelas incluídas:</strong> Imóveis, Mídias, Contatos, Leads, Vendas, Documentos de venda, Inquilinos, Documentos de inquilinos, Contratos, Documentos de contratos, Transações financeiras, Vistorias, Mídias de vistorias, Visitas agendadas, Sequências de código e Roles de usuários.
        </AlertDescription>
      </Alert>

      <Alert variant="destructive">
        <AlertTriangle size={16} />
        <AlertDescription>
          <strong>Atenção:</strong> A restauração JSON <u>não inclui arquivos de storage</u> (fotos, PDFs). Para backup completo use o script SSH <code className="font-mono text-xs">backup.sh</code> na VPS.
        </AlertDescription>
      </Alert>
    </div>
  );
};

export default BackupTab;
