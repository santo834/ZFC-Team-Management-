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
- `/teams/`, `/drivers/` und zugehörige Profile leiten auf die öffentliche Startseite um
- `/insurance/` öffentliche Versicherungsangebote
- `/sponsors/shop.html` Sponsoring-Angebote und Anfragen
- `/hq/shop.html` HQ-Angebote und Anfragen
- `/marketplace/` alle veröffentlichten Angebotsarten
- `/news/` und einzelne Artikel leiten auf die öffentliche Startseite um
- `/hq/shop.html` HQ-Angebote; `/hq/` leitet dorthin weiter
- `/login/` Anmeldung mit E-Mail und Passwort
- `/admin/` Control Center für Angebote, Kaufanfragen, Konten, Rechnungen und Verträge
- `/team/` Team-E-Banking mit Kontostand, Rechnungen, Druck/PDF-Ansicht und Vertragsentwürfen
- `/office/` leitet zum geschützten Adminbereich weiter
- `/contact.html`, `/imprint.html`, `/privacy.html` klar markierte Platzhalter

## Verwaltungsbereich

Die frühere lokale Finance-Office-Demo ist nicht mehr öffentlich erreichbar. `/office/` leitet zum Admin-Login weiter.

Ohne Supabase-Konfiguration bleiben Admin- und Team-Bereich im lokalen Demo-Modus. Mit Supabase werden Login, Rollen, Teamzuordnung, Angebote, öffentliche Kaufanfragen, Rechnungen und Kontobuchungen gemeinsam gespeichert. Anfragen erscheinen im Admin unter **Kaufanfragen**; dort kann eine Rechnung erstellt und als PDF-Entwurf gedruckt werden. Der tatsächliche Geldtransfer erfolgt manuell außerhalb der Website und wird erst danach im Admin bestätigt. Vertrags- und Supportfunktionen sind weiterhin lokal.

GitHub Pages bleibt statisch; Authentifizierung und gemeinsame Datenspeicherung laufen über Supabase. Rechnungen sind zunächst Entwürfe und müssen vor dem Versand um vollständige Aussteller-/Steuerangaben ergänzt und rechtlich geprüft werden. Vertragsannahmen sind keine rechtsgültigen Signaturen. Keine echten Bankzugänge eintragen.

## Supabase-Schema für Login und Rollen

Die Migrationen unter `supabase/migrations/` legen Teams, Profile, Rollen, kategorisierte Angebote, Anfragen, Rechnungen und Kontobuchungen an. Row-Level-Security begrenzt Teamdaten auf das zugewiesene Team. Edge Functions für öffentliche Anfragen und sichere Admin-Kontoanlage liegen unter `supabase/functions/`.

Migration in ein Supabase-Projekt einspielen:

1. Ein Supabase-Projekt anlegen und das Repository lokal mit der Supabase CLI verknüpfen (`supabase link --project-ref <PROJECT_REF>`).
2. `supabase db push` ausführen.
3. `assets/supabase-config.js` enthält bereits die Projekt-URL und den öffentlichen Publishable-Key. Den `service_role`-Schlüssel niemals hier oder in anderem Browser-Code hinterlegen.
4. Beide Edge Functions deployen:

```sh
supabase functions deploy public-purchase
supabase functions deploy admin-create-user
```

5. Im Supabase Auth Dashboard den ersten Benutzer `s.barbosa.galaxy@gmail.com` mit einem sicheren Passwort anlegen. Anschließend im **SQL Editor** das Profil zum Admin machen:

```sql
update public.profiles
set role = 'admin', team_id = null
where id = (select id from auth.users where lower(email) = 's.barbosa.galaxy@gmail.com');
```

Teamchef einem Team zuordnen (die Team-ID entspricht den IDs in der Website):

```sql
update public.profiles
set role = 'team_chief', team_id = 'scuderia-rosso'
where id = (select id from auth.users where email = 'chef@example.com');
```

Danach unter `/login/` anmelden. Weitere Benutzer lassen sich im Admin unter **Benutzer & Rollen** anlegen; Teamchefs werden dort einem Team zugewiesen. `admin-create-user` prüft die Admin-Rolle serverseitig, setzt das angegebene Startpasswort und ordnet das Profil zu. `public-purchase` prüft Angebot und Preis serverseitig und begrenzt Anfragen je E-Mail-Adresse.

Der Storage-Bucket `portal-media` ist für Website-Bilder vorbereitet. Bild-Uploads, Verträge und Supportmeldungen sind noch nicht in die gemeinsame Datenbank integriert.

## Beispieldaten und Marken

Teams, Fahrer, Partner, Punkte, Gebäude und News sind frei erfundene Beispiele und auf den Seiten als solche markiert. Es werden keine offiziellen Kooperationen oder Markenassets behauptet. Vor einer öffentlichen Liga-Nutzung die Beispieldaten ersetzen und echte Veröffentlichungsrechte prüfen.

## Vor Veröffentlichung ergänzen

- Betreiber- und Kontaktangaben
- Rechtlich geprüfte Impressums- und Datenschutzerklärung
- Saison-, Team-, Fahrer- und News-Inhalte
- Optional ein eigenes, für die Veröffentlichung lizenziertes Rennsport-Hintergrundbild

Der aktuelle Hero-Hintergrund und die Display-Schrift laden bei Internetverbindung von externen Unsplash-/Google-Fonts-Adressen. Die Seite bleibt auch ohne diese Dienste lesbar; für Datenschutz oder Offline-Nutzung können die Assets später durch lokal bereitgestellte, lizenzierte Dateien ersetzt werden.
