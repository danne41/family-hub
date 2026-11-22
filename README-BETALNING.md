# Family Hub 0.7 – Stripe testbetalningar

Detta paket är kod för `Develope`, INTE en driftsatt Stripe-koppling. Ändra inte `main`. `config.js` i paketet är en platshållare; behåll din fungerande version.

## Steg 1: Supabase SQL Editor
Kör `supabase-migration-0.7-billing.sql` efter tidigare migreringar.

## Steg 2: Supabase Edge Functions
Skapa tre funktioner med exakt namnen `billing-checkout`, `billing-portal`, `stripe-webhook` och respektive `index.ts`. Funktionerna importerar `_shared/common.ts` – deploya med Supabase CLI så att mappstrukturen följer med. Enklast via dator/terminal med Supabase CLI:

```
supabase login
supabase link --project-ref DIN_PROJEKTREFERENS
supabase functions deploy billing-checkout --no-verify-jwt
supabase functions deploy billing-portal --no-verify-jwt
supabase functions deploy stripe-webhook --no-verify-jwt
```

**Viktigt:** `billing-checkout` och `billing-portal` har egen server-side tokenvalidering via `auth.getUser(token)` och strikt Origin-kontroll. `--no-verify-jwt` behövs för kompatibilitet med Supabase publishable-nycklar. `stripe-webhook` är publik men verifierar Stripe-signatur.

## Steg 3: Supabase Edge Function Secrets
Ange direkt i Supabase Dashboard → Edge Functions → Secrets (ALDRIG i GitHub eller ChatGPT):

- `STRIPE_SECRET_KEY` = din `sk_test_...`
- `STRIPE_WEBHOOK_SECRET` = din webhook-signaturhemlighet `whsec_...` (efter steg 4)
- `APP_ORIGIN` = exakt ursprung för din testapp, t.ex. `https://DIN-PREVIEW.pages.dev` (utan avslutande `/`)

Supabase tillhandahåller normalt `SUPABASE_URL` och `SUPABASE_SERVICE_ROLE_KEY` till Edge Functions; kontrollera miljön. Ge aldrig ut dessa.

## Steg 4: Stripe Dashboard (testläge)
Skapa webhook destination: `https://DIN-PROJEKTREFERENS.supabase.co/functions/v1/stripe-webhook`.
Välj händelser:
- `checkout.session.completed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`

Spara endpointens `whsec_...` som `STRIPE_WEBHOOK_SECRET` i Supabase.
Aktivera Stripe Customer Portal i testläget för hantering av betalningsmetoder och uppsägning.

## Steg 5: GitHub Develope
Ladda upp ändrade `index.html`, `billing.js`, `sw.js` samt Edge Functions-mappen och SQL/README till `Develope`. Behåll din riktiga `config.js` och dina andra appfiler. Uppdatera inte `main`.

## Steg 6: Test
1. Logga in på preview-URL och välj Plus månad.
2. Betala med Stripes testkort enligt Stripe Dashboard. Kontrollera att webhooken har levererats.
3. Kontrollera `billing_subscriptions` i Supabase och status under Min profil.
4. Öppna Hantera abonnemang och testa uppsägning. Verifiera webhookens uppdatering.
5. Testa Premium Family och årspriser separat.

**Begränsningar:** Detta är testbetalning och abonnemangssynk. Premium-rättigheter är ännu INTE kopplade till skyddade funktioner och gruppval/sexpersonsgräns är inte implementerad. Publicera inte som betald tjänst förrän serverkontrollerad åtkomst, familjegruppstilldelning, villkor och sluttester är klara. För Apple Pay visas knappen automatiskt av Stripe Checkout när användarens miljö stöder det.
