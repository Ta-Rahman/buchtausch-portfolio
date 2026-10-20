-- =====================================================================
-- Geschäftsregeln der Buchtausch-App als Trigger (Phase 2)
-- Läuft beim ersten Containerstart nach 02_schema.sql.
--
-- Regel 1 (Double-Booking) braucht keinen Trigger: sie ist deklarativ als
-- EXCLUDE-Constraint excl_ausleihe_doppelbuchung in 02_schema.sql umgesetzt.
-- Die Regeln 2–4 vergleichen Werte ÜBER Tabellengrenzen hinweg (Ausleihe ↔
-- Exemplar, Bewertung ↔ Ausleihe, alter ↔ neuer Status) — das kann ein
-- CHECK-Constraint nicht, deshalb Trigger.
--
-- Jede Funktion wirft RAISE EXCEPTION (SQLSTATE P0001, raise_exception) mit
-- einer Meldung, die mit der Regelnummer beginnt. Die Negativtests in
-- 06_tests.sql fangen genau diesen Fehler ab.
-- Handgeschrieben; die zulässigen Statusübergänge stehen zusätzlich in
-- tools/model.py (STATUS_UEBERGAENGE) — bei Änderung beide Stellen pflegen.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Regel 3: Maximale Leihdauer des Exemplars darf nicht überschritten werden.
-- Leihdauer zählt inklusiv (1.10.–14.10. = 14 Tage), passend zum EXCLUDE
-- mit daterange '[]', bei dem beide Randtage belegt sind.
-- Greift bei INSERT und bei jedem UPDATE, der Zeitraum oder Exemplar ändert.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pruefe_leihdauer() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_max   SMALLINT;
    v_dauer INT := NEW.zeitraum_bis - NEW.zeitraum_von + 1;
BEGIN
    SELECT max_leihdauer_tage INTO v_max
      FROM exemplar
     WHERE exemplar_id = NEW.exemplar_id;

    IF v_dauer > v_max THEN
        RAISE EXCEPTION 'Regel 3: Leihdauer % Tage überschreitet das Maximum von % Tagen für Exemplar %',
              v_dauer, v_max, NEW.exemplar_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ausleihe_leihdauer
    BEFORE INSERT OR UPDATE OF zeitraum_von, zeitraum_bis, exemplar_id ON ausleihe
    FOR EACH ROW EXECUTE FUNCTION pruefe_leihdauer();


-- ---------------------------------------------------------------------
-- Regel 4: Eine Ausleihe darf nur die definierten Statusübergänge durchlaufen.
--
--   angefragt  -> bestaetigt | abgelehnt | storniert
--   bestaetigt -> laufend    | storniert
--   laufend    -> abgeschlossen | verspaetet
--   verspaetet -> abgeschlossen
--
-- abgeschlossen, abgelehnt und storniert sind Endzustände.
-- Bewusst nur bei UPDATE: Seed-Daten dürfen historische Ausleihen direkt in
-- ihrem Endzustand einfügen; neue Ausleihen starten über DEFAULT 'angefragt'.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pruefe_statusuebergang() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (OLD.status, NEW.status) NOT IN (
        ('angefragt',  'bestaetigt'),
        ('angefragt',  'abgelehnt'),
        ('angefragt',  'storniert'),
        ('bestaetigt', 'laufend'),
        ('bestaetigt', 'storniert'),
        ('laufend',    'abgeschlossen'),
        ('laufend',    'verspaetet'),
        ('verspaetet', 'abgeschlossen')
    ) THEN
        RAISE EXCEPTION 'Regel 4: Statusübergang % -> % ist nicht zulässig (Ausleihe %)',
              OLD.status, NEW.status, OLD.ausleihe_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ausleihe_status
    BEFORE UPDATE OF status ON ausleihe
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)   -- unveränderter Status ist kein Übergang
    EXECUTE FUNCTION pruefe_statusuebergang();


-- ---------------------------------------------------------------------
-- Regel 2a: Werkbewertung nur nach abgeschlossener eigener Ausleihe.
-- Prüft drei Dinge über den Berechtigungsnachweis ausleihe_id:
--   1. die Ausleihe ist abgeschlossen,
--   2. die bewertende Person ist die ausleihende Person dieser Ausleihe,
--   3. das bewertete Werk ist das Werk des ausgeliehenen Exemplars.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pruefe_bewertung_werk() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status    VARCHAR(15);
    v_ausleiher INT;
    v_werk      INT;
BEGIN
    SELECT a.status, a.ausleiher_id, e.werk_id
      INTO v_status, v_ausleiher, v_werk
      FROM ausleihe a
      JOIN exemplar e ON e.exemplar_id = a.exemplar_id
     WHERE a.ausleihe_id = NEW.ausleihe_id;

    IF v_status <> 'abgeschlossen' THEN
        RAISE EXCEPTION 'Regel 2: Werkbewertung nur nach abgeschlossener Ausleihe (Ausleihe % hat Status %)',
              NEW.ausleihe_id, v_status;
    END IF;
    IF NEW.verfasser_id <> v_ausleiher THEN
        RAISE EXCEPTION 'Regel 2: Benutzer % ist nicht die ausleihende Person der Ausleihe %',
              NEW.verfasser_id, NEW.ausleihe_id;
    END IF;
    IF NEW.werk_id <> v_werk THEN
        RAISE EXCEPTION 'Regel 2: Werk % gehört nicht zur Ausleihe % (dort Werk %)',
              NEW.werk_id, NEW.ausleihe_id, v_werk;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bewertung_werk_berechtigung
    BEFORE INSERT OR UPDATE OF werk_id, verfasser_id, ausleihe_id ON bewertung_werk
    FOR EACH ROW EXECUTE FUNCTION pruefe_bewertung_werk();


-- ---------------------------------------------------------------------
-- Regel 2b: Personenbewertung nur nach abgeschlossener eigener Ausleihe.
-- Beide Parteien dürfen sich gegenseitig bewerten — die bewertende Person
-- muss eine Partei der Ausleihe sein und die bewertete Person die andere.
-- (Selbstbewertung ist bereits per CHECK chk_bewertung_person_selbst verboten.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pruefe_bewertung_person() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_status    VARCHAR(15);
    v_ausleiher INT;
    v_besitzer  INT;
BEGIN
    SELECT a.status, a.ausleiher_id, e.besitzer_id
      INTO v_status, v_ausleiher, v_besitzer
      FROM ausleihe a
      JOIN exemplar e ON e.exemplar_id = a.exemplar_id
     WHERE a.ausleihe_id = NEW.ausleihe_id;

    IF v_status <> 'abgeschlossen' THEN
        RAISE EXCEPTION 'Regel 2: Personenbewertung nur nach abgeschlossener Ausleihe (Ausleihe % hat Status %)',
              NEW.ausleihe_id, v_status;
    END IF;
    IF (NEW.bewertender_id, NEW.bewerteter_id) NOT IN ((v_ausleiher, v_besitzer), (v_besitzer, v_ausleiher)) THEN
        RAISE EXCEPTION 'Regel 2: Benutzer % darf Benutzer % nicht über Ausleihe % bewerten (Parteien: % und %)',
              NEW.bewertender_id, NEW.bewerteter_id, NEW.ausleihe_id, v_ausleiher, v_besitzer;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bewertung_person_berechtigung
    BEFORE INSERT OR UPDATE OF bewertender_id, bewerteter_id, ausleihe_id ON bewertung_person
    FOR EACH ROW EXECUTE FUNCTION pruefe_bewertung_person();
