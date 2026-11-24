-- FAMUNOVA clean installation candidate. EMPTY ISOLATED TEST PROJECT ONLY.
-- Never run on production or existing Famunova database.
BEGIN;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relname IN ('family_groups','family_memberships','family_invites','profiles','shopping_items','family_calendar_events','billing_customers','billing_subscriptions','billing_webhook_events','famunova_plan_limits','famunova_member_permissions')) THEN RAISE EXCEPTION 'Installation requires an empty Famunova schema'; END IF; END $$;

-- SOURCE: supabase-schema.sql blob 9a59b1c3b56585b3cca721696a68e0953a0371ed
-- Family Hub 0.3: kör i Supabase SQL Editor i ett nytt projekt.
-- Gruppmedlemskap, inga kalenderhändelser eller personuppgifter utöver auth och gruppnamn.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.family_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 60),
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.family_memberships (
  group_id uuid not null references public.family_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id,user_id)
);
create table if not exists public.family_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.family_groups(id) on delete cascade,
  code_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists family_memberships_user_idx on public.family_memberships(user_id);
create index if not exists family_invites_group_idx on public.family_invites(group_id);

alter table public.family_groups enable row level security;
alter table public.family_memberships enable row level security;
alter table public.family_invites enable row level security;

-- Endast egna medlemskapsrader kan läsas. Inga direkta skrivningar.
revoke all on public.family_groups, public.family_memberships, public.family_invites from anon, authenticated;
grant select on public.family_groups, public.family_memberships to authenticated;
create policy "Read own memberships" on public.family_memberships for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Read joined groups" on public.family_groups for select to authenticated
  using (exists (select 1 from public.family_memberships m where m.group_id=id and m.user_id=(select auth.uid())));

