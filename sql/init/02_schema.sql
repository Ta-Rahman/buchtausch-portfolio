-- =====================================================================
-- Schema der Buchtausch-App — ERZEUGT aus tools/model.py durch tools/build_ddl.py
-- Nicht von Hand ändern: Änderung in model.py, dann `python3 build_ddl.py`.
-- Läuft beim ersten Containerstart nach 01_extensions.sql (Docker-Entrypoint).
--
-- 21 Tabellen, 29 Beziehungen, 3 Dreifachbeziehungen.
-- Fremdschlüssel: ON DELETE RESTRICT als Standard (Konten werden deaktiviert,
-- nie gelöscht); CASCADE nur bei n:m-Auflösungstabellen; SET NULL bei optionalem Bezug.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Personen & Rollen
-- ---------------------------------------------------------------------

-- benutzer: Registrierte Person; tritt je nach Transaktion als verleihende oder ausleihende Person auf.
CREATE TABLE benutzer (
    benutzer_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    vorname VARCHAR(60) NOT NULL,  -- Vorname der Person.
    nachname VARCHAR(60) NOT NULL,  -- Nachname der Person.
    email VARCHAR(120) NOT NULL UNIQUE,  -- E-Mail-Adresse; dient als eindeutige Anmeldekennung.
    telefon VARCHAR(30),  -- Telefonnummer für die Abstimmung der Übergabe; optional.
    passwort_hash CHAR(60) NOT NULL,  -- bcrypt-Hash des Passworts; niemals Klartext.
    registriert_am DATE NOT NULL DEFAULT CURRENT_DATE,  -- Datum der Registrierung.
    kontostatus VARCHAR(15) NOT NULL DEFAULT 'aktiv',  -- aktiv | gesperrt | deaktiviert (CHECK-Constraint).
    CONSTRAINT chk_benutzer_kontostatus CHECK (kontostatus IN ('aktiv', 'gesperrt', 'deaktiviert'))  -- zulässige Werte für kontostatus
);
COMMENT ON TABLE benutzer IS 'Registrierte Person; tritt je nach Transaktion als verleihende oder ausleihende Person auf.';
COMMENT ON COLUMN benutzer.benutzer_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN benutzer.vorname IS 'Vorname der Person.';
COMMENT ON COLUMN benutzer.nachname IS 'Nachname der Person.';
COMMENT ON COLUMN benutzer.email IS 'E-Mail-Adresse; dient als eindeutige Anmeldekennung.';
COMMENT ON COLUMN benutzer.telefon IS 'Telefonnummer für die Abstimmung der Übergabe; optional.';
COMMENT ON COLUMN benutzer.passwort_hash IS 'bcrypt-Hash des Passworts; niemals Klartext.';
COMMENT ON COLUMN benutzer.registriert_am IS 'Datum der Registrierung.';
COMMENT ON COLUMN benutzer.kontostatus IS 'aktiv | gesperrt | deaktiviert (CHECK-Constraint).';

-- adresse: Wohn- und Übergabeadresse einer Person, einschließlich Geokoordinaten für die Umkreissuche.
CREATE TABLE adresse (
    adresse_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    benutzer_id INT NOT NULL UNIQUE REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; eindeutig, daher 1:1-Beziehung.
    strasse VARCHAR(80) NOT NULL,  -- Straßenname.
    hausnummer VARCHAR(10) NOT NULL,  -- Hausnummer inkl. Zusatz (z. B. 12a).
    plz VARCHAR(10) NOT NULL,  -- Postleitzahl; als Text, da führende Nullen erhalten bleiben müssen.
    ort VARCHAR(80) NOT NULL,  -- Ortsname.
    land CHAR(2) NOT NULL,  -- Ländercode nach ISO 3166-1 alpha-2.
    position GEOGRAPHY(Point,4326) NOT NULL,  -- Geografischer Punkt (WGS 84) für die Umkreissuche; GiST-indiziert.
    CONSTRAINT chk_adresse_land CHECK (land ~ '^[A-Z]{2}$')  -- Ländercode: genau zwei Großbuchstaben (ISO 3166-1 alpha-2).
);
COMMENT ON TABLE adresse IS 'Wohn- und Übergabeadresse einer Person, einschließlich Geokoordinaten für die Umkreissuche.';
COMMENT ON COLUMN adresse.adresse_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN adresse.benutzer_id IS 'Verweis auf benutzer; eindeutig, daher 1:1-Beziehung.';
COMMENT ON COLUMN adresse.strasse IS 'Straßenname.';
COMMENT ON COLUMN adresse.hausnummer IS 'Hausnummer inkl. Zusatz (z. B. 12a).';
COMMENT ON COLUMN adresse.plz IS 'Postleitzahl; als Text, da führende Nullen erhalten bleiben müssen.';
COMMENT ON COLUMN adresse.ort IS 'Ortsname.';
COMMENT ON COLUMN adresse.land IS 'Ländercode nach ISO 3166-1 alpha-2.';
COMMENT ON COLUMN adresse.position IS 'Geografischer Punkt (WGS 84) für die Umkreissuche; GiST-indiziert.';

