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
 -- Reject invalid customer and price, and a second active subscription.
 g:=public.famunova_begin_stripe_observation('sub_TestB');
 BEGIN
 PERFORM public.famunova_apply_stripe_observation('evt_WrongCustomer',g,'sub_TestB',u,b,'cus_TestA',p,'plus','month','active',now(),false);
 RAISE EXCEPTION 'Unexpected acceptance';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'Customer ownership mismatch' THEN RAISE; END IF; END;
 BEGIN
 PERFORM public.famunova_apply_stripe_observation('evt_WrongPrice',g,'sub_TestB',u,b,'cus_TestB',p,'premium_family','month','active',now(),false);
 RAISE EXCEPTION 'Unexpected acceptance';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'Unapproved price' THEN RAISE; END IF; END;
 r:=public.famunova_apply_stripe_observation('evt_Premium',g,'sub_TestB',u,b,'cus_TestB','price_1UeZsrDHyA40vHHZHasgi7rX','premium_family','month','active',now()+interval '1 month',false);
 IF r IS DISTINCT FROM 'applied' OR public.famunova_group_plan_internal(b) IS DISTINCT FROM 'premium_family' THEN RAISE EXCEPTION 'Premium activation failed'; END IF;
 oldg:=public.famunova_begin_stripe_observation('sub_Conflict');
 BEGIN
 PERFORM public.famunova_apply_stripe_observation('evt_Conflict',oldg,'sub_Conflict',u,b,'cus_TestB',p,'plus','month','active',now(),false);
 RAISE EXCEPTION 'Unexpected acceptance';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM <> 'Conflicting subscription for family' THEN RAISE; END IF; END;
 INSERT INTO auth.users(id) SELECT gen_random_uuid() FROM generate_series(1,4);
 INSERT INTO public.family_memberships(group_id,user_id,role) SELECT b,id,CASE WHEN id=u THEN 'owner' ELSE 'member' END FROM auth.users WHERE id=u OR id<>u LIMIT 5;
 INSERT INTO public.shopping_items(group_id,week_start,name,created_by) VALUES(b,date_trunc('week',CURRENT_DATE)::date,'Retained item',u);
 g:=public.famunova_begin_stripe_observation('sub_TestB');
 r:=public.famunova_apply_stripe_observation('evt_PremiumCancel',g,'sub_TestB',u,b,'cus_TestB','price_1UeZsrDHyA40vHHZHasgi7rX','premium_family','month','canceled',now(),false);
 IF r IS DISTINCT FROM 'applied' OR public.famunova_group_plan_internal(b) IS DISTINCT FROM 'free' OR (SELECT count(*) FROM public.family_memberships WHERE group_id=b)<>5 OR NOT EXISTS(SELECT 1 FROM public.shopping_items WHERE group_id=b AND name='Retained item') THEN RAISE EXCEPTION 'Downgrade retention failed'; END IF;
 RAISE NOTICE 'PASS: customer mismatch, price mismatch, duplicate subscription and premium downgrade retention';
 RAISE NOTICE 'PASS: billing isolation, reservation, generation, duplicate event, downgrade';
END $$;
ROLLBACK;
