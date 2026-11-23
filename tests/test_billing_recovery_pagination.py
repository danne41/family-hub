from pathlib import Path
root=Path(__file__).resolve().parents[1]
src=(root/'functions/billing-reconcile/index.ts').read_text()
assert '.order("stripe_subscription_id",{ascending:true}).limit(26)' in src
assert 'query.gt("stripe_subscription_id",cursor)' in src
assert 'const batch=(data||[]).slice(0,25)' in src
assert 'nextCursor,hasMore' in src
assert 'status:failed?503:200' in src
assert 'updated_at",{ascending:true}' not in src
print("Static pagination contract passed; no live Stripe or DB tests")