-- rolle: Systemrolle zur Rechtevergabe (Stammdaten).
CREATE TABLE rolle (
    rolle_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    bezeichnung VARCHAR(30) NOT NULL UNIQUE,  -- Mitglied | Moderation | Administration.
    beschreibung VARCHAR(200)  -- Kurzbeschreibung der mit der Rolle verbundenen Rechte.
);
COMMENT ON TABLE rolle IS 'Systemrolle zur Rechtevergabe (Stammdaten).';
COMMENT ON COLUMN rolle.rolle_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN rolle.bezeichnung IS 'Mitglied | Moderation | Administration.';
COMMENT ON COLUMN rolle.beschreibung IS 'Kurzbeschreibung der mit der Rolle verbundenen Rechte.';

-- benutzer_rolle: Zuordnung von Systemrollen zu Personen (n:m-Auflösung).
CREATE TABLE benutzer_rolle (
    benutzer_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE CASCADE,  -- Teil des zusammengesetzten Primärschlüssels; Verweis auf benutzer.
    rolle_id INT NOT NULL REFERENCES rolle (rolle_id) ON DELETE CASCADE,  -- Teil des zusammengesetzten Primärschlüssels; Verweis auf rolle.
    zugewiesen_am DATE NOT NULL DEFAULT CURRENT_DATE,  -- Datum der Rollenzuweisung.
    PRIMARY KEY (benutzer_id, rolle_id)  -- zusammengesetzter Primärschlüssel
);
COMMENT ON TABLE benutzer_rolle IS 'Zuordnung von Systemrollen zu Personen (n:m-Auflösung).';
COMMENT ON COLUMN benutzer_rolle.benutzer_id IS 'Teil des zusammengesetzten Primärschlüssels; Verweis auf benutzer.';
COMMENT ON COLUMN benutzer_rolle.rolle_id IS 'Teil des zusammengesetzten Primärschlüssels; Verweis auf rolle.';
COMMENT ON COLUMN benutzer_rolle.zugewiesen_am IS 'Datum der Rollenzuweisung.';

-- ---------------------------------------------------------------------
-- Bibliografische Stammdaten
-- ---------------------------------------------------------------------

-- autor: Verfassende Person eines Werks (Stammdaten).
CREATE TABLE autor (
    autor_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    vorname VARCHAR(60),  -- Vorname; optional bei einnamigen Autor:innen.
    nachname VARCHAR(60) NOT NULL,  -- Nachname bzw. Künstlername.
    geburtsjahr SMALLINT  -- Geburtsjahr zur Unterscheidung namensgleicher Personen.
);
COMMENT ON TABLE autor IS 'Verfassende Person eines Werks (Stammdaten).';
COMMENT ON COLUMN autor.autor_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN autor.vorname IS 'Vorname; optional bei einnamigen Autor:innen.';
COMMENT ON COLUMN autor.nachname IS 'Nachname bzw. Künstlername.';
COMMENT ON COLUMN autor.geburtsjahr IS 'Geburtsjahr zur Unterscheidung namensgleicher Personen.';

-- verlag: Verlag, in dem ein Werk erschienen ist (Stammdaten).
CREATE TABLE verlag (
    verlag_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    name VARCHAR(100) NOT NULL UNIQUE,  -- Verlagsname; eindeutig.
    sitz VARCHAR(80)  -- Verlagsort.
);
COMMENT ON TABLE verlag IS 'Verlag, in dem ein Werk erschienen ist (Stammdaten).';
COMMENT ON COLUMN verlag.verlag_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN verlag.name IS 'Verlagsname; eindeutig.';
COMMENT ON COLUMN verlag.sitz IS 'Verlagsort.';

