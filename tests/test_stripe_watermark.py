# Static contract checks. Not a substitute for a live database or Stripe integration.
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sql=(root/'006_stripe_event_watermark.sql').read_text()
webhook=(root/'functions/stripe-webhook/index.ts').read_text()
assert 'stripe_event_created bigint' in sql
assert 'p_event_created<=v_previous.stripe_event_created' in sql
assert 'FOR UPDATE' in sql
assert "RETURN 'stale'" in sql
assert 'p_observed_at:observedAt' in webhook
assert 'famunova_reconcile_stripe_subscription' in webhook
print('Watermark static checks passed; DB/Stripe integration NOT run')
