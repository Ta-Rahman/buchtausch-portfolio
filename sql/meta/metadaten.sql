-- =====================================================================
-- Metadaten der Datenbank buchtausch (Phase 3, Bericht)
-- Handgeschrieben; reines SQL ohne psql-Metabefehle, läuft also auch in
-- DBeaver oder pgAdmin. Liest die Systemkataloge und zählt Zeilen; legt nur
-- temporäre Hilfsobjekte an, die mit der Sitzung verschwinden.
--
-- Abschnitte der Ausgabe:
--   1 Kopf · 2 Datenbankgröße · 3 Tabellen je Schema · 4 je Tabelle ·
--   5 je Index · 6 Zähler · 7 Erweiterungen · 8 Objekte aus Erweiterungen
--
-- Gezählt werden die eigenen Objekte in den Schemas public (21 Fachtabellen)
-- und meta (1 Metatabelle). Was eine Erweiterung mitbringt (PostGIS:
-- spatial_ref_sys, geometry_columns, geography_columns), ist in pg_depend
-- mit deptype = 'e' eingetragen; es zählt nicht mit und steht getrennt in
-- Abschnitt 8, weil es in der Datenbankgröße enthalten ist.
--
-- Laufabhängig: erhoben_am und alle Spalten *_groesse / *_bytes (Dateigrößen
-- hängen z. B. davon ab, wann Autovacuum Freispeicher- und
-- Sichtbarkeitskarten anlegt). Lauf-unabhängig: Namen, Zeilen,
-- Zugriffsmethoden, Zähler.
--
-- Ausführen (Container läuft, aus dem Wurzelverzeichnis des Repos):
--   docker cp sql/meta/metadaten.sql buchtausch-db:/tmp/metadaten.sql
--   docker exec buchtausch-db psql -U buchtausch -d buchtausch -X -q -v ON_ERROR_STOP=1 -f /tmp/metadaten.sql -o /tmp/metadaten.txt
--   docker cp buchtausch-db:/tmp/metadaten.txt docs/belege/metadaten.txt
-- In Git Bash vorher MSYS_NO_PATHCONV=1 setzen, sonst schreibt Git Bash die
-- Containerpfade in Windows-Pfade um. -q unterdrückt die Meldungen SET und
-- CREATE, die Ergebnistabellen bleiben.
-- =====================================================================

SET TimeZone = 'Europe/Berlin';

-- 1 Kopf
SELECT current_database()                                             AS datenbank,
       current_setting('server_version')                              AS postgresql,
       (SELECT extversion FROM pg_extension WHERE extname = 'postgis') AS postgis,
       date_trunc('second', now())                                    AS erhoben_am,
       'erhoben_am, *_groesse, *_bytes'                               AS laufabhaengig;

-- 2 Datenbankgröße, erhoben vor den temporären Hilfsobjekten
SELECT pg_size_pretty(pg_database_size(current_database())) AS datenbank_groesse,
       pg_database_size(current_database())                 AS datenbank_bytes;

-- Hilfsobjekte, nur für diese Sitzung
-- eigene_relationen: Tabellen und Views in public und meta ohne die Objekte
-- von Erweiterungen
CREATE TEMP VIEW eigene_relationen AS
SELECT c.oid, n.nspname AS schema, c.relname AS name, c.relkind
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public', 'meta')
   AND c.relkind IN ('r', 'v')                     -- r = Tabelle, v = View
   AND NOT EXISTS (SELECT 1
                     FROM pg_depend d
                    WHERE d.classid = 'pg_class'::regclass
                      AND d.objid   = c.oid
                      AND d.deptype = 'e');        -- e = gehört zu einer Erweiterung

-- zeilen(t): exakte Zeilenzahl einer Tabelle, deren Name erst zur Laufzeit
-- feststeht (dynamisches SQL mit EXECUTE); count(*) statt der Schätzung
-- pg_class.reltuples. Ein regclass gibt seinen Namen schon richtig
-- gequotet und bei Bedarf mit Schema aus, deshalb reicht %s.
CREATE FUNCTION pg_temp.zeilen(t regclass) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
    EXECUTE format('SELECT count(*) FROM %s', t) INTO n;
    RETURN n;
END $$;

-- 3 Tabellen je Schema (Schema mit der zuerst angelegten Tabelle zuerst)
SELECT schema,
       count(*)                                         AS tabellen,
       sum(pg_temp.zeilen(oid))                         AS zeilen,
       pg_size_pretty(sum(pg_total_relation_size(oid))) AS gesamt_groesse,
       sum(pg_total_relation_size(oid))                 AS gesamt_bytes
  FROM eigene_relationen
 WHERE relkind = 'r'
 GROUP BY schema
 ORDER BY min(oid);

