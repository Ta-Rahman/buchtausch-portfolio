-- =====================================================================
-- Testfälle der vier Geschäftsregeln (A6) und der Löschregeln — Positiv- und Negativtests
-- Läuft beim ersten Containerstart nach 05_seed.sql, vor 07_views.sql und 08_init_abschluss.sql.
--
-- Aufbau:
--   * Eine Transaktion um alles, am Ende ROLLBACK: die Datenbank bleibt exakt
--     im Seed-Zustand, egal was die Tests einfügen.
--   * Fixtures (eigenes Testexemplar mit 14 Tagen Leihdauer) in einer
--     temporären Tabelle, damit die Tests nicht von Seed-IDs abhängen.
--   * Je Regel ein DO-Block, danach je ein Block für Änderungen (UPDATE),
--     Grenzfälle und Löschregeln (DELETE). Negativtests fangen den ERWARTETEN
--     Fehler mit EXCEPTION WHEN ab; PL/pgSQL setzt dafür intern einen
--     Savepoint, die Transaktion läuft weiter. Ein Negativtest gilt nur als
--     bestanden, wenn der Fehler auch wirklich auftritt; ab Fall 17 prüfen
--     die Negativtests zusätzlich den Namen des verletzten Constraints.
--   * Jeder Fall schreibt eine Zeile in testergebnis; die Tabelle wird am Ende
--     ausgegeben (Screenshot-Vorlage). Ist ein Fall nicht bestanden, bricht das
--     Skript mit RAISE EXCEPTION ab — der Container startet dann nicht.
--
-- Manuell ausführen (nach dem Start):
--   docker exec -i buchtausch-db psql -U buchtausch -d buchtausch \
--       -f /docker-entrypoint-initdb.d/06_tests.sql
-- =====================================================================

BEGIN;

CREATE TEMP TABLE testergebnis (
    nr        SERIAL,
    regel     TEXT,
    testfall  TEXT,
    erwartet  TEXT,
    ergebnis  TEXT,
    bestanden BOOLEAN
);

-- Fixtures: Person 1 besitzt ein neues Exemplar von Werk 1 (max. 14 Tage);
-- Person 2 leiht aus, Person 3 ist unbeteiligt.
CREATE TEMP TABLE fix (besitzer INT, ausleiher INT, dritter INT, werk INT, anderes_werk INT, exemplar INT);
DO $$
DECLARE v_ex INT;
BEGIN
    INSERT INTO exemplar (werk_id, besitzer_id, zustand_id, max_leihdauer_tage)
    VALUES (1, 1, 2, 14) RETURNING exemplar_id INTO v_ex;
    INSERT INTO fix VALUES (1, 2, 3, 1, 2, v_ex);
END $$;

-- ---------------------------------------------------------------------
-- Regel 1: Double-Booking (EXCLUDE-Constraint excl_ausleihe_doppelbuchung)
-- ---------------------------------------------------------------------
DO $$
DECLARE f fix%ROWTYPE;
BEGIN
    SELECT * INTO f FROM fix;

    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.ausleiher, '2026-12-01', '2026-12-10', 'bestaetigt');
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('1', 'Positiv: bestätigte Ausleihe 01.–10.12.', 'angenommen', 'angenommen', TRUE);

    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.dritter, '2026-12-05', '2026-12-12', 'angefragt');
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('1', 'Positiv: überlappende Anfrage (noch keine Reservierung)', 'angenommen', 'angenommen', TRUE);

    BEGIN
        INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
        VALUES (f.exemplar, f.dritter, '2026-12-05', '2026-12-12', 'bestaetigt');
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('1', 'Negativ: überlappende Bestätigung 05.–12.12.', 'exclusion_violation', 'angenommen', FALSE);
    EXCEPTION WHEN exclusion_violation THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('1', 'Negativ: überlappende Bestätigung 05.–12.12.', 'exclusion_violation', SQLSTATE || ' ' || SQLERRM, TRUE);
    END;
END $$;

