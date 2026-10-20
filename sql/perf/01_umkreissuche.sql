-- =====================================================================
-- Performance-Beleg 1: Umkreissuche „Bücher in meiner Nähe“ (Phase 2)
-- Handgeschrieben. Läuft NICHT beim Containerstart, sondern von Hand:
--   docker cp sql/perf/01_umkreissuche.sql buchtausch-db:/tmp/
--   docker exec -i buchtausch-db psql -U buchtausch -d buchtausch \
--       -v ON_ERROR_STOP=1 -v rechner='<Rechnerbeschreibung>' \
--       -f /tmp/01_umkreissuche.sql
-- Messreihe über 1.000 bis 1.000.000 Zeilen: python tools/run_perf.py
--
-- Warum eine eigene Demo-Tabelle? Der Seed enthält 40 Adressen; das reicht, um
-- die Abfrage zu prüfen, aber nicht, um Laufzeiten zu vergleichen. Den
-- GiST-Index wählt der Planer für diese Abfrage schon bei den 40 Adressen
-- (Index Scan) und in der Messreihe ab 1.000 Zeilen (Bitmap Heap Scan); wie der
-- Zeitabstand mit der Tabellengröße wächst, zeigt
-- sql/perf/ergebnis/messreihe_umkreis.md (1.000 bis 1.000.000 Zeilen).
-- adresse_perf hat dieselben Spalten wie adresse, aber keine Fremdschlüssel —
-- sie ist reines Messwerkzeug und wird am Ende wieder gelöscht, der Seed
-- bleibt unangetastet.
--
-- Gemessen wird zweimal dieselbe Abfrage: einmal ohne, einmal mit GiST-Index.
-- Jede Messung läuft zweimal; aufgezeichnet wird der zweite Lauf, damit beide
-- Pläne einen warmen Cache sehen und der Unterschied wirklich aus dem Plan
-- kommt und nicht daraus, welcher Lauf zufällig von der Platte lesen musste.
-- Die Serverkonfiguration bleibt unverändert (u. a. Parallelität aktiv).
-- =====================================================================

-- Nur für diese psql-Sitzung: JIT, also das Übersetzen der Abfrage in
-- Maschinencode, wird abgeschaltet, damit die gemessene Zeit den Scan gegen den
-- Index vergleicht und nicht die Kompilierung.
SET jit = off;

-- Skript ist wiederholbar: ein Rest aus einem früheren Lauf wird entfernt.
DROP TABLE IF EXISTS adresse_perf;

-- Gleiche Spalten und Typen wie adresse, aber ohne Fremdschlüssel, ohne UNIQUE
-- und ohne CHECK: gemessen wird die Umkreissuche, nicht die Integritätsprüfung.
CREATE TABLE adresse_perf (
    adresse_id  SERIAL PRIMARY KEY,
    benutzer_id INT NOT NULL,
    strasse     VARCHAR(80) NOT NULL,
    hausnummer  VARCHAR(10) NOT NULL,
    plz         VARCHAR(10) NOT NULL,
    ort         VARCHAR(80) NOT NULL,
    land        CHAR(2) NOT NULL,
    position    GEOGRAPHY(Point,4326) NOT NULL
);

-- Fester Startwert des Zufallsgenerators: jeder Lauf erzeugt dieselben
-- 200.000 Punkte, die Messung ist damit wiederholbar.
SELECT setseed(0.42);

-- generate_series liefert die Zahlen 1 bis 200000 als 200.000 Zeilen; je Zeile
-- entsteht ein Punkt, dessen Länge und Breite zufällig in der Bounding-Box von
-- Frankfurt am Main liegen (Länge 8,60–8,75 / Breite 50,08–50,16).
-- ST_MakePoint nimmt zuerst die Länge und dann die Breite, ST_SetSRID(...,4326)
-- kennzeichnet sie als WGS-84-Koordinaten (das System des GPS), und ::geography
-- sorgt dafür, dass PostGIS Entfernungen anschließend in Metern auf der
-- Erdkugel rechnet statt in Grad auf einer Ebene.
-- Zeilenzahl: tools/run_perf.py setzt für die Messreihe statt 200000 andere
-- Werte ein; von Hand ausgeführt bleiben es 200.000 Zeilen.
INSERT INTO adresse_perf (benutzer_id, strasse, hausnummer, plz, ort, land, position)
SELECT i,
       'Teststraße',
       (i % 200 + 1)::text,
       '60' || lpad((i % 100)::text, 3, '0'),
       'Frankfurt am Main',
       'DE',
       ST_SetSRID(ST_MakePoint(8.60 + random() * 0.15,
                               50.08 + random() * 0.08), 4326)::geography
  FROM generate_series(1, 200000) AS i;

-- Ohne frische Statistiken schätzt der Planer die Zeilenzahl aus Vorgabewerten
-- und entscheidet womöglich aus dem falschen Grund; ANALYZE sammelt sie ein.
ANALYZE adresse_perf;


-- ---------------------------------------------------------------------
-- Messung A: ohne räumlichen Index
-- ---------------------------------------------------------------------

-- Aufwärmlauf: füllt den Cache, die Ausgabe wird verworfen.
\o /dev/null
EXPLAIN (ANALYZE, BUFFERS)
SELECT adresse_id, strasse, hausnummer, plz, ort
  FROM adresse_perf
 WHERE ST_DWithin(position,
                  ST_SetSRID(ST_MakePoint(8.6850, 50.1250), 4326)::geography,
                  1500);
