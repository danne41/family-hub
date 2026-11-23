# Etapp 2 – Checkout race hardening (utkast)
Branch: feature/famunova-v1. No production changes.

## New files and behavior
- 005_checkout_reservation.sql: locks the family row and reserves a single pending Checkout per family for 35 minutes.
- functions/billing-checkout/index.ts: reserves before calling Stripe; uses unique Stripe idempotency key, 30-minute Stripe session expiration.
- tests/test_checkout_reservation.py: static checks only.

## Important remaining work
- Webhook monotonicity remains unresolved: current retrieval of Stripe state does NOT guarantee ordered database updates. Do not deploy.
- Reservation cleanup/reconciliation and Stripe-session creation failure handling need integration tests. A failed Stripe call leaves reservation until expiry.
- A 35-minute reservation can expire before webhook reconciliation; block any new session if Stripe has a live subscription. Implement reconciliation before deployment.
- A Stripe customer creation and billing_customers upsert happen before reservation; test concurrent first-time customers and Stripe idempotency.
- Check whether the deployed Supabase functions and Stripe test Price IDs match source.
- Test two simultaneous requests from separate sessions; exactly one should acquire reservation. Test expiry, checkout cancel, network failure, webhook delay and retry.
- Validate Postgres privileges and RPC exposure in isolated test project. No production SQL migrations.
