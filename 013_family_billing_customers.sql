-- TEST ONLY. Requires stage 1 and 012. No automatic legacy customer migration.
BEGIN;
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
COMMIT;
