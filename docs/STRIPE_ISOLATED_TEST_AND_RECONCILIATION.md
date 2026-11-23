# Famunova – isolerad testmiljö och Stripe-avstämning

**ENDAST utvecklingsgrenen `feature/famunova-v1`.** Denna guide utför inga externa ändringar.

## Identifierad risk
Webhook läser aktuell Stripe-subscription och skriver med tidsstämpeln från **händelsen**.
Om ett gammalt event anländer sent, men Stripe-objektet är nytt, kan en korrekt
aktuell status sparas med en gammal tidsstämpel. Om två events har samma
`event.created` sekund kan en senare ändring hoppas över. Det går därför inte
att påstå att migration 006 ensam ger korrekt ordning.

Även 004-funktionen är fortfarande exekverbar för service_role och kan kringgå
ordningskontrollen. Inför driftsättning krävs att den gamla funktionen spärras
och att en säker avstämningsmekanism är klar.

## Föreslagen avstämning (ej implementerad)
1. En serverstyrd, autentiserad kö tar emot verifierade Stripe-event.
2. För varje subscription-ID: lås den tillhörande familjens DB-rad, hämta
   **aktuell** subscription från Stripe och verifiera kund, ägare, pris och grupp.
3. Uppdatera DB i en transaktion; använd en separat reconciliation-version
   eller låssekvens, inte `event.created` som källa till ordningen för ett
   nyhämtat Stripe-objekt.
4. Om Stripe-hämtning misslyckas: behåll uppdraget för retry, ge inte felaktigt
   lyckat svar. Logga bara säkra tekniska ID:n.
5. För terminala subscription-objekt och `customer.subscription.deleted`:
   verifiera hur Stripe API svarar efter radering; tillåt inte gamla
   events att återaktivera en avslutad subscription.
6. Kontrollera att en familj bara har en aktuell betalningsrelation och att
   reservationen från 005 hanteras vid utgång, avbrott och lyckad betalning.

## Isolerat Supabase-testprojekt (kräver separat beslut)
- Skapa **nytt** Supabase-projekt utan produktionsdata, separata API-nycklar.
- Lägg in enbart syntetiska användare, familjer och medlemskap.
- Kör baseline SQL i ordning: `supabase-schema.sql`, `supabase-migration-0.4.sql`,
  `supabase-migration-0.6.sql`, `supabase-migration-0.7-billing.sql`;
  verifiera övriga beroenden från repot före körning.
- Kör sedan 001, 002, 003 v2, 004, 005 och 006 **i isolerad testdatabas**.
- Kör `tests/007_billing_catalog_checks.sql`. Detta är endast katalogkontroll.
- Konfigurera separata Stripe **test mode**-produkter och pris-ID:n; verifiera
  att kodens allowlist matchar dessa ID:n innan några funktioner används.
- Använd en separat test-origin och Edge Function-miljö; produktionsnycklar får
  aldrig återanvändas.

## Obligatoriska integrationstester före eventuell driftsättning
- Ägare A med familj X och Y: betalning i X får aldrig ändra Y.
- Medlem som inte är ägare nekas Checkout/Portal.
- Två samtidiga Checkout-anrop till X: exakt en reservation.
- Session avbryts, går ut eller Stripe timeout: kan säkert försöka igen.
- Webhook duplicate, sent event, samma sekund, deleted, uppgradering,
  downgrade, past_due och återaktivering.
- Två abonnemang med samma Stripe-kund men olika familjer: portalens
  kundomfattning och spärr måste testas.
- RLS med riktiga användar-JWT, inte bara service_role.
- Verifiera backup/återställning och att inga ändringar rör produktionsmiljön.

## Stoppskyltar
Inga SQL-migrationer eller Edge Functions i produktion. Nuvarande webhook är
**utkast**, inte säker för driftsättning. Statiska tester bevisar inte korrekt
beteende under samtidighet eller i Stripe.
