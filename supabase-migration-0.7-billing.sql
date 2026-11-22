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