-- sprache: Sprache, in der ein Werk verfasst ist (Stammdaten).
CREATE TABLE sprache (
    sprache_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    iso_code CHAR(2) NOT NULL UNIQUE,  -- Sprachcode nach ISO 639-1 (z. B. de, en).
    bezeichnung VARCHAR(40) NOT NULL  -- Ausgeschriebener Sprachname.
);
COMMENT ON TABLE sprache IS 'Sprache, in der ein Werk verfasst ist (Stammdaten).';
COMMENT ON COLUMN sprache.sprache_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN sprache.iso_code IS 'Sprachcode nach ISO 639-1 (z. B. de, en).';
COMMENT ON COLUMN sprache.bezeichnung IS 'Ausgeschriebener Sprachname.';

-- genre: Genre zur Klassifikation von Werken (Stammdaten).
CREATE TABLE genre (
    genre_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    bezeichnung VARCHAR(50) NOT NULL UNIQUE  -- Genrebezeichnung, z. B. Roman, Sachbuch.
);
COMMENT ON TABLE genre IS 'Genre zur Klassifikation von Werken (Stammdaten).';
COMMENT ON COLUMN genre.genre_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN genre.bezeichnung IS 'Genrebezeichnung, z. B. Roman, Sachbuch.';

-- werk: Buchtitel als bibliografische Einheit — unabhängig davon, wie viele physische Bücher existieren.
CREATE TABLE werk (
    werk_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    titel VARCHAR(200) NOT NULL,  -- Haupttitel des Werks.
    untertitel VARCHAR(200),  -- Untertitel; optional.
    isbn13 CHAR(13) UNIQUE,  -- 13-stellige ISBN; eindeutig, aber bei alten Ausgaben optional.
    erscheinungsjahr SMALLINT,  -- Jahr der Veröffentlichung.
    verlag_id INT NOT NULL REFERENCES verlag (verlag_id) ON DELETE RESTRICT,  -- Verweis auf verlag.
    sprache_id INT NOT NULL REFERENCES sprache (sprache_id) ON DELETE RESTRICT,  -- Verweis auf sprache.
    CONSTRAINT chk_werk_isbn13 CHECK (isbn13 ~ '^[0-9]{13}$'),  -- ISBN-13 besteht aus genau 13 Ziffern.
    CONSTRAINT chk_werk_jahr CHECK (erscheinungsjahr BETWEEN 1450 AND 2100)  -- Plausibilitätsgrenze für das Erscheinungsjahr.
);
COMMENT ON TABLE werk IS 'Buchtitel als bibliografische Einheit — unabhängig davon, wie viele physische Bücher existieren.';
COMMENT ON COLUMN werk.werk_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN werk.titel IS 'Haupttitel des Werks.';
COMMENT ON COLUMN werk.untertitel IS 'Untertitel; optional.';
COMMENT ON COLUMN werk.isbn13 IS '13-stellige ISBN; eindeutig, aber bei alten Ausgaben optional.';
COMMENT ON COLUMN werk.erscheinungsjahr IS 'Jahr der Veröffentlichung.';
COMMENT ON COLUMN werk.verlag_id IS 'Verweis auf verlag.';
COMMENT ON COLUMN werk.sprache_id IS 'Verweis auf sprache.';

-- werk_autor: Zuordnung von Werken zu verfassenden Personen (n:m-Auflösung).
CREATE TABLE werk_autor (
    werk_id INT NOT NULL REFERENCES werk (werk_id) ON DELETE CASCADE,  -- Teil des zusammengesetzten Primärschlüssels; Verweis auf werk.
    autor_id INT NOT NULL REFERENCES autor (autor_id) ON DELETE CASCADE,  -- Teil des zusammengesetzten Primärschlüssels; Verweis auf autor.
    beitragsart VARCHAR(20) NOT NULL,  -- Autor | Herausgeber | Übersetzung.
    CONSTRAINT chk_werk_autor_beitragsart CHECK (beitragsart IN ('Autor', 'Herausgeber', 'Übersetzung')),  -- zulässige Werte für beitragsart
    PRIMARY KEY (werk_id, autor_id)  -- zusammengesetzter Primärschlüssel
);
COMMENT ON TABLE werk_autor IS 'Zuordnung von Werken zu verfassenden Personen (n:m-Auflösung).';
COMMENT ON COLUMN werk_autor.werk_id IS 'Teil des zusammengesetzten Primärschlüssels; Verweis auf werk.';
COMMENT ON COLUMN werk_autor.autor_id IS 'Teil des zusammengesetzten Primärschlüssels; Verweis auf autor.';
COMMENT ON COLUMN werk_autor.beitragsart IS 'Autor | Herausgeber | Übersetzung.';

