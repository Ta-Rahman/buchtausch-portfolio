# Datenwörterbuch – Buchtausch-App

**21 Entitäten · 108 Attribute · 29 Beziehungen · 3 Dreifachbeziehungen**

Legende: **PK** = Primärschlüssel · **FK** = Fremdschlüssel · **UK** = eindeutig (UNIQUE). Attribute ohne Kennzeichnung sind einfache Datenfelder. Datentypen sind für PostgreSQL angegeben.

## Personen & Rollen

### `benutzer`

*Registrierte Person; tritt je nach Transaktion als verleihende oder ausleihende Person auf.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `benutzer_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `vorname` | VARCHAR(60) | — | Vorname der Person. |
| `nachname` | VARCHAR(60) | — | Nachname der Person. |
| `email` | VARCHAR(120) | UK | E-Mail-Adresse; dient als eindeutige Anmeldekennung. |
| `telefon` | VARCHAR(30) | — | Telefonnummer für die Abstimmung der Übergabe; optional. |
| `passwort_hash` | CHAR(60) | — | bcrypt-Hash des Passworts; niemals Klartext. |
| `registriert_am` | DATE | — | Datum der Registrierung. |
| `kontostatus` | VARCHAR(15) | — | aktiv \| gesperrt \| deaktiviert (CHECK-Constraint). |

### `adresse`

*Wohn- und Übergabeadresse einer Person, einschließlich Geokoordinaten für die Umkreissuche.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `adresse_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `benutzer_id` | INT | FK UK | Verweis auf benutzer; eindeutig, daher 1:1-Beziehung. |
| `strasse` | VARCHAR(80) | — | Straßenname. |
| `hausnummer` | VARCHAR(10) | — | Hausnummer inkl. Zusatz (z. B. 12a). |
| `plz` | VARCHAR(10) | — | Postleitzahl; als Text, da führende Nullen erhalten bleiben müssen. |
| `ort` | VARCHAR(80) | — | Ortsname. |
| `land` | CHAR(2) | — | Ländercode nach ISO 3166-1 alpha-2. |
| `position` | GEOGRAPHY(Point,4326) | — | Geografischer Punkt (WGS 84) für die Umkreissuche; GiST-indiziert. |

### `rolle`

*Systemrolle zur Rechtevergabe (Stammdaten).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `rolle_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `bezeichnung` | VARCHAR(30) | UK | Mitglied \| Moderation \| Administration. |
| `beschreibung` | VARCHAR(200) | — | Kurzbeschreibung der mit der Rolle verbundenen Rechte. |

### `benutzer_rolle`

*Zuordnung von Systemrollen zu Personen (n:m-Auflösung).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `benutzer_id` | INT | PK FK | Teil des zusammengesetzten Primärschlüssels; Verweis auf benutzer. |
| `rolle_id` | INT | PK FK | Teil des zusammengesetzten Primärschlüssels; Verweis auf rolle. |
| `zugewiesen_am` | DATE | — | Datum der Rollenzuweisung. |

## Bibliografische Stammdaten

### `autor`

*Verfassende Person eines Werks (Stammdaten).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `autor_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `vorname` | VARCHAR(60) | — | Vorname; optional bei einnamigen Autor:innen. |
| `nachname` | VARCHAR(60) | — | Nachname bzw. Künstlername. |
| `geburtsjahr` | SMALLINT | — | Geburtsjahr zur Unterscheidung namensgleicher Personen. |

### `verlag`

*Verlag, in dem ein Werk erschienen ist (Stammdaten).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `verlag_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `name` | VARCHAR(100) | UK | Verlagsname; eindeutig. |
| `sitz` | VARCHAR(80) | — | Verlagsort. |

### `sprache`

*Sprache, in der ein Werk verfasst ist (Stammdaten).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `sprache_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `iso_code` | CHAR(2) | UK | Sprachcode nach ISO 639-1 (z. B. de, en). |
| `bezeichnung` | VARCHAR(40) | — | Ausgeschriebener Sprachname. |

### `genre`

