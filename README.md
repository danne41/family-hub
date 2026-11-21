# Family Hub 0.1

En mobilanpassad, svensk, statisk prototyp av en familjeapp. Ingen server, inget konto, inga betaltjänster.

## Funktioner
- Familjemedlemmar med egna färger
- Kalenderaktiviteter och filtrering
- Import av enkla ICS-kalenderfiler
- Inköpslista med avprickning och vem som lagt till varan
- Idrottssektion för manuellt tillagda idrottsaktiviteter
- Lokal lagring och export/import av JSON-säkerhetskopia
- Grundläggande PWA/offline-cache

## Begränsningar
- **Ingen synkronisering mellan familjemedlemmar eller enheter**; uppgifterna sparas i den aktuella webbläsaren.
- ICS-parsern är begränsad: inga RRULE-upprepningar, undantag, korrekt TZID-tolkning eller uppdateringshantering. Import kan skapa dubbletter.
- Inga riktiga kopplingar till Google, Apple, laget.se, Svenskalag, SportAdmin eller e-post.
- Ingen autentisering, behörighetskontroll, notifiering eller betalning.
- Återställ endast JSON från betrodd källa.
- Detta är en testprototyp, inte en produktionsklar tjänst.

## Testa lokalt
Starta en statisk webbserver i projektmappen, t.ex. `python3 -m http.server 8080`, och öppna `http://localhost:8080`. På iPad kan du i stället publicera de statiska filerna via en gratis hostingtjänst. För Cloudflare Pages Direct Upload: ladda upp mappen med `index.html`, `app.js`, `style.css`, `sw.js` och `manifest.webmanifest`.

## Nästa steg
1. Stabil kalenderhantering (ICS med tidszoner/återkommande händelser).
2. Säker familjeinloggning, databas, behörigheter och synk.
3. Godkända kalenderintegrationer.
4. Sports Inbox och hantering av kallelser.
5. Premium och betalningar efter säkerhetsgranskning.