-- werk_genre: Zuordnung von Werken zu Genres (n:m-Auflösung).
CREATE TABLE werk_genre (
    werk_id INT NOT NULL REFERENCES werk (werk_id) ON DELETE CASCADE,  -- Teil des zusammengesetzten Primärschlüssels; Verweis auf werk.
    genre_id INT NOT NULL REFERENCES genre (genre_id) ON DELETE CASCADE,  -- Teil des zusammengesetzten Primärschlüssels; Verweis auf genre.
    PRIMARY KEY (werk_id, genre_id)  -- zusammengesetzter Primärschlüssel
);
COMMENT ON TABLE werk_genre IS 'Zuordnung von Werken zu Genres (n:m-Auflösung).';
COMMENT ON COLUMN werk_genre.werk_id IS 'Teil des zusammengesetzten Primärschlüssels; Verweis auf werk.';
COMMENT ON COLUMN werk_genre.genre_id IS 'Teil des zusammengesetzten Primärschlüssels; Verweis auf genre.';

-- ---------------------------------------------------------------------
-- Besitz & Verfügbarkeit
-- ---------------------------------------------------------------------

-- zustand: Ordinale Zustandsskala eines Exemplars (Stammdaten).
CREATE TABLE zustand (
    zustand_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    stufe SMALLINT NOT NULL UNIQUE,  -- 1 = neuwertig bis 5 = stark abgenutzt; erlaubt Sortierung und Filterung.
    bezeichnung VARCHAR(30) NOT NULL,  -- Sprechende Bezeichnung der Stufe.
    beschreibung VARCHAR(200),  -- Kriterien der Einstufung.
    CONSTRAINT chk_zustand_stufe CHECK (stufe BETWEEN 1 AND 5)  -- Ordinale Skala 1 (neuwertig) bis 5 (stark abgenutzt).
);
COMMENT ON TABLE zustand IS 'Ordinale Zustandsskala eines Exemplars (Stammdaten).';
COMMENT ON COLUMN zustand.zustand_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN zustand.stufe IS '1 = neuwertig bis 5 = stark abgenutzt; erlaubt Sortierung und Filterung.';
COMMENT ON COLUMN zustand.bezeichnung IS 'Sprechende Bezeichnung der Stufe.';
COMMENT ON COLUMN zustand.beschreibung IS 'Kriterien der Einstufung.';

-- exemplar: Physisches Buch im Besitz einer bestimmten Person — die eigentliche Leiheinheit.
CREATE TABLE exemplar (
    exemplar_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    werk_id INT NOT NULL REFERENCES werk (werk_id) ON DELETE RESTRICT,  -- Verweis auf das bibliografische Werk.
    besitzer_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; die Person, der das Exemplar gehört.
    zustand_id INT NOT NULL REFERENCES zustand (zustand_id) ON DELETE RESTRICT,  -- Verweis auf zustand.
    max_leihdauer_tage SMALLINT NOT NULL,  -- Maximale Leihdauer, die die besitzende Person zulässt.
    versand_moeglich BOOLEAN NOT NULL DEFAULT FALSE,  -- Gibt an, ob Postversand angeboten wird.
    anmerkung VARCHAR(300),  -- Freitext, z. B. Widmung oder Mängel.
    status VARCHAR(15) NOT NULL DEFAULT 'verfuegbar',  -- verfuegbar | pausiert | entfernt (CHECK-Constraint).
    eingestellt_am DATE NOT NULL DEFAULT CURRENT_DATE,  -- Datum der Einstellung in die Plattform.
    CONSTRAINT chk_exemplar_status CHECK (status IN ('verfuegbar', 'pausiert', 'entfernt')),  -- zulässige Werte für status
    CONSTRAINT chk_exemplar_leihdauer CHECK (max_leihdauer_tage > 0)  -- Eine Leihdauer von null oder negativen Tagen ist sinnlos.
);
COMMENT ON TABLE exemplar IS 'Physisches Buch im Besitz einer bestimmten Person — die eigentliche Leiheinheit.';
COMMENT ON COLUMN exemplar.exemplar_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN exemplar.werk_id IS 'Verweis auf das bibliografische Werk.';
COMMENT ON COLUMN exemplar.besitzer_id IS 'Verweis auf benutzer; die Person, der das Exemplar gehört.';
COMMENT ON COLUMN exemplar.zustand_id IS 'Verweis auf zustand.';
COMMENT ON COLUMN exemplar.max_leihdauer_tage IS 'Maximale Leihdauer, die die besitzende Person zulässt.';
COMMENT ON COLUMN exemplar.versand_moeglich IS 'Gibt an, ob Postversand angeboten wird.';
COMMENT ON COLUMN exemplar.anmerkung IS 'Freitext, z. B. Widmung oder Mängel.';
COMMENT ON COLUMN exemplar.status IS 'verfuegbar | pausiert | entfernt (CHECK-Constraint).';
COMMENT ON COLUMN exemplar.eingestellt_am IS 'Datum der Einstellung in die Plattform.';

