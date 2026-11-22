# Family Hub 0.3.1 – inloggningssida och förbättrad felhantering

Uppdatering av 0.3. Dag/vecka/månad och lokala funktioner finns kvar.

## Installera på GitHub (Develope)
1. Ersätt `index.html`, `auth.js`, `style.css` och `sw.js` med filerna i paketet.
2. **Behåll din nuvarande `config.js` i GitHub.** Paketets `config.js` har en platshållare för nyckeln och ska INTE ersätta din fungerande konfiguration.
3. Låt Cloudflare Pages publicera preview-grenen.
4. Testa Skapa konto, e-postbekräftelse, Logga in och Logga ut.

## Felsökning
Om Safari visar `Load failed` kan orsaken vara nätverk, CDN, blockerad förfrågan eller felaktig Supabase URL. Denna version använder jsDelivr med fallback till esm.sh och visar fel på inloggningssidan. Det är ingen garanti för att felet är löst. Kontrollera Safari Web Inspector och Supabase Authentication logs om problemet kvarstår.

## Säkerhet och status
Familjegrupper sparas i Supabase, men kalenderaktiviteter och inköpslistor är ännu lokala. Google/Apple-inloggning, extern kalender-RSVP och synk är inte implementerade. SQL/RLS bör granskas och testas innan verklig familjedata lagras.