-- RPC: säkerhetsdefinierade funktioner skapar och ansluter grupper utan klientskrivrättigheter.
create or replace function public.create_family_group(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_group uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 1 and 60 then raise exception 'Invalid group name'; end if;
  insert into public.family_groups(name,owner_id) values(trim(p_name),auth.uid()) returning id into v_group;
  insert into public.family_memberships(group_id,user_id) values(v_group,auth.uid());
  return v_group;
end; $$;

create or replace function public.create_group_invite(p_group_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_code text;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not exists(select 1 from public.family_groups where id=p_group_id and owner_id=auth.uid()) then
    raise exception 'Only the group owner can invite';
  end if;
  v_code := upper(encode(extensions.gen_random_bytes(12),'hex'));
  insert into public.family_invites(group_id,code_hash,expires_at)
  values(p_group_id,encode(extensions.digest(v_code,'sha256'),'hex'),now()+interval '48 hours');
  return v_code;
end; $$;

create or replace function public.join_family_group(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_invite public.family_invites%rowtype;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  select * into v_invite from public.family_invites
  where code_hash=encode(extensions.digest(upper(trim(coalesce(p_code,''))),'sha256'),'hex')
    and expires_at>now() and used_at is null
  for update;
  if not found then raise exception 'Invalid or expired invite'; end if;
  -- Undvik att förbruka kod när användaren redan är medlem.
  if exists(select 1 from public.family_memberships where group_id=v_invite.group_id and user_id=auth.uid()) then
    raise exception 'Already a member';
  end if;
  insert into public.family_memberships(group_id,user_id) values(v_invite.group_id,auth.uid());
  update public.family_invites set used_at=now() where id=v_invite.id;
  return v_invite.group_id;
end; $$;

revoke all on function public.create_family_group(text) from public, anon;
revoke all on function public.create_group_invite(uuid) from public, anon;
revoke all on function public.join_family_group(text) from public, anon;
grant execute on function public.create_family_group(text) to authenticated;
grant execute on function public.create_group_invite(uuid) to authenticated;
grant execute on function public.join_family_group(text) to authenticated;


-- SOURCE: supabase-migration-0.4.sql blob 4bf80045435a5a887aae7980a08e15bb7609c89d
-- Kör EN gång i Supabase SQL Editor efter v0.3-schemat.
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 first_name text not null check (char_length(trim(first_name)) between 1 and 60),
 last_name text not null default '' check (char_length(last_name)<=60),
 color text not null default '#237b9a' check (color ~ '^#[0-9a-fA-F]{6}$'),
 updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
grant select,insert,update on public.profiles to authenticated;
create policy "Read own profile" on public.profiles for select to authenticated using (id=(select auth.uid()));
create policy "Insert own profile" on public.profiles for insert to authenticated with check (id=(select auth.uid()));
create policy "Update own profile" on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));

create table if not exists public.shopping_items (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.family_groups(id) on delete cascade,
 week_start date not null,
 name text not null check (char_length(trim(name)) between 1 and 100),
 done boolean not null default false,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 constraint shopping_monday check (extract(isodow from week_start)=1)
);
create index if not exists shopping_items_group_week_idx on public.shopping_items(group_id,week_start);
alter table public.shopping_items enable row level security;
grant select,insert,update,delete on public.shopping_items to authenticated;
create policy "Members read shopping" on public.shopping_items for select to authenticated
 using (exists(select 1 from public.family_memberships m where m.group_id=shopping_items.group_id and m.user_id=(select auth.uid())));
create policy "Members add shopping" on public.shopping_items for insert to authenticated
 with check (created_by=(select auth.uid()) and exists(select 1 from public.family_memberships m where m.group_id=shopping_items.group_id and m.user_id=(select auth.uid())));
create policy "Members edit shopping" on public.shopping_items for update to authenticated
 using (exists(select 1 from public.family_memberships m where m.group_id=shopping_items.group_id and m.user_id=(select auth.uid())))
 with check (exists(select 1 from public.family_memberships m where m.group_id=shopping_items.group_id and m.user_id=(select auth.uid())));
create policy "Members remove shopping" on public.shopping_items for delete to authenticated
 using (exists(select 1 from public.family_memberships m where m.group_id=shopping_items.group_id and m.user_id=(select auth.uid())));
-- Förhindra att en medlem flyttar inköp mellan grupper eller ändrar skapare.
create or replace function public.shopping_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if new.group_id<>old.group_id or new.created_by<>old.created_by or new.week_start<>old.week_start then
  raise exception 'Shopping ownership and week cannot be changed';
 end if;
 return new;
end; $$;
create trigger shopping_guard_update before update on public.shopping_items for each row execute function public.shopping_guard();


-- SOURCE: supabase-migration-0.6.sql blob 03122096ae05c6ee21df0ce70cf7f3b9447e15c5
-- Family Hub 0.6: delade kalenderaktiviteter. Kör EN gång efter tidigare migreringar.
create table if not exists public.family_calendar_events (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.family_groups(id) on delete cascade,
 title text not null check (char_length(trim(title)) between 1 and 120),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 kind text not null default 'calendar' check (kind in ('calendar','sport')),
 location text not null default '' check (char_length(location)<=120),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 constraint event_end_after_start check (ends_at>starts_at)
);
create index if not exists family_calendar_group_start_idx on public.family_calendar_events(group_id,starts_at);
alter table public.family_calendar_events enable row level security;
grant select,insert,delete on public.family_calendar_events to authenticated;
create policy "Members read calendar events" on public.family_calendar_events for select to authenticated using (exists (select 1 from public.family_memberships m where m.group_id=family_calendar_events.group_id and m.user_id=(select auth.uid())));
create policy "Members add calendar events" on public.family_calendar_events for insert to authenticated with check (created_by=(select auth.uid()) and exists (select 1 from public.family_memberships m where m.group_id=family_calendar_events.group_id and m.user_id=(select auth.uid())));
create policy "Members delete calendar events" on public.family_calendar_events for delete to authenticated using (exists (select 1 from public.family_memberships m where m.group_id=family_calendar_events.group_id and m.user_id=(select auth.uid())));
notify pgrst, 'reload schema';


-- SOURCE: supabase-migration-0.7-billing.sql blob 617fec5ff30006e54f36a91b9f37805c8c92ac50
-- Family Hub 0.7: Stripe billing. Run after earlier migrations.
create table if not exists public.billing_customers (
 user_id uuid primary key references auth.users(id) on delete cascade,
 stripe_customer_id text not null unique
);
create table if not exists public.billing_subscriptions (
 stripe_subscription_id text primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 stripe_customer_id text not null,
 stripe_price_id text,
 plan text not null,
 billing_interval text,
 status text not null,
 current_period_end timestamptz,
 cancel_at_period_end boolean not null default false,
 updated_at timestamptz not null default now()
);
create index if not exists billing_subscriptions_user_idx on public.billing_subscriptions(user_id);
create table if not exists public.billing_webhook_events (
 id text primary key,
 processed_at timestamptz
);
alter table public.billing_customers enable row level security;
alter table public.billing_subscriptions enable row level security;
alter table public.billing_webhook_events enable row level security;
revoke all on public.billing_customers from anon, authenticated;
revoke all on public.billing_webhook_events from anon, authenticated;
revoke all on public.billing_subscriptions from anon, authenticated;
grant select on public.billing_subscriptions to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='billing_subscriptions' and policyname='Read own subscription') then
 create policy "Read own subscription" on public.billing_subscriptions for select to authenticated using (user_id=(select auth.uid()));
 end if;