-- zeitslot: Konkretes Zeitfenster für Verfügbarkeit oder Übergabe.
CREATE TABLE zeitslot (
    zeitslot_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    beginn TIMESTAMPTZ NOT NULL,  -- Beginn des Zeitfensters inkl. Zeitzone.
    ende TIMESTAMPTZ NOT NULL,  -- Ende des Zeitfensters; CHECK erzwingt ende > beginn.
    CONSTRAINT chk_zeitslot_reihenfolge CHECK (ende > beginn)  -- Ein Zeitfenster muss eine positive Dauer haben.
);
COMMENT ON TABLE zeitslot IS 'Konkretes Zeitfenster für Verfügbarkeit oder Übergabe.';
COMMENT ON COLUMN zeitslot.zeitslot_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN zeitslot.beginn IS 'Beginn des Zeitfensters inkl. Zeitzone.';
COMMENT ON COLUMN zeitslot.ende IS 'Ende des Zeitfensters; CHECK erzwingt ende > beginn.';

-- uebergabeart: Art der Übergabe eines Exemplars (Stammdaten).
CREATE TABLE uebergabeart (
    uebergabeart_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    bezeichnung VARCHAR(20) NOT NULL UNIQUE  -- Abholung | Postversand.
);
COMMENT ON TABLE uebergabeart IS 'Art der Übergabe eines Exemplars (Stammdaten).';
COMMENT ON COLUMN uebergabeart.uebergabeart_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN uebergabeart.bezeichnung IS 'Abholung | Postversand.';

-- verfuegbarkeit (Dreifachbeziehung): DREIFACHBEZIEHUNG: Wann ist welches Exemplar auf welchem Weg übergebbar?
CREATE TABLE verfuegbarkeit (
    verfuegbarkeit_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    exemplar_id INT NOT NULL REFERENCES exemplar (exemplar_id) ON DELETE RESTRICT,  -- Verweis auf exemplar.
    zeitslot_id INT NOT NULL REFERENCES zeitslot (zeitslot_id) ON DELETE RESTRICT,  -- Verweis auf zeitslot.
    uebergabeart_id INT NOT NULL REFERENCES uebergabeart (uebergabeart_id) ON DELETE RESTRICT,  -- Verweis auf uebergabeart; UNIQUE über alle drei Fremdschlüssel.
    CONSTRAINT uq_verfuegbarkeit UNIQUE (exemplar_id, zeitslot_id, uebergabeart_id)  -- Dieselbe Kombination aus Exemplar, Zeitfenster und Übergabeart nur einmal.
);
COMMENT ON TABLE verfuegbarkeit IS 'DREIFACHBEZIEHUNG: Wann ist welches Exemplar auf welchem Weg übergebbar?';
COMMENT ON COLUMN verfuegbarkeit.verfuegbarkeit_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN verfuegbarkeit.exemplar_id IS 'Verweis auf exemplar.';
COMMENT ON COLUMN verfuegbarkeit.zeitslot_id IS 'Verweis auf zeitslot.';
COMMENT ON COLUMN verfuegbarkeit.uebergabeart_id IS 'Verweis auf uebergabeart; UNIQUE über alle drei Fremdschlüssel.';

-- ---------------------------------------------------------------------
-- Transaktion
-- ---------------------------------------------------------------------