\o

-- Ab hier schreibt psql jede Ausgabe in die Ergebnisdatei statt auf den Schirm.
\o /tmp/01a_umkreissuche_ohne_index.txt
\qecho '-- ==================================================================='
\qecho '-- Umkreissuche OHNE Index: 200.000 Adressen in der Bounding-Box'
\qecho '-- Frankfurt am Main, ST_DWithin 1.500 m um den festen Punkt'
\qecho '-- 8,6850 / 50,1250 (Nordend). Tabelle adresse_perf, Zufalls-Seed 0.42.'
\qecho '-- Aufgezeichnet ist der ZWEITE Lauf der Abfrage (warmer Cache), damit'
\qecho '-- der Vergleich mit 01b nur den Plan misst. Serverkonfiguration'
\qecho '-- unverändert (max_parallel_workers_per_gather = 2).'
\qecho '-- Einzige Abweichung von der Standardkonfiguration: JIT ist für die'
\qecho '-- Messung abgeschaltet (SET jit = off), damit die Zeit den Scan gegen'
\qecho '-- den Index vergleicht und nicht das Übersetzen in Maschinencode.'
\qecho '-- Messrechner:' :rechner
\qecho '-- ==================================================================='
SELECT version() AS postgresql,
       postgis_lib_version() AS postgis,
       now() AS gemessen_am;

-- Wie viele der 200.000 Adressen liegen im Umkreis? Zahl für die Folie.
SELECT count(*) AS treffer_im_umkreis
  FROM adresse_perf
 WHERE ST_DWithin(position,
                  ST_SetSRID(ST_MakePoint(8.6850, 50.1250), 4326)::geography,
                  1500);

-- ANALYZE führt die Abfrage wirklich aus und zeigt die gemessene Zeit und die
-- tatsächlichen Zeilen je Planknoten; BUFFERS zeigt zusätzlich, wie viele
-- Seiten aus dem Cache kamen (shared hit) und wie viele gelesen werden mussten.
EXPLAIN (ANALYZE, BUFFERS)
SELECT adresse_id, strasse, hausnummer, plz, ort
  FROM adresse_perf
 WHERE ST_DWithin(position,
                  ST_SetSRID(ST_MakePoint(8.6850, 50.1250), 4326)::geography,
                  1500);
\o


-- ---------------------------------------------------------------------
-- Messung B: mit räumlichem GiST-Index
-- ---------------------------------------------------------------------

-- GiST ist der Indextyp für räumliche Daten: er merkt sich zu jedem Punkt ein
-- umschließendes Rechteck und kann damit ganze Kartenausschnitte auf einmal
-- ausschließen, statt für jede Adresse einzeln die Entfernung zu berechnen.
-- Genau diesen Index legt 03_indexes.sql auch auf der echten Tabelle adresse an.
CREATE INDEX idx_adresse_perf_position ON adresse_perf USING gist (position);

-- Nach dem Indexaufbau erneut Statistiken sammeln.
ANALYZE adresse_perf;

-- Aufwärmlauf, diesmal mit Index; Ausgabe wird wieder verworfen.
\o /dev/null
EXPLAIN (ANALYZE, BUFFERS)
SELECT adresse_id, strasse, hausnummer, plz, ort
  FROM adresse_perf
 WHERE ST_DWithin(position,
                  ST_SetSRID(ST_MakePoint(8.6850, 50.1250), 4326)::geography,
                  1500);
\o

\o /tmp/01b_umkreissuche_mit_index.txt
\qecho '-- ==================================================================='
\qecho '-- Umkreissuche MIT GiST-Index idx_adresse_perf_position.'
\qecho '-- Identische Abfrage und identische Daten wie in 01a — einziger'
\qecho '-- Unterschied ist der Index. Aufgezeichnet ist der ZWEITE Lauf'
\qecho '-- (warmer Cache). Serverkonfiguration unverändert.'
\qecho '-- Einzige Abweichung von der Standardkonfiguration: JIT ist für die'
\qecho '-- Messung abgeschaltet (SET jit = off), damit die Zeit den Scan gegen'
\qecho '-- den Index vergleicht und nicht das Übersetzen in Maschinencode.'
\qecho '-- Messrechner:' :rechner
\qecho '-- ==================================================================='
SELECT version() AS postgresql,
       postgis_lib_version() AS postgis,
       now() AS gemessen_am;

-- Was der Index an Platz kostet — die Gegenrechnung zum Zeitgewinn.
SELECT pg_size_pretty(pg_relation_size('adresse_perf'))              AS tabelle,
       pg_size_pretty(pg_relation_size('idx_adresse_perf_position')) AS indexgroesse;

EXPLAIN (ANALYZE, BUFFERS)
SELECT adresse_id, strasse, hausnummer, plz, ort
  FROM adresse_perf
 WHERE ST_DWithin(position,
                  ST_SetSRID(ST_MakePoint(8.6850, 50.1250), 4326)::geography,
                  1500);
\o


-- Messwerkzeug wieder entfernen: die Datenbank steht danach exakt in dem
-- Zustand, den 05_seed.sql erzeugt hat.
DROP TABLE adresse_perf;
