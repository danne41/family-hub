-- FAMUNOVA 005: Checkout admission reservation, TEST DATABASE ONLY.
-- Requires 001, 004. Never run against production without separate approval.
BEGIN;
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
COMMIT;