-- ausleihe: Vorgang von der Anfrage bis zur Rückgabe; Kern des Transaktionsmodells.
CREATE TABLE ausleihe (
    ausleihe_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    exemplar_id INT NOT NULL REFERENCES exemplar (exemplar_id) ON DELETE RESTRICT,  -- Verweis auf das ausgeliehene Exemplar.
    ausleiher_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; die ausleihende Person.
    zeitraum_von DATE NOT NULL,  -- Beginn des gewünschten bzw. vereinbarten Leihzeitraums.
    zeitraum_bis DATE NOT NULL,  -- Ende des Leihzeitraums; CHECK erzwingt bis >= von.
    status VARCHAR(15) NOT NULL DEFAULT 'angefragt',  -- angefragt | bestaetigt | laufend | abgeschlossen | abgelehnt | storniert | verspaetet.
    angefragt_am TIMESTAMPTZ NOT NULL DEFAULT now(),  -- Zeitpunkt der Anfrage.
    entschieden_am TIMESTAMPTZ,  -- Zeitpunkt der Bestätigung oder Ablehnung.
    uebergeben_am DATE,  -- Tatsächlicher Übergabetag.
    zurueckgegeben_am DATE,  -- Tatsächlicher Rückgabetag.
    CONSTRAINT chk_ausleihe_status CHECK (status IN ('angefragt', 'bestaetigt', 'laufend', 'abgeschlossen', 'abgelehnt', 'storniert', 'verspaetet')),  -- zulässige Werte für status
    CONSTRAINT chk_ausleihe_zeitraum CHECK (zeitraum_bis >= zeitraum_von),  -- Leihzeitraum darf nicht rückwärts laufen.
    CONSTRAINT chk_ausleihe_rueckgabe CHECK (zurueckgegeben_am IS NULL OR uebergeben_am IS NULL OR zurueckgegeben_am >= uebergeben_am),  -- Rückgabe kann nicht vor der Übergabe liegen.
    CONSTRAINT excl_ausleihe_doppelbuchung EXCLUDE USING gist (exemplar_id WITH =, daterange(zeitraum_von, zeitraum_bis, '[]') WITH &&) WHERE (status IN ('bestaetigt', 'laufend', 'verspaetet'))  -- GESCHÄFTSREGEL 1 (Double-Booking): Für dasselbe Exemplar dürfen sich zwei bestätigte, laufende oder verspätete Leihzeiträume nicht überlappen (btree_gist).
);
COMMENT ON TABLE ausleihe IS 'Vorgang von der Anfrage bis zur Rückgabe; Kern des Transaktionsmodells.';
COMMENT ON COLUMN ausleihe.ausleihe_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN ausleihe.exemplar_id IS 'Verweis auf das ausgeliehene Exemplar.';
COMMENT ON COLUMN ausleihe.ausleiher_id IS 'Verweis auf benutzer; die ausleihende Person.';
COMMENT ON COLUMN ausleihe.zeitraum_von IS 'Beginn des gewünschten bzw. vereinbarten Leihzeitraums.';
COMMENT ON COLUMN ausleihe.zeitraum_bis IS 'Ende des Leihzeitraums; CHECK erzwingt bis >= von.';
COMMENT ON COLUMN ausleihe.status IS 'angefragt | bestaetigt | laufend | abgeschlossen | abgelehnt | storniert | verspaetet.';
COMMENT ON COLUMN ausleihe.angefragt_am IS 'Zeitpunkt der Anfrage.';
COMMENT ON COLUMN ausleihe.entschieden_am IS 'Zeitpunkt der Bestätigung oder Ablehnung.';
COMMENT ON COLUMN ausleihe.uebergeben_am IS 'Tatsächlicher Übergabetag.';
COMMENT ON COLUMN ausleihe.zurueckgegeben_am IS 'Tatsächlicher Rückgabetag.';

