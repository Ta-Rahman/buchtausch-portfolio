-- =====================================================================
-- Performance-Beleg 2: Titelsuche mitten im Wort (Trigram-Suche, Phase 2)
-- Handgeschrieben. Läuft NICHT beim Containerstart, sondern von Hand:
--   docker cp sql/perf/02_trigramsuche.sql buchtausch-db:/tmp/
--   docker exec -i buchtausch-db psql -U buchtausch -d buchtausch \
--       -v ON_ERROR_STOP=1 -v rechner='<Rechnerbeschreibung>' \
--       -f /tmp/02_trigramsuche.sql
-- Messreihe über 1.000 bis 1.000.000 Zeilen: python tools/run_perf.py
--
-- Gegenstück zu 01_umkreissuche.sql, gleiche Bauart. Gemessen wird die Suche
-- ILIKE '%…%', also ein Suchbegriff, der auch mitten im Titel stehen darf.
-- Ein B-Baum hilft dabei nicht: er ist nach dem Anfang der Zeichenkette
-- sortiert, ein Treffer in der Mitte steht an keiner vorhersagbaren Stelle.
-- pg_trgm zerlegt stattdessen jeden Titel in Dreier-Fragmente („Garten“ ->
-- „Gar“, „art“, „rte“, „ten“) und legt sie in einen GIN-Index; der Suchbegriff
-- wird genauso zerlegt und über seine Fragmente nachgeschlagen.
--
-- Die echte Tabelle werk hat 60 Zeilen und wird NICHT aufgebläht; gemessen
-- wird an der Demo-Tabelle werk_perf mit 200.000 aus einer Wortliste
-- zusammengesetzten Titeln. werk_perf wird am Ende wieder gelöscht.
--
-- Jede Messung läuft zweimal; aufgezeichnet wird der zweite Lauf (warmer
-- Cache), damit der Unterschied aus dem Plan kommt und nicht aus der Platte.
-- =====================================================================

-- Nur für diese psql-Sitzung: JIT, also das Übersetzen der Abfrage in
-- Maschinencode, wird abgeschaltet, damit die gemessene Zeit den Scan gegen den
-- Index vergleicht und nicht die Kompilierung.
SET jit = off;

-- Skript ist wiederholbar: ein Rest aus einem früheren Lauf wird entfernt.
DROP TABLE IF EXISTS werk_perf;

-- Gleiche Spalten und Typen wie werk, aber ohne Fremdschlüssel und ohne das
-- UNIQUE auf isbn13: gemessen wird die Titelsuche, nicht die Integrität.
CREATE TABLE werk_perf (
    werk_id          SERIAL PRIMARY KEY,
    titel            VARCHAR(200) NOT NULL,
    untertitel       VARCHAR(200),
    isbn13           CHAR(13),
    erscheinungsjahr SMALLINT,
    verlag_id        INT NOT NULL,
    sprache_id       INT NOT NULL
);

-- Derselbe feste Startwert wie in 01_umkreissuche.sql: jeder Lauf erzeugt
-- dieselben 200.000 Titel, die Messung ist damit wiederholbar.
SELECT setseed(0.42);

-- Jeder Titel entsteht nach dem Muster „<Substantiv> und <Substantiv> von <Ort>“,
-- die Bausteine werden zufällig aus drei Wortlisten gezogen. 20 * 20 * 8 = 3.200
-- mögliche Titel auf 200.000 Zeilen — ein Suchbegriff aus zwei Wörtern trifft
-- damit nur einen kleinen Bruchteil, und genau darum kann sich ein Index lohnen.
-- Wichtig beim Ziehen: floor() schneidet ab, ein blosser Cast auf int würde
-- RUNDEN und damit gelegentlich einen Index hinter dem Array-Ende erzeugen.
-- Zeilenzahl: tools/run_perf.py setzt für die Messreihe statt 200000 andere
-- Werte ein; von Hand ausgeführt bleiben es 200.000 Zeilen.
INSERT INTO werk_perf (titel, untertitel, isbn13, erscheinungsjahr, verlag_id, sprache_id)
SELECT (ARRAY['Garten','Schatten','Fluss','Turm','Spiegel','Brief','Winter','Hafen',
              'Wald','Schlüssel','Weg','Traum','Berg','Brunnen','Stern','Uhr',
              'Bote','Pfad','Ring','Chor'])[floor(random() * 20)::int + 1]
       || ' und ' ||
       (ARRAY['Garten','Schatten','Fluss','Turm','Spiegel','Brief','Winter','Hafen',
              'Wald','Schlüssel','Weg','Traum','Berg','Brunnen','Stern','Uhr',
              'Bote','Pfad','Ring','Chor'])[floor(random() * 20)::int + 1]
       || ' von ' ||
       (ARRAY['Bornheim','Nordend','Ostend','Sachsenhausen','Bockenheim',
              'Westend','Höchst','Rödelheim'])[floor(random() * 8)::int + 1],
       NULL,
       lpad(i::text, 13, '0'),
       (1950 + floor(random() * 75))::smallint,
       floor(random() * 12)::int + 1,
       floor(random() * 12)::int + 1
  FROM generate_series(1, 200000) AS i;

