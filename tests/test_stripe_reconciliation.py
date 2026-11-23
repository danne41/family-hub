# Static review of current-state reconciliation. No DB or Stripe connection.
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sql=(root/'008_stripe_current_state_reconciliation.sql').read_text()
webhook=(root/'functions/stripe-webhook/index.ts').read_text()
assert 'stripe_observed_at timestamptz' in sql
assert 'p_observed_at<=v_old.stripe_observed_at' in sql
assert "RETURN 'stale_observation'" in sql
assert 'FOR UPDATE' in sql
assert 'famunova_apply_stripe_event_v2' in sql and 'FROM service_role' in sql
assert 'const observedAt=new Date().toISOString();' in webhook
assert webhook.index('const observedAt=') < webhook.index('subscriptions.retrieve(subscriptionId)')
assert 'famunova_reconcile_stripe_subscription' in webhook
assert 'p_observed_at:observedAt' in webhook
print('Static reconciliation checks passed; NOT live integration tests')
