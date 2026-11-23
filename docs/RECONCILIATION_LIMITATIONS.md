# Current-state reconciliation – limitations and next gate
Development branch only. No SQL has been executed.

Migration 008 replaces event.created ordering with a timestamp captured immediately
before retrieving current subscription state from Stripe. This avoids the known
same-second event.created collision and orders concurrent observations by start time.

It is **not** a complete reconciliation worker:
- A webhook can fail permanently if Stripe cannot retrieve a deleted subscription.
- Network delay, clock skew across Edge instances and Stripe consistency can still
  cause unexpected ordering. The observation clock is application-side.
- A new subscription can be created during a pending Checkout reservation before
  the webhook arrives. Database-only admission does not guarantee Stripe-side uniqueness.
- Missing webhooks are not recovered without scheduled Stripe polling or event replay.
- Stripe customer-wide portal must be reviewed for multiple owned families.
- RPC privileges, function ownership, migrations, and real JWT/RLS behavior are untested.
- Tests remain static; no test DB, Stripe test payment or deployment was executed.

Before production, implement a server-owned reconciliation queue or scheduled sweep
with retry/backoff, deletion fallback, group locking, and Stripe-side subscription
checks. Test duplicates, same-second events, parallel fetches, cancellation,
upgrade/downgrade, failed payments and multi-family owners in isolated services.
