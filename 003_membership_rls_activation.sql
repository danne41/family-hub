-- FAMUNOVA 003: ACTIVATION CANDIDATE. TEST DATABASE ONLY. DO NOT RUN IN PRODUCTION.
-- Requires 001, 002. This changes RLS and join RPC; must be reviewed and tested.
-- IMPORTANT: this migration deliberately refuses activation when legacy active subscriptions
-- remain unlinked, or when existing group membership exceeds resolved entitlement.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM public.billing_subscriptions
            WHERE status IN ('active','trialing') AND plan IN ('plus','premium_family')
              AND group_id IS NULL) THEN
   RAISE EXCEPTION 'Activation blocked: active paid subscriptions without group mapping';
 END IF;
 IF EXISTS (SELECT 1 FROM public.billing_subscriptions s
            JOIN public.family_groups g ON g.id=s.group_id
            WHERE s.status IN ('active','trialing') AND s.plan IN ('plus','premium_family')
              AND s.user_id<>g.owner_id) THEN
   RAISE EXCEPTION 'Activation blocked: paid subscription does not belong to group owner';
 END IF;
 IF EXISTS (SELECT 1 FROM public.family_groups g
            JOIN public.famunova_plan_limits l
              ON l.plan=public.famunova_group_plan_internal(g.id)
            WHERE (SELECT count(*) FROM public.family_memberships m WHERE m.group_id=g.id)>l.max_members) THEN
   RAISE EXCEPTION 'Activation blocked: existing family exceeds plan limit';
 END IF;
END $$;

