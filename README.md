# Family Hub 0.5 – landningssida och prisplaner

## Nytt
- Publik responsiv startsida med funktioner, interaktiv demokalender och demolista.
- Inloggning och registrering i dialog från startsidan, med befintlig Supabase Auth.
- Prisnivåer (förslag): Free 0 kr, Plus 39 kr/mån, Premium Family 69 kr/mån.
- Årspriser i jämförelsen: Plus 390 kr, Premium Family 690 kr (förslag).
- Premium Family-modell: abonnemang på person, förmåner för betalaren och högst fem inbjudna i EN vald familjegrupp.
- Inga annonser, betalningar eller verkliga abonnemang aktiverade. Knapparna för betalnivåerna markerar att de kommer senare.

## Installera
1. Packa upp och ladda upp appfilerna till GitHub-grenen `Develope`.
2. BEHÅLL den fungerande `config.js` från ditt repo (ZIP innehåller endast en platshållare).
3. Kontrollera att Supabase-migrationen för v0.4 redan körts.
4. Testa Cloudflare-förhandsversionen på mobil och dator, inklusive inloggning och befintliga appfunktioner.
5. Publicera inte till `main` förrän testet är godkänt.

## Viktigt
Ingen ny SQL behövs för landningssidan. Riktig betalning, behörighetsstyrd Premium-delning, annonser och extern kalendersynk är INTE implementerade i denna version. Prisplanerna är marknadsföringsförslag, inte aktiva produkter.
