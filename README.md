# Family Hub 0.6 – testversion

1. Kör `supabase-migration-0.6.sql` i Supabase SQL Editor EN gång. Kräver tidigare schema och 0.4-migration.
2. Ladda upp webbappens filer till grenen `Develope`, inte `main`. Behåll din fungerande `config.js`.
3. Testa två olika användare i samma familjegrupp. Välj gruppkalender och skapa en aktivitet. Den andra användaren ska se den efter uppdatering.
4. Standardkalender sparas per webbläsare/enhet.

OBS: Egna lokala kalendrar och deras aktiviteter lagras fortfarande på enheten. Gruppkalenderaktiviteter sparas i Supabase. Automatisk synk i realtid, personliga molnkalendrar, prenumerationer och extern idrottssynk är inte klara.
