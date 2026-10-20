-- =====================================================================
-- Indizes der Buchtausch-App — ERZEUGT aus tools/model.py durch tools/build_ddl.py
-- Nicht von Hand ändern: Änderung in model.py, dann `python3 build_ddl.py`.
--
-- Teil 1: Ein B-Baum-Index je Fremdschlüssel. PostgreSQL legt FK-Indizes nicht
--         automatisch an; ohne sie wird jeder JOIN und jede ON-DELETE-Prüfung
--         zum Seq Scan. Übersprungen, wenn die Spalte schon vorn in einem
--         Primärschlüssel, UNIQUE oder fachlichen Index steht.
-- Teil 2: Fachliche Indizes (GiST, GIN/pg_trgm, partiell) mit Begründung.
-- =====================================================================

-- Teil 1: Fremdschlüssel-Indizes

CREATE INDEX idx_benutzer_rolle_rolle_id ON benutzer_rolle (rolle_id);
CREATE INDEX idx_werk_verlag_id ON werk (verlag_id);
CREATE INDEX idx_werk_sprache_id ON werk (sprache_id);
CREATE INDEX idx_werk_autor_autor_id ON werk_autor (autor_id);
CREATE INDEX idx_werk_genre_genre_id ON werk_genre (genre_id);
CREATE INDEX idx_exemplar_werk_id ON exemplar (werk_id);
CREATE INDEX idx_exemplar_besitzer_id ON exemplar (besitzer_id);
CREATE INDEX idx_exemplar_zustand_id ON exemplar (zustand_id);
CREATE INDEX idx_verfuegbarkeit_zeitslot_id ON verfuegbarkeit (zeitslot_id);
CREATE INDEX idx_verfuegbarkeit_uebergabeart_id ON verfuegbarkeit (uebergabeart_id);
CREATE INDEX idx_ausleihe_ausleiher_id ON ausleihe (ausleiher_id);
CREATE INDEX idx_uebergabe_zeitslot_id ON uebergabe (zeitslot_id);
CREATE INDEX idx_uebergabe_uebergabeart_id ON uebergabe (uebergabeart_id);
CREATE INDEX idx_bewertung_werk_werk_id ON bewertung_werk (werk_id);
CREATE INDEX idx_bewertung_werk_verfasser_id ON bewertung_werk (verfasser_id);
CREATE INDEX idx_bewertung_person_bewerteter_id ON bewertung_person (bewerteter_id);
CREATE INDEX idx_bewertung_person_ausleihe_id ON bewertung_person (ausleihe_id);
CREATE INDEX idx_nachricht_absender_id ON nachricht (absender_id);
CREATE INDEX idx_nachricht_empfaenger_id ON nachricht (empfaenger_id);
CREATE INDEX idx_nachricht_ausleihe_id ON nachricht (ausleihe_id);

-- Teil 2: Fachliche Indizes

-- Umkreissuche „Bücher in meiner Nähe“: ST_DWithin auf geography braucht einen räumlichen GiST-Index, sonst prüft PostgreSQL jede Adresse einzeln (Seq Scan).
CREATE INDEX idx_adresse_position ON adresse USING gist (position);

-- Ähnlichkeits-/Teilstringsuche im Titel (ILIKE '%…%', similarity) über pg_trgm; ein B-Baum hilft bei Suche mitten im Wort nicht.
CREATE INDEX idx_werk_titel_trgm ON werk USING gin (titel gin_trgm_ops);

-- Gleiche Begründung für die Autorensuche, tolerant gegen Tippfehler.
CREATE INDEX idx_autor_nachname_trgm ON autor USING gin (nachname gin_trgm_ops);

-- Verfügbarkeits-Abfragen „welche Zeitfenster überlappen mit …“ nutzen den Bereichsoperator &&, den nur ein GiST-Index auf dem Bereich bedienen kann.
CREATE INDEX idx_zeitslot_zeitraum ON zeitslot USING gist (tstzrange(beginn, ende));

-- Die häufigste Transaktionsfrage: aktive Ausleihen eines Exemplars; ersetzt den reinen FK-Index auf exemplar_id.
CREATE INDEX idx_ausleihe_exemplar_status ON ausleihe (exemplar_id, status);

-- Partieller Index: Posteingang zeigt nur ungelesene Nachrichten, der Index bleibt klein, weil gelesene Nachrichten die Mehrheit sind.
CREATE INDEX idx_nachricht_ungelesen ON nachricht (empfaenger_id) WHERE NOT gelesen;

-- Partieller Index für „verfügbare Exemplare eines Werks“ — entfernte und pausierte Exemplare werden nie durchsucht.
CREATE INDEX idx_exemplar_verfuegbar ON exemplar (werk_id) WHERE status = 'verfuegbar';

-- Zusammenfassung: 20 Fremdschlüssel-Indizes, 7 fachliche Indizes.
