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
