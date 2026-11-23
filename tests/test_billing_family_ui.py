# Static frontend contract assertions. Browser/JWT tests still required.
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'billing.js').read_text()
assert "g.owner_id===window.FH.user.id" in s
assert "Välj först vilken familjegrupp" in s
assert "chosen=null;refresh()" in s
assert "call('billing-checkout',{groupId,priceId:" in s
assert "call('billing-portal',{groupId})" in s
assert ".eq('group_id',groupId).eq('user_id',window.FH.user.id)" in s
assert "['checkout.stripe.com','billing.stripe.com'].includes(u.hostname)" in s
assert "pending=priceId" not in s
print('Billing UI static contract passed; no browser or payment tests performed')
