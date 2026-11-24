BEGIN;
INSERT INTO auth.users(id) VALUES ('10000000-0000-4000-8000-000000000001');
INSERT INTO public.family_groups(id,name,owner_id) VALUES
('20000000-0000-4000-8000-000000000001','Billing A','10000000-0000-4000-8000-000000000001'),
('20000000-0000-4000-8000-000000000002','Billing B','10000000-0000-4000-8000-000000000001');
DO $$
DECLARE a uuid:='20000000-0000-4000-8000-000000000001'; b uuid:='20000000-0000-4000-8000-000000000002'; u uuid:='10000000-0000-4000-8000-000000000001'; g bigint; oldg bigint; r text; p text:='price_1UeZokDHyA40vHHZfdf1YLJv'; k uuid:='30000000-0000-4000-8000-000000000001';
BEGIN
 PERFORM public.famunova_bind_family_customer(a,u,'cus_TestA');
 PERFORM public.famunova_bind_family_customer(b,u,'cus_TestB');
 IF public.famunova_reserve_checkout_internal(a,u,p,k) IS DISTINCT FROM 'acquired' THEN RAISE EXCEPTION 'Reservation failed'; END IF;
 IF public.famunova_reserve_checkout_internal(a,u,p,gen_random_uuid()) IS DISTINCT FROM 'reserved' THEN RAISE EXCEPTION 'Duplicate reservation admitted'; END IF;
 IF NOT public.famunova_bind_checkout_session(a,k,'cs_test_TestA') THEN RAISE EXCEPTION 'Session binding failed'; END IF;
 IF public.famunova_release_expired_checkout(a,k,'cs_test_Wrong') THEN RAISE EXCEPTION 'Wrong session released'; END IF;
 oldg:=public.famunova_begin_stripe_observation('sub_TestA');
 g:=public.famunova_begin_stripe_observation('sub_TestA');
 r:=public.famunova_apply_stripe_observation('evt_Old',oldg,'sub_TestA',u,a,'cus_TestA',p,'plus','month','active',now()+interval '1 month',false);
 IF r IS DISTINCT FROM 'retry' THEN RAISE EXCEPTION 'Superseded observation accepted'; END IF;
 r:=public.famunova_apply_stripe_observation('evt_New',g,'sub_TestA',u,a,'cus_TestA',p,'plus','month','active',now()+interval '1 month',false);
 IF r IS DISTINCT FROM 'applied' THEN RAISE EXCEPTION 'Activation failed'; END IF;
 r:=public.famunova_apply_stripe_observation('evt_New',g,'sub_TestA',u,a,'cus_TestA',p,'plus','month','active',now()+interval '1 month',false);
 IF r IS DISTINCT FROM 'duplicate' THEN RAISE EXCEPTION 'Duplicate event not detected'; END IF;
 IF public.famunova_group_plan_internal(a) IS DISTINCT FROM 'plus' OR public.famunova_group_plan_internal(b) IS DISTINCT FROM 'free' THEN RAISE EXCEPTION 'Family isolation failed'; END IF;
 IF public.famunova_release_expired_checkout(a,k,'cs_test_TestA') THEN RAISE EXCEPTION 'Active subscription reservation released'; END IF;
 g:=public.famunova_begin_stripe_observation('sub_TestA');
 r:=public.famunova_apply_stripe_observation('evt_Cancel',g,'sub_TestA',u,a,'cus_TestA',p,'plus','month','canceled',now(),false);
 IF r IS DISTINCT FROM 'applied' OR public.famunova_group_plan_internal(a) IS DISTINCT FROM 'free' THEN RAISE EXCEPTION 'Downgrade failed'; END IF;
 IF has_function_privilege('authenticated','public.famunova_begin_stripe_observation(text)','EXECUTE') THEN RAISE EXCEPTION 'Client can allocate observation'; END IF;
 RAISE NOTICE 'PASS: billing isolation, reservation, generation, duplicate event, downgrade';
END $$;
ROLLBACK;
