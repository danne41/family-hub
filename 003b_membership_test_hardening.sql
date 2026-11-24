-- TEST ONLY. Apply after 003_membership_rls_activation_v2.sql.
-- Consolidates test changes through step 74. Clean installation not yet verified.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION public.famunova_can_internal(p_group uuid,p_action text,p_user uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid; v_role text; v_allowed boolean;
BEGIN
 IF p_user IS NULL OR p_group IS NULL OR p_action IS NULL THEN RETURN false; END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group;
 IF v_owner IS NULL THEN RETURN false; END IF;
 SELECT role INTO v_role FROM public.family_memberships WHERE group_id=p_group AND user_id=p_user;
 IF NOT FOUND THEN RETURN false; END IF;
 IF p_user=v_owner THEN RETURN true; END IF;
 IF v_role NOT IN ('admin','member') OR v_role IS NULL THEN RETURN false; END IF;
 IF p_action NOT IN ('calendar.create','calendar.edit_own','calendar.edit_all','calendar.delete_own','calendar.delete_all','shopping.add','shopping.complete','shopping.delete') THEN RETURN false; END IF;
 SELECT allowed INTO v_allowed FROM public.famunova_member_permissions WHERE group_id=p_group AND user_id=p_user AND permission=p_action;
 IF FOUND THEN RETURN COALESCE(v_allowed,false); END IF;
 IF v_role='admin' THEN RETURN true; END IF;
 RETURN p_action IN ('calendar.create','calendar.edit_own','calendar.delete_own','shopping.add','shopping.complete');
END $$;
REVOKE ALL ON FUNCTION public.famunova_can_internal(uuid,text,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.famunova_can(p_group uuid,p_action text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE WHEN auth.uid() IS NULL THEN false ELSE COALESCE(public.famunova_can_internal(p_group,p_action,auth.uid()),false) END;
$$;
ALTER POLICY "Famunova calendar create" ON public.family_calendar_events WITH CHECK(created_by=(SELECT auth.uid()) AND public.famunova_can(group_id,'calendar.create'));
ALTER POLICY "Famunova calendar delete" ON public.family_calendar_events USING(public.famunova_can(group_id,'calendar.delete_all') OR (created_by=(SELECT auth.uid()) AND public.famunova_can(group_id,'calendar.delete_own')));
ALTER POLICY "Famunova shopping add" ON public.shopping_items WITH CHECK(created_by=(SELECT auth.uid()) AND public.famunova_can(group_id,'shopping.add'));
ALTER POLICY "Famunova shopping delete" ON public.shopping_items USING(public.famunova_can(group_id,'shopping.delete'));
ALTER POLICY "Famunova shopping update" ON public.shopping_items USING(public.famunova_can(group_id,'shopping.complete')) WITH CHECK(public.famunova_can(group_id,'shopping.complete'));
REVOKE UPDATE ON public.shopping_items FROM PUBLIC,anon,authenticated;
REVOKE UPDATE(id,group_id,week_start,name,done,created_by,created_at) ON public.shopping_items FROM PUBLIC,anon,authenticated;
GRANT UPDATE(done) ON public.shopping_items TO authenticated;
REVOKE UPDATE ON public.family_calendar_events FROM PUBLIC,anon,authenticated;
REVOKE UPDATE(id,group_id,title,starts_at,ends_at,kind,location,created_by,created_at) ON public.family_calendar_events FROM PUBLIC,anon,authenticated;
GRANT UPDATE(title,starts_at,ends_at,kind,location) ON public.family_calendar_events TO authenticated;
DROP POLICY IF EXISTS "Famunova calendar update" ON public.family_calendar_events;
CREATE POLICY "Famunova calendar update" ON public.family_calendar_events FOR UPDATE TO authenticated
USING(public.famunova_can(group_id,'calendar.edit_all') OR (created_by=(SELECT auth.uid()) AND public.famunova_can(group_id,'calendar.edit_own')))
WITH CHECK(public.famunova_can(group_id,'calendar.edit_all') OR (created_by=(SELECT auth.uid()) AND public.famunova_can(group_id,'calendar.edit_own')));
CREATE OR REPLACE FUNCTION public.create_family_group(p_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_group uuid; v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
 IF char_length(trim(coalesce(p_name,''))) NOT BETWEEN 1 AND 60 THEN RAISE EXCEPTION 'Invalid group name'; END IF;
 INSERT INTO public.family_groups(name,owner_id) VALUES(trim(p_name),v_user) RETURNING id INTO v_group;
 INSERT INTO public.family_memberships(group_id,user_id,role) VALUES(v_group,v_user,'owner');
 RETURN v_group;
END $$;
CREATE OR REPLACE FUNCTION public.famunova_set_member_permission(p_group uuid,p_user uuid,p_permission text,p_allowed boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group FOR UPDATE;
 IF v_owner IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Only family owner can manage permissions'; END IF;
 IF p_user IS NULL OR p_user=v_owner THEN RAISE EXCEPTION 'Invalid target or protected owner'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.family_memberships WHERE group_id=p_group AND user_id=p_user) THEN RAISE EXCEPTION 'Target user is not a group member'; END IF;
 IF p_permission IS NULL OR p_permission NOT IN ('calendar.create','calendar.edit_own','calendar.edit_all','calendar.delete_own','calendar.delete_all','shopping.add','shopping.complete','shopping.delete') THEN RAISE EXCEPTION 'Invalid permission'; END IF;
 IF p_allowed IS NULL THEN
 DELETE FROM public.famunova_member_permissions WHERE group_id=p_group AND user_id=p_user AND permission=p_permission;
 RETURN;
 END IF;
 INSERT INTO public.famunova_member_permissions(group_id,user_id,permission,allowed) VALUES(p_group,p_user,p_permission,p_allowed)
 ON CONFLICT(group_id,user_id,permission) DO UPDATE SET allowed=EXCLUDED.allowed,updated_at=now();
END $$;
CREATE OR REPLACE FUNCTION public.famunova_list_members(p_group uuid)
RETURNS TABLE(user_id uuid,role text,joined_at timestamptz) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.family_memberships m WHERE m.group_id=p_group AND m.user_id=auth.uid()) THEN RAISE EXCEPTION 'Access denied'; END IF;
 RETURN QUERY SELECT m.user_id,CASE WHEN m.user_id=g.owner_id THEN 'owner' ELSE m.role END,m.joined_at
 FROM public.family_memberships m JOIN public.family_groups g ON g.id=m.group_id WHERE m.group_id=p_group
 ORDER BY CASE WHEN m.user_id=g.owner_id THEN 0 ELSE 1 END,m.joined_at;
END $$;
CREATE OR REPLACE FUNCTION public.famunova_set_member_role(p_group uuid,p_user uuid,p_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group FOR UPDATE;
 IF v_owner IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Only family owner'; END IF;
 IF p_user IS NULL OR p_user=v_owner THEN RAISE EXCEPTION 'Protected owner'; END IF;
 IF p_role IS NULL OR p_role NOT IN ('admin','member') THEN RAISE EXCEPTION 'Invalid role'; END IF;
 UPDATE public.family_memberships SET role=p_role WHERE group_id=p_group AND user_id=p_user;
 IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.famunova_remove_member(p_group uuid,p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_owner uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
 SELECT owner_id INTO v_owner FROM public.family_groups WHERE id=p_group FOR UPDATE;
 IF v_owner IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Only family owner'; END IF;
 IF p_user IS NULL OR p_user=v_owner THEN RAISE EXCEPTION 'Protected owner'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.family_memberships WHERE group_id=p_group AND user_id=p_user) THEN RAISE EXCEPTION 'Member not found'; END IF;
 DELETE FROM public.famunova_member_permissions WHERE group_id=p_group AND user_id=p_user;
 DELETE FROM public.family_memberships WHERE group_id=p_group AND user_id=p_user;
END $$;
REVOKE ALL ON FUNCTION public.famunova_can(uuid,text),public.create_family_group(text),public.famunova_set_member_permission(uuid,uuid,text,boolean),public.famunova_list_members(uuid),public.famunova_set_member_role(uuid,uuid,text),public.famunova_remove_member(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.famunova_can(uuid,text),public.create_family_group(text),public.famunova_set_member_permission(uuid,uuid,text,boolean),public.famunova_list_members(uuid),public.famunova_set_member_role(uuid,uuid,text),public.famunova_remove_member(uuid,uuid) TO authenticated;
UPDATE public.family_memberships m SET role='owner' FROM public.family_groups g WHERE m.group_id=g.id AND m.user_id=g.owner_id AND m.role IS DISTINCT FROM 'owner';
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.family_memberships m JOIN public.family_groups g ON g.id=m.group_id WHERE m.role='owner' AND m.user_id<>g.owner_id) THEN RAISE EXCEPTION 'Invalid owner membership'; END IF;
 IF EXISTS(SELECT 1 FROM public.family_groups g WHERE NOT EXISTS(SELECT 1 FROM public.family_memberships m WHERE m.group_id=g.id AND m.user_id=g.owner_id AND m.role='owner')) THEN RAISE EXCEPTION 'Missing owner membership'; END IF;
 IF EXISTS(SELECT 1 FROM public.family_memberships WHERE role IS NULL) THEN RAISE EXCEPTION 'Missing membership role'; END IF;
END $$;
ALTER TABLE public.family_memberships ALTER COLUMN role SET NOT NULL;
ALTER TABLE public.family_memberships VALIDATE CONSTRAINT famunova_membership_role_valid;
NOTIFY pgrst,'reload schema';
COMMIT;
