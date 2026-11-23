# Famunova billing-reconcile – TEST ONLY

The Edge Function `functions/billing-reconcile/index.ts` provides an **on-demand
batch check** for at most 25 subscription rows **already in the database**.
It does not automatically run on a schedule and cannot discover a subscription
whose initial webhook never created a database row.

## Required test configuration
- Separate Supabase test project and Stripe **test mode** secret.
- Migration 008 applied after earlier draft migrations.
- `BILLING_RECONCILE_TOKEN`: random private secret of at least 32 characters,
  held only by the server/scheduler; never place in browser code.
- Test Edge Function deployment must be explicitly approved. For custom bearer
  authentication, Supabase gateway JWT verification must be configured appropriately
  for this function, with the server-side token check remaining mandatory.
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`,
  and `APP_ORIGIN` point **only** at test resources.
- The function returns 503 if any row fails, so a caller can retry.

## Important gaps before any deployment
- No scheduler has been connected. A separate approved scheduled invocation is needed.
- Batch always selects oldest updated rows; if there are more than 25, newer
  subscriptions may never be reached. Implement cursor/pagination and persistent
  per-row retry state before scheduled use.
- Deletion/retrieval failure remains unresolved and requires Stripe deleted-event
  fallback verified against Stripe API.
- A missing initial webhook cannot be recovered by this DB-only scan; a Stripe
  subscription-list sweep with strict customer and group checks is required.
- Application timestamps are not an absolute cross-instance ordering guarantee.
- An attacker with the scheduler token can invoke service-role operations; protect
  the token, restrict network exposure and rotate it on compromise.
- Static code review is not integration testing.

**Do not deploy this draft to production.**
