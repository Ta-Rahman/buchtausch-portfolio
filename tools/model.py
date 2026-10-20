#!/usr/bin/env python3
"""
Single Source of Truth des Datenmodells der Buchtausch-App.

Aus dieser Datei werden erzeugt:
  - build_erm.py   -> ER-Diagramm (PNG/SVG/PDF)
  - build_dict.py  -> Datenwörterbuch (Markdown)
  - build_ddl.py   -> CREATE-TABLE-Skript (Phase 2)

Vorteil: Modell, Diagramm, Wörterbuch und Schema können nicht auseinanderlaufen.
"""

GROUPS = {
    "personen":    ("Personen & Rollen",         "#E8EEF7", "#2F5597"),
    "biblio":      ("Bibliografische Stammdaten","#EAF3EA", "#3C7A3C"),
    "besitz":      ("Besitz & Verfügbarkeit",    "#FDF2E3", "#B5761E"),
    "transaktion": ("Transaktion",               "#F6E9EE", "#94355A"),
    "community":   ("Community",                 "#F0EDF7", "#5B4A94"),
}

# entitaet: (gruppe, zweck, [(attribut, datentyp, schluessel, beschreibung)])
E = {
 "benutzer": ("personen", "Registrierte Person; tritt je nach Transaktion als verleihende oder ausleihende Person auf.", [
    ("benutzer_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("vorname","VARCHAR(60)","","Vorname der Person."),
    ("nachname","VARCHAR(60)","","Nachname der Person."),
    ("email","VARCHAR(120)","UK","E-Mail-Adresse; dient als eindeutige Anmeldekennung."),
    ("telefon","VARCHAR(30)","","Telefonnummer für die Abstimmung der Übergabe; optional."),
    ("passwort_hash","CHAR(60)","","bcrypt-Hash des Passworts; niemals Klartext."),
    ("registriert_am","DATE","","Datum der Registrierung."),
    ("kontostatus","VARCHAR(15)","","aktiv | gesperrt | deaktiviert (CHECK-Constraint)."),
 ]),
 "adresse": ("personen", "Wohn- und Übergabeadresse einer Person, einschließlich Geokoordinaten für die Umkreissuche.", [
    ("adresse_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("benutzer_id","INT","FK UK","Verweis auf benutzer; eindeutig, daher 1:1-Beziehung."),
    ("strasse","VARCHAR(80)","","Straßenname."),
    ("hausnummer","VARCHAR(10)","","Hausnummer inkl. Zusatz (z. B. 12a)."),
    ("plz","VARCHAR(10)","","Postleitzahl; als Text, da führende Nullen erhalten bleiben müssen."),
    ("ort","VARCHAR(80)","","Ortsname."),
    ("land","CHAR(2)","","Ländercode nach ISO 3166-1 alpha-2."),
    ("position","GEOGRAPHY(Point,4326)","","Geografischer Punkt (WGS 84) für die Umkreissuche; GiST-indiziert."),
 ]),
 "rolle": ("personen", "Systemrolle zur Rechtevergabe (Stammdaten).", [
    ("rolle_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("bezeichnung","VARCHAR(30)","UK","Mitglied | Moderation | Administration."),
    ("beschreibung","VARCHAR(200)","","Kurzbeschreibung der mit der Rolle verbundenen Rechte."),
 ]),
 "benutzer_rolle": ("personen", "Zuordnung von Systemrollen zu Personen (n:m-Auflösung).", [
    ("benutzer_id","INT","PK FK","Teil des zusammengesetzten Primärschlüssels; Verweis auf benutzer."),
    ("rolle_id","INT","PK FK","Teil des zusammengesetzten Primärschlüssels; Verweis auf rolle."),
    ("zugewiesen_am","DATE","","Datum der Rollenzuweisung."),
 ]),

 "autor": ("biblio", "Verfassende Person eines Werks (Stammdaten).", [
    ("autor_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("vorname","VARCHAR(60)","","Vorname; optional bei einnamigen Autor:innen."),
    ("nachname","VARCHAR(60)","","Nachname bzw. Künstlername."),
    ("geburtsjahr","SMALLINT","","Geburtsjahr zur Unterscheidung namensgleicher Personen."),
 ]),
 "verlag": ("biblio", "Verlag, in dem ein Werk erschienen ist (Stammdaten).", [
    ("verlag_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("name","VARCHAR(100)","UK","Verlagsname; eindeutig."),
    ("sitz","VARCHAR(80)","","Verlagsort."),
 ]),
 "sprache": ("biblio", "Sprache, in der ein Werk verfasst ist (Stammdaten).", [
    ("sprache_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("iso_code","CHAR(2)","UK","Sprachcode nach ISO 639-1 (z. B. de, en)."),
    ("bezeichnung","VARCHAR(40)","","Ausgeschriebener Sprachname."),
 ]),
 "genre": ("biblio", "Genre zur Klassifikation von Werken (Stammdaten).", [
    ("genre_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("bezeichnung","VARCHAR(50)","UK","Genrebezeichnung, z. B. Roman, Sachbuch."),
 ]),
 "werk": ("biblio", "Buchtitel als bibliografische Einheit — unabhängig davon, wie viele physische Bücher existieren.", [
    ("werk_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("titel","VARCHAR(200)","","Haupttitel des Werks."),
    ("untertitel","VARCHAR(200)","","Untertitel; optional."),
    ("isbn13","CHAR(13)","UK","13-stellige ISBN; eindeutig, aber bei alten Ausgaben optional."),
    ("erscheinungsjahr","SMALLINT","","Jahr der Veröffentlichung."),
    ("verlag_id","INT","FK","Verweis auf verlag."),
    ("sprache_id","INT","FK","Verweis auf sprache."),
 ]),
 "werk_autor": ("biblio", "Zuordnung von Werken zu verfassenden Personen (n:m-Auflösung).", [
    ("werk_id","INT","PK FK","Teil des zusammengesetzten Primärschlüssels; Verweis auf werk."),
    ("autor_id","INT","PK FK","Teil des zusammengesetzten Primärschlüssels; Verweis auf autor."),
    ("beitragsart","VARCHAR(20)","","Autor | Herausgeber | Übersetzung."),
 ]),
 "werk_genre": ("biblio", "Zuordnung von Werken zu Genres (n:m-Auflösung).", [
    ("werk_id","INT","PK FK","Teil des zusammengesetzten Primärschlüssels; Verweis auf werk."),
    ("genre_id","INT","PK FK","Teil des zusammengesetzten Primärschlüssels; Verweis auf genre."),
 ]),

 "zustand": ("besitz", "Ordinale Zustandsskala eines Exemplars (Stammdaten).", [
    ("zustand_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("stufe","SMALLINT","UK","1 = neuwertig bis 5 = stark abgenutzt; erlaubt Sortierung und Filterung."),
    ("bezeichnung","VARCHAR(30)","","Sprechende Bezeichnung der Stufe."),
    ("beschreibung","VARCHAR(200)","","Kriterien der Einstufung."),
 ]),
 "exemplar": ("besitz", "Physisches Buch im Besitz einer bestimmten Person — die eigentliche Leiheinheit.", [
    ("exemplar_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("werk_id","INT","FK","Verweis auf das bibliografische Werk."),
    ("besitzer_id","INT","FK","Verweis auf benutzer; die Person, der das Exemplar gehört."),
    ("zustand_id","INT","FK","Verweis auf zustand."),
    ("max_leihdauer_tage","SMALLINT","","Maximale Leihdauer, die die besitzende Person zulässt."),
    ("versand_moeglich","BOOLEAN","","Gibt an, ob Postversand angeboten wird."),
    ("anmerkung","VARCHAR(300)","","Freitext, z. B. Widmung oder Mängel."),
    ("status","VARCHAR(15)","","verfuegbar | pausiert | entfernt (CHECK-Constraint)."),
    ("eingestellt_am","DATE","","Datum der Einstellung in die Plattform."),
 ]),
 "zeitslot": ("besitz", "Konkretes Zeitfenster für Verfügbarkeit oder Übergabe.", [
    ("zeitslot_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("beginn","TIMESTAMPTZ","","Beginn des Zeitfensters inkl. Zeitzone."),
    ("ende","TIMESTAMPTZ","","Ende des Zeitfensters; CHECK erzwingt ende > beginn."),
 ]),
 "uebergabeart": ("besitz", "Art der Übergabe eines Exemplars (Stammdaten).", [
    ("uebergabeart_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("bezeichnung","VARCHAR(20)","UK","Abholung | Postversand."),
 ]),
 "verfuegbarkeit": ("besitz", "DREIFACHBEZIEHUNG: Wann ist welches Exemplar auf welchem Weg übergebbar?", [
    ("verfuegbarkeit_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("exemplar_id","INT","FK","Verweis auf exemplar."),
    ("zeitslot_id","INT","FK","Verweis auf zeitslot."),
    ("uebergabeart_id","INT","FK","Verweis auf uebergabeart; UNIQUE über alle drei Fremdschlüssel."),
 ]),

 "ausleihe": ("transaktion", "Vorgang von der Anfrage bis zur Rückgabe; Kern des Transaktionsmodells.", [
    ("ausleihe_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("exemplar_id","INT","FK","Verweis auf das ausgeliehene Exemplar."),
    ("ausleiher_id","INT","FK","Verweis auf benutzer; die ausleihende Person."),
    ("zeitraum_von","DATE","","Beginn des gewünschten bzw. vereinbarten Leihzeitraums."),
    ("zeitraum_bis","DATE","","Ende des Leihzeitraums; CHECK erzwingt bis >= von."),
    ("status","VARCHAR(15)","","angefragt | bestaetigt | laufend | abgeschlossen | abgelehnt | storniert | verspaetet."),
    ("angefragt_am","TIMESTAMPTZ","","Zeitpunkt der Anfrage."),
    ("entschieden_am","TIMESTAMPTZ","","Zeitpunkt der Bestätigung oder Ablehnung."),
    ("uebergeben_am","DATE","","Tatsächlicher Übergabetag."),
    ("zurueckgegeben_am","DATE","","Tatsächlicher Rückgabetag."),
 ]),
 "uebergabe": ("transaktion", "DREIFACHBEZIEHUNG: Wann und auf welchem Weg wechselt das Exemplar den Besitz — hin und zurück?", [
    ("uebergabe_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("ausleihe_id","INT","FK","Verweis auf ausleihe."),
    ("zeitslot_id","INT","FK","Verweis auf zeitslot; nur bei persönlicher Abholung belegt."),
    ("uebergabeart_id","INT","FK","Verweis auf uebergabeart."),
    ("richtung","VARCHAR(10)","","hinweg | rueckweg (CHECK-Constraint)."),
    ("sendungsnummer","VARCHAR(40)","","Sendungsnummer; nur bei Postversand belegt."),
    ("versandkosten","NUMERIC(6,2)","","Portokosten in Euro; nur bei Postversand belegt."),
    ("erfolgt_am","TIMESTAMPTZ","","Zeitpunkt der tatsächlichen Übergabe."),
 ]),

 "bewertung_werk": ("community", "Bewertung und Kommentar zu einem Werk; nur nach abgeschlossener eigener Ausleihe zulässig.", [
    ("bewertung_werk_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("werk_id","INT","FK","Verweis auf das bewertete Werk."),
    ("verfasser_id","INT","FK","Verweis auf benutzer; die bewertende Person."),
    ("ausleihe_id","INT","FK UK","Verweis auf ausleihe als Berechtigungsnachweis; eindeutig, daher genau eine Werkbewertung je Ausleihe."),
    ("sterne","SMALLINT","","Bewertung von 1 bis 5 (CHECK-Constraint)."),
    ("kommentar","VARCHAR(1000)","","Freitextkommentar; optional."),
    ("erstellt_am","TIMESTAMPTZ","","Zeitpunkt der Erstellung."),
    ("gemeldet","BOOLEAN","","Kennzeichen für die Moderation."),
 ]),
 "bewertung_person": ("community", "DREIFACHBEZIEHUNG: Wer bewertet wen aufgrund welcher konkreten Ausleihe?", [
    ("bewertung_person_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("bewertender_id","INT","FK","Verweis auf benutzer; die bewertende Person."),
    ("bewerteter_id","INT","FK","Verweis auf benutzer; die bewertete Person. CHECK verhindert Selbstbewertung."),
    ("ausleihe_id","INT","FK","Verweis auf ausleihe; UNIQUE über bewertender_id und ausleihe_id."),
    ("sterne","SMALLINT","","Bewertung von 1 bis 5 (CHECK-Constraint)."),
    ("kommentar","VARCHAR(500)","","Freitextkommentar; optional."),
    ("erstellt_am","TIMESTAMPTZ","","Zeitpunkt der Erstellung."),
 ]),
 "nachricht": ("community", "Direktnachricht zwischen zwei Personen, optional mit Bezug zu einer Ausleihe.", [
    ("nachricht_id","SERIAL","PK","Künstlicher Primärschlüssel."),
    ("absender_id","INT","FK","Verweis auf benutzer; sendende Person."),
    ("empfaenger_id","INT","FK","Verweis auf benutzer; empfangende Person."),
    ("ausleihe_id","INT","FK","Verweis auf ausleihe; optional, für Nachrichten ohne Vorgangsbezug."),
    ("text","VARCHAR(2000)","","Nachrichtentext."),
    ("gesendet_am","TIMESTAMPTZ","","Sendezeitpunkt."),
    ("gelesen","BOOLEAN","","Lesebestätigung."),
 ]),
}

# (von, nach, label, kardinalitaet_quelle, kardinalitaet_ziel)
R = [
 ("benutzer","adresse","wohnt an","1","1"),
 ("benutzer","benutzer_rolle","besitzt","1","0..n"),
 ("rolle","benutzer_rolle","wird vergeben","1","0..n"),
 ("verlag","werk","veroeffentlicht","1","0..n"),
 ("sprache","werk","verfasst in","1","0..n"),
 ("werk","werk_autor","zugeordnet","1","n"),
 ("autor","werk_autor","verfasst","1","n"),
 ("werk","werk_genre","eingeordnet","1","0..n"),
 ("genre","werk_genre","klassifiziert","1","0..n"),
 ("werk","exemplar","liegt vor als","1","0..n"),
 ("benutzer","exemplar","besitzt","1","0..n"),
 ("zustand","exemplar","beschreibt","1","0..n"),
 ("exemplar","verfuegbarkeit","ist verfuegbar","1","0..n"),
 ("zeitslot","verfuegbarkeit","im Zeitfenster","1","0..n"),
 ("uebergabeart","verfuegbarkeit","per Art","1","0..n"),
 ("exemplar","ausleihe","verliehen in","1","0..n"),
 ("benutzer","ausleihe","leiht aus","1","0..n"),
 ("ausleihe","uebergabe","erfolgt durch","1","n"),
 ("zeitslot","uebergabe","zum Zeitfenster","0..1","0..n"),
 ("uebergabeart","uebergabe","per Art","1","0..n"),
 ("werk","bewertung_werk","wird bewertet","1","0..n"),
 ("benutzer","bewertung_werk","verfasst","1","0..n"),
 ("ausleihe","bewertung_werk","berechtigt zu","1","0..1"),
 ("benutzer","bewertung_person","bewertet","1","0..n"),
 ("benutzer","bewertung_person","wird bewertet","1","0..n"),
 ("ausleihe","bewertung_person","berechtigt zu","1","0..n"),
 ("benutzer","nachricht","sendet","1","0..n"),
 ("benutzer","nachricht","empfaengt","1","0..n"),
 ("ausleihe","nachricht","betrifft","0..1","0..n"),
]

TERNAER = ["verfuegbarkeit", "uebergabe", "bewertung_person"]

# ===========================================================================
# Ergänzungen für build_ddl.py (Phase 2). Die Tupel oben bleiben unverändert,
# damit build_erm.py und build_dict.py weiterhin funktionieren.
# ===========================================================================

# Spalten, die NULL erlauben. Alles andere wird NOT NULL.
# Entscheidung Tanzin (17.09.2026): explizite Liste statt Heuristik.
NULLABLE = {
    ("benutzer", "telefon"),
    ("autor", "vorname"),                 # einnamige Autor:innen
    ("autor", "geburtsjahr"),
    ("verlag", "sitz"),
    ("werk", "untertitel"),
    ("werk", "isbn13"),                   # alte Ausgaben ohne ISBN
    ("werk", "erscheinungsjahr"),
    ("rolle", "beschreibung"),
    ("zustand", "beschreibung"),
    ("exemplar", "anmerkung"),
    ("ausleihe", "entschieden_am"),       # erst nach Entscheidung belegt
    ("ausleihe", "uebergeben_am"),
    ("ausleihe", "zurueckgegeben_am"),
    ("uebergabe", "zeitslot_id"),         # nur bei Abholung (Kardinalität 0..1)
    ("uebergabe", "sendungsnummer"),      # nur bei Postversand
    ("uebergabe", "versandkosten"),
    ("uebergabe", "erfolgt_am"),          # erst nach tatsächlicher Übergabe
    ("bewertung_werk", "kommentar"),
    ("bewertung_person", "kommentar"),
    ("nachricht", "ausleihe_id"),         # Nachricht ohne Vorgangsbezug (0..1)
}

# Ziel eines Fremdschlüssels: Konvention "<tabelle>_id" -> tabelle.
# Nur Abweichungen (Rollenbezeichner auf benutzer) stehen hier.
FK_ZIEL = {
    "besitzer_id":   "benutzer",
    "ausleiher_id":  "benutzer",
    "verfasser_id":  "benutzer",
    "bewertender_id": "benutzer",
    "bewerteter_id": "benutzer",
    "absender_id":   "benutzer",
    "empfaenger_id": "benutzer",
}

# ON DELETE: Standard RESTRICT ("Konto deaktivieren, nie löschen").
# CASCADE nur bei reinen n:m-Auflösungstabellen, SET NULL bei optionalem Bezug.
ON_DELETE = {
    ("benutzer_rolle", "benutzer_id"): "CASCADE",
    ("benutzer_rolle", "rolle_id"):    "CASCADE",
    ("werk_autor", "werk_id"):         "CASCADE",
    ("werk_autor", "autor_id"):        "CASCADE",
    ("werk_genre", "werk_id"):         "CASCADE",
    ("werk_genre", "genre_id"):        "CASCADE",
    ("nachricht", "ausleihe_id"):      "SET NULL",
}

# DEFAULT-Werte (SQL-Ausdrücke).
DEFAULTS = {
    ("benutzer", "registriert_am"):     "CURRENT_DATE",
    ("benutzer", "kontostatus"):        "'aktiv'",
    ("benutzer_rolle", "zugewiesen_am"): "CURRENT_DATE",
    ("exemplar", "versand_moeglich"):   "FALSE",
    ("exemplar", "status"):             "'verfuegbar'",
    ("exemplar", "eingestellt_am"):     "CURRENT_DATE",
    ("ausleihe", "status"):             "'angefragt'",
    ("ausleihe", "angefragt_am"):       "now()",
    ("bewertung_werk", "erstellt_am"):  "now()",
    ("bewertung_werk", "gemeldet"):     "FALSE",
    ("bewertung_person", "erstellt_am"): "now()",
    ("nachricht", "gesendet_am"):       "now()",
    ("nachricht", "gelesen"):           "FALSE",
}

# Zulässige Statuswerte (werden zu CHECK-Constraints; Text statt Lookup-Tabelle
# ist Entscheidung aus Phase 1).
STATUS = {
    "benutzer.kontostatus": ["aktiv", "gesperrt", "deaktiviert"],
    "exemplar.status":      ["verfuegbar", "pausiert", "entfernt"],
    "ausleihe.status":      ["angefragt", "bestaetigt", "laufend", "abgeschlossen",
                             "abgelehnt", "storniert", "verspaetet"],
    "uebergabe.richtung":   ["hinweg", "rueckweg"],
    "werk_autor.beitragsart": ["Autor", "Herausgeber", "Übersetzung"],
}

# Zulässige Statusübergänge einer Ausleihe (Arbeitsraster §4, ergänzt um
# verspaetet -> abgeschlossen; Entscheidung Tanzin 17.09.2026).
# Wird vom Trigger in sql/init/04_regeln.sql geprüft (Geschäftsregel 4).
STATUS_UEBERGAENGE = [
    ("angefragt",  "bestaetigt"),
    ("angefragt",  "abgelehnt"),
    ("angefragt",  "storniert"),
    ("bestaetigt", "laufend"),
    ("bestaetigt", "storniert"),
    ("laufend",    "abgeschlossen"),
    ("laufend",    "verspaetet"),
    ("verspaetet", "abgeschlossen"),
]

# Tabellen-Constraints jenseits von PK/FK/UK: (constraint_name, SQL, Erklärung).
# Die Erklärung landet als Kommentar im Schema (Dokumentationspflicht).
CONSTRAINTS = {
    "adresse": [
        ("chk_adresse_land", "CHECK (land ~ '^[A-Z]{2}$')",
         "Ländercode: genau zwei Großbuchstaben (ISO 3166-1 alpha-2)."),
    ],
    "werk": [
        ("chk_werk_isbn13", "CHECK (isbn13 ~ '^[0-9]{13}$')",
         "ISBN-13 besteht aus genau 13 Ziffern."),
        ("chk_werk_jahr", "CHECK (erscheinungsjahr BETWEEN 1450 AND 2100)",
         "Plausibilitätsgrenze für das Erscheinungsjahr."),
    ],
    "zustand": [
        ("chk_zustand_stufe", "CHECK (stufe BETWEEN 1 AND 5)",
         "Ordinale Skala 1 (neuwertig) bis 5 (stark abgenutzt)."),
    ],
    "exemplar": [
        ("chk_exemplar_leihdauer", "CHECK (max_leihdauer_tage > 0)",
         "Eine Leihdauer von null oder negativen Tagen ist sinnlos."),
    ],
    "zeitslot": [
        ("chk_zeitslot_reihenfolge", "CHECK (ende > beginn)",
         "Ein Zeitfenster muss eine positive Dauer haben."),
    ],
    "verfuegbarkeit": [
        ("uq_verfuegbarkeit", "UNIQUE (exemplar_id, zeitslot_id, uebergabeart_id)",
         "Dieselbe Kombination aus Exemplar, Zeitfenster und Übergabeart nur einmal."),
    ],
    "ausleihe": [
        ("chk_ausleihe_zeitraum", "CHECK (zeitraum_bis >= zeitraum_von)",
         "Leihzeitraum darf nicht rückwärts laufen."),
        ("chk_ausleihe_rueckgabe", "CHECK (zurueckgegeben_am IS NULL OR uebergeben_am IS NULL OR zurueckgegeben_am >= uebergeben_am)",
         "Rückgabe kann nicht vor der Übergabe liegen."),
        ("excl_ausleihe_doppelbuchung",
         "EXCLUDE USING gist (exemplar_id WITH =, daterange(zeitraum_von, zeitraum_bis, '[]') WITH &&) "
         "WHERE (status IN ('bestaetigt', 'laufend', 'verspaetet'))",
         "GESCHÄFTSREGEL 1 (Double-Booking): Für dasselbe Exemplar dürfen sich zwei "
         "bestätigte, laufende oder verspätete Leihzeiträume nicht überlappen (btree_gist)."),
    ],
    "uebergabe": [
        ("uq_uebergabe_richtung", "UNIQUE (ausleihe_id, richtung)",
         "Genau eine Hin- und eine Rückübergabe je Ausleihe."),
        ("chk_uebergabe_weg", "CHECK (num_nonnulls(zeitslot_id, sendungsnummer) = 1)",
         "Entweder Abhol-Zeitfenster oder Sendungsnummer, nie beides, nie keins."),
        ("chk_uebergabe_versandkosten", "CHECK (versandkosten IS NULL OR versandkosten >= 0)",
         "Versandkosten sind nicht negativ."),
    ],
    "bewertung_werk": [
        ("chk_bewertung_werk_sterne", "CHECK (sterne BETWEEN 1 AND 5)",
         "Sternebewertung von 1 bis 5."),
    ],
    "bewertung_person": [
        ("chk_bewertung_person_sterne", "CHECK (sterne BETWEEN 1 AND 5)",
         "Sternebewertung von 1 bis 5."),
        ("chk_bewertung_person_selbst", "CHECK (bewertender_id <> bewerteter_id)",
         "Niemand bewertet sich selbst."),
        ("uq_bewertung_person", "UNIQUE (bewertender_id, ausleihe_id)",
         "Je Ausleihe bewertet eine Person die Gegenseite höchstens einmal."),
    ],
    "nachricht": [
        ("chk_nachricht_selbst", "CHECK (absender_id <> empfaenger_id)",
         "Keine Nachricht an sich selbst."),
    ],
}

# Fachliche Indizes jenseits der FK-Indizes (die build_ddl.py automatisch
# anlegt): (name, tabelle, definition, begründung). Die Begründung landet als
# Kommentar in 03_indexes.sql — Indizes werden begründet, nicht nur gesetzt.
INDEXES = [
    ("idx_adresse_position", "adresse", "USING gist (position)",
     "Umkreissuche „Bücher in meiner Nähe“: ST_DWithin auf geography braucht einen "
     "räumlichen GiST-Index, sonst prüft PostgreSQL jede Adresse einzeln (Seq Scan)."),
    ("idx_werk_titel_trgm", "werk", "USING gin (titel gin_trgm_ops)",
     "Ähnlichkeits-/Teilstringsuche im Titel (ILIKE '%…%', similarity) über pg_trgm; "
     "ein B-Baum hilft bei Suche mitten im Wort nicht."),
    ("idx_autor_nachname_trgm", "autor", "USING gin (nachname gin_trgm_ops)",
     "Gleiche Begründung für die Autorensuche, tolerant gegen Tippfehler."),
    ("idx_zeitslot_zeitraum", "zeitslot", "USING gist (tstzrange(beginn, ende))",
     "Verfügbarkeits-Abfragen „welche Zeitfenster überlappen mit …“ nutzen den "
     "Bereichsoperator &&, den nur ein GiST-Index auf dem Bereich bedienen kann."),
    ("idx_ausleihe_exemplar_status", "ausleihe", "(exemplar_id, status)",
     "Die häufigste Transaktionsfrage: aktive Ausleihen eines Exemplars; ersetzt "
     "den reinen FK-Index auf exemplar_id."),
    ("idx_nachricht_ungelesen", "nachricht", "(empfaenger_id) WHERE NOT gelesen",
     "Partieller Index: Posteingang zeigt nur ungelesene Nachrichten, der Index "
     "bleibt klein, weil gelesene Nachrichten die Mehrheit sind."),
    ("idx_exemplar_verfuegbar", "exemplar", "(werk_id) WHERE status = 'verfuegbar'",
     "Partieller Index für „verfügbare Exemplare eines Werks“ — entfernte und "
     "pausierte Exemplare werden nie durchsucht."),
]
