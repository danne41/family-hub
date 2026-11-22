# Family Hub 0.8 – visuell uppdatering
- Samma varma, ljusa färgtema i den inloggade appen som på landningssidan.
- Ny menypunkt: Priser & abonnemang (fungerar även inloggad).
- Ny synlig knapp: Logga ut.
- Befintliga funktioner, Supabase-kopplingar, Edge Functions och SQL-filer finns kvar.
- Stripe är fortsatt i testläge. Inga riktiga betalningar ska göras.

## Installera
1. Öppna grenen `Develope` i GitHub (inte `main`).
2. Ersätt befintliga filer med innehållet i denna ZIP. Behåll mappstrukturen, särskilt `supabase/functions`.
3. Vänta på Cloudflare Pages preview-deploy och uppdatera sidan i Safari.
4. Testa logga in, välj `Priser & abonnemang`, öppna `Min profil` och tryck `Logga ut`.
5. Ingen ny SQL-migrering behövs för just denna visuella version.

Obs: Funktionerna för Stripe-portal och checkout behöver fortfarande felsökas separat om fel uppstår.