*Genre zur Klassifikation von Werken (Stammdaten).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `genre_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `bezeichnung` | VARCHAR(50) | UK | Genrebezeichnung, z. B. Roman, Sachbuch. |

### `werk`

*Buchtitel als bibliografische Einheit — unabhängig davon, wie viele physische Bücher existieren.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `werk_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `titel` | VARCHAR(200) | — | Haupttitel des Werks. |
| `untertitel` | VARCHAR(200) | — | Untertitel; optional. |
| `isbn13` | CHAR(13) | UK | 13-stellige ISBN; eindeutig, aber bei alten Ausgaben optional. |
| `erscheinungsjahr` | SMALLINT | — | Jahr der Veröffentlichung. |
| `verlag_id` | INT | FK | Verweis auf verlag. |
| `sprache_id` | INT | FK | Verweis auf sprache. |

### `werk_autor`

*Zuordnung von Werken zu verfassenden Personen (n:m-Auflösung).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `werk_id` | INT | PK FK | Teil des zusammengesetzten Primärschlüssels; Verweis auf werk. |
| `autor_id` | INT | PK FK | Teil des zusammengesetzten Primärschlüssels; Verweis auf autor. |
| `beitragsart` | VARCHAR(20) | — | Autor \| Herausgeber \| Übersetzung. |

### `werk_genre`

*Zuordnung von Werken zu Genres (n:m-Auflösung).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `werk_id` | INT | PK FK | Teil des zusammengesetzten Primärschlüssels; Verweis auf werk. |
| `genre_id` | INT | PK FK | Teil des zusammengesetzten Primärschlüssels; Verweis auf genre. |

## Besitz & Verfügbarkeit

### `zustand`

*Ordinale Zustandsskala eines Exemplars (Stammdaten).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `zustand_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `stufe` | SMALLINT | UK | 1 = neuwertig bis 5 = stark abgenutzt; erlaubt Sortierung und Filterung. |
| `bezeichnung` | VARCHAR(30) | — | Sprechende Bezeichnung der Stufe. |
| `beschreibung` | VARCHAR(200) | — | Kriterien der Einstufung. |

### `exemplar`

*Physisches Buch im Besitz einer bestimmten Person — die eigentliche Leiheinheit.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `exemplar_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `werk_id` | INT | FK | Verweis auf das bibliografische Werk. |
| `besitzer_id` | INT | FK | Verweis auf benutzer; die Person, der das Exemplar gehört. |
| `zustand_id` | INT | FK | Verweis auf zustand. |
| `max_leihdauer_tage` | SMALLINT | — | Maximale Leihdauer, die die besitzende Person zulässt. |
| `versand_moeglich` | BOOLEAN | — | Gibt an, ob Postversand angeboten wird. |
| `anmerkung` | VARCHAR(300) | — | Freitext, z. B. Widmung oder Mängel. |
| `status` | VARCHAR(15) | — | verfuegbar \| pausiert \| entfernt (CHECK-Constraint). |
| `eingestellt_am` | DATE | — | Datum der Einstellung in die Plattform. |

### `zeitslot`

*Konkretes Zeitfenster für Verfügbarkeit oder Übergabe.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `zeitslot_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `beginn` | TIMESTAMPTZ | — | Beginn des Zeitfensters inkl. Zeitzone. |
| `ende` | TIMESTAMPTZ | — | Ende des Zeitfensters; CHECK erzwingt ende > beginn. |

### `uebergabeart`

*Art der Übergabe eines Exemplars (Stammdaten).*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `uebergabeart_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `bezeichnung` | VARCHAR(20) | UK | Abholung \| Postversand. |

### `verfuegbarkeit`  ⟨Dreifachbeziehung⟩

