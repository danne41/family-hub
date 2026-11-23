# Famunova 003 – review gates and test plan

**DRAFT / NOT PRODUCTION READY.** Run only in a disposable isolated database with synthetic test users and after 001 + 002. SQL 003 is an activation candidate, not an approved production migration.

## Stripe dependency (verified from repo)
- `billing.js` sends only `{priceId}` to `billing-checkout`; no family `group_id` is supplied.
- `billing.js` shows the latest subscription by `user_id`, not by selected family group.
- 001 adds nullable `billing_subscriptions.group_id`, but does not populate it.
- 002 treats unknown, unlinked, ambiguous, or invalid paid subscriptions as Free.
- The repository's billing migration does not enforce uniqueness of an active subscription per group or ownership alignment. The frontend price IDs are not a server-side authorization source.

**Before activation:** inspect the *deployed* Edge Functions (checkout, webhook, portal) and Stripe test-mode Price IDs, add verified group ownership to checkout, bind group ID to Stripe metadata, validate metadata and price IDs server-side in webhook, ensure idempotent writes and handle lifecycle updates/out-of-order events. Reconcile existing paid subscriptions. Never assume one user owns only one family group.

## Mandatory security/integration tests
1. Test clean install 001→002→003 with synthetic auth users and service role; verify no schema errors.
2. Free group: owner + 2 members succeeds, fourth rejected. Plus: sixth succeeds, seventh rejected. Premium: tenth succeeds, eleventh rejected. Include owner in count.
3. Race: two distinct invite codes, two authenticated users joining simultaneously when one slot remains; exactly one succeeds. Test direct service-role membership inserts racing with join.
4. Existing group over cap / active paid subscription with NULL group ID: 003 must refuse activation without modifying state.
5. Member cannot call owner permission RPC to grant themselves rights, cannot edit another member's rights, cannot mutate permission table directly. Owner can grant/revoke only for a member in their own group.
6. Member cannot delete another member's calendar event unless explicit `calendar.delete_all` grant; can delete own with default; cannot create with revoked permission.
7. Member can add/complete shopping by default, cannot delete without grant. **KNOWN GAP:** shopping UPDATE policy permits name edits too. Fix before production.
8. Member in group A cannot read/write group B; owner of A has no authority over B.
9. Validate no new calendar UPDATE permission is assumed: existing schema lacks UPDATE grant and policy.
10. Verify downgrade never deletes data; over-cap group keeps records but cannot admit new members. Review billing expiry and trialing rules.
11. Test auth and RLS through actual Supabase client JWTs, not just SQL Editor/service-role sessions.
12. Run `003_security_tests.sql` after migration and inspect GRANTs, policies, triggers, constraints. Restore backup in isolated environment.

## Review blockers before production
- The 003 preflight rejects any over-cap existing group, which conflicts with a non-destructive downgrade if activated against already-over-cap families. Decide migration/activation policy separately.
- Current shopping UPDATE cannot distinguish toggling `done` from editing `name` through RLS alone. Need a protected RPC or column-specific privileges.
- `famunova_group_plan_internal` treats `active` and `trialing` as paid and does not independently validate Stripe price IDs or period end. This requires webhook/server-side integrity and business-rule review.
- 002 has a `NOT VALID` role CHECK and existing role values may be `member` for owner; owner authority must continue to use `family_groups.owner_id`.
- Validate deadlock/lock behavior under concurrency, and review other membership mutation paths, SECURITY DEFINER ownership, function EXECUTE privileges, and group owner consistency.
- Explicit approval required for any production SQL, Stripe or Cloudflare changes.
