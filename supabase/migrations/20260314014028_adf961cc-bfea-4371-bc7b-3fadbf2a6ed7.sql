
-- 1. Create app_role enum and user_roles table
CREATE TYPE public.app_role AS ENUM ('admin', 'moderator', 'user');

CREATE TABLE public.user_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role app_role NOT NULL,
    UNIQUE (user_id, role)
);

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Only admins can view/manage roles
CREATE POLICY "Admins can view roles"
  ON public.user_roles FOR SELECT
  TO authenticated
  USING (true);

-- 2. Create security definer function to check roles (avoids RLS recursion)
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- 3. Fix contact_submissions: restrict SELECT/UPDATE/DELETE to admin only
DROP POLICY IF EXISTS "Authenticated users can view contacts" ON public.contact_submissions;
DROP POLICY IF EXISTS "Authenticated users can update contacts" ON public.contact_submissions;
DROP POLICY IF EXISTS "Authenticated users can delete contacts" ON public.contact_submissions;

CREATE POLICY "Admins can view contacts"
  ON public.contact_submissions FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update contacts"
  ON public.contact_submissions FOR UPDATE
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can delete contacts"
  ON public.contact_submissions FOR DELETE
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- 4. Fix scheduled_visits: restrict SELECT to admin only, add UPDATE/DELETE
DROP POLICY IF EXISTS "Authenticated users can view visits" ON public.scheduled_visits;

CREATE POLICY "Admins can view visits"
  ON public.scheduled_visits FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update visits"
  ON public.scheduled_visits FOR UPDATE
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can delete visits"
  ON public.scheduled_visits FOR DELETE
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));
