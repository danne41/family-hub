# Famunova – Etapp 2 (förberedelser)

**Status: utkast. Kör inte SQL mot produktionsdatabasen.**

## Bekräftad utgångspunkt

- Basgren: `Develope`; isolerad utvecklingsgren: `feature/famunova-v1`.
- Befintlig SQL: `supabase-schema.sql`, migreringarna 0.4, 0.6 och 0.7.
- Beslutade medlemsgränser inklusive ägare: Free 3, Plus 6, Premium Family 10.
- Stripe-priser och gruppkoppling måste valideras mot serverkonfiguration före aktivering.

## Fil 001_family_foundation.sql

En **additiv** förberedelse som skapar en tabell för planbegränsningar, lägger till en medlemsroll med standardvärde och en valfri gruppreferens på befintliga prenumerationer. Den **inför ännu inte** nya RLS-policyer, medlemsgränser eller abonnemangsbehörigheter. `group_id` är avsiktligt nullable så att äldre abonnemang inte felaktigt kopplas till en familj.

## Kvar före körning

1. Verifiera återställningsbar Supabase-backup och testa återställning i isolerad miljö.
2. Granska aktuella GRANT, triggers, constraints och befintliga abonnemangsdata.
3. Testa migrering 001 i en separat databas och verifiera att tidigare flöden fungerar.
4. Bygg senare en atomär medlemsgränskontroll i `join_family_group` med grupplås och serverhärledda entitlements.
5. Bygg familjeanknuten Checkout/webhook med idempotens, rätt pris-ID och konsekvent status.
6. Lägg till individuella behörigheter och RLS först efter regressionstester.
7. Ingen produktionsdriftsättning eller Stripe-ändring utan uttryckligt godkännande.

## Viktig designfråga

En person kan äga flera grupper. Ett betalt abonnemang ska bara gälla en uttryckligt vald grupp. Äldre prenumerationer måste därför mappas manuellt eller via ett verifierat migreringsflöde; gissa aldrig grupp utifrån användar-ID.