end $$;
notify pgrst,'reload schema';


-- SOURCE: 001_family_foundation.sql blob 078dd60955a557dece6c80d98e07a8d1e35980b1
-- Famunova v1.0 / Stage 2 / DRAFT: DO NOT RUN IN PRODUCTION.
-- Additive schema preparation only. No existing RLS policies or data are changed.
-- Apply only in an isolated Supabase test database after a verified backup.

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


-- SOURCE: 002_membership_permissions.sql blob f70677e1ae9897925bbb8f8047764821b1477d54
-- Famunova v1 / Migration 002 - PREPARATION ONLY
-- Requires 001_family_foundation.sql. DO NOT APPLY TO PRODUCTION.
-- No current policies, join RPCs, billing data, or grants are replaced.

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


-- SOURCE: 003_membership_rls_activation_v2.sql blob b4ab672cb47e94a77a64d3166b48b54b6bb79ef0
-- FAMUNOVA 003: ACTIVATION CANDIDATE. TEST DATABASE ONLY. DO NOT RUN IN PRODUCTION.
-- Requires 001, 002. This changes RLS and join RPC; must be reviewed and tested.
-- IMPORTANT: refuses activation when legacy active paid subscriptions remain unlinked.
-- Existing over-cap families retain data but cannot add members until below cap.

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
 -- Existing over-cap groups are preserved; new admissions are blocked by the trigger.
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
DROP TRIGGER IF EXISTS famunova_membership_capacity_before_insert ON public.family_memberships;
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

-- Restrict direct client UPDATE to done only. RLS controls WHO; column grants control WHAT.
-- Do not grant table-wide UPDATE back to authenticated in subsequent migrations.
REVOKE UPDATE ON public.shopping_items FROM authenticated;
GRANT UPDATE (done) ON public.shopping_items TO authenticated;
-- Existing shopping_guard remains active and protects group_id, creator, and week.
-- Explicit name editing, if desired, needs a separate audited permission/RPC.
NOTIFY pgrst,'reload schema';


-- SOURCE: 003b_membership_test_hardening.sql blob 1cc8d03a01c579606f9017d60695862fff4d7373
-- TEST ONLY. Apply after 003_membership_rls_activation_v2.sql.
-- Consolidates test changes through step 74. Clean installation not yet verified.

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


-- Normalize client grants regardless of Supabase default privileges.
REVOKE ALL ON public.family_groups,public.family_memberships,public.family_invites,public.profiles,public.shopping_items,public.family_calendar_events,public.billing_customers,public.billing_subscriptions,public.billing_webhook_events,public.famunova_plan_limits,public.famunova_member_permissions FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.family_groups,public.family_memberships,public.billing_subscriptions TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.profiles TO authenticated;
GRANT SELECT,INSERT,DELETE ON public.shopping_items,public.family_calendar_events TO authenticated;
GRANT UPDATE(done) ON public.shopping_items TO authenticated;
GRANT UPDATE(title,starts_at,ends_at,kind,location) ON public.family_calendar_events TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'PASS: Installation completed' AS result;
