
ALTER TABLE public.contact_submissions 
ADD COLUMN IF NOT EXISTS chat_transcript text,
ADD COLUMN IF NOT EXISTS visit_date text,
ADD COLUMN IF NOT EXISTS source text DEFAULT 'form';
