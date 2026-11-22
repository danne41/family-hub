# Family Hub 0.3 – konton och familjegrupper (test)

Den tidigare lokala kalendern, shoppinglistan och idrottsöversikten finns kvar. Nytt: Supabase e-postinloggning, skapa familjegrupp, engångsinbjudningskod som gäller 48 timmar, ansluta till flera grupper.

## Konfiguration (krävs innan inloggningen fungerar)

1. Skapa ett Supabase-projekt. Öppna SQL Editor och kör hela `supabase-schema.sql`.
2. I Supabase: Project Settings → API (eller Connect) – kopiera **Project URL** och **publishable key / anon key**. Använd **ALDRIG** `service_role` eller `secret` key i webbkod.
3. Fyll i de två värdena i `config.js`.
4. Under Authentication → URL Configuration, sätt **Site URL** till din Cloudflare Pages-testadress och lägg till motsvarande tillåtna **Redirect URLs**. Bekräftelselänkar för e-post behöver tillåten URL. Om Cloudflare skapar nya slumpmässiga preview-URL:er behöver du konfigurera dessa eller använda en stabil branch-URL.
5. Ladda upp filerna i utvecklingsgrenen, inte `main`. Testa registrering och bekräftelse med två olika e-postkonton.

## Vad fungerar och vad fungerar inte?

**Fungerar efter Supabase-konfiguration:** kontoregistrering med e-post/lösenord, inloggning, utloggning, gruppskapande, engångsinbjudan och anslutning till grupper. Grupper och medlemskap ligger i Supabase med RLS och serverkontrollerade RPC:er.

**Inte klart:** Google/Apple/Facebook OAuth, automatisk koppling av lokal kalender till grupp, synk av aktiviteter eller shopping mellan enheter, e-post-/kalenderinbjudningar och RSVP-status. Kalenderdata ligger kvar i `localStorage` på den enhet som skapade dem. Skicka därför inga verkliga privata familjeuppgifter i testet.

**Säkerhet:** lösenord hanteras av Supabase Auth. Klienten har endast publik nyckel. Inbjudningskoder lagras som SHA-256-hashar, är engångskoder och löper ut efter 48 timmar. För produktionslansering behövs bl.a. tydliga dataskyddsvillkor, kontoborttagning, missbruksbegränsning och noggrannare säkerhetstester.

## Teststeg

- Skapa konto A, bekräfta e-post, logga in.
- Skapa familjegrupp och skapa kod. Kopiera koden (den visas bara en gång).
- Skapa konto B i separat privat fönster/enhet, bekräfta e-post och logga in.
- Gå med via koden. Kontrollera att båda ser gruppen.
- Kontrollera att samma kod inte kan användas igen.
- Kontrollera att kalenderaktiviteter inte delas ännu (förväntat i 0.3).
