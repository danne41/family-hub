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
