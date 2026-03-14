export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.4"
  }
  public: {
    Tables: {
      contact_submissions: {
        Row: {
          chat_transcript: string | null
          created_at: string
          email: string
          id: string
          message: string
          name: string
          phone: string | null
          read: boolean
          source: string | null
          subject: string | null
          visit_date: string | null
        }
        Insert: {
          chat_transcript?: string | null
          created_at?: string
          email: string
          id?: string
          message: string
          name: string
          phone?: string | null
          read?: boolean
          source?: string | null
          subject?: string | null
          visit_date?: string | null
        }
        Update: {
          chat_transcript?: string | null
          created_at?: string
          email?: string
          id?: string
          message?: string
          name?: string
          phone?: string | null
          read?: boolean
          source?: string | null
          subject?: string | null
          visit_date?: string | null
        }
        Relationships: []
      }
      contract_documents: {
        Row: {
          contract_id: string | null
          created_at: string
          document_type: Database["public"]["Enums"]["document_type"]
          file_name: string
          file_path: string
          file_type: string
          id: string
          notes: string | null
          user_id: string
        }
        Insert: {
          contract_id?: string | null
          created_at?: string
          document_type?: Database["public"]["Enums"]["document_type"]
          file_name: string
          file_path: string
          file_type: string
          id?: string
          notes?: string | null
          user_id: string
        }
        Update: {
          contract_id?: string | null
          created_at?: string
          document_type?: Database["public"]["Enums"]["document_type"]
          file_name?: string
          file_path?: string
          file_type?: string
          id?: string
          notes?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "contract_documents_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "rental_contracts"
            referencedColumns: ["id"]
          },
        ]
      }
      financial_transactions: {
        Row: {
          amount: number
          category: Database["public"]["Enums"]["transaction_category"]
          contract_id: string | null
          created_at: string
          date: string
          description: string
          due_date: string | null
          id: string
          notes: string | null
          paid_date: string | null
          payment_method: string | null
          property_id: string | null
          receipt_path: string | null
          status: Database["public"]["Enums"]["invoice_status"]
          tenant_id: string | null
          type: Database["public"]["Enums"]["transaction_type"]
          user_id: string
        }
        Insert: {
          amount: number
          category?: Database["public"]["Enums"]["transaction_category"]
          contract_id?: string | null
          created_at?: string
          date?: string
          description: string
          due_date?: string | null
          id?: string
          notes?: string | null
          paid_date?: string | null
          payment_method?: string | null
          property_id?: string | null
          receipt_path?: string | null
          status?: Database["public"]["Enums"]["invoice_status"]
          tenant_id?: string | null
          type: Database["public"]["Enums"]["transaction_type"]
          user_id: string
        }
        Update: {
          amount?: number
          category?: Database["public"]["Enums"]["transaction_category"]
          contract_id?: string | null
          created_at?: string
          date?: string
          description?: string
          due_date?: string | null
          id?: string
          notes?: string | null
          paid_date?: string | null
          payment_method?: string | null
          property_id?: string | null
          receipt_path?: string | null
          status?: Database["public"]["Enums"]["invoice_status"]
          tenant_id?: string | null
          type?: Database["public"]["Enums"]["transaction_type"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "financial_transactions_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "rental_contracts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "financial_transactions_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "financial_transactions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      leads: {
        Row: {
          assigned_to: string | null
          budget_max: number | null
          budget_min: number | null
          created_at: string
          email: string | null
          id: string
          interest_type: string | null
          name: string
          next_follow_up: string | null
          notes: string | null
          phone: string | null
          property_id: string | null
          source: Database["public"]["Enums"]["lead_source"]
          status: Database["public"]["Enums"]["lead_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          assigned_to?: string | null
          budget_max?: number | null
          budget_min?: number | null
          created_at?: string
          email?: string | null
          id?: string
          interest_type?: string | null
          name: string
          next_follow_up?: string | null
          notes?: string | null
          phone?: string | null
          property_id?: string | null
          source?: Database["public"]["Enums"]["lead_source"]
          status?: Database["public"]["Enums"]["lead_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          assigned_to?: string | null
          budget_max?: number | null
          budget_min?: number | null
          created_at?: string
          email?: string | null
          id?: string
          interest_type?: string | null
          name?: string
          next_follow_up?: string | null
          notes?: string | null
          phone?: string | null
          property_id?: string | null
          source?: Database["public"]["Enums"]["lead_source"]
          status?: Database["public"]["Enums"]["lead_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "leads_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      properties: {
        Row: {
          active: boolean
          address: string
          area: number
          bathrooms: number
          bedrooms: number
          city: string | null
          created_at: string
          description: string | null
          featured: boolean
          garage_spots: number
          id: string
          nearby_points: string | null
          neighborhood: string | null
          pool_size: number | null
          price: number
          status: Database["public"]["Enums"]["property_status"]
          suites: number
          title: string
          type: Database["public"]["Enums"]["property_type"]
          updated_at: string
          user_id: string
        }
        Insert: {
          active?: boolean
          address: string
          area?: number
          bathrooms?: number
          bedrooms?: number
          city?: string | null
          created_at?: string
          description?: string | null
          featured?: boolean
          garage_spots?: number
          id?: string
          nearby_points?: string | null
          neighborhood?: string | null
          pool_size?: number | null
          price: number
          status?: Database["public"]["Enums"]["property_status"]
          suites?: number
          title: string
          type?: Database["public"]["Enums"]["property_type"]
          updated_at?: string
          user_id: string
        }
        Update: {
          active?: boolean
          address?: string
          area?: number
          bathrooms?: number
          bedrooms?: number
          city?: string | null
          created_at?: string
          description?: string | null
          featured?: boolean
          garage_spots?: number
          id?: string
          nearby_points?: string | null
          neighborhood?: string | null
          pool_size?: number | null
          price?: number
          status?: Database["public"]["Enums"]["property_status"]
          suites?: number
          title?: string
          type?: Database["public"]["Enums"]["property_type"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      property_media: {
        Row: {
          created_at: string
          file_path: string
          file_type: string
          id: string
          property_id: string
          sort_order: number
        }
        Insert: {
          created_at?: string
          file_path: string
          file_type: string
          id?: string
          property_id: string
          sort_order?: number
        }
        Update: {
          created_at?: string
          file_path?: string
          file_type?: string
          id?: string
          property_id?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "property_media_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      rental_contracts: {
        Row: {
          adjustment_index: string | null
          created_at: string
          deposit_amount: number | null
          end_date: string
          id: string
          late_fee_percentage: number | null
          monthly_rent: number
          notes: string | null
          payment_day: number
          property_id: string | null
          start_date: string
          status: Database["public"]["Enums"]["contract_status"]
          tenant_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          adjustment_index?: string | null
          created_at?: string
          deposit_amount?: number | null
          end_date: string
          id?: string
          late_fee_percentage?: number | null
          monthly_rent: number
          notes?: string | null
          payment_day?: number
          property_id?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["contract_status"]
          tenant_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          adjustment_index?: string | null
          created_at?: string
          deposit_amount?: number | null
          end_date?: string
          id?: string
          late_fee_percentage?: number | null
          monthly_rent?: number
          notes?: string | null
          payment_day?: number
          property_id?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["contract_status"]
          tenant_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rental_contracts_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rental_contracts_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      sales: {
        Row: {
          buyer_cpf: string | null
          buyer_email: string | null
          buyer_name: string | null
          buyer_phone: string | null
          closing_date: string | null
          commission_rate: number | null
          commission_value: number | null
          created_at: string
          id: string
          lead_id: string | null
          notes: string | null
          property_id: string | null
          proposal_date: string | null
          sale_value: number | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          buyer_cpf?: string | null
          buyer_email?: string | null
          buyer_name?: string | null
          buyer_phone?: string | null
          closing_date?: string | null
          commission_rate?: number | null
          commission_value?: number | null
          created_at?: string
          id?: string
          lead_id?: string | null
          notes?: string | null
          property_id?: string | null
          proposal_date?: string | null
          sale_value?: number | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          buyer_cpf?: string | null
          buyer_email?: string | null
          buyer_name?: string | null
          buyer_phone?: string | null
          closing_date?: string | null
          commission_rate?: number | null
          commission_value?: number | null
          created_at?: string
          id?: string
          lead_id?: string | null
          notes?: string | null
          property_id?: string | null
          proposal_date?: string | null
          sale_value?: number | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sales_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sales_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      scheduled_visits: {
        Row: {
          client_email: string | null
          client_name: string
          client_phone: string
          created_at: string
          id: string
          notes: string | null
          preferred_date: string
          preferred_time: string
          property_id: string | null
          status: string
        }
        Insert: {
          client_email?: string | null
          client_name: string
          client_phone: string
          created_at?: string
          id?: string
          notes?: string | null
          preferred_date: string
          preferred_time: string
          property_id?: string | null
          status?: string
        }
        Update: {
          client_email?: string | null
          client_name?: string
          client_phone?: string
          created_at?: string
          id?: string
          notes?: string | null
          preferred_date?: string
          preferred_time?: string
          property_id?: string | null
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "scheduled_visits_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      tenants: {
        Row: {
          address: string | null
          cpf_cnpj: string | null
          created_at: string
          email: string | null
          id: string
          name: string
          notes: string | null
          phone: string | null
          rg: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          address?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          email?: string | null
          id?: string
          name: string
          notes?: string | null
          phone?: string | null
          rg?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          address?: string | null
          cpf_cnpj?: string | null
          created_at?: string
          email?: string | null
          id?: string
          name?: string
          notes?: string | null
          phone?: string | null
          rg?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
    }
    Enums: {
      app_role: "admin" | "moderator" | "user"
      contract_status: "ativo" | "encerrado" | "cancelado" | "pendente"
      document_type:
        | "contrato"
        | "foto"
        | "documento"
        | "laudo"
        | "comprovante"
        | "outro"
      invoice_status: "pendente" | "pago" | "atrasado" | "cancelado"
      lead_source:
        | "site"
        | "whatsapp"
        | "indicacao"
        | "portal"
        | "placa"
        | "telefone"
        | "chat"
        | "outro"
      lead_status:
        | "novo"
        | "contato_feito"
        | "visita_agendada"
        | "proposta"
        | "negociacao"
        | "fechado_ganho"
        | "fechado_perdido"
      property_status: "venda" | "aluguel"
      property_type:
        | "Apartamento"
        | "Casa"
        | "Cobertura"
        | "Terreno"
        | "Sala Comercial"
      transaction_category:
        | "aluguel"
        | "venda"
        | "comissao"
        | "manutencao"
        | "condominio"
        | "iptu"
        | "seguro"
        | "taxa_administracao"
        | "reparo"
        | "outro"
      transaction_type: "receita" | "despesa"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "moderator", "user"],
      contract_status: ["ativo", "encerrado", "cancelado", "pendente"],
      document_type: [
        "contrato",
        "foto",
        "documento",
        "laudo",
        "comprovante",
        "outro",
      ],
      invoice_status: ["pendente", "pago", "atrasado", "cancelado"],
      lead_source: [
        "site",
        "whatsapp",
        "indicacao",
        "portal",
        "placa",
        "telefone",
        "chat",
        "outro",
      ],
      lead_status: [
        "novo",
        "contato_feito",
        "visita_agendada",
        "proposta",
        "negociacao",
        "fechado_ganho",
        "fechado_perdido",
      ],
      property_status: ["venda", "aluguel"],
      property_type: [
        "Apartamento",
        "Casa",
        "Cobertura",
        "Terreno",
        "Sala Comercial",
      ],
      transaction_category: [
        "aluguel",
        "venda",
        "comissao",
        "manutencao",
        "condominio",
        "iptu",
        "seguro",
        "taxa_administracao",
        "reparo",
        "outro",
      ],
      transaction_type: ["receita", "despesa"],
    },
  },
} as const
