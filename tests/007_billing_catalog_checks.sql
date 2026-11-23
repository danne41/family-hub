-- Famunova 007: isolated test-database safety checks (read-only).
-- Run after baseline + 001..006 in a disposable Supabase project.
DO $$
DECLARE v_count int;
BEGIN
 SELECT count(*) INTO v_count FROM information_schema.columns
 WHERE table_schema='public' AND table_name='billing_subscriptions'
 AND column_name IN ('group_id','stripe_event_created','stripe_event_id');
 IF v_count<>3 THEN RAISE EXCEPTION 'Missing family-scoped billing columns'; END IF;
 SELECT count(*) INTO v_count FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='famunova_apply_stripe_event_v2';
 IF v_count<>1 THEN RAISE EXCEPTION 'Missing webhook v2 RPC'; END IF;
 IF has_function_privilege('authenticated',
 'public.famunova_apply_stripe_event_v2(text,bigint,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean)','EXECUTE')
 THEN RAISE EXCEPTION 'Authenticated can execute internal webhook RPC'; END IF;
 IF has_function_privilege('anon',
 'public.famunova_apply_stripe_event_v2(text,bigint,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean)','EXECUTE')
 THEN RAISE EXCEPTION 'Anon can execute internal webhook RPC'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname='famunova_checkout_reservations' AND c.relrowsecurity)
 THEN RAISE EXCEPTION 'Reservation RLS disabled'; END IF;
 RAISE NOTICE 'Catalog checks passed. JWT, concurrency and Stripe tests NOT covered.';
END $$;
