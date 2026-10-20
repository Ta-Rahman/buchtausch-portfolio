# Datenwörterbuch (Kompaktfassung)

21 Entitäten, 108 Attribute. **Fett** = Primärschlüssel, *kursiv* = Fremdschlüssel, ° = eindeutig. Datentypen für PostgreSQL. Ausführliche Fassung mit Attributbeschreibungen: siehe Repository.

**Personen & Rollen**

- `benutzer` — Registrierte Person; tritt je nach Transaktion als verleihende oder ausleihende Person auf: **benutzer_id** SERIAL · vorname VARCHAR(60) · nachname VARCHAR(60) · email° VARCHAR(120) · telefon VARCHAR(30) · passwort_hash CHAR(60) · registriert_am DATE · kontostatus VARCHAR(15)
- `adresse` — Wohn- und Übergabeadresse einer Person, einschließlich Geokoordinaten für die Umkreissuche: **adresse_id** SERIAL · *benutzer_id*° INT · strasse VARCHAR(80) · hausnummer VARCHAR(10) · plz VARCHAR(10) · ort VARCHAR(80) · land CHAR(2) · position GEOGRAPHY(Point,4326)
- `rolle` — Systemrolle zur Rechtevergabe (Stammdaten): **rolle_id** SERIAL · bezeichnung° VARCHAR(30) · beschreibung VARCHAR(200)
- `benutzer_rolle` — Zuordnung von Systemrollen zu Personen (n:m-Auflösung): **benutzer_id** INT · **rolle_id** INT · zugewiesen_am DATE

**Bibliografische Stammdaten**

- `autor` — Verfassende Person eines Werks (Stammdaten): **autor_id** SERIAL · vorname VARCHAR(60) · nachname VARCHAR(60) · geburtsjahr SMALLINT
- `verlag` — Verlag, in dem ein Werk erschienen ist (Stammdaten): **verlag_id** SERIAL · name° VARCHAR(100) · sitz VARCHAR(80)
- `sprache` — Sprache, in der ein Werk verfasst ist (Stammdaten): **sprache_id** SERIAL · iso_code° CHAR(2) · bezeichnung VARCHAR(40)
- `genre` — Genre zur Klassifikation von Werken (Stammdaten): **genre_id** SERIAL · bezeichnung° VARCHAR(50)
- `werk` — Buchtitel als bibliografische Einheit — unabhängig davon, wie viele physische Bücher existieren: **werk_id** SERIAL · titel VARCHAR(200) · untertitel VARCHAR(200) · isbn13° CHAR(13) · erscheinungsjahr SMALLINT · *verlag_id* INT · *sprache_id* INT
- `werk_autor` — Zuordnung von Werken zu verfassenden Personen (n:m-Auflösung): **werk_id** INT · **autor_id** INT · beitragsart VARCHAR(20)
- `werk_genre` — Zuordnung von Werken zu Genres (n:m-Auflösung): **werk_id** INT · **genre_id** INT

**Besitz & Verfügbarkeit**

- `zustand` — Ordinale Zustandsskala eines Exemplars (Stammdaten): **zustand_id** SERIAL · stufe° SMALLINT · bezeichnung VARCHAR(30) · beschreibung VARCHAR(200)
- `exemplar` — Physisches Buch im Besitz einer bestimmten Person — die eigentliche Leiheinheit: **exemplar_id** SERIAL · *werk_id* INT · *besitzer_id* INT · *zustand_id* INT · max_leihdauer_tage SMALLINT · versand_moeglich BOOLEAN · anmerkung VARCHAR(300) · status VARCHAR(15) · eingestellt_am DATE
- `zeitslot` — Konkretes Zeitfenster für Verfügbarkeit oder Übergabe: **zeitslot_id** SERIAL · beginn TIMESTAMPTZ · ende TIMESTAMPTZ
- `uebergabeart` — Art der Übergabe eines Exemplars (Stammdaten): **uebergabeart_id** SERIAL · bezeichnung° VARCHAR(20)
- `verfuegbarkeit` ⟨3er⟩ — DREIFACHBEZIEHUNG: Wann ist welches Exemplar auf welchem Weg übergebbar?: **verfuegbarkeit_id** SERIAL · *exemplar_id* INT · *zeitslot_id* INT · *uebergabeart_id* INT

**Transaktion**

- `ausleihe` — Vorgang von der Anfrage bis zur Rückgabe; Kern des Transaktionsmodells: **ausleihe_id** SERIAL · *exemplar_id* INT · *ausleiher_id* INT · zeitraum_von DATE · zeitraum_bis DATE · status VARCHAR(15) · angefragt_am TIMESTAMPTZ · entschieden_am TIMESTAMPTZ · uebergeben_am DATE · zurueckgegeben_am DATE
- `uebergabe` ⟨3er⟩ — DREIFACHBEZIEHUNG: Wann und auf welchem Weg wechselt das Exemplar den Besitz — hin und zurück?: **uebergabe_id** SERIAL · *ausleihe_id* INT · *zeitslot_id* INT · *uebergabeart_id* INT · richtung VARCHAR(10) · sendungsnummer VARCHAR(40) · versandkosten NUMERIC(6,2) · erfolgt_am TIMESTAMPTZ

**Community**

- `bewertung_werk` — Bewertung und Kommentar zu einem Werk; nur nach abgeschlossener eigener Ausleihe zulässig: **bewertung_werk_id** SERIAL · *werk_id* INT · *verfasser_id* INT · *ausleihe_id*° INT · sterne SMALLINT · kommentar VARCHAR(1000) · erstellt_am TIMESTAMPTZ · gemeldet BOOLEAN
- `bewertung_person` ⟨3er⟩ — DREIFACHBEZIEHUNG: Wer bewertet wen aufgrund welcher konkreten Ausleihe?: **bewertung_person_id** SERIAL · *bewertender_id* INT · *bewerteter_id* INT · *ausleihe_id* INT · sterne SMALLINT · kommentar VARCHAR(500) · erstellt_am TIMESTAMPTZ
- `nachricht` — Direktnachricht zwischen zwei Personen, optional mit Bezug zu einer Ausleihe: **nachricht_id** SERIAL · *absender_id* INT · *empfaenger_id* INT · *ausleihe_id* INT · text VARCHAR(2000) · gesendet_am TIMESTAMPTZ · gelesen BOOLEAN