*DREIFACHBEZIEHUNG: Wann ist welches Exemplar auf welchem Weg übergebbar?*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `verfuegbarkeit_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `exemplar_id` | INT | FK | Verweis auf exemplar. |
| `zeitslot_id` | INT | FK | Verweis auf zeitslot. |
| `uebergabeart_id` | INT | FK | Verweis auf uebergabeart; UNIQUE über alle drei Fremdschlüssel. |

## Transaktion

### `ausleihe`

*Vorgang von der Anfrage bis zur Rückgabe; Kern des Transaktionsmodells.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `ausleihe_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `exemplar_id` | INT | FK | Verweis auf das ausgeliehene Exemplar. |
| `ausleiher_id` | INT | FK | Verweis auf benutzer; die ausleihende Person. |
| `zeitraum_von` | DATE | — | Beginn des gewünschten bzw. vereinbarten Leihzeitraums. |
| `zeitraum_bis` | DATE | — | Ende des Leihzeitraums; CHECK erzwingt bis >= von. |
| `status` | VARCHAR(15) | — | angefragt \| bestaetigt \| laufend \| abgeschlossen \| abgelehnt \| storniert \| verspaetet. |
| `angefragt_am` | TIMESTAMPTZ | — | Zeitpunkt der Anfrage. |
| `entschieden_am` | TIMESTAMPTZ | — | Zeitpunkt der Bestätigung oder Ablehnung. |
| `uebergeben_am` | DATE | — | Tatsächlicher Übergabetag. |
| `zurueckgegeben_am` | DATE | — | Tatsächlicher Rückgabetag. |

### `uebergabe`  ⟨Dreifachbeziehung⟩

*DREIFACHBEZIEHUNG: Wann und auf welchem Weg wechselt das Exemplar den Besitz — hin und zurück?*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `uebergabe_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `ausleihe_id` | INT | FK | Verweis auf ausleihe. |
| `zeitslot_id` | INT | FK | Verweis auf zeitslot; nur bei persönlicher Abholung belegt. |
| `uebergabeart_id` | INT | FK | Verweis auf uebergabeart. |
| `richtung` | VARCHAR(10) | — | hinweg \| rueckweg (CHECK-Constraint). |
| `sendungsnummer` | VARCHAR(40) | — | Sendungsnummer; nur bei Postversand belegt. |
| `versandkosten` | NUMERIC(6,2) | — | Portokosten in Euro; nur bei Postversand belegt. |
| `erfolgt_am` | TIMESTAMPTZ | — | Zeitpunkt der tatsächlichen Übergabe. |

## Community

### `bewertung_werk`

*Bewertung und Kommentar zu einem Werk; nur nach abgeschlossener eigener Ausleihe zulässig.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `bewertung_werk_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `werk_id` | INT | FK | Verweis auf das bewertete Werk. |
| `verfasser_id` | INT | FK | Verweis auf benutzer; die bewertende Person. |
| `ausleihe_id` | INT | FK UK | Verweis auf ausleihe als Berechtigungsnachweis; eindeutig, daher genau eine Werkbewertung je Ausleihe. |
| `sterne` | SMALLINT | — | Bewertung von 1 bis 5 (CHECK-Constraint). |
| `kommentar` | VARCHAR(1000) | — | Freitextkommentar; optional. |
| `erstellt_am` | TIMESTAMPTZ | — | Zeitpunkt der Erstellung. |
| `gemeldet` | BOOLEAN | — | Kennzeichen für die Moderation. |

### `bewertung_person`  ⟨Dreifachbeziehung⟩