-- Ohne frische Statistiken schätzt der Planer die Zeilenzahl aus Vorgabewerten
-- und entscheidet womöglich aus dem falschen Grund; ANALYZE sammelt sie ein.
ANALYZE werk_perf;


-- ---------------------------------------------------------------------
-- Messung A: ohne Trigram-Index
-- ---------------------------------------------------------------------

-- Aufwärmlauf: füllt den Cache, die Ausgabe wird verworfen.
\o /dev/null
EXPLAIN (ANALYZE, BUFFERS)
SELECT werk_id, titel, erscheinungsjahr
  FROM werk_perf
 WHERE titel ILIKE '%Turm und Spiegel%';
\o

-- Ab hier schreibt psql jede Ausgabe in die Ergebnisdatei statt auf den Schirm.
\o /tmp/02a_trigramsuche_ohne_index.txt
\qecho '-- ==================================================================='
\qecho '-- Titelsuche OHNE Index: 200.000 Titel in der Tabelle werk_perf,'
\qecho '-- Suche nach ILIKE ''%Turm und Spiegel%'' (Treffer mitten im Titel).'
\qecho '-- Zufalls-Seed 0.42, damit die Daten reproduzierbar sind.'
\qecho '-- Aufgezeichnet ist der ZWEITE Lauf der Abfrage (warmer Cache), damit'
\qecho '-- der Vergleich mit 02b nur den Plan misst. Serverkonfiguration'
\qecho '-- unverändert (max_parallel_workers_per_gather = 2).'
\qecho '-- Einzige Abweichung von der Standardkonfiguration: JIT ist für die'
\qecho '-- Messung abgeschaltet (SET jit = off), damit die Zeit den Scan gegen'
\qecho '-- den Index vergleicht und nicht das Übersetzen in Maschinencode.'
\qecho '-- Messrechner:' :rechner
\qecho '-- ==================================================================='
SELECT version() AS postgresql,
       postgis_lib_version() AS postgis,
       now() AS gemessen_am;

-- Wie viele der 200.000 Titel passen auf den Suchbegriff? Zahl für die Folie.
SELECT count(*) AS treffer
  FROM werk_perf
 WHERE titel ILIKE '%Turm und Spiegel%';

-- ANALYZE führt die Abfrage wirklich aus und zeigt die gemessene Zeit und die
-- tatsächlichen Zeilen je Planknoten; BUFFERS zeigt zusätzlich, wie viele
-- Seiten aus dem Cache kamen (shared hit) und wie viele gelesen werden mussten.
EXPLAIN (ANALYZE, BUFFERS)
SELECT werk_id, titel, erscheinungsjahr
  FROM werk_perf
 WHERE titel ILIKE '%Turm und Spiegel%';
\o


-- ---------------------------------------------------------------------
-- Messung B: mit GIN-Index über Trigramme
-- ---------------------------------------------------------------------

-- GIN ist der Indextyp für „ein Wert enthält viele Elemente“: hier steht im
-- Index je Trigramm eine Liste der Titel, in denen es vorkommt. gin_trgm_ops
-- sagt PostgreSQL, dass die Elemente die Dreier-Fragmente aus pg_trgm sein
-- sollen. Genau diesen Index legt 03_indexes.sql auch auf werk.titel an.
CREATE INDEX idx_werk_perf_titel_trgm ON werk_perf USING gin (titel gin_trgm_ops);

-- Nach dem Indexaufbau erneut Statistiken sammeln.
ANALYZE werk_perf;

-- Aufwärmlauf, diesmal mit Index; Ausgabe wird wieder verworfen.
\o /dev/null
EXPLAIN (ANALYZE, BUFFERS)
SELECT werk_id, titel, erscheinungsjahr
  FROM werk_perf
 WHERE titel ILIKE '%Turm und Spiegel%';
\o

\o /tmp/02b_trigramsuche_mit_index.txt
\qecho '-- ==================================================================='
\qecho '-- Titelsuche MIT GIN-Index idx_werk_perf_titel_trgm (gin_trgm_ops).'
\qecho '-- Identische Abfrage und identische Daten wie in 02a — einziger'
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
SELECT pg_size_pretty(pg_relation_size('werk_perf'))                AS tabelle,
       pg_size_pretty(pg_relation_size('idx_werk_perf_titel_trgm')) AS indexgroesse;

EXPLAIN (ANALYZE, BUFFERS)
SELECT werk_id, titel, erscheinungsjahr
  FROM werk_perf
 WHERE titel ILIKE '%Turm und Spiegel%';
\o


-- Messwerkzeug wieder entfernen: die Datenbank steht danach exakt in dem
-- Zustand, den 05_seed.sql erzeugt hat.
DROP TABLE werk_perf;
