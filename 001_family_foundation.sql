-- Famunova v1.0 / Stage 2 / DRAFT: DO NOT RUN IN PRODUCTION.
-- Additive schema preparation only. No existing RLS policies or data are changed.
-- Apply only in an isolated Supabase test database after a verified backup.
BEGIN;

CREATE TABLE IF NOT EXISTS public.famunova_plan_limits (
  plan text PRIMARY KEY CHECK (plan IN ('free', 'plus', 'premium_family')),
  max_members integer NOT NULL CHECK (max_members BETWEEN 1 AND 10),
  max_calendars integer NOT NULL CHECK (max_calendars >= 1),
  max_shopping_lists integer,
  CHECK (max_shopping_lists IS NULL OR max_shopping_lists >= 1)
);

INSERT INTO public.famunova_plan_limits(plan,max_members,max_calendars,max_shopping_lists)
VALUES ('free',3,1,1), ('plus',6,2,5), ('premium_family',10,5,NULL)
ON CONFLICT (plan) DO NOTHING;

-- Membership role defaults preserve current membership records.
ALTER TABLE public.family_memberships
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'member';

-- Do not impose a role CHECK before existing rows and app workflows are audited.
-- Group ownership remains authoritative through family_groups.owner_id.

-- A subscription may eventually grant entitlements to one specific family group.
-- Existing subscription records remain unassigned until explicitly reconciled.
ALTER TABLE public.billing_subscriptions
  ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES public.family_groups(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS billing_subscriptions_group_idx
  ON public.billing_subscriptions(group_id);

-- New tables are private until a dedicated, tested authorization migration.
ALTER TABLE public.famunova_plan_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.famunova_plan_limits FROM anon, authenticated;

COMMIT;
