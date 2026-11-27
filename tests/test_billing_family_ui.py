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
assert "groups.length===1?groups[0].id:null" in s
assert "groups.some(g=>g.id===previous)" in s
assert "active.length>1" in s
assert "['active','trialing'].includes(s.status)" in s
assert "label==='Plus'?6:label==='Premium Family'?10:3" in s
assert "annual?390:39" in s and "annual?690:69" in s
assert "sub.cancel_at_period_end?'Avslutas: '" in s
assert "seq!==statusSequence||chosen!==groupId" in s
assert "profile.prepend(card)" in s
print('Billing UI static contract passed; no browser or payment tests performed')