*DREIFACHBEZIEHUNG: Wer bewertet wen aufgrund welcher konkreten Ausleihe?*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `bewertung_person_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `bewertender_id` | INT | FK | Verweis auf benutzer; die bewertende Person. |
| `bewerteter_id` | INT | FK | Verweis auf benutzer; die bewertete Person. CHECK verhindert Selbstbewertung. |
| `ausleihe_id` | INT | FK | Verweis auf ausleihe; UNIQUE über bewertender_id und ausleihe_id. |
| `sterne` | SMALLINT | — | Bewertung von 1 bis 5 (CHECK-Constraint). |
| `kommentar` | VARCHAR(500) | — | Freitextkommentar; optional. |
| `erstellt_am` | TIMESTAMPTZ | — | Zeitpunkt der Erstellung. |

### `nachricht`

*Direktnachricht zwischen zwei Personen, optional mit Bezug zu einer Ausleihe.*

| Attribut | Datentyp | Schlüssel | Beschreibung |
|---|---|---|---|
| `nachricht_id` | SERIAL | PK | Künstlicher Primärschlüssel. |
| `absender_id` | INT | FK | Verweis auf benutzer; sendende Person. |
| `empfaenger_id` | INT | FK | Verweis auf benutzer; empfangende Person. |
| `ausleihe_id` | INT | FK | Verweis auf ausleihe; optional, für Nachrichten ohne Vorgangsbezug. |
| `text` | VARCHAR(2000) | — | Nachrichtentext. |
| `gesendet_am` | TIMESTAMPTZ | — | Sendezeitpunkt. |
| `gelesen` | BOOLEAN | — | Lesebestätigung. |

## Beziehungsübersicht

Kardinalitäten in der Krähenfuß-Notation; `0..n` bedeutet optional viele, `1` genau eins, `0..1` optional eins.

| Von | Kardinalität | Beziehung | Kardinalität | Nach |
|---|---|---|---|---|
| `benutzer` | 1 | wohnt an | 1 | `adresse` |
| `benutzer` | 1 | besitzt | 0..n | `benutzer_rolle` |
| `rolle` | 1 | wird vergeben | 0..n | `benutzer_rolle` |
| `verlag` | 1 | veroeffentlicht | 0..n | `werk` |
| `sprache` | 1 | verfasst in | 0..n | `werk` |
| `werk` | 1 | zugeordnet | n | `werk_autor` |
| `autor` | 1 | verfasst | n | `werk_autor` |
| `werk` | 1 | eingeordnet | 0..n | `werk_genre` |
| `genre` | 1 | klassifiziert | 0..n | `werk_genre` |
| `werk` | 1 | liegt vor als | 0..n | `exemplar` |
| `benutzer` | 1 | besitzt | 0..n | `exemplar` |
| `zustand` | 1 | beschreibt | 0..n | `exemplar` |
| `exemplar` | 1 | ist verfuegbar | 0..n | `verfuegbarkeit` |
| `zeitslot` | 1 | im Zeitfenster | 0..n | `verfuegbarkeit` |
| `uebergabeart` | 1 | per Art | 0..n | `verfuegbarkeit` |
| `exemplar` | 1 | verliehen in | 0..n | `ausleihe` |
| `benutzer` | 1 | leiht aus | 0..n | `ausleihe` |
| `ausleihe` | 1 | erfolgt durch | n | `uebergabe` |
| `zeitslot` | 0..1 | zum Zeitfenster | 0..n | `uebergabe` |
| `uebergabeart` | 1 | per Art | 0..n | `uebergabe` |
| `werk` | 1 | wird bewertet | 0..n | `bewertung_werk` |
| `benutzer` | 1 | verfasst | 0..n | `bewertung_werk` |
| `ausleihe` | 1 | berechtigt zu | 0..1 | `bewertung_werk` |
| `benutzer` | 1 | bewertet | 0..n | `bewertung_person` |
| `benutzer` | 1 | wird bewertet | 0..n | `bewertung_person` |
| `ausleihe` | 1 | berechtigt zu | 0..n | `bewertung_person` |
| `benutzer` | 1 | sendet | 0..n | `nachricht` |
| `benutzer` | 1 | empfaengt | 0..n | `nachricht` |
| `ausleihe` | 0..1 | betrifft | 0..n | `nachricht` |

## Dreifachbeziehungen

| Beziehungstabelle | Verknüpfte Entitäten | Fachliche Aussage |
|---|---|---|
| `verfuegbarkeit` | exemplar × zeitslot × uebergabeart | Wann ist welches Exemplar auf welchem Weg übergebbar? |
| `uebergabe` | ausleihe × zeitslot × uebergabeart | Wann und auf welchem Weg wechselt das Exemplar den Besitz? |
| `bewertung_person` | benutzer × benutzer × ausleihe | Wer bewertet wen aufgrund welcher konkreten Ausleihe? |
