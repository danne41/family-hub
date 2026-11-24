# Stage 2 — isolated Stripe integration readiness
Status: offline CI passed through a6ac195; no hosted integration deployment approved.
## Required configuration
- Confirm target is famunova-test, never production; record its project reference (not credentials).
- Confirm Stripe sandbox/test account and four configured price IDs against actual currency SEK, recurring interval and amounts 3900/39000/6900/69000 minor units.
- APP_ORIGIN must be an isolated frontend origin, never the production site.
- STRIPE_SECRET_KEY must be a test key; STRIPE_WEBHOOK_SECRET must belong to the test endpoint. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must belong to the test project. Never commit or paste secrets into chat.
- Checkout and portal authenticate users; webhook requires Stripe signature verification and must be reachable without Supabase user JWT.
## Database
Inspect existing test schema first; do not run the clean-install script on the existing stage 1 database. Apply only missing reviewed migrations in CI order 004,005,006,009–014 after explicit approval.
## Blocking issues before full integration approval
- Completed checkout reservations currently persist after cancellation, preventing a later subscription. Implement transactional consumption of a verified completed session, with regression tests.
- Verify Stripe prices against sandbox and check actual Edge Function deployment layout and JWT settings.
- Add positive signed webhook and portal integration coverage.
- Check service-role grants and paid entitlement expiration semantics.
## Integration acceptance
Test Plus and Premium, monthly and annual prices, owner-only access, separate families, duplicate delivery, portal cancellation, downgrade retention, re-subscription, and rejected live-mode events. Record actual results, not simulated results.
No production changes or external deployment without explicit approval.