-- ---------------------------------------------------------------------
-- Regel 3: Maximale Leihdauer (Trigger trg_ausleihe_leihdauer, inklusiv gezählt)
-- ---------------------------------------------------------------------
DO $$
DECLARE f fix%ROWTYPE;
BEGIN
    SELECT * INTO f FROM fix;

    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis)
    VALUES (f.exemplar, f.ausleiher, '2027-01-01', '2027-01-14');
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('3', 'Positiv: genau 14 Tage (01.–14.01.)', 'angenommen', 'angenommen', TRUE);

    BEGIN
        INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis)
        VALUES (f.exemplar, f.ausleiher, '2027-02-01', '2027-02-15');
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('3', 'Negativ: 15 Tage (01.–15.02.)', 'raise_exception „Regel 3“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('3', 'Negativ: 15 Tage (01.–15.02.)', 'raise_exception „Regel 3“', SQLERRM, SQLERRM LIKE 'Regel 3%');
    END;
END $$;

-- ---------------------------------------------------------------------
-- Regel 4: Statusübergänge (Trigger trg_ausleihe_status)
-- ---------------------------------------------------------------------
DO $$
DECLARE f fix%ROWTYPE; v_id INT;
BEGIN
    SELECT * INTO f FROM fix;
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis)
    VALUES (f.exemplar, f.ausleiher, '2027-03-01', '2027-03-10')
    RETURNING ausleihe_id INTO v_id;

    UPDATE ausleihe SET status = 'bestaetigt' WHERE ausleihe_id = v_id;
    UPDATE ausleihe SET status = 'laufend'    WHERE ausleihe_id = v_id;
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('4', 'Positiv: angefragt → bestaetigt → laufend', 'angenommen', 'angenommen', TRUE);

    BEGIN
        UPDATE ausleihe SET status = 'angefragt' WHERE ausleihe_id = v_id;
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('4', 'Negativ: laufend → angefragt', 'raise_exception „Regel 4“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('4', 'Negativ: laufend → angefragt', 'raise_exception „Regel 4“', SQLERRM, SQLERRM LIKE 'Regel 4%');
    END;

    UPDATE ausleihe SET status = 'verspaetet'    WHERE ausleihe_id = v_id;
    UPDATE ausleihe SET status = 'abgeschlossen' WHERE ausleihe_id = v_id;
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('4', 'Positiv: laufend → verspaetet → abgeschlossen', 'angenommen', 'angenommen', TRUE);

    BEGIN
        UPDATE ausleihe SET status = 'laufend' WHERE ausleihe_id = v_id;
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('4', 'Negativ: abgeschlossen → laufend (Endzustand)', 'raise_exception „Regel 4“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('4', 'Negativ: abgeschlossen → laufend (Endzustand)', 'raise_exception „Regel 4“', SQLERRM, SQLERRM LIKE 'Regel 4%');
    END;
END $$;

-- ---------------------------------------------------------------------
-- Regel 2: Bewertung nur nach abgeschlossener eigener Ausleihe
-- (Trigger trg_bewertung_werk_berechtigung, trg_bewertung_person_berechtigung,
--  CHECK chk_bewertung_person_selbst)
-- ---------------------------------------------------------------------
DO $$
DECLARE f fix%ROWTYPE; v_laufend INT; v_fertig INT;
BEGIN
    SELECT * INTO f FROM fix;

    -- eine laufende und eine abgeschlossene Ausleihe des Testexemplars
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status, uebergeben_am)
    VALUES (f.exemplar, f.ausleiher, '2027-04-01', '2027-04-10', 'laufend', '2027-04-01')
    RETURNING ausleihe_id INTO v_laufend;
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status, uebergeben_am, zurueckgegeben_am)
    VALUES (f.exemplar, f.ausleiher, '2027-05-01', '2027-05-10', 'abgeschlossen', '2027-05-01', '2027-05-10')
    RETURNING ausleihe_id INTO v_fertig;

    BEGIN
        INSERT INTO bewertung_werk (werk_id, verfasser_id, ausleihe_id, sterne)
        VALUES (f.werk, f.ausleiher, v_laufend, 5);
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: Werkbewertung zu laufender Ausleihe', 'raise_exception „Regel 2“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: Werkbewertung zu laufender Ausleihe', 'raise_exception „Regel 2“', SQLERRM, SQLERRM LIKE 'Regel 2%');
    END;

    BEGIN
        INSERT INTO bewertung_werk (werk_id, verfasser_id, ausleihe_id, sterne)
        VALUES (f.werk, f.besitzer, v_fertig, 5);
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: besitzende Person bewertet das Werk', 'raise_exception „Regel 2“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: besitzende Person bewertet das Werk', 'raise_exception „Regel 2“', SQLERRM, SQLERRM LIKE 'Regel 2%');
    END;

    BEGIN
        INSERT INTO bewertung_werk (werk_id, verfasser_id, ausleihe_id, sterne)
        VALUES (f.anderes_werk, f.ausleiher, v_fertig, 5);
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: Bewertung eines fremden Werks über diese Ausleihe', 'raise_exception „Regel 2“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: Bewertung eines fremden Werks über diese Ausleihe', 'raise_exception „Regel 2“', SQLERRM, SQLERRM LIKE 'Regel 2%');
    END;

    INSERT INTO bewertung_werk (werk_id, verfasser_id, ausleihe_id, sterne)
    VALUES (f.werk, f.ausleiher, v_fertig, 4);
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('2', 'Positiv: ausleihende Person bewertet das Werk nach Abschluss', 'angenommen', 'angenommen', TRUE);

    BEGIN
        INSERT INTO bewertung_person (bewertender_id, bewerteter_id, ausleihe_id, sterne)
        VALUES (f.dritter, f.besitzer, v_fertig, 4);
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: unbeteiligte Person bewertet eine Partei', 'raise_exception „Regel 2“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: unbeteiligte Person bewertet eine Partei', 'raise_exception „Regel 2“', SQLERRM, SQLERRM LIKE 'Regel 2%');
    END;

    -- Selbstbewertung ist doppelt abgesichert: CHECK chk_bewertung_person_selbst
    -- und der Trigger. PostgreSQL führt BEFORE-Trigger VOR den CHECK-Constraints
    -- aus, deshalb meldet sich hier der Trigger (raise_exception); der CHECK
    -- bleibt als zweite Verteidigungslinie, falls der Trigger je deaktiviert wird.
    BEGIN
        INSERT INTO bewertung_person (bewertender_id, bewerteter_id, ausleihe_id, sterne)
        VALUES (f.ausleiher, f.ausleiher, v_fertig, 5);
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: Selbstbewertung', 'raise_exception oder check_violation', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception OR check_violation THEN
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('2', 'Negativ: Selbstbewertung', 'raise_exception oder check_violation', SQLSTATE || ' ' || SQLERRM, TRUE);
    END;

    INSERT INTO bewertung_person (bewertender_id, bewerteter_id, ausleihe_id, sterne)
    VALUES (f.ausleiher, f.besitzer, v_fertig, 5), (f.besitzer, f.ausleiher, v_fertig, 4);
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('2', 'Positiv: beide Parteien bewerten sich gegenseitig', 'angenommen', 'angenommen', TRUE);
END $$;

