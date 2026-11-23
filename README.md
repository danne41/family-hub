# Famunova – Stripe familjeabonnemang, Etapp 2 (UTKAST)

**ENDAST utvecklingsgren och isolerad testmiljö. INGEN produktionsdriftsättning.**

## Källunderlag
Granskat ursprungliga uppladdade ZIP-filer: `billing-checkout.zip`, `billing-portal-fixed.zip`, `stripe-webhook.zip` (index.ts), samt GitHub `billing.js`, `001`, `002`, `003 v2` och ursprungligt billing-schema på `feature/famunova-v1`. ZIP-versioner kan skilja sig från Supabases driftsatta funktioner.

## Filer
- `functions/_shared/billing.ts`: gemensam testprislista, JWT, ägarskapskontroll, CORS.
- `functions/billing-checkout/index.ts`: `{groupId,priceId}`, verifierad ägare, Stripe-metadata.
- `functions/billing-portal/index.ts`: verifierad ägare; blockerar flerfamiljskunder tills portalens kundomfattande beteende beslutats.
- `functions/stripe-webhook/index.ts`: signaturkontroll, hämtar aktuellt abonnemang från Stripe, atomär RPC.
- `004_stripe_event_atomic.sql`: transaktionell webhook-uppdatering och deduplicering; **endast testdatabas**.
- `tests/test_contract.py`: statiska kontraktstester.

## Kritiska återstående risker / produktionsblockerare
1. **Checkout race:** två parallella Checkout-sessioner kan skapas för samma grupp innan webhooken skriver till databasen. Inför server-side reservations-/pending-checkout-tabell med unik gruppnyckel och utgångstid, eller Stripe-avstämning. SQL-RPC vägrar konkurrerande aktiva prenumerationer men kan inte förhindra dubbla Stripe-debiteringar.
2. **Stripe webhook aktuell status:** att hämta aktuell Stripe-prenumeration minskar out-of-order-risk, men ett äldre svar kan fortfarande komma fram efter ett nyare svar. Inför monotont versions-/händelsevillkor eller per-subscription serialiserad Stripe-avstämning. Testa deleted/terminal state.
3. **Price ID och metadata:** pris-ID är hämtade från tidigare testkod. Validera dem mot testkontot och serverkonfiguration. En webhook måste inte lita enbart på metadata från Stripe utan måste verifiera kund- och gruppägande; SQL-RPC gör extra kontroller.
4. **Rättighetsgräns:** RPC har EXECUTE återkallat från PUBLIC/anon/authenticated, men `service_role` kan fortfarande vara behörig via privilegierad kontext. Audit av funktionens ägare, API-exponering och dedikerad serverroll behövs.
5. **Portal:** Stripe Portal är kundomfattande. Denna prototyp nekar kunder med prenumerationer i flera grupper, men det finns andra gränsfall (okopplade abonnemang). Ingen portal bör aktiveras innan det är utrett.
6. **Frontend:** `billing.js` måste ändras så att familjeägaren väljer grupp, skickar `{groupId,priceId}` och visar abonnemang per grupp. Detta paket ändrar inte befintlig frontend.
7. **Databasmigreringar:** `001`, `002`, `003 v2` är ännu inte testade eller körda i separat Supabase-instans. SQL 004 är beroende av 001.
8. **Tester:** inga körda Stripe-testbetalningar, riktiga JWT-test, samtidighetsprov eller DB-integrationstester. Återställningsbar backup och testprojekt krävs.

## Testplan
- Kör statiskt test: `python tests/test_contract.py`.
- I **separat Supabase-testprojekt**: installera bas-schema + 001, 002, 003 v2, 004; testa behörigheter och RPC via autentiserad JWT och service roll.
- Testa användare A som äger grupp X och Y: Plus för X får inte ge Plus till Y. Användare B får inte skapa Checkout för X.
- Testa webhook: giltig/ogiltig signatur, duplicerat event-ID, parallella event, äldre event, okänd pris-ID, fel kund, fel ägare, annan grupp, deleted/canceled, periodslut.
- Testa två samtidiga Checkout-anrop för samma grupp, se att detta **ännu är ett känt gap**.
- Testa att portal inte visar eller kan ändra fel familjs prenumeration.
- Besluta och testa historiska abonnemangs koppling till familjer; ingen automatisk gissning.

**Ändra aldrig produktionsdatabas, Stripe eller Cloudflare utan nytt uttryckligt godkännande.**
