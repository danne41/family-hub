-- TEST ONLY. Requires 013. Switch all billing endpoints together.
BEGIN;
CREATE OR REPLACE FUNCTION public.famunova_apply_stripe_observation(
 p_event_id text,p_generation bigint,p_subscription_id text,p_user_id uuid,p_group_id uuid,
 p_customer_id text,p_price_id text,p_plan text,p_interval text,p_status text,
 p_period_end timestamptz,p_cancel_at_period_end boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;v_customer text;v_previous public.billing_subscriptions%ROWTYPE; v_generation bigint;
BEGIN
 IF p_event_id IS NULL OR length(p_event_id)=0 OR p_generation IS NULL OR p_generation<=0
 OR p_subscription_id IS NULL OR p_user_id IS NULL OR p_group_id IS NULL OR p_customer_id IS NULL
 THEN RAISE EXCEPTION 'Missing event identifiers';END IF;
 SELECT generation INTO v_generation FROM public.famunova_stripe_observations WHERE subscription_id=p_subscription_id FOR UPDATE;
 IF v_generation IS DISTINCT FROM p_generation THEN RETURN 'retry'; END IF;
 IF p_price_id IS NULL OR p_plan IS NULL OR p_interval IS NULL OR p_status IS NULL OR p_cancel_at_period_end IS NULL THEN RAISE EXCEPTION 'Missing subscription fields'; END IF;
 -- Serialize all events for a group; also protects conflicting subscriptions.
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group_id FOR UPDATE;
 IF v_owner IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'Group ownership mismatch';END IF;
 SELECT stripe_customer_id INTO v_customer FROM public.famunova_family_billing_customers WHERE group_id=p_group_id AND owner_id=p_user_id;
 IF v_customer IS DISTINCT FROM p_customer_id THEN RAISE EXCEPTION 'Customer ownership mismatch';END IF;
 IF (p_price_id,p_plan,p_interval) NOT IN (
 ('price_1UeZokDHyA40vHHZfdf1YLJv','plus','month'),
 ('price_1UeZrDDHyA40vHHZNtj3nqLS','plus','year'),
 ('price_1UeZsrDHyA40vHHZHasgi7rX','premium_family','month'),
 ('price_1UeZu9DHyA40vHHZKanc2Yhx','premium_family','year'))
 THEN RAISE EXCEPTION 'Unapproved price';END IF;
 IF p_status NOT IN ('active','trialing','past_due','unpaid','incomplete','incomplete_expired','canceled','paused')
 THEN RAISE EXCEPTION 'Invalid subscription status';END IF;
 INSERT INTO public.billing_webhook_events(id) VALUES(p_event_id) ON CONFLICT(id) DO NOTHING;
 PERFORM 1 FROM public.billing_webhook_events WHERE id=p_event_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.billing_webhook_events WHERE id=p_event_id AND processed_at IS NOT NULL)
 THEN RETURN 'duplicate';END IF;
 SELECT * INTO v_previous FROM public.billing_subscriptions
 WHERE stripe_subscription_id=p_subscription_id FOR UPDATE;
 IF FOUND AND (v_previous.group_id IS DISTINCT FROM p_group_id
 OR v_previous.user_id IS DISTINCT FROM p_user_id
 OR v_previous.stripe_customer_id IS DISTINCT FROM p_customer_id)
 THEN RAISE EXCEPTION 'Subscription identity reassignment denied';END IF;
 IF p_status IN ('active','trialing','past_due','unpaid','incomplete','paused') AND EXISTS(SELECT 1 FROM public.billing_subscriptions
 WHERE group_id=p_group_id AND stripe_subscription_id<>p_subscription_id
 AND status IN ('active','trialing','past_due','unpaid','incomplete','paused'))
 THEN RAISE EXCEPTION 'Conflicting subscription for family';END IF;
 INSERT INTO public.billing_subscriptions(
 stripe_subscription_id,user_id,group_id,stripe_customer_id,stripe_price_id,plan,billing_interval,
 status,current_period_end,cancel_at_period_end,updated_at,stripe_event_id)
 VALUES(p_subscription_id,p_user_id,p_group_id,p_customer_id,p_price_id,p_plan,p_interval,
 p_status,p_period_end,p_cancel_at_period_end,now(),p_event_id)
 ON CONFLICT(stripe_subscription_id) DO UPDATE SET
 stripe_price_id=EXCLUDED.stripe_price_id,plan=EXCLUDED.plan,
 billing_interval=EXCLUDED.billing_interval,status=EXCLUDED.status,
 current_period_end=EXCLUDED.current_period_end,
 cancel_at_period_end=EXCLUDED.cancel_at_period_end,updated_at=now(),
 stripe_event_id=EXCLUDED.stripe_event_id;
 UPDATE public.billing_webhook_events SET processed_at=now() WHERE id=p_event_id;
 RETURN 'applied';
END $$;
COMMIT;
