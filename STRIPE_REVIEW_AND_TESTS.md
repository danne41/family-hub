# Famunova – Stripe-granskning och migrationsgrind (utkast)

**Källor granskade:** GitHub-grenen `feature/famunova-v1`: `billing.js`, SQL 001–003 och tidigare uppladdade ZIP-källor `billing-checkout.zip`, `billing-portal-fixed.zip`, `stripe-webhook.zip`. ZIP-filerna kan avvika från driftsatta Edge Functions. Ingen ändring har driftsatts.

## Verifierade källkodsobservationer

- Checkout tar emot endast `priceId`, validerar mot en serverlista, autentiserar JWT och skapar Stripe Subscription med `supabase_user_id` i metadata. Den känner inte till familj/grupp. Nuvarande kontroll av befintligt abonnemang är per `user_id`, inte per familj.
- Portal autentiserar JWT och öppnar kundens portal utifrån `billing_customers.user_id`; saknar gruppval och avgränsning av prenumeration i portalen.
- Webhook verifierar Stripe-signatur och hanterar checkout.completed samt subscription.created/updated/deleted. Den kopplar kund till användare och upsertar prenumeration men lagrar inte `group_id` och använder inte Stripe subscription metadata för gruppval. Den har en separat kontroll/insert/update för event-id; inte en transaktionell reservation + upsert. För updated/created hämtas aktuell Stripe Subscription; deleted använder eventobjektet. Tidsordning måste testas.
- `billing.js` visar senaste abonnemang för användaren, inte familjen. Frontend-priserna får inte vara enda auktoriteten.

## Föreslaget kontrakt – ingen implementering/driftsättning ännu

1. Checkout-anrop `{groupId, priceId}`. Verifiera Supabase JWT; hämta grupp från DB; kontrollera att `owner_id === user.id`, att medlemskap finns och att priset finns i **serverns** godkända test-Price-ID-karta. Tillåt inte klienten ange `userId`, plan eller Stripe customer ID.
2. Besluta affärsregeln för flera familjer: en prenumeration per grupp; samma Stripe-kund kan ha flera prenumerationer. Ändra befintlig kontroll per användare till kontroll per grupp och skydda mot parallella Checkout-sessioner.
3. Stripe subscription metadata: `supabase_user_id`, `family_group_id`; även Checkout Session metadata för spårbarhet. `client_reference_id` kan vara user ID men räcker inte som familjekoppling.
4. Webhook: verifiera signatur och pris-ID mot serverkarta, kund→användare och familjeägande, matcha metadata med ägaren. Skriv `billing_subscriptions.group_id` via en transaktionell DB-RPC som också markerar event-id behandlat. Hantera replay, parallella leveranser, fel/retry, out-of-order och deleted. Lita inte enbart på metadata vid framtida ägarbyte.
5. Portal: verifiera ägarskap till vald grupp och relevant prenumeration. Stripe Billing Portal kan exponera samtliga kundens abonnemang; om flera grupper delar kund måste portalens användarupplevelse och rättigheter utredas innan den används för gruppspecifik hantering.
6. Planresolvern i 002 ska inte aktiveras mot produktion förrän prenumerationer har korrekt gruppkoppling, unikhet/konfliktpolicy och aktuell betalningsstatus. Pröva särskilt `past_due`, `unpaid`, trialing, avbokning, utgången period och okända pris-ID.

## SQL 003 v2 – säkerhetskorrigeringar

- Behåller överfulla befintliga grupper vid nedgradering: inga data raderas; triggern blockerar nya medlemmar när gränsen är nådd.
- Byter tabellövergripande UPDATE på shopping_items mot `UPDATE(done)` för authenticated. RLS avgör vem som får uppdatera; kolumnprivilegiet hindrar ändring av `name`. Detta behöver testas via PostgREST/Supabase JWT. En framtida redigeringsfunktion för varunamn behöver egen auktoriserad RPC.
- Idempotent triggerdefinition med DROP TRIGGER IF EXISTS före CREATE; kör inte v1 och v2 tillsammans.

## Kvarstående produktionsblockerare

- **Ingen verifierad återställningsbar backup eller separat testdatabas.**
- **Inga körda JWT-/PostgREST- eller samtidighetstester.** Testa två samtidiga olika inbjudningar med en plats kvar; ägarens första medlemskap; service-role inserts; nedgradering; ägare i flera grupper.
- **Säkerhetsgranskning:** SECURITY DEFINER-ägare och EXECUTE, GRANTs, triggerordning, deadlocks, inbjudningslås, RLS SELECT-synlighet vid UPDATE och eventuella fler vägar för medlemsändring.
- **Rättighetsmodell:** Admin-rollen är ännu inte implementerad som egen auktorisationsnivå. Ägaren har alltid full behörighet, medlem får snäva standardrättigheter och explicita undantag.
- **Stripe:** kontrollera exakt driftsatt Checkout/Portal/Webhook-kod, test-Price-ID, konfiguration och hur befintliga prenumerationer migreras. Inga hemliga nycklar ska kopieras till GitHub.
- **Migration 002:** `ADD CONSTRAINT ... NOT VALID` är inte idempotent vid omkörning. Testa ren installation och återkörning separat.

## Testordning

1. Isolerad Supabase-instans med syntetiska användare; applicera ursprungligt schema och 001, 002, **003 v2 (inte v1)**.
2. Kör `002_security_catalog_tests.sql` och `003_v2_catalog_tests.sql`.
3. JWT-integration: medlemmars läs/skriv/radera över grupper; ägare/medlem; `shopping.done` tillåten och `shopping.name` nekad; calendar delete_own/delete_all; otillåtna RPC-anrop.
4. Samtidighet: två olika invite-koder och service-role-insert, en ledig plats, exakt en lyckas; överfulla grupper behåller data men nekar nya.
5. Stripe testmode: skapa checkout för rätt/annan grupp, två grupper per ägare, webhook duplicate/reordered, cancel/downgrade, portalen.
6. Restore-test från backup, kodgranskning, separat uttryckligt produktionsgodkännande.