-- 4 Je Tabelle, in der Reihenfolge des Anlegens (OID): die 21 Fachtabellen
--   wie in tools/model.py, danach meta.init_status.
--   gesamt  = Tabelle mit Freispeicher-/Sichtbarkeitskarte und TOAST + Indizes
--   tabelle = nur die Hauptdatei der Tabelle
SELECT schema,
       name                                        AS tabelle,
       pg_temp.zeilen(oid)                         AS zeilen,
       pg_size_pretty(pg_total_relation_size(oid)) AS gesamt_groesse,
       pg_total_relation_size(oid)                 AS gesamt_bytes,
       pg_size_pretty(pg_relation_size(oid))       AS tabelle_groesse,
       pg_relation_size(oid)                       AS tabelle_bytes,
       pg_size_pretty(pg_indexes_size(oid))        AS indizes_groesse,
       pg_indexes_size(oid)                        AS indizes_bytes
  FROM eigene_relationen
 WHERE relkind = 'r'
 ORDER BY oid;

-- 5 Je Index, auch die, die PostgreSQL für PRIMARY KEY, UNIQUE und EXCLUDE
--   selbst anlegt
SELECT r.schema,
       r.name                                   AS tabelle,
       ic.relname                               AS index,
       am.amname                                AS zugriffsmethode,
       pg_size_pretty(pg_relation_size(ic.oid)) AS groesse,
       pg_relation_size(ic.oid)                 AS bytes
  FROM eigene_relationen r
  JOIN pg_index i  ON i.indrelid = r.oid
  JOIN pg_class ic ON ic.oid     = i.indexrelid
  JOIN pg_am am    ON am.oid     = ic.relam
 ORDER BY r.oid, ic.relname;

-- 6 Zähler über die eigenen Objekte. Constraints und Trigger nur auf den
--   eigenen Tabellen (conrelid/tgrelid), sonst zählen die Systemkataloge und
--   spatial_ref_sys mit; NOT tgisinternal lässt die Trigger weg, die
--   PostgreSQL selbst für jeden Fremdschlüssel anlegt.
SELECT objektart, anzahl
  FROM (SELECT 1 AS nr, 'Tabellen' AS objektart, count(*) AS anzahl
          FROM eigene_relationen WHERE relkind = 'r'
        UNION ALL
        SELECT 2, 'Views', count(*)
          FROM eigene_relationen WHERE relkind = 'v'
        UNION ALL
        SELECT 3, 'Indizes', count(*)
          FROM pg_index WHERE indrelid IN (SELECT oid FROM eigene_relationen)
        UNION ALL
        SELECT 4, 'PRIMARY KEY', count(*)
          FROM pg_constraint WHERE contype = 'p' AND conrelid IN (SELECT oid FROM eigene_relationen)
        UNION ALL
        SELECT 5, 'FOREIGN KEY', count(*)
          FROM pg_constraint WHERE contype = 'f' AND conrelid IN (SELECT oid FROM eigene_relationen)
        UNION ALL
        SELECT 6, 'UNIQUE', count(*)
          FROM pg_constraint WHERE contype = 'u' AND conrelid IN (SELECT oid FROM eigene_relationen)
        UNION ALL
        SELECT 7, 'CHECK', count(*)
          FROM pg_constraint WHERE contype = 'c' AND conrelid IN (SELECT oid FROM eigene_relationen)
        UNION ALL
        SELECT 8, 'EXCLUDE', count(*)
          FROM pg_constraint WHERE contype = 'x' AND conrelid IN (SELECT oid FROM eigene_relationen)
        UNION ALL
        SELECT 9, 'Trigger', count(*)
          FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (SELECT oid FROM eigene_relationen)
        UNION ALL
        SELECT 10, 'Erweiterungen', count(*)
          FROM pg_extension) AS z
 ORDER BY nr;

-- 7 Erweiterungen mit Version
SELECT e.extname    AS erweiterung,
       e.extversion AS version,
       n.nspname    AS schema
  FROM pg_extension e
  JOIN pg_namespace n ON n.oid = e.extnamespace
 ORDER BY e.extname;

-- 8 Objekte aus Erweiterungen (nicht mitgezählt, aber in der Datenbankgröße)
SELECT n.nspname                                                  AS schema,
       c.relname                                                  AS objekt,
       CASE c.relkind WHEN 'r' THEN 'Tabelle' WHEN 'v' THEN 'View' END AS art,
       x.extname                                                  AS erweiterung,
       CASE WHEN c.relkind = 'r' THEN pg_temp.zeilen(c.oid) END   AS zeilen,
       pg_size_pretty(pg_total_relation_size(c.oid))              AS gesamt_groesse,
       pg_total_relation_size(c.oid)                              AS gesamt_bytes
  FROM pg_depend d
  JOIN pg_class c     ON c.oid = d.objid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_extension x ON x.oid = d.refobjid
 WHERE d.classid    = 'pg_class'::regclass
   AND d.refclassid = 'pg_extension'::regclass
   AND d.deptype    = 'e'
   AND c.relkind IN ('r', 'v')
 ORDER BY c.relkind, c.relname;
