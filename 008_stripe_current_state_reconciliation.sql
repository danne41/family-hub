-- Famunova 008: Stripe current-state reconciliation (DRAFT, ISOLATED TEST DB ONLY).
-- The observation timestamp is captured BEFORE fetching Stripe, not from event.created.
-- A later-started observation supersedes an earlier one even when events share a second.
BEGIN;
ALTER TABLE public.billing_subscriptions
 ADD COLUMN IF NOT EXISTS stripe_observed_at timestamptz;
CREATE OR REPLACE FUNCTION public.famunova_reconcile_stripe_subscription(
 p_event_id text,p_observed_at timestamptz,p_subscription_id text,p_user_id uuid,
 p_group_id uuid,p_customer_id text,p_price_id text,p_plan text,p_interval text,
 p_status text,p_period_end timestamptz,p_cancel_at_period_end boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;v_customer text;v_old public.billing_subscriptions%ROWTYPE;
BEGIN
 IF nullif(p_event_id,'') IS NULL OR nullif(p_subscription_id,'') IS NULL
 OR p_observed_at IS NULL OR p_observed_at>now()+interval '5 minutes'
 OR p_user_id IS NULL OR p_group_id IS NULL OR nullif(p_customer_id,'') IS NULL
 THEN RAISE EXCEPTION 'Invalid reconciliation identifiers'; END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group_id FOR UPDATE;
 IF v_owner IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'Family ownership mismatch'; END IF;
 SELECT stripe_customer_id INTO v_customer FROM public.billing_customers WHERE user_id=p_user_id;
 IF v_customer IS DISTINCT FROM p_customer_id THEN RAISE EXCEPTION 'Stripe customer mismatch'; END IF;
 IF (p_price_id,p_plan,p_interval) NOT IN (
 ('price_1UeZokDHyA40vHHZfdf1YLJv','plus','month'),
 ('price_1UeZrDDHyA40vHHZNtj3nqLS','plus','year'),
 ('price_1UeZsrDHyA40vHHZHasgi7rX','premium_family','month'),
 ('price_1UeZu9DHyA40vHHZKanc2Yhx','premium_family','year'))
 THEN RAISE EXCEPTION 'Unapproved price'; END IF;
 IF p_status NOT IN ('active','trialing','past_due','unpaid','incomplete',
 'incomplete_expired','canceled','paused') THEN RAISE EXCEPTION 'Invalid status'; END IF;
 -- Baseline processed_at has NO default, so new rows remain unprocessed until committed.
 INSERT INTO public.billing_webhook_events(id) VALUES(p_event_id) ON CONFLICT(id) DO NOTHING;
 PERFORM 1 FROM public.billing_webhook_events WHERE id=p_event_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.billing_webhook_events WHERE id=p_event_id AND processed_at IS NOT NULL)
 THEN RETURN 'duplicate'; END IF;
 SELECT * INTO v_old FROM public.billing_subscriptions
 WHERE stripe_subscription_id=p_subscription_id FOR UPDATE;
 IF FOUND AND (v_old.group_id IS DISTINCT FROM p_group_id
 OR v_old.user_id IS DISTINCT FROM p_user_id
 OR v_old.stripe_customer_id IS DISTINCT FROM p_customer_id)
 THEN RAISE EXCEPTION 'Subscription identity reassignment denied'; END IF;
 IF FOUND AND v_old.stripe_observed_at IS NOT NULL AND p_observed_at<=v_old.stripe_observed_at THEN
 UPDATE public.billing_webhook_events SET processed_at=now() WHERE id=p_event_id;
 RETURN 'stale_observation';
 END IF;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions
 WHERE group_id=p_group_id AND stripe_subscription_id<>p_subscription_id
 AND status IN ('active','trialing','past_due','unpaid','incomplete'))
 THEN RAISE EXCEPTION 'Family has conflicting subscription'; END IF;
 INSERT INTO public.billing_subscriptions(
 stripe_subscription_id,user_id,group_id,stripe_customer_id,stripe_price_id,plan,billing_interval,
 status,current_period_end,cancel_at_period_end,updated_at,stripe_observed_at)
 VALUES(p_subscription_id,p_user_id,p_group_id,p_customer_id,p_price_id,p_plan,p_interval,
 p_status,p_period_end,p_cancel_at_period_end,now(),p_observed_at)
 ON CONFLICT(stripe_subscription_id) DO UPDATE SET
 stripe_price_id=EXCLUDED.stripe_price_id,plan=EXCLUDED.plan,
 billing_interval=EXCLUDED.billing_interval,status=EXCLUDED.status,
 current_period_end=EXCLUDED.current_period_end,
 cancel_at_period_end=EXCLUDED.cancel_at_period_end,updated_at=now(),
 stripe_observed_at=EXCLUDED.stripe_observed_at;
 UPDATE public.billing_webhook_events SET processed_at=now() WHERE id=p_event_id;
 RETURN 'applied';
END $$;
REVOKE ALL ON FUNCTION public.famunova_reconcile_stripe_subscription(text,timestamptz,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean)
 FROM PUBLIC,anon,authenticated;
-- Prevent accidental bypass via legacy service-role RPCs in isolated test environment.
REVOKE ALL ON FUNCTION public.famunova_apply_stripe_event(text,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean) FROM service_role;
REVOKE ALL ON FUNCTION public.famunova_apply_stripe_event_v2(text,bigint,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.famunova_reconcile_stripe_subscription(text,timestamptz,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean) TO service_role;
COMMIT;
