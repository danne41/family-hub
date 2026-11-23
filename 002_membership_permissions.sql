-- Famunova v1 / Migration 002 - PREPARATION ONLY
-- Requires 001_family_foundation.sql. DO NOT APPLY TO PRODUCTION.
-- No current policies, join RPCs, billing data, or grants are replaced.
BEGIN;

-- Roles are administrative; age presets will be handled separately in the app.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.family_memberships WHERE role NOT IN ('owner','admin','member')) THEN
    RAISE EXCEPTION 'Unexpected membership role: review existing records before migration';
  END IF;
END $$;
ALTER TABLE public.family_memberships
  ADD CONSTRAINT famunova_membership_role_valid
  CHECK (role IN ('owner','admin','member')) NOT VALID;
-- Do not change existing role values; owner is still determined by family_groups.owner_id.

CREATE TABLE IF NOT EXISTS public.famunova_member_permissions (
  group_id uuid NOT NULL,
  user_id uuid NOT NULL,
  permission text NOT NULL CHECK (permission IN (
    'calendar.create','calendar.edit_own','calendar.edit_all','calendar.delete_own','calendar.delete_all',
    'shopping.add','shopping.complete','shopping.delete',
    'chores.create','chores.assign','chores.complete_assigned','chores.manage',
    'members.invite','members.manage'
  )),
  allowed boolean NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id,user_id,permission),
  FOREIGN KEY (group_id,user_id) REFERENCES public.family_memberships(group_id,user_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS famunova_member_permissions_user_idx
  ON public.famunova_member_permissions(user_id,group_id);
ALTER TABLE public.famunova_member_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.famunova_member_permissions FROM PUBLIC, anon, authenticated;
-- No direct client grants or policies yet: a later migration will add audited owner-controlled RPCs.

-- Read-only internal entitlement resolver. Unknown, unlinked, or ambiguous subscriptions -> Free.
-- SECURITY DEFINER avoids depending on caller's subscription RLS.
CREATE OR REPLACE FUNCTION public.famunova_group_plan_internal(p_group_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_plan text; v_count integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.family_groups WHERE id = p_group_id) THEN
    RETURN 'free';
  END IF;
  SELECT count(*), max(s.plan) INTO v_count,v_plan
  FROM public.billing_subscriptions s
  JOIN public.family_groups g ON g.id=s.group_id AND g.owner_id=s.user_id
  WHERE s.group_id=p_group_id AND s.status IN ('active','trialing')
    AND s.plan IN ('plus','premium_family');
  IF v_count <> 1 THEN RETURN 'free'; END IF;
  RETURN v_plan;
END; $$;
REVOKE ALL ON FUNCTION public.famunova_group_plan_internal(uuid) FROM PUBLIC, anon, authenticated;

-- This function is NOT wired into join_family_group until Stripe group mapping is verified.
-- Lock the group row to serialize all admissions using this function.
CREATE OR REPLACE FUNCTION public.famunova_assert_member_capacity_internal(p_group_id uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_plan text; v_max integer; v_current integer;
BEGIN
  PERFORM 1 FROM public.family_groups WHERE id=p_group_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown family group'; END IF;
  v_plan := public.famunova_group_plan_internal(p_group_id);
  SELECT max_members INTO v_max FROM public.famunova_plan_limits WHERE plan=v_plan;
  IF v_max IS NULL THEN RAISE EXCEPTION 'Plan limits not configured'; END IF;
  SELECT count(*) INTO v_current FROM public.family_memberships WHERE group_id=p_group_id;
  IF v_current >= v_max THEN RAISE EXCEPTION 'Family member limit reached for plan %',v_plan; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.famunova_assert_member_capacity_internal(uuid) FROM PUBLIC, anon, authenticated;

COMMIT;
