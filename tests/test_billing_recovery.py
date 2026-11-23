from pathlib import Path
root=Path(__file__).resolve().parents[1]
webhook=(root/'functions/stripe-webhook/index.ts').read_text()
checkout=(root/'functions/billing-checkout/index.ts').read_text()
reconcile=(root/'functions/billing-reconcile/index.ts').read_text()
assert '\\n  const observedAt' not in webhook
assert 'Object.hasOwn(priceMap,item.price.id)' in webhook
assert 'Object.hasOwn(priceMap,priceId)' in checkout
assert 'BILLING_RECONCILE_TOKEN' in reconcile
assert '.limit(25)' in reconcile
assert 'famunova_reconcile_stripe_subscription' in reconcile
assert 'status:failed?503:200' in reconcile
print('Static recovery contract checks passed; no live tests performed')
