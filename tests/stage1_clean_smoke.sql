\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relrowsecurity AND c.relname IN ('family_groups','family_memberships','family_invites','profiles','shopping_items','family_calendar_events','billing_customers','billing_subscriptions','billing_webhook_events','famunova_plan_limits','famunova_member_permissions')) <> 11 THEN RAISE EXCEPTION 'RLS missing'; END IF;
 IF has_function_privilege('authenticated','public.famunova_can_internal(uuid,text,uuid)','EXECUTE') OR has_function_privilege('anon','public.create_family_group(text)','EXECUTE') THEN RAISE EXCEPTION 'Unexpected function grant'; END IF;
 IF has_column_privilege('authenticated','public.shopping_items','name','UPDATE') OR NOT has_column_privilege('authenticated','public.shopping_items','done','UPDATE') THEN RAISE EXCEPTION 'Shopping grants incorrect'; END IF;
END $$;
INSERT INTO auth.users(id) VALUES ('10000000-0000-4000-8000-000000000001'),('10000000-0000-4000-8000-000000000002'),('10000000-0000-4000-8000-000000000003'),('10000000-0000-4000-8000-000000000004');
SET LOCAL ROLE authenticated;
DO $$
DECLARE g uuid; a text; b text; c text; blocked boolean:=false;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
 g:=public.create_family_group('CI family');
 a:=public.create_group_invite(g); b:=public.create_group_invite(g); c:=public.create_group_invite(g);
 PERFORM set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
 PERFORM public.join_family_group(a);
 IF public.famunova_can(g,'shopping.delete') IS DISTINCT FROM false THEN RAISE EXCEPTION 'Member delete grant'; END IF;
 INSERT INTO public.shopping_items(group_id,week_start,name,created_by) VALUES(g,date_trunc('week',CURRENT_DATE)::date,'CI item',auth.uid());
 PERFORM set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
 PERFORM public.join_family_group(b);
 PERFORM set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
 BEGIN
 PERFORM public.join_family_group(c);
 EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT LIKE 'Family member limit reached%' THEN RAISE; END IF;
 blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Free limit bypass'; END IF;
 IF EXISTS(SELECT 1 FROM public.shopping_items WHERE group_id=g) THEN RAISE EXCEPTION 'Outsider read'; END IF;
 PERFORM set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
 IF (SELECT count(*) FROM public.famunova_list_members(g))<>3 THEN RAISE EXCEPTION 'Member count'; END IF;
 PERFORM public.famunova_set_member_role(g,'10000000-0000-4000-8000-000000000002','admin');
 PERFORM set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
 IF public.famunova_can(g,'shopping.delete') IS DISTINCT FROM true THEN RAISE EXCEPTION 'Admin grant missing'; END IF;
END $$;
RESET ROLE;
ROLLBACK;
SELECT 'PASS: Stage 1 smoke tests';
