# ZFC · Zenith Formula Championship

Statische, mehrseitige Website für GitHub Pages. Keine Installation, kein Build, kein Node.js und kein Server nötig. Jede Seite ist eine eigene HTML-Datei und direkt über ihre URL erreichbar.

## Im Browser ansehen

`index.html` öffnen. Für lokale Vorschau kann die Datei direkt geöffnet werden; alle Inhalte und Navigation funktionieren ohne JavaScript-Build oder Paketinstallation.

## Über GitHub veröffentlichen

1. Dieses Repository auf GitHub pushen.
2. In den Repository-Einstellungen unter **Pages** die Quelle **Deploy from a branch** wählen.
3. Branch `main` und Ordner `/ (root)` einstellen und speichern.
4. GitHub veröffentlicht `index.html` und die Unterseiten automatisch. Es ist kein GitHub-Actions-Build nötig.

Die `.nojekyll`-Datei schaltet die Jekyll-Verarbeitung aus. Die öffentlichen Navigationen verwenden relative Links und funktionieren daher auch, wenn Pages das Projekt unter einem Repository-Unterpfad bereitstellt.

## Seiten

- `/` öffentliche Startseite
- `/teams/` öffentliches Grid mit allen elf Teams der F1-Saison 2026; einzelne Teamprofile sind noch nicht angelegt
- `/drivers/` und zugehörige Profile leiten auf die öffentliche Startseite um
- `/insurance/` öffentliche Versicherungsangebote
- `/sponsors/shop.html` Sponsoring-Angebote und Anfragen
- `/hq/shop.html` HQ-Angebote und Anfragen
- `/marketplace/` alle veröffentlichten Angebotsarten
- `/news/` und einzelne Artikel leiten auf die öffentliche Startseite um
- `/hq/shop.html` HQ-Angebote; `/hq/` leitet dorthin weiter
- `/login/` Anmeldung mit E-Mail und Passwort
- `/admin/` Control Center für Angebote, Kaufanfragen, Konten, Rechnungen und Verträge; Admins können offene Verträge hier oder im Team-E-Banking annehmen
- `/team/` Team-E-Banking mit Kontostand, Rechnungen, Druck/PDF-Ansicht und Vertragsentwürfen
- `/office/` leitet zum geschützten Adminbereich weiter
- `/contact.html`, `/imprint.html`, `/privacy.html` klar markierte Platzhalter

## Verwaltungsbereich

Die frühere lokale Finance-Office-Demo ist nicht mehr öffentlich erreichbar. `/office/` leitet zum Admin-Login weiter.

Mit der eingetragenen Supabase-Konfiguration laufen Login, Rollen, Teamzuordnung, Angebote, öffentliche Kaufanfragen, Rechnungen, Kontobuchungen und Verträge über Supabase. Damit sich Admin und Teamchefs anmelden können, müssen die Datenbankmigrationen ausgeführt und für jedes Auth-Konto ein korrektes Profil mit Rolle angelegt sein. Anfragen erscheinen im Admin unter **Kaufanfragen**; dort kann eine Rechnung erstellt und als PDF-Entwurf gedruckt werden. Der tatsächliche Geldtransfer erfolgt manuell außerhalb der Website und wird erst danach im Admin bestätigt. Supportmeldungen sind weiterhin lokal.

GitHub Pages bleibt statisch; Authentifizierung und gemeinsame Datenspeicherung laufen über Supabase. Rechnungen sind zunächst Entwürfe und müssen vor dem Versand um vollständige Aussteller-/Steuerangaben ergänzt und rechtlich geprüft werden. Vertragsannahmen sind keine rechtsgültigen Signaturen. Keine echten Bankzugänge eintragen.

## Neu: Verträge, Monatsabrechnung, Bilder

- Admin → **Team-E-Banking**: Team wählen, Verträge (Fahrer, Teamchef, Insurance, Sponsoring, HQ, Fahrerkauf) anlegen und offene Verträge annehmen, Monatsabrechnung und Rechnungen als PDF öffnen.
- Eigene Angebotsbilder haben keine Größenbegrenzung mehr (sehr große Bilder werden automatisch verkleinert) und werden zentral gespeichert.
- Entfernte Angebote werden wirklich gelöscht. Dafür sowie für die neuen Vertragsarten `npx supabase db push` ausführen.

