# Static checks only; DB concurrency and Stripe test-mode integration remain mandatory.
from pathlib import Path
root=Path(__file__).resolve().parents[1]
checkout=(root/'functions/billing-checkout/index.ts').read_text()
sql=(root/'005_checkout_reservation.sql').read_text()
assert 'famunova_reserve_checkout_internal' in checkout
assert checkout.index('famunova_reserve_checkout_internal') < checkout.index('checkout.sessions.create')
assert 'idempotencyKey:`famunova-checkout-' in checkout
assert 'expires_at:Math.floor(Date.now()/1000)+1800' in checkout
assert 'FOR UPDATE' in sql
assert 'group_id uuid PRIMARY KEY' in sql
assert 'REVOKE ALL ON FUNCTION' in sql
print('Reservation static checks passed; no real Stripe/DB tests performed')
