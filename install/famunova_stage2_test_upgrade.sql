BEGIN;
DO $$ BEGIN
 IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE') <> 11 THEN RAISE EXCEPTION 'Unexpected baseline table count'; END IF;
 IF EXISTS (SELECT 1 FROM public.family_groups) OR EXISTS (SELECT 1 FROM public.billing_subscriptions) OR EXISTS (SELECT 1 FROM public.billing_customers) THEN RAISE EXCEPTION 'Expected empty test data'; END IF;
END $$;
-- 004_stripe_event_atomic.sql
-- DRAFT / TEST DB ONLY. Requires 001 and billing tables. DO NOT RUN IN PRODUCTION.
-- A single transaction applies one event; ownership, customer, price and conflict checks happen server-side.

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


-- 005_checkout_reservation.sql
-- FAMUNOVA 005: Checkout admission reservation, TEST DATABASE ONLY.
-- Requires 001, 004. Never run against production without separate approval.

CREATE TABLE IF NOT EXISTS public.famunova_checkout_reservations (
 group_id uuid PRIMARY KEY REFERENCES public.family_groups(id) ON DELETE CASCADE,
 owner_id uuid NOT NULL REFERENCES auth.users(id),
 reservation_key uuid NOT NULL UNIQUE,
 price_id text NOT NULL,
 expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.famunova_checkout_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.famunova_checkout_reservations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.famunova_reserve_checkout_internal(
 p_group_id uuid,p_owner_id uuid,p_price_id text,p_key uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;v_old public.famunova_checkout_reservations%rowtype;
BEGIN
 IF p_key IS NULL OR p_group_id IS NULL OR p_owner_id IS NULL THEN RAISE EXCEPTION 'Missing identifiers';END IF;
 IF p_price_id NOT IN (
  'price_1UeZokDHyA40vHHZfdf1YLJv','price_1UeZrDDHyA40vHHZNtj3nqLS',
  'price_1UeZsrDHyA40vHHZHasgi7rX','price_1UeZu9DHyA40vHHZKanc2Yhx')
 THEN RAISE EXCEPTION 'Invalid price';END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group_id FOR UPDATE;
 IF v_owner IS DISTINCT FROM p_owner_id THEN RAISE EXCEPTION 'Not group owner';END IF;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions WHERE group_id=p_group_id
 AND status IN ('active','trialing','past_due','unpaid','incomplete')) THEN RETURN 'subscribed';END IF;
 SELECT * INTO v_old FROM public.famunova_checkout_reservations WHERE group_id=p_group_id FOR UPDATE;
 IF FOUND AND v_old.expires_at>now() THEN RETURN 'reserved';END IF;
 INSERT INTO public.famunova_checkout_reservations(group_id,owner_id,reservation_key,price_id,expires_at)
 VALUES(p_group_id,p_owner_id,p_key,p_price_id,now()+interval '35 minutes')
 ON CONFLICT(group_id) DO UPDATE SET owner_id=EXCLUDED.owner_id,reservation_key=EXCLUDED.reservation_key,
 price_id=EXCLUDED.price_id,expires_at=EXCLUDED.expires_at,created_at=now();
 RETURN 'acquired';
END $$;
REVOKE ALL ON FUNCTION public.famunova_reserve_checkout_internal(uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated;
-- No client EXECUTE. Service role only, subject to role/ownership audit.


-- 006_stripe_event_watermark.sql
-- Famunova 006: event-time watermark for Stripe webhook, TEST DATABASE ONLY.
-- Requires baseline billing tables, 001, 004. Does NOT solve same-second ordering or stale Stripe reads.

ALTER TABLE public.billing_subscriptions
 ADD COLUMN IF NOT EXISTS stripe_event_created bigint,
 ADD COLUMN IF NOT EXISTS stripe_event_id text;
CREATE OR REPLACE FUNCTION public.famunova_apply_stripe_event_v2(
 p_event_id text,p_event_created bigint,p_subscription_id text,p_user_id uuid,p_group_id uuid,
 p_customer_id text,p_price_id text,p_plan text,p_interval text,p_status text,
 p_period_end timestamptz,p_cancel_at_period_end boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;v_customer text;v_previous public.billing_subscriptions%ROWTYPE;
BEGIN
 IF p_event_id IS NULL OR length(p_event_id)=0 OR p_event_created IS NULL OR p_event_created<=0
 OR p_subscription_id IS NULL OR p_user_id IS NULL OR p_group_id IS NULL OR p_customer_id IS NULL
 THEN RAISE EXCEPTION 'Missing event identifiers';END IF;
 -- Serialize all events for a group; also protects conflicting subscriptions.
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group_id FOR UPDATE;
 IF v_owner IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'Group ownership mismatch';END IF;
 SELECT stripe_customer_id INTO v_customer FROM public.billing_customers WHERE user_id=p_user_id;
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
 -- Stripe event.created is seconds resolution. Conservatively ignore ties to avoid regressions.
 -- Reconciliation is required to recover a newer event in the same second.
 IF FOUND AND v_previous.stripe_event_created IS NOT NULL
 AND p_event_created<=v_previous.stripe_event_created THEN
 UPDATE public.billing_webhook_events SET processed_at=now() WHERE id=p_event_id;
 RETURN 'stale';
 END IF;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions
 WHERE group_id=p_group_id AND stripe_subscription_id<>p_subscription_id
 AND status IN ('active','trialing','past_due','unpaid','incomplete'))
 THEN RAISE EXCEPTION 'Conflicting subscription for family';END IF;
 INSERT INTO public.billing_subscriptions(
 stripe_subscription_id,user_id,group_id,stripe_customer_id,stripe_price_id,plan,billing_interval,
 status,current_period_end,cancel_at_period_end,updated_at,stripe_event_created,stripe_event_id)
 VALUES(p_subscription_id,p_user_id,p_group_id,p_customer_id,p_price_id,p_plan,p_interval,
 p_status,p_period_end,p_cancel_at_period_end,now(),p_event_created,p_event_id)
 ON CONFLICT(stripe_subscription_id) DO UPDATE SET
 stripe_price_id=EXCLUDED.stripe_price_id,plan=EXCLUDED.plan,
 billing_interval=EXCLUDED.billing_interval,status=EXCLUDED.status,
 current_period_end=EXCLUDED.current_period_end,
 cancel_at_period_end=EXCLUDED.cancel_at_period_end,updated_at=now(),
 stripe_event_created=EXCLUDED.stripe_event_created,stripe_event_id=EXCLUDED.stripe_event_id;
 UPDATE public.billing_webhook_events SET processed_at=now() WHERE id=p_event_id;
 RETURN 'applied';
END $$;
REVOKE ALL ON FUNCTION public.famunova_apply_stripe_event_v2(text,bigint,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean) FROM PUBLIC,anon,authenticated;
-- Old 004 RPC remains present: it MUST be retired before any deployment, as it bypasses watermark.


-- 009_stripe_reconciliation_generation.sql
-- TEST ONLY. Requires stage 1 and billing migrations 004-006.
-- Not yet wired into webhook. Do not deploy separately.

CREATE TABLE public.famunova_stripe_observations (
 subscription_id text PRIMARY KEY,
 generation bigint NOT NULL CHECK(generation>0)
);
ALTER TABLE public.famunova_stripe_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.famunova_stripe_observations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.famunova_begin_stripe_observation(p_subscription_id text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_generation bigint;
BEGIN
 IF p_subscription_id IS NULL OR p_subscription_id !~ '^sub_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'Invalid subscription identifier'; END IF;
 INSERT INTO public.famunova_stripe_observations AS o(subscription_id,generation)
 VALUES(p_subscription_id,1)
 ON CONFLICT(subscription_id) DO UPDATE SET generation=o.generation+1
 RETURNING generation INTO v_generation;
 RETURN v_generation;
END $$;
REVOKE ALL ON FUNCTION public.famunova_begin_stripe_observation(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_begin_stripe_observation(text) TO service_role;
-- The future apply RPC must lock this row and verify generation in the SAME
-- transaction as the subscription update. Superseded requests must retry;
-- they must not acknowledge an event that has not been reconciled.


-- 010_stripe_apply_observation.sql
-- TEST ONLY. Requires 004, 005, 006, 009. Not deployed.

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
 SELECT stripe_customer_id INTO v_customer FROM public.billing_customers WHERE user_id=p_user_id;
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
REVOKE ALL ON FUNCTION public.famunova_apply_stripe_observation(text,bigint,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_apply_stripe_observation(text,bigint,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean) TO service_role;
DROP FUNCTION IF EXISTS public.famunova_apply_stripe_event_v2(text,bigint,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean);
DROP FUNCTION IF EXISTS public.famunova_apply_stripe_event(text,text,uuid,uuid,text,text,text,text,text,timestamptz,boolean);


-- 011_checkout_fail_closed.sql
-- TEST ONLY. Requires 005 and 010. Fail closed on unresolved checkout.
-- A later server-side reconciliation must prove Stripe session terminal/unpaid
-- before releasing a reservation. Never release solely based on elapsed time.

CREATE OR REPLACE FUNCTION public.famunova_reserve_checkout_internal(
 p_group_id uuid,p_owner_id uuid,p_price_id text,p_key uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;v_old public.famunova_checkout_reservations%rowtype;
BEGIN
 IF p_key IS NULL OR p_group_id IS NULL OR p_owner_id IS NULL THEN RAISE EXCEPTION 'Missing identifiers';END IF;
 IF p_price_id IS NULL OR p_price_id NOT IN (
  'price_1UeZokDHyA40vHHZfdf1YLJv','price_1UeZrDDHyA40vHHZNtj3nqLS',
  'price_1UeZsrDHyA40vHHZHasgi7rX','price_1UeZu9DHyA40vHHZKanc2Yhx')
 THEN RAISE EXCEPTION 'Invalid price';END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group_id FOR UPDATE;
 IF v_owner IS DISTINCT FROM p_owner_id THEN RAISE EXCEPTION 'Not group owner';END IF;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions WHERE group_id=p_group_id
 AND status IN ('active','trialing','past_due','unpaid','incomplete','paused')) THEN RETURN 'subscribed';END IF;
 SELECT * INTO v_old FROM public.famunova_checkout_reservations WHERE group_id=p_group_id FOR UPDATE;
 -- Expiration alone is not proof that Stripe did not collect payment.
 IF FOUND THEN RETURN 'reserved';END IF;
 INSERT INTO public.famunova_checkout_reservations(group_id,owner_id,reservation_key,price_id,expires_at)
 VALUES(p_group_id,p_owner_id,p_key,p_price_id,now()+interval '35 minutes')
 ON CONFLICT(group_id) DO UPDATE SET owner_id=EXCLUDED.owner_id,reservation_key=EXCLUDED.reservation_key,
 price_id=EXCLUDED.price_id,expires_at=EXCLUDED.expires_at,created_at=now();
 RETURN 'acquired';
END $$;
REVOKE ALL ON FUNCTION public.famunova_reserve_checkout_internal(uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated;

GRANT EXECUTE ON FUNCTION public.famunova_reserve_checkout_internal(uuid,uuid,text,uuid) TO service_role;
CREATE UNIQUE INDEX famunova_one_open_subscription_per_group
ON public.billing_subscriptions(group_id)
WHERE group_id IS NOT NULL AND status IN ('active','trialing','past_due','unpaid','incomplete','paused');


-- 012_checkout_session_tracking.sql
-- TEST ONLY. Requires 011. Unknown session creation outcomes remain blocked.

ALTER TABLE public.famunova_checkout_reservations ADD COLUMN stripe_session_id text UNIQUE;
CREATE FUNCTION public.famunova_bind_checkout_session(p_group uuid,p_key uuid,p_session text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_session IS NULL OR p_session !~ '^cs_test_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'Invalid test session'; END IF;
 PERFORM 1 FROM public.family_groups WHERE id=p_group FOR UPDATE;
 UPDATE public.famunova_checkout_reservations SET stripe_session_id=p_session
 WHERE group_id=p_group AND reservation_key=p_key AND (stripe_session_id IS NULL OR stripe_session_id=p_session);
 RETURN FOUND;
END $$;
-- Trusted server must retrieve the exact Stripe session and verify expired,
-- unpaid, no subscription, matching customer and reservation metadata.
CREATE FUNCTION public.famunova_release_expired_checkout(p_group uuid,p_key uuid,p_session text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM public.family_groups WHERE id=p_group FOR UPDATE;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions WHERE group_id=p_group AND status IN ('active','trialing','past_due','unpaid','incomplete','paused')) THEN RETURN false; END IF;
 DELETE FROM public.famunova_checkout_reservations WHERE group_id=p_group AND reservation_key=p_key AND stripe_session_id=p_session;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.famunova_bind_checkout_session(uuid,uuid,text),public.famunova_release_expired_checkout(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_bind_checkout_session(uuid,uuid,text),public.famunova_release_expired_checkout(uuid,uuid,text) TO service_role;


-- 013_family_billing_customers.sql
-- TEST ONLY. Requires stage 1 and 012. No automatic legacy customer migration.

CREATE TABLE public.famunova_family_billing_customers (
 group_id uuid PRIMARY KEY REFERENCES public.family_groups(id) ON DELETE RESTRICT,
 owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 stripe_customer_id text NOT NULL UNIQUE CHECK(stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.famunova_family_billing_customers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.famunova_family_billing_customers FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.famunova_family_billing_customers TO service_role;
CREATE FUNCTION public.famunova_bind_family_customer(p_group uuid,p_owner uuid,p_customer text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid; v_existing public.famunova_family_billing_customers%ROWTYPE;
BEGIN
 IF p_group IS NULL OR p_owner IS NULL OR p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' THEN RAISE EXCEPTION 'Invalid customer binding'; END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group FOR UPDATE;
 IF v_owner IS DISTINCT FROM p_owner THEN RAISE EXCEPTION 'Owner mismatch'; END IF;
 SELECT * INTO v_existing FROM public.famunova_family_billing_customers WHERE group_id=p_group;
 IF FOUND THEN
  IF v_existing.owner_id IS DISTINCT FROM p_owner OR v_existing.stripe_customer_id IS DISTINCT FROM p_customer THEN RAISE EXCEPTION 'Customer reassignment denied'; END IF;
  RETURN v_existing.stripe_customer_id;
 END IF;
 IF EXISTS(SELECT 1 FROM public.billing_customers WHERE stripe_customer_id=p_customer) THEN RAISE EXCEPTION 'Legacy shared customer cannot be bound'; END IF;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions WHERE group_id=p_group) OR EXISTS(SELECT 1 FROM public.famunova_checkout_reservations WHERE group_id=p_group) THEN RAISE EXCEPTION 'Existing billing requires reconciliation'; END IF;
 INSERT INTO public.famunova_family_billing_customers(group_id,owner_id,stripe_customer_id) VALUES(p_group,p_owner,p_customer);
 RETURN p_customer;
END $$;
REVOKE ALL ON FUNCTION public.famunova_bind_family_customer(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_bind_family_customer(uuid,uuid,text) TO service_role;
-- Checkout, webhook and portal must switch together before deployment.


-- 014_family_customer_reconciliation.sql
-- TEST ONLY. Requires 013. Switch all billing endpoints together.

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


-- 015_checkout_resubscription.sql
-- TEST ONLY. Caller must verify completed Stripe session and its subscription.

CREATE FUNCTION public.famunova_release_completed_checkout(p_group uuid,p_key uuid,p_session text,p_subscription text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM public.family_groups WHERE id=p_group FOR UPDATE;
 IF NOT FOUND THEN RETURN false; END IF;
 IF EXISTS(SELECT 1 FROM public.billing_subscriptions WHERE group_id=p_group AND status IN ('active','trialing','past_due','unpaid','incomplete','paused')) THEN RETURN false; END IF;
 DELETE FROM public.famunova_checkout_reservations r
 USING public.billing_subscriptions s,public.famunova_family_billing_customers c
 WHERE r.group_id=p_group AND r.reservation_key=p_key AND r.stripe_session_id=p_session
 AND s.stripe_subscription_id=p_subscription AND s.group_id=r.group_id AND s.user_id=r.owner_id
 AND c.group_id=r.group_id AND c.owner_id=r.owner_id AND c.stripe_customer_id=s.stripe_customer_id
 AND s.status IN ('canceled','incomplete_expired');
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.famunova_release_completed_checkout(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_release_completed_checkout(uuid,uuid,text,text) TO service_role;

COMMIT;