-- ---------------------------------------------------------------------
-- Änderungen bestehender Ausleihen (UPDATE): EXCLUDE und Leihdauer-Trigger
-- greifen auch, wenn eine vorhandene Zeile geändert wird.
-- Die Zeiträume dieses und der folgenden Blöcke liegen ab Juni 2027 und
-- berühren damit die Ausleihen der Blöcke oben (Dez. 2026 bis Mai 2027) nicht.
-- ---------------------------------------------------------------------
DO $$
DECLARE f fix%ROWTYPE; v_id INT; v_constraint TEXT;
BEGIN
    SELECT * INTO f FROM fix;

    -- zwei bestätigte Ausleihen ohne Überschneidung; die zweite wird in die erste hinein verschoben
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.ausleiher, '2027-06-01', '2027-06-10', 'bestaetigt');
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.dritter, '2027-06-15', '2027-06-20', 'bestaetigt')
    RETURNING ausleihe_id INTO v_id;

    BEGIN
        UPDATE ausleihe SET zeitraum_von = '2027-06-08', zeitraum_bis = '2027-06-13'
         WHERE ausleihe_id = v_id;
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('1', 'Negativ: UPDATE verschiebt 15.–20.06. auf 08.–13.06.', 'excl_ausleihe_doppelbuchung', 'angenommen', FALSE);
    EXCEPTION WHEN exclusion_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;   -- Name des verletzten Constraints
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('1', 'Negativ: UPDATE verschiebt 15.–20.06. auf 08.–13.06.', 'excl_ausleihe_doppelbuchung',
                SQLSTATE || ' ' || v_constraint, v_constraint = 'excl_ausleihe_doppelbuchung');
    END;

    -- bestätigte Ausleihe über 10 Tage wird auf 15 Tage verlängert (Maximum 14)
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.ausleiher, '2027-07-01', '2027-07-10', 'bestaetigt')
    RETURNING ausleihe_id INTO v_id;

    BEGIN
        UPDATE ausleihe SET zeitraum_bis = '2027-07-15' WHERE ausleihe_id = v_id;
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('3', 'Negativ: UPDATE verlängert 01.–10.07. auf 15 Tage', 'trg_ausleihe_leihdauer „Regel 3“', 'angenommen', FALSE);
    EXCEPTION WHEN raise_exception THEN
        -- Die Meldung „Regel 3“ wirft nur pruefe_leihdauer(), die Funktion von trg_ausleihe_leihdauer;
        -- den Triggernamen selbst enthält der Fehler nicht.
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('3', 'Negativ: UPDATE verlängert 01.–10.07. auf 15 Tage', 'trg_ausleihe_leihdauer „Regel 3“', SQLERRM, SQLERRM LIKE 'Regel 3%');
    END;
