# Static smoke tests; do not require Stripe credentials or a database.
from pathlib import Path
root=Path(__file__).resolve().parents[1]
checkout=(root/'functions/billing-checkout/index.ts').read_text()
portal=(root/'functions/billing-portal/index.ts').read_text()
webhook=(root/'functions/stripe-webhook/index.ts').read_text()
sql=(root/'004_stripe_event_atomic.sql').read_text()
assert 'groupId' in checkout and 'isOwner(groupId,user.id)' in checkout
assert 'family_group_id:groupId' in checkout
assert 'Multi-family portal requires review' in portal
assert 'constructEventAsync' in webhook and 'subscriptions.retrieve' in webhook
assert 'famunova_reconcile_stripe_subscription' in webhook and 'FOR UPDATE' in sql
assert 'REVOKE ALL ON FUNCTION' in sql
print('Static contract checks passed (NOT integration/security validation)')
