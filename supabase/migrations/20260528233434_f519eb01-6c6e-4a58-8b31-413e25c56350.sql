-- Lead Activities for Timeline
CREATE TABLE IF NOT EXISTS public.lead_activities (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    lead_id UUID NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
    type TEXT NOT NULL, -- 'ligacao', 'visita', 'proposta', 'nota', 'status_change'
    description TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    user_id UUID REFERENCES auth.users(id)
);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_activities TO authenticated;
GRANT ALL ON public.lead_activities TO service_role;

-- Enable RLS
ALTER TABLE public.lead_activities ENABLE ROW LEVEL SECURITY;

-- Simple policies (assuming admin access via admin-crud/service_role mostly, but good to have)
CREATE POLICY "Admin can do everything on lead_activities" ON public.lead_activities
    FOR ALL USING (true);

-- Add probability to sales for forecasting if not exists
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name='sales' AND column_name='probability') THEN
        ALTER TABLE public.sales ADD COLUMN probability NUMERIC DEFAULT 50;
    END IF;
END $$;
