-- TEST ONLY. Caller must verify completed Stripe session and its subscription.
BEGIN;
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
