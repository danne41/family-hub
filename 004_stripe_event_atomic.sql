-- DRAFT / TEST DB ONLY. Requires 001 and billing tables. DO NOT RUN IN PRODUCTION.
-- A single transaction applies one event; ownership, customer, price and conflict checks happen server-side.
BEGIN;
CREATE OR REPLACE FUNCTION public.famunova_apply_stripe_event(
 p_event_id text,p_subscription_id text,p_user_id uuid,p_group_id uuid,p_customer_id text,
 p_price_id text,p_plan text,p_interval text,p_status text,p_period_end timestamptz,p_cancel_at_period_end boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;v_customer text;v_existing_group uuid;
BEGIN
 IF p_event_id IS NULL OR p_subscription_id IS NULL OR p_group_id IS NULL THEN RAISE EXCEPTION 'Missing identifiers';END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group_id FOR UPDATE;
 IF v_owner IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'Group ownership mismatch';END IF;
 SELECT stripe_customer_id INTO v_customer FROM public.billing_customers WHERE user_id=p_user_id;
 IF v_customer IS DISTINCT FROM p_customer_id THEN RAISE EXCEPTION 'Customer ownership mismatch';END IF;
 IF (p_price_id,p_plan,p_interval) NOT IN (
  ('price_1UeZokDHyA40vHHZfdf1YLJv','plus','month'),
  ('price_1UeZrDDHyA40vHHZNtj3nqLS','plus','year'),
  ('price_1UeZsrDHyA40vHHZHasgi7rX','premium_family','month'),
  ('price_1UeZu9DHyA40vHHZKanc2Yhx','premium_family','year')) THEN RAISE EXCEPTION 'Unapproved price';END IF;
 IF p_status NOT IN ('active','trialing','past_due','unpaid','incomplete','incomplete_expired','canceled','paused') THEN RAISE EXCEPTION 'Unexpected subscription status';END IF;
 INSERT INTO public.billing_webhook_events(id) VALUES(p_event_id) ON CONFLICT(id) DO NOTHING;
 PERFORM 1 FROM public.billing_webhook_events WHERE id=p_event_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.billing_webhook_events WHERE id=p_event_id AND processed_at IS NOT NULL) THEN RETURN 'duplicate';END IF;
 SELECT group_id INTO v_existing_group FROM public.billing_subscriptions WHERE stripe_subscription_id=p_subscription_id FOR UPDATE;
 IF FOUND AND v_existing_group IS DISTINCT FROM p_group_id THEN RAISE EXCEPTION 'Subscription group reassignment denied';END IF;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions WHERE group_id=p_group_id AND stripe_subscription_id<>p_subscription_id AND status IN ('active','trialing','past_due','unpaid','incomplete')) THEN RAISE EXCEPTION 'Group has conflicting subscription';END IF;
 INSERT INTO public.billing_subscriptions(stripe_subscription_id,user_id,group_id,stripe_customer_id,stripe_price_id,plan,billing_interval,status,current_period_end,cancel_at_period_end,updated_at)
 VALUES(p_subscription_id,p_user_id,p_group_id,p_customer_id,p_price_id,p_plan,p_interval,p_status,p_period_end,p_cancel_at_period_end,now())
 ON CONFLICT(stripe_subscription_id) DO UPDATE SET user_id=EXCLUDED.user_id,group_id=EXCLUDED.group_id,stripe_customer_id=EXCLUDED.stripe_customer_id,stripe_price_id=EXCLUDED.stripe_price_id,plan=EXCLUDED.plan,billing_interval=EXCLUDED.billing_interval,status=EXCLUDED.status,current_period_end=EXCLUDED.current_period_end,cancel_at_period_end=EXCLUDED.cancel_at_period_end,updated_at=now();
 UPDATE public.billing_webhook_events SET processed_at=now() WHERE id=p_event_id;
 RETURN 'applied';
END $$;
REVOKE ALL ON FUNCTION public.famunova_apply_stripe_event(text,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean) FROM PUBLIC,anon,authenticated;
-- SECURITY NOTE: This is callable by service_role, but service_role is not a dedicated trust boundary.
-- Production hardening requires a dedicated DB role or trusted server-only endpoint and an audit of function ownership.
COMMIT;