END $$;

-- ---------------------------------------------------------------------
-- Grenzfälle der Regel 1: Storno gibt den Zeitraum frei; angrenzende
-- Zeiträume kollidieren, weil daterange '[]' beide Randtage belegt
-- (Entscheidung „Leihdauer inklusiv“).
-- ---------------------------------------------------------------------
DO $$
DECLARE f fix%ROWTYPE; v_id INT; v_constraint TEXT;
BEGIN
    SELECT * INTO f FROM fix;

    -- bestätigte Ausleihe wird storniert, danach bucht eine andere Person denselben Zeitraum
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.ausleiher, '2027-08-01', '2027-08-10', 'bestaetigt')
    RETURNING ausleihe_id INTO v_id;
    UPDATE ausleihe SET status = 'storniert' WHERE ausleihe_id = v_id;
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.dritter, '2027-08-01', '2027-08-10', 'bestaetigt');
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('1', 'Positiv: nach Storno ist 01.–10.08. wieder buchbar', 'angenommen', 'angenommen', TRUE);

    -- neue Buchung beginnt am Rückgabetag einer bestehenden Buchung
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
    VALUES (f.exemplar, f.ausleiher, '2027-09-01', '2027-09-10', 'bestaetigt');

    BEGIN
        INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status)
        VALUES (f.exemplar, f.dritter, '2027-09-10', '2027-09-15', 'bestaetigt');
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('1', 'Negativ: Beginn 10.09. = letzter Tag von 01.–10.09.', 'excl_ausleihe_doppelbuchung', 'angenommen', FALSE);
    EXCEPTION WHEN exclusion_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('1', 'Negativ: Beginn 10.09. = letzter Tag von 01.–10.09.', 'excl_ausleihe_doppelbuchung',
                SQLSTATE || ' ' || v_constraint, v_constraint = 'excl_ausleihe_doppelbuchung');
    END;
END $$;

-- ---------------------------------------------------------------------
-- Löschregeln der Fremdschlüssel (DELETE): RESTRICT verhindert das Löschen,
-- SET NULL löst den Bezug, CASCADE löscht die abhängigen Zeilen mit.
-- ---------------------------------------------------------------------
DO $$
DECLARE f fix%ROWTYPE; v_id INT; v_nachricht INT; v_werk INT; v_constraint TEXT;
        v_anzahl INT; v_vorher INT; v_nachher INT;
