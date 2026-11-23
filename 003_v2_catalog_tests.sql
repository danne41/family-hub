-- TEST DATABASE ONLY, after 001 -> 002 -> 003 v2. Catalog assertions, not end-to-end tests.
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='famunova_membership_capacity_before_insert' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'Capacity trigger missing'; END IF;
 IF has_table_privilege('authenticated','public.shopping_items','UPDATE')
 THEN RAISE EXCEPTION 'Table-wide shopping UPDATE still granted'; END IF;
 IF NOT has_column_privilege('authenticated','public.shopping_items','done','UPDATE')
 THEN RAISE EXCEPTION 'Shopping done column UPDATE missing'; END IF;
 IF has_column_privilege('authenticated','public.shopping_items','name','UPDATE')
 THEN RAISE EXCEPTION 'Shopping name is unexpectedly editable'; END IF;
 IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND
   ((tablename='shopping_items' AND policyname IN ('Members add shopping','Members edit shopping','Members remove shopping')) OR
    (tablename='family_calendar_events' AND policyname IN ('Members add calendar events','Members delete calendar events'))))
 THEN RAISE EXCEPTION 'Legacy broad policies remain'; END IF;
 IF has_function_privilege('authenticated','public.famunova_can_internal(uuid,text,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Internal authorization function exposed'; END IF;
 RAISE NOTICE 'Catalog checks passed; run JWT and concurrency tests next';
END $$;