-- uebergabe (Dreifachbeziehung): DREIFACHBEZIEHUNG: Wann und auf welchem Weg wechselt das Exemplar den Besitz — hin und zurück?
CREATE TABLE uebergabe (
    uebergabe_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    ausleihe_id INT NOT NULL REFERENCES ausleihe (ausleihe_id) ON DELETE RESTRICT,  -- Verweis auf ausleihe.
    zeitslot_id INT REFERENCES zeitslot (zeitslot_id) ON DELETE RESTRICT,  -- Verweis auf zeitslot; nur bei persönlicher Abholung belegt.
    uebergabeart_id INT NOT NULL REFERENCES uebergabeart (uebergabeart_id) ON DELETE RESTRICT,  -- Verweis auf uebergabeart.
    richtung VARCHAR(10) NOT NULL,  -- hinweg | rueckweg (CHECK-Constraint).
    sendungsnummer VARCHAR(40),  -- Sendungsnummer; nur bei Postversand belegt.
    versandkosten NUMERIC(6,2),  -- Portokosten in Euro; nur bei Postversand belegt.
    erfolgt_am TIMESTAMPTZ,  -- Zeitpunkt der tatsächlichen Übergabe.
    CONSTRAINT chk_uebergabe_richtung CHECK (richtung IN ('hinweg', 'rueckweg')),  -- zulässige Werte für richtung
    CONSTRAINT uq_uebergabe_richtung UNIQUE (ausleihe_id, richtung),  -- Genau eine Hin- und eine Rückübergabe je Ausleihe.
    CONSTRAINT chk_uebergabe_weg CHECK (num_nonnulls(zeitslot_id, sendungsnummer) = 1),  -- Entweder Abhol-Zeitfenster oder Sendungsnummer, nie beides, nie keins.
    CONSTRAINT chk_uebergabe_versandkosten CHECK (versandkosten IS NULL OR versandkosten >= 0)  -- Versandkosten sind nicht negativ.
);
COMMENT ON TABLE uebergabe IS 'DREIFACHBEZIEHUNG: Wann und auf welchem Weg wechselt das Exemplar den Besitz — hin und zurück?';
COMMENT ON COLUMN uebergabe.uebergabe_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN uebergabe.ausleihe_id IS 'Verweis auf ausleihe.';
COMMENT ON COLUMN uebergabe.zeitslot_id IS 'Verweis auf zeitslot; nur bei persönlicher Abholung belegt.';
COMMENT ON COLUMN uebergabe.uebergabeart_id IS 'Verweis auf uebergabeart.';
COMMENT ON COLUMN uebergabe.richtung IS 'hinweg | rueckweg (CHECK-Constraint).';
COMMENT ON COLUMN uebergabe.sendungsnummer IS 'Sendungsnummer; nur bei Postversand belegt.';
COMMENT ON COLUMN uebergabe.versandkosten IS 'Portokosten in Euro; nur bei Postversand belegt.';
COMMENT ON COLUMN uebergabe.erfolgt_am IS 'Zeitpunkt der tatsächlichen Übergabe.';

-- ---------------------------------------------------------------------
-- Community
-- ---------------------------------------------------------------------

-- bewertung_werk: Bewertung und Kommentar zu einem Werk; nur nach abgeschlossener eigener Ausleihe zulässig.
CREATE TABLE bewertung_werk (
    bewertung_werk_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    werk_id INT NOT NULL REFERENCES werk (werk_id) ON DELETE RESTRICT,  -- Verweis auf das bewertete Werk.
    verfasser_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; die bewertende Person.
    ausleihe_id INT NOT NULL UNIQUE REFERENCES ausleihe (ausleihe_id) ON DELETE RESTRICT,  -- Verweis auf ausleihe als Berechtigungsnachweis; eindeutig, daher genau eine Werkbewertung je Ausleihe.
    sterne SMALLINT NOT NULL,  -- Bewertung von 1 bis 5 (CHECK-Constraint).
    kommentar VARCHAR(1000),  -- Freitextkommentar; optional.
    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT now(),  -- Zeitpunkt der Erstellung.
    gemeldet BOOLEAN NOT NULL DEFAULT FALSE,  -- Kennzeichen für die Moderation.
    CONSTRAINT chk_bewertung_werk_sterne CHECK (sterne BETWEEN 1 AND 5)  -- Sternebewertung von 1 bis 5.
);
COMMENT ON TABLE bewertung_werk IS 'Bewertung und Kommentar zu einem Werk; nur nach abgeschlossener eigener Ausleihe zulässig.';
COMMENT ON COLUMN bewertung_werk.bewertung_werk_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN bewertung_werk.werk_id IS 'Verweis auf das bewertete Werk.';
COMMENT ON COLUMN bewertung_werk.verfasser_id IS 'Verweis auf benutzer; die bewertende Person.';
COMMENT ON COLUMN bewertung_werk.ausleihe_id IS 'Verweis auf ausleihe als Berechtigungsnachweis; eindeutig, daher genau eine Werkbewertung je Ausleihe.';
COMMENT ON COLUMN bewertung_werk.sterne IS 'Bewertung von 1 bis 5 (CHECK-Constraint).';
COMMENT ON COLUMN bewertung_werk.kommentar IS 'Freitextkommentar; optional.';
COMMENT ON COLUMN bewertung_werk.erstellt_am IS 'Zeitpunkt der Erstellung.';
COMMENT ON COLUMN bewertung_werk.gemeldet IS 'Kennzeichen für die Moderation.';

