# Family Hub 0.5.1 – design och kalenderkopplingar

Detta är en uppdatering av 0.5 med lugnare landningssida och kalenderkopplingspanel under **Min profil**.

## Installera
1. Ladda upp ZIP-filens appfiler till GitHub-grenen `Develope`.
2. **Behåll din fungerande `config.js`** – ZIP-filen innehåller endast en tom mall.
3. Vänta på Cloudflare Pages preview-deploy och testa startsidan och Min profil.
4. För veckohandling krävs fortfarande Supabase-migrationen `supabase-migration-0.4.sql` om den inte redan körts.

## Begränsningar
- Knapparna för Google, Outlook och Apple visar information, men ansluter inte till respektive tjänst. Inga tokens eller externa kalenderdata behandlas.
- Priserna är preliminära; inga betalningar eller annonser är aktiverade.
- Kalenderhändelser är fortfarande lokala i den här versionen.
