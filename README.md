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
- `/teams/` Teamübersicht, Suche, Filter und Seitenwechsel
- `/teams/<team>.html` individuelle Teamprofile
- `/drivers/` Fahrerübersicht mit Team- und Statusfiltern
- `/drivers/<fahrer>.html` individuelle Fahrerprofile
- `/sponsors/` veröffentlichte Beispielpartner
- `/news/` Meldungsübersicht und einzelne Artikelseiten
- `/hq/` öffentliche Gebäudeübersicht
- `/login/` Auswahl zwischen Admin-Bereich und Teamchef-E-Banking
- `/admin/` Demo-Control-Center für Website-Inhalte, Bildgalerie, Sponsoring-Angebote, Anfragen, Teamkonten, Rechnungen und Verträge
- `/team/` Team-E-Banking mit Kontostand, Rechnungen, Druck/PDF-Ansicht und Vertragsentwürfen
- `/office/` vorhandenes Browser-Verwaltungstool
- `/contact.html`, `/imprint.html`, `/privacy.html` klar markierte Platzhalter

## Verwaltungsbereich

Das ursprüngliche `index.html` wurde unverändert nach `office/index.html` verschoben. Das Browsertool bietet weiterhin lokale Team-, Fahrer-, Sponsoren- und virtuelle Kontofunktionen, JSON-Backup, CSV-Export und Buchungsjournal. Seine Daten werden im jeweiligen Browser gespeichert. Es gibt keine Anmeldung, keine Synchronisierung und keinen serverseitigen Zugriffsschutz. Verwende dort keine echten Bank-, Vertrags- oder sensiblen Personendaten.

Admin- und Team-Bereich sind ein **klickbarer, browserlokaler Prototyp**. Auf demselben Browser können Startseitentexte, Bilder, Angebote, Sponsorenanfragen, Rechnungen und Vertragsentwürfe ausprobiert werden; Rechnungen lassen sich über den Druckdialog als PDF speichern. Die linke Arbeitsbereich-Navigation erscheint nur im Admin-Bereich, während das Team-E-Banking seine eigene Teamnavigation hat.

Es gibt noch **keine echten Logins oder Zugriffskontrollen**: die Rollenauswahl ist keine Authentifizierung, Teamdaten sind nicht geschützt und lokale Daten werden nicht zwischen Personen oder Geräten synchronisiert. Auch Rechnungen und Vertragsannahmen sind Demo-Dokumente bzw. keine rechtsgültigen Signaturen. GitHub Pages kann ausschließlich statische Dateien ausliefern; echte Mehrbenutzerverwaltung, vertrauliche Finanzdaten, rechtssichere Verträge und zentrale Speicherung benötigen später einen Backend-Dienst mit Anmeldung, Rollen/Rechten und geeigneter Datenbank. Keine echten Zugangsdaten, Bankdaten oder Vertragsinformationen verwenden.

## Supabase-Schema für Login und Rollen

Die vorbereitende Datenbankmigration liegt unter [`supabase/migrations/20261022000000_zfc_team_management.sql`](./supabase/migrations/20261022000000_zfc_team_management.sql). Sie legt Teams, Profile, die Rollen `admin` und `team_chief`, Sponsorenangebote und -akten, Rechnungen, Kontobuchungen, Verträge und Supportmeldungen an. Row-Level-Security (RLS) begrenzt Teamdaten auf das jeweils zugeordnete Team; administrative Änderungen sind auf Admin-Profile beschränkt. Ein neu angelegter Supabase-Auth-Benutzer erhält zunächst ein nicht zugewiesenes `team_chief`-Profil. Die Migration vergibt **keine** Admin-Rolle automatisch.

Migration in ein Supabase-Projekt einspielen:

1. Ein Supabase-Projekt anlegen und das Repository lokal mit der Supabase CLI verknüpfen (`supabase link --project-ref <PROJECT_REF>`).
2. `supabase db push` ausführen – oder den Inhalt der Migration einmalig im Supabase SQL Editor ausführen.
3. Im Supabase Auth Dashboard Benutzer einladen/anlegen. Anschließend im **SQL Editor** die Profile einer privilegierten Rolle zuordnen. Beispielsweise zuerst den Admin:

```sql
update public.profiles
set role = 'admin', team_id = null
where id = (select id from auth.users where email = 'admin@example.com');
```

Teamchef einem Team zuordnen (die Team-ID entspricht den IDs in der Website):

```sql
update public.profiles
set role = 'team_chief', team_id = 'scuderia-rosso'
where id = (select id from auth.users where email = 'chef@example.com');
```

Diese Rollenänderungen gehören in den SQL Editor oder in einen vertrauenswürdigen Server-/Edge-Function-Aufruf. **Niemals** den Supabase `service_role`-Schlüssel in die statische Website oder in einen Browser geben. Änderungen an Adminrollen über normale angemeldete Client-Sitzungen werden zusätzlich durch einen Datenbank-Trigger abgewiesen. Sponsorenbestellungen können Teamchefs für ihr Team anlegen; ein öffentlicher Checkout für nicht angemeldete Käufer benötigt später einen serverseitigen Edge-Function-Endpunkt mit geeigneten Spam-Schutzmaßnahmen.

Das Schema stellt die Datenbank- und Zugriffsschicht bereit, schaltet aber den bestehenden browserlokalen Prototyp noch **nicht** auf Supabase um. Login-UI, Team-/Admin-Abfragen und Datei-Uploads müssen in einem folgenden Schritt mit Supabase Auth und den Tabellen/API-Funktionen verbunden werden. Die Migration erzeugt außerdem den öffentlichen Storage-Bucket `portal-media`; Uploads und Änderungen sind Admins vorbehalten, Lesen ist für Website-Bilder öffentlich.

## Beispieldaten und Marken

Teams, Fahrer, Partner, Punkte, Gebäude und News sind frei erfundene Beispiele und auf den Seiten als solche markiert. Es werden keine offiziellen Kooperationen oder Markenassets behauptet. Vor einer öffentlichen Liga-Nutzung die Beispieldaten ersetzen und echte Veröffentlichungsrechte prüfen.

## Vor Veröffentlichung ergänzen

- Betreiber- und Kontaktangaben
- Rechtlich geprüfte Impressums- und Datenschutzerklärung
- Saison-, Team-, Fahrer- und News-Inhalte
- Optional ein eigenes, für die Veröffentlichung lizenziertes Rennsport-Hintergrundbild

Der aktuelle Hero-Hintergrund und die Display-Schrift laden bei Internetverbindung von externen Unsplash-/Google-Fonts-Adressen. Die Seite bleibt auch ohne diese Dienste lesbar; für Datenschutz oder Offline-Nutzung können die Assets später durch lokal bereitgestellte, lizenzierte Dateien ersetzt werden.
