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
