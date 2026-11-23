-- Run ONLY on disposable Supabase/Postgres test database AFTER 001,002,003.
-- Catalog assertions do not replace authenticated integration/concurrency tests.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='famunova_membership_capacity_before_insert' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'Missing membership admission trigger'; END IF;
 IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public'
  AND ((tablename='shopping_items' AND policyname IN ('Members add shopping','Members edit shopping','Members remove shopping'))
    OR (tablename='family_calendar_events' AND policyname IN ('Members add calendar events','Members delete calendar events'))))
 THEN RAISE EXCEPTION 'Legacy permissive policies still present'; END IF;
 IF has_function_privilege('authenticated','public.famunova_can_internal(uuid,text,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Internal permission evaluator is exposed'; END IF;
 IF NOT has_function_privilege('authenticated','public.famunova_set_member_permission(uuid,uuid,text,boolean)','EXECUTE')
 THEN RAISE EXCEPTION 'Owner-controlled permission RPC unavailable'; END IF;
 RAISE NOTICE '003 catalog assertions passed';
END $$;
