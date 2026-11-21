# Family Hub 0.2 – lokal testversion

## Nytt
- Dag-, vecko- och månadsvy med navigering och färgkodade aktiviteter.
- Flera lokala kalendrar, välj en kalender eller visa alla.
- Skapa och ta bort tomma kalendrar.
- Behåller inköpslista, idrott, ICS-import, backup och återställning.
- Importerar automatiskt data från Family Hub 0.1 **om samma webbadress används i samma webbläsare**.

## Publicera på Cloudflare Pages
Ladda upp innehållet i den här mappen till ett **separat test-repository eller en separat branch**. Testa där innan du uppdaterar den publicerade 0.1-versionen. Om du använder en ny adress följer inte lokal data automatiskt med: exportera först backup från 0.1 och återställ i 0.2.

## Viktiga begränsningar
Detta är en lokal prototyp, **inte** ett fleranvändarsystem. Inloggning, Google/Apple/Facebook OAuth, verkliga familjeinbjudningar, delning och molnsynk är **inte** implementerade. De kräver säker backend (t.ex. Supabase), databasbehörigheter och OAuth-konfiguration. ICS-import saknar fullständigt stöd för tidszoner och återkommande aktiviteter. Lagra inte känslig familjeinformation i prototypen.

## Nästa etapp
Supabase Auth + databas med Row Level Security, medlemskap, kalenderbehörigheter och tidsbegränsade inbjudningar. Sedan realtidssynk och separata OAuth-godkännanden för externa kalendrar.
