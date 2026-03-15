
-- Fix 1: Create missing triggers for short_code generation
CREATE OR REPLACE TRIGGER set_short_code
  BEFORE INSERT ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.generate_property_short_code();

CREATE OR REPLACE TRIGGER update_short_code
  BEFORE UPDATE ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.update_property_short_code_on_status_change();

-- Fix 2: Add missing RLS policies on user_roles (Cloud only has SELECT)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='user_roles' AND policyname='Admins can insert roles') THEN
    CREATE POLICY "Admins can insert roles" ON public.user_roles FOR INSERT TO authenticated
      WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='user_roles' AND policyname='Admins can update roles') THEN
    CREATE POLICY "Admins can update roles" ON public.user_roles FOR UPDATE TO authenticated
      USING (public.has_role(auth.uid(), 'admin'::app_role))
      WITH CHECK (public.has_role(auth.uid(), 'admin'::app_role));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='user_roles' AND policyname='Admins can delete roles') THEN
    CREATE POLICY "Admins can delete roles" ON public.user_roles FOR DELETE TO authenticated
      USING (public.has_role(auth.uid(), 'admin'::app_role));
  END IF;
END $$;

-- Fix 3: Ensure user_roles SELECT policy allows authenticated users to check own role (needed for has_role to work via RPC)
-- Current policy requires admin to view roles, but has_role uses SECURITY DEFINER so this is OK
-- However, let's also allow any authenticated user to see their own role
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='user_roles' AND policyname='Users can view own role') THEN
    CREATE POLICY "Users can view own role" ON public.user_roles FOR SELECT TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;