-- Private permission evaluator: only valid group members may have entitlements.
-- Owner is derived from family_groups.owner_id, never from editable membership.role.
-- Default member rights are deliberately narrow. Explicit per-user override wins.
CREATE OR REPLACE FUNCTION public.famunova_can_internal(p_group uuid,p_action text,p_user uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid; v_allowed boolean; v_exists boolean;
BEGIN
 IF p_user IS NULL OR p_group IS NULL OR p_action IS NULL THEN RETURN false; END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group;
 IF v_owner IS NULL THEN RETURN false; END IF;
 SELECT EXISTS(SELECT 1 FROM public.family_memberships WHERE group_id=p_group AND user_id=p_user) INTO v_exists;
 IF NOT v_exists THEN RETURN false; END IF;
 IF p_user=v_owner THEN RETURN true; END IF;
 SELECT allowed INTO v_allowed FROM public.famunova_member_permissions
  WHERE group_id=p_group AND user_id=p_user AND permission=p_action;
 IF FOUND THEN RETURN v_allowed; END IF;
 RETURN p_action IN ('calendar.create','calendar.edit_own','calendar.delete_own',
                     'shopping.add','shopping.complete');
END $$;
REVOKE ALL ON FUNCTION public.famunova_can_internal(uuid,text,uuid) FROM PUBLIC,anon,authenticated;

-- Owner-only permission changes; no client table write grant.
CREATE OR REPLACE FUNCTION public.famunova_set_member_permission(p_group uuid,p_user uuid,p_permission text,p_allowed boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS
  (SELECT 1 FROM public.family_groups WHERE id=p_group AND owner_id=auth.uid())
 THEN RAISE EXCEPTION 'Only family owner can manage permissions'; END IF;
 IF p_user=auth.uid() THEN RAISE EXCEPTION 'Owner permissions cannot be overridden'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.family_memberships WHERE group_id=p_group AND user_id=p_user)
 THEN RAISE EXCEPTION 'Target user is not a group member'; END IF;
 INSERT INTO public.famunova_member_permissions(group_id,user_id,permission,allowed)
 VALUES(p_group,p_user,p_permission,p_allowed)
 ON CONFLICT(group_id,user_id,permission) DO UPDATE SET allowed=EXCLUDED.allowed,updated_at=now();
END $$;
REVOKE ALL ON FUNCTION public.famunova_set_member_permission(uuid,uuid,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.famunova_set_member_permission(uuid,uuid,text,boolean) TO authenticated;

-- Database-level admission guard applies to ALL inserts (including service role writes).
-- Group row lock serializes admissions; existing owner insertion is counted as member 1.
CREATE OR REPLACE FUNCTION public.famunova_membership_capacity_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 PERFORM public.famunova_assert_member_capacity_internal(NEW.group_id);
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.famunova_membership_capacity_trigger() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER famunova_membership_capacity_before_insert
 BEFORE INSERT ON public.family_memberships
 FOR EACH ROW EXECUTE FUNCTION public.famunova_membership_capacity_trigger();

-- Preserve invite lock and one-use behavior. Capacity trigger checks insert atomically.
CREATE OR REPLACE FUNCTION public.join_family_group(p_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_invite public.family_invites%rowtype;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
 SELECT * INTO v_invite FROM public.family_invites
 WHERE code_hash=encode(extensions.digest(upper(trim(coalesce(p_code,''))),'sha256'),'hex')
 AND expires_at>now() AND used_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or expired invite'; END IF;
 IF EXISTS(SELECT 1 FROM public.family_memberships
           WHERE group_id=v_invite.group_id AND user_id=auth.uid())
 THEN RAISE EXCEPTION 'Already a member'; END IF;
 INSERT INTO public.family_memberships(group_id,user_id) VALUES(v_invite.group_id,auth.uid());
 UPDATE public.family_invites SET used_at=now() WHERE id=v_invite.id;
 RETURN v_invite.group_id;
END $$;
REVOKE ALL ON FUNCTION public.join_family_group(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.join_family_group(text) TO authenticated;

-- Replace permissive policies, never add permissive policies alongside them.
DROP POLICY IF EXISTS "Members add calendar events" ON public.family_calendar_events;
DROP POLICY IF EXISTS "Members delete calendar events" ON public.family_calendar_events;
DROP POLICY IF EXISTS "Members add shopping" ON public.shopping_items;
DROP POLICY IF EXISTS "Members edit shopping" ON public.shopping_items;
DROP POLICY IF EXISTS "Members remove shopping" ON public.shopping_items;

CREATE POLICY "Famunova calendar create" ON public.family_calendar_events FOR INSERT TO authenticated
 WITH CHECK(created_by=(SELECT auth.uid()) AND
   public.famunova_can_internal(group_id,'calendar.create',(SELECT auth.uid())));
CREATE POLICY "Famunova calendar delete" ON public.family_calendar_events FOR DELETE TO authenticated
 USING(public.famunova_can_internal(group_id,'calendar.delete_all',(SELECT auth.uid())) OR
       (created_by=(SELECT auth.uid()) AND public.famunova_can_internal(group_id,'calendar.delete_own',(SELECT auth.uid()))));
-- No calendar UPDATE grant or policy currently exists; defer edits until a separate audited migration.
CREATE POLICY "Famunova shopping add" ON public.shopping_items FOR INSERT TO authenticated
 WITH CHECK(created_by=(SELECT auth.uid()) AND
   public.famunova_can_internal(group_id,'shopping.add',(SELECT auth.uid())));
CREATE POLICY "Famunova shopping update" ON public.shopping_items FOR UPDATE TO authenticated
 USING(public.famunova_can_internal(group_id,'shopping.complete',(SELECT auth.uid())))
 WITH CHECK(public.famunova_can_internal(group_id,'shopping.complete',(SELECT auth.uid())));
CREATE POLICY "Famunova shopping delete" ON public.shopping_items FOR DELETE TO authenticated
 USING(public.famunova_can_internal(group_id,'shopping.delete',(SELECT auth.uid())));

-- NOTE: shopping UPDATE currently also allows editing item name, not just done.
-- A separate column-level privilege / RPC redesign is REQUIRED before production approval.
NOTIFY pgrst,'reload schema';
COMMIT;
