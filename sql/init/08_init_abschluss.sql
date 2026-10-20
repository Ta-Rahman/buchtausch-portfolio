-- =====================================================================
-- Init-Abschluss-Marker (Phase 3, Feedback Phase 2: Reproduzierbarkeit)
-- Läuft beim ersten Containerstart als letztes Init-Skript, nach 07_views.sql.
-- Handgeschrieben; nicht in tools/model.py und nicht im ERM (wie 07_views.sql).
--
-- pg_isready zeigt nur, dass der Server Verbindungen annimmt — nicht, dass
-- die Init-Kette vollständig durchlief. Der Entrypoint führt die Skripte der
-- Reihe nach mit ON_ERROR_STOP aus und bricht beim ersten Fehler ab: schlägt
-- etwa ein Testfall in 06_tests.sql fehl, läuft dieses Skript nie. Fehlt die
-- Zeile in meta.init_status, ist die Initialisierung also nicht
-- abgeschlossen. Der Healthcheck in docker-compose.yml prüft deshalb
-- zusätzlich zu pg_isready genau diese Zeile.
--
-- Eigenes Schema meta, weil der Marker nicht zum Fachmodell gehört.
-- Zählung ab Phase 3: 21 Fachtabellen + 1 Metatabelle.
--
-- Die Zähler halten fest, was die Kette im Schema public angelegt hat.
-- Objekte, die eine Erweiterung mitbringt (PostGIS: Tabelle spatial_ref_sys,
-- Views geometry_columns und geography_columns), zählen nicht mit: sie sind
-- in pg_depend mit deptype = 'e' als Teil ihrer Erweiterung eingetragen.
-- =====================================================================

BEGIN;   -- Schema, Tabelle und Zeile entstehen ganz oder gar nicht

CREATE SCHEMA meta;

COMMENT ON SCHEMA meta IS
  'Technische Metadaten der Datenbank, nicht Teil des Fachmodells.';

CREATE TABLE meta.init_status (
    init_status_id      smallint    PRIMARY KEY DEFAULT 1,
    abgeschlossen       boolean     NOT NULL,
    init_skripte        smallint    NOT NULL,
    fachtabellen        smallint    NOT NULL,
    views               smallint    NOT NULL,
    trigger             smallint    NOT NULL,
    constraints_fk      smallint    NOT NULL,
    constraints_unique  smallint    NOT NULL,
    constraints_check   smallint    NOT NULL,
    constraints_exclude smallint    NOT NULL,
    abgeschlossen_am    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_init_status_eine_zeile CHECK (init_status_id = 1)  -- genau eine Zeile, Schlüssel immer 1
);

COMMENT ON TABLE meta.init_status IS
  'Abschlussmarker der Init-Kette: eine Zeile, geschrieben von 08_init_abschluss.sql als letztem Init-Skript. Der Healthcheck prüft sie zusätzlich zu pg_isready.';

-- eigene: Tabellen und Views im Schema public ohne die Objekte von Erweiterungen
WITH eigene AS (
    SELECT c.oid, c.relkind
      FROM pg_class c
     WHERE c.relnamespace = 'public'::regnamespace
       AND c.relkind IN ('r', 'v')                 -- r = Tabelle, v = View
       AND NOT EXISTS (SELECT 1
                         FROM pg_depend d
                        WHERE d.classid = 'pg_class'::regclass
                          AND d.objid   = c.oid
                          AND d.deptype = 'e')     -- e = gehört zu einer Erweiterung
)
INSERT INTO meta.init_status
       (abgeschlossen, init_skripte, fachtabellen, views, trigger,
        constraints_fk, constraints_unique, constraints_check, constraints_exclude)
SELECT true,
       8,   -- Skripte in sql/init/, dieses eingeschlossen; bei einem neuen Skript anpassen
       (SELECT count(*) FROM eigene WHERE relkind = 'r'),
       (SELECT count(*) FROM eigene WHERE relkind = 'v'),
       -- NOT tgisinternal: die Trigger, die PostgreSQL selbst für jeden
       -- Fremdschlüssel anlegt, zählen nicht mit
       (SELECT count(*) FROM pg_trigger t
         WHERE t.tgrelid IN (SELECT oid FROM eigene) AND NOT t.tgisinternal),
       -- conrelid: nur Constraints auf den eigenen Tabellen, nicht die der
       -- Systemkataloge und nicht die von spatial_ref_sys
       (SELECT count(*) FROM pg_constraint k
         WHERE k.conrelid IN (SELECT oid FROM eigene) AND k.contype = 'f'),
       (SELECT count(*) FROM pg_constraint k
         WHERE k.conrelid IN (SELECT oid FROM eigene) AND k.contype = 'u'),
       (SELECT count(*) FROM pg_constraint k
         WHERE k.conrelid IN (SELECT oid FROM eigene) AND k.contype = 'c'),
       (SELECT count(*) FROM pg_constraint k
         WHERE k.conrelid IN (SELECT oid FROM eigene) AND k.contype = 'x');

COMMIT;
