# Family Hub 0.5.2 – testversion

## Nytt
- Kalendern är standardvy vid inloggning och siduppdatering; profilens kompletteringsmeddelande finns kvar utan automatisk omdirigering.
- Inköpslistan visar varan omedelbart och återställer vid serverfel.
- Automatisk idrottskoppling beskrivs som en framtida Premium Family-funktion (inte aktiv ännu).
- Installationsguide med illustrerade iOS/Android-instruktioner.
- Årspriser med cirka 10 % rabatt: Plus 421 kr/år, Premium Family 745 kr/år.
- Utkast till juridiska informationssidor; inte godkända villkor.

## Installera
1. Lägg upp filerna på GitHub-grenen Develope.
2. Behåll din fungerande config.js, eftersom den bifogade är en tom mall.
3. Låt Cloudflare Pages skapa en preview. Testa inköp, siduppdatering, profil, mobilguide och priser.
4. Supabase-migrationen 0.4 krävs för profiles och shopping_items. Kör den endast om den inte redan körts.

## Begränsningar
Riktig kalender- och idrottssynk, betalningar, annonser och Premium-behörighetskontroller är inte implementerade. Juridiktexterna är enbart utkast.
