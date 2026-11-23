# Famunova 002 – testplan och aktiveringsgrind

**Status:** Förberedelseutkast. Kör inte i produktion. Migrering 001 måste köras först i en isolerad testdatabas.

## Varför 002 inte aktiverar behörigheter

De befintliga kalender- och inköpspolicyerna ger fortfarande breda rättigheter till gruppmedlemmar. Den nya tabellen är låst och är ännu inte kopplad till RLS. Detta är avsiktligt: inga användare ska tappa åtkomst innan ägarstyrda RPC-funktioner och regressionstester är färdiga.

`famunova_assert_member_capacity_internal` är en intern byggsten. Den används **inte** av befintliga `join_family_group`. En senare aktiveringsmigrering måste anropa den inom samma transaktion, och varje väg som skapar medlemskap måste använda samma grupplås. Ingen ny medlemsgräns är aktiv ännu.

`famunova_group_plan_internal` är fail-closed: oidentifierade, obetalda, okopplade eller tvetydiga abonnemang räknas som Free. Innan aktivering måste historiska prenumerationer kopplas till rätt familjegrupp och verifieras.

## Testmatris för isolerad testmiljö

1. Kör 001, därefter 002, sedan `002_security_catalog_tests.sql`. Verifiera RLS och att internfunktionerna inte är tillgängliga via `authenticated`.
2. Kör gamla appflöden: skapa grupp, skapa inbjudan, gå med, kalender, inköp. Inga nya RLS-regler ska påverka dem.
3. Bekräfta att befintliga medlemsroller är bevarade och att ägaren fortfarande identifieras via `family_groups.owner_id`.
4. Testa planresolver med ingen prenumeration, okänt pris/plan, `past_due`, `canceled`, `active`, `trialing`, två aktiva prenumerationer och prenumeration där `user_id` inte är gruppägaren. Endast exakt en verifierad aktiv/trialing prenumeration för ägaren och gruppen ska ge betald plan.
5. Efter separat aktiveringsmigrering: testa Free 3→4, Plus 6→7, Premium 10→11; kontrollera även två samtidiga inbjudningar med **olika** giltiga koder.
6. Efter aktivering: testa roll- och behörighetseskalering, medlem i flera grupper, direkt REST-skrivning, ägarbyte och nedgradering utan dataradering.
7. Testa återställning från en faktisk backup i en isolerad databas före produktionsgodkännande.

## Säkerhetsgrindar

- Bekräfta faktisk backup och restore-test.
- Granska verkliga triggers, GRANT, constraints och databasens befintliga medlemsantal.
- Granska webhook/Checkout och koppla varje betald prenumeration till exakt en ägd grupp.
- Inför ägarstyrda behörighets-RPC:er, RLS-ersättning och medlemskapsspärr som separat migrering 003.
- Kör end-to-end-test med två autentiserade användare och samtidighetsprov innan aktivering.

**Ingen del av 002 ger i sig säker individuell kalender- eller inköpsbehörighet.**