-- bewertung_person (Dreifachbeziehung): DREIFACHBEZIEHUNG: Wer bewertet wen aufgrund welcher konkreten Ausleihe?
CREATE TABLE bewertung_person (
    bewertung_person_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    bewertender_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; die bewertende Person.
    bewerteter_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; die bewertete Person. CHECK verhindert Selbstbewertung.
    ausleihe_id INT NOT NULL REFERENCES ausleihe (ausleihe_id) ON DELETE RESTRICT,  -- Verweis auf ausleihe; UNIQUE über bewertender_id und ausleihe_id.
    sterne SMALLINT NOT NULL,  -- Bewertung von 1 bis 5 (CHECK-Constraint).
    kommentar VARCHAR(500),  -- Freitextkommentar; optional.
    erstellt_am TIMESTAMPTZ NOT NULL DEFAULT now(),  -- Zeitpunkt der Erstellung.
    CONSTRAINT chk_bewertung_person_sterne CHECK (sterne BETWEEN 1 AND 5),  -- Sternebewertung von 1 bis 5.
    CONSTRAINT chk_bewertung_person_selbst CHECK (bewertender_id <> bewerteter_id),  -- Niemand bewertet sich selbst.
    CONSTRAINT uq_bewertung_person UNIQUE (bewertender_id, ausleihe_id)  -- Je Ausleihe bewertet eine Person die Gegenseite höchstens einmal.
);
COMMENT ON TABLE bewertung_person IS 'DREIFACHBEZIEHUNG: Wer bewertet wen aufgrund welcher konkreten Ausleihe?';
COMMENT ON COLUMN bewertung_person.bewertung_person_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN bewertung_person.bewertender_id IS 'Verweis auf benutzer; die bewertende Person.';
COMMENT ON COLUMN bewertung_person.bewerteter_id IS 'Verweis auf benutzer; die bewertete Person. CHECK verhindert Selbstbewertung.';
COMMENT ON COLUMN bewertung_person.ausleihe_id IS 'Verweis auf ausleihe; UNIQUE über bewertender_id und ausleihe_id.';
COMMENT ON COLUMN bewertung_person.sterne IS 'Bewertung von 1 bis 5 (CHECK-Constraint).';
COMMENT ON COLUMN bewertung_person.kommentar IS 'Freitextkommentar; optional.';
COMMENT ON COLUMN bewertung_person.erstellt_am IS 'Zeitpunkt der Erstellung.';

-- nachricht: Direktnachricht zwischen zwei Personen, optional mit Bezug zu einer Ausleihe.
CREATE TABLE nachricht (
    nachricht_id SERIAL PRIMARY KEY,  -- Künstlicher Primärschlüssel.
    absender_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; sendende Person.
    empfaenger_id INT NOT NULL REFERENCES benutzer (benutzer_id) ON DELETE RESTRICT,  -- Verweis auf benutzer; empfangende Person.
    ausleihe_id INT REFERENCES ausleihe (ausleihe_id) ON DELETE SET NULL,  -- Verweis auf ausleihe; optional, für Nachrichten ohne Vorgangsbezug.
    text VARCHAR(2000) NOT NULL,  -- Nachrichtentext.
    gesendet_am TIMESTAMPTZ NOT NULL DEFAULT now(),  -- Sendezeitpunkt.
    gelesen BOOLEAN NOT NULL DEFAULT FALSE,  -- Lesebestätigung.
    CONSTRAINT chk_nachricht_selbst CHECK (absender_id <> empfaenger_id)  -- Keine Nachricht an sich selbst.
);
COMMENT ON TABLE nachricht IS 'Direktnachricht zwischen zwei Personen, optional mit Bezug zu einer Ausleihe.';
COMMENT ON COLUMN nachricht.nachricht_id IS 'Künstlicher Primärschlüssel.';
COMMENT ON COLUMN nachricht.absender_id IS 'Verweis auf benutzer; sendende Person.';
COMMENT ON COLUMN nachricht.empfaenger_id IS 'Verweis auf benutzer; empfangende Person.';
COMMENT ON COLUMN nachricht.ausleihe_id IS 'Verweis auf ausleihe; optional, für Nachrichten ohne Vorgangsbezug.';
COMMENT ON COLUMN nachricht.text IS 'Nachrichtentext.';
COMMENT ON COLUMN nachricht.gesendet_am IS 'Sendezeitpunkt.';
COMMENT ON COLUMN nachricht.gelesen IS 'Lesebestätigung.';

-- ---------------------------------------------------------------------
-- Zusammenfassung: 21 Tabellen, 29 Fremdschlüssel, 13 UNIQUE, 19 CHECK, 1 EXCLUDE.
-- ---------------------------------------------------------------------