BEGIN
    SELECT * INTO f FROM fix;

    -- RESTRICT: das Testexemplar hat eine Ausleihe und darf deshalb nicht gelöscht werden
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis)
    VALUES (f.exemplar, f.ausleiher, '2027-10-01', '2027-10-05');

    BEGIN
        DELETE FROM exemplar WHERE exemplar_id = f.exemplar;
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('FK', 'Negativ: DELETE Exemplar mit Ausleihe (RESTRICT)', 'ausleihe_exemplar_id_fkey', 'angenommen', FALSE);
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
        VALUES ('FK', 'Negativ: DELETE Exemplar mit Ausleihe (RESTRICT)', 'ausleihe_exemplar_id_fkey',
                SQLSTATE || ' ' || v_constraint, v_constraint = 'ausleihe_exemplar_id_fkey');
    END;

    -- SET NULL: die Nachricht zur gelöschten Ausleihe bleibt, verliert aber den Bezug
    INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis)
    VALUES (f.exemplar, f.ausleiher, '2027-11-01', '2027-11-05')
    RETURNING ausleihe_id INTO v_id;
    INSERT INTO nachricht (absender_id, empfaenger_id, ausleihe_id, text)
    VALUES (f.ausleiher, f.besitzer, v_id, 'Testnachricht zur Ausleihe')
    RETURNING nachricht_id INTO v_nachricht;

    DELETE FROM ausleihe WHERE ausleihe_id = v_id;
    SELECT count(*) INTO v_anzahl
      FROM nachricht WHERE nachricht_id = v_nachricht AND ausleihe_id IS NULL;
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('FK', 'Positiv: DELETE Ausleihe mit Nachricht (SET NULL)', 'Nachricht bleibt, ausleihe_id NULL',
            v_anzahl || ' Nachricht mit ausleihe_id NULL', v_anzahl = 1);

    -- CASCADE: eigenes Werk ohne Exemplar mit zwei Autorzuordnungen; beim Löschen
    -- des Werks verschwinden die werk_autor-Zeilen mit
    INSERT INTO werk (titel, verlag_id, sprache_id)
    SELECT 'Testwerk ohne Exemplar', verlag_id, sprache_id FROM werk WHERE werk_id = f.werk
    RETURNING werk_id INTO v_werk;
    INSERT INTO werk_autor (werk_id, autor_id, beitragsart)
    SELECT v_werk, autor_id, 'Autor' FROM autor ORDER BY autor_id LIMIT 2;
    SELECT count(*) INTO v_vorher FROM werk_autor WHERE werk_id = v_werk;

    DELETE FROM werk WHERE werk_id = v_werk;
    SELECT count(*) INTO v_nachher FROM werk_autor WHERE werk_id = v_werk;
    INSERT INTO testergebnis (regel, testfall, erwartet, ergebnis, bestanden)
    VALUES ('FK', 'Positiv: DELETE Werk ohne Exemplar (CASCADE)', 'werk_autor-Zeilen gelöscht',
            'werk_autor: ' || v_vorher || ' → ' || v_nachher || ' Zeilen', v_vorher = 2 AND v_nachher = 0);
END $$;

-- ---------------------------------------------------------------------
-- Auswertung
-- ---------------------------------------------------------------------
SELECT nr, regel, testfall, erwartet, left(ergebnis, 70) AS ergebnis, bestanden
  FROM testergebnis ORDER BY nr;

DO $$
DECLARE n_gesamt INT; n_fehl INT;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE NOT bestanden) INTO n_gesamt, n_fehl FROM testergebnis;
    IF n_fehl > 0 THEN
        RAISE EXCEPTION 'Geschäftsregel-Tests: % von % Fällen NICHT bestanden', n_fehl, n_gesamt;
    END IF;
    RAISE NOTICE 'Geschäftsregel-Tests: alle % Fälle bestanden', n_gesamt;
END $$;

ROLLBACK;   -- Testdaten verwerfen, Seed-Zustand bleibt erhalten
