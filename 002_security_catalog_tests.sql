-- Read-only catalog assertions; run ONLY in isolated test DB after migrations 001 and 002.
-- This does not exercise concurrent joins or real authenticated API access.
DO $$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.famunova_plan_limits
    WHERE (plan='free' AND max_members=3)
       OR (plan='plus' AND max_members=6)
       OR (plan='premium_family' AND max_members=10);
  IF v_count<>3 THEN RAISE EXCEPTION 'Plan limits mismatch'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='famunova_member_permissions' AND c.relrowsecurity)
  THEN RAISE EXCEPTION 'Permissions RLS is disabled'; END IF;
  IF has_table_privilege('authenticated','public.famunova_member_permissions','INSERT')
    OR has_table_privilege('authenticated','public.famunova_member_permissions','UPDATE')
    OR has_table_privilege('authenticated','public.famunova_member_permissions','DELETE')
  THEN RAISE EXCEPTION 'Unexpected direct permission writes'; END IF;
  IF has_function_privilege('authenticated','public.famunova_group_plan_internal(uuid)','EXECUTE')
    OR has_function_privilege('authenticated','public.famunova_assert_member_capacity_internal(uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'Internal function exposed to authenticated'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='famunova_membership_role_valid')
  THEN RAISE EXCEPTION 'Role constraint missing'; END IF;
  RAISE NOTICE 'Famunova 002 catalog checks passed';
END $$;