## Supabase-Schema für Login und Rollen

Die Migrationen unter `supabase/migrations/` legen Teams, Profile, Rollen, kategorisierte Angebote, Anfragen, Rechnungen, Kontobuchungen und Verträge an. Row-Level-Security begrenzt Teamdaten auf das zugewiesene Team. Teamchefs können nur Verträge ihres Teams beantworten; Admins können offene Verträge aller Teams annehmen. Edge Functions für öffentliche Anfragen und sichere Admin-Kontoanlage liegen unter `supabase/functions/`.

Supabase CLI einmalig anmelden und das Projekt verknüpfen. Der persönliche Access Token wird ausschließlich direkt in der Terminalabfrage eingegeben, niemals in Chat, Code oder Browserdateien:

```sh
npx supabase login
npx supabase link --project-ref yibyvdxrvnxfnmzmufnm
```

Neue Migrationen, einschließlich der Admin-Annahme für Verträge, mit dem folgenden Befehl auf das Projekt anwenden:

```sh
npx supabase db push
```

`assets/supabase-config.js` enthält bereits die Projekt-URL und den öffentlichen Publishable-Key. Den `service_role`-Schlüssel niemals hier oder in anderem Browser-Code hinterlegen.

Die Edge Functions für öffentliche Kaufanfragen und Admin-Rollenzuweisungen deployen:

```sh
npx supabase functions deploy public-purchase --project-ref yibyvdxrvnxfnmzmufnm
npx supabase functions deploy admin-assign-role --project-ref yibyvdxrvnxfnmzmufnm
```

Im Supabase Auth Dashboard den Benutzer `s.barbosa.galaxy@gmail.com` mit einem sicheren Passwort anlegen und die Bestätigungs-E-Mail abschließen. Danach im **SQL Editor** das Profil zum Admin machen (die Migration kann das nur übernehmen, wenn der Benutzer zu diesem Zeitpunkt bereits existiert):

```sql
update public.profiles
set role = 'admin', team_id = null
where id = (select id from auth.users where lower(email) = 's.barbosa.galaxy@gmail.com');
```

Teamchef einem Team zuordnen (den Teamnamen und die interne ID kannst du in der Teamtabelle nachsehen):

```sql
update public.profiles
set role = 'team_chief',
    team_id = (select id from public.teams where name = 'Ferrari')
where id = (select id from auth.users where email = 'chef@example.com');
```

Zusätzliche Konten werden direkt im Supabase Dashboard unter **Authentication → Users** mit E-Mail und Passwort angelegt. Nach der E-Mail-Bestätigung erzeugt der Datenbank-Trigger das Profil. Im Admin unter **Benutzer & Rollen** weist du anschließend `Admin` oder `Teamchef` zu; Teamchefs benötigen zusätzlich ein Team. Die Function `admin-assign-role` erlaubt diese Änderung nur für angemeldete Admins. `public-purchase` prüft Angebot und Preis serverseitig und begrenzt Anfragen je E-Mail-Adresse.

Der Storage-Bucket `portal-media` ist für Website-Bilder vorbereitet. Bild-Uploads, Verträge und Supportmeldungen sind noch nicht in die gemeinsame Datenbank integriert.

## Beispieldaten und Marken

Die Teamnamen im öffentlichen Grid entsprechen den elf F1-Teams der Saison 2026. Teamchefs und Fahrer werden später ergänzt. Die lokal erstellten Team-Badges sind eigenständige Entwürfe und keine offiziellen Markenlogos; es werden keine offiziellen Kooperationen behauptet. Partner, Punkte, Gebäude und News bleiben Beispieldaten. Vor einer öffentlichen Liga-Nutzung Veröffentlichungsrechte prüfen.

## Vor Veröffentlichung ergänzen

- Betreiber- und Kontaktangaben
- Rechtlich geprüfte Impressums- und Datenschutzerklärung
- Saison-, Team-, Fahrer- und News-Inhalte
- Optional ein eigenes, für die Veröffentlichung lizenziertes Rennsport-Hintergrundbild

Die Rennsportbilder liegen lokal in `assets/`. Bildnachweise und Creative-Commons-Lizenzen stehen im Footer der Startseite. Die Display-Schrift wird weiterhin von Google Fonts geladen; ohne Internetverbindung greift die lokale Ersatzschrift.
