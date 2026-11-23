from pathlib import Path
root=Path(__file__).resolve().parents[1]
src=(root/'functions/billing-reconcile/index.ts').read_text()
sql=(root/'009_billing_reconciliation_checkpoint.sql').read_text()
assert '.order("stripe_subscription_id",{ascending:true}).limit(11)' in src
assert 'query.gt("stripe_subscription_id",cursor)' in src
assert 'const batch=(data||[]).slice(0,10)' in src
assert 'famunova_claim_reconcile_job' in src
assert 'famunova_finish_reconcile_job' in src
assert 'await finish(lastCompletedCursor,String(e))' in src
assert 'await finish(nextCursor,null)' in src
assert 'p_token:leaseToken' in src
assert 'const deadline=Date.now()+90_000' in src
assert 'if(Date.now()>=deadline)' in src
assert 'billing_reconcile_jobs' in sql
assert 'FOR UPDATE' in sql
assert "CASE WHEN p_error IS NULL THEN p_next_cursor ELSE v_job.cursor END" in sql
print("Static checkpoint contract passed; no live DB/Stripe tests")
