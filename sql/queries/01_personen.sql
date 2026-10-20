-- =====================================================================
-- Fachabfragen, Gruppe 1: Personen & Rollen (Phase 2)
-- Handgeschrieben. Läuft NICHT beim Containerstart.
--
-- Je Entität genau eine Abfrage mit maschinenlesbarem Kopfblock:
--   @entitaet · @frage · @konstrukt · @erwartet · @erklaerung
-- @erwartet ist nach dem Lauf aus der echten Ausgabe gefüllt (Zeilenzahl und
-- erste Zeile), @erklaerung füllt Tanzin.
--
-- Ausführen und Ergebnisbelege schreiben:  python3 tools/run_queries.py
-- Belege:                                  sql/queries/ergebnis/<nr>_<entitaet>.txt
--
-- Die Datei enthält bewusst keine psql-Metabefehle (\o, \qecho): sie ist
-- portables SQL und lässt sich auch in DBeaver oder pgAdmin am Stück ausführen.
-- =====================================================================

-- Zeitstempel liegen in UTC in der Datenbank, die Fachfragen sind in Ortszeit
-- formuliert; die Einstellung gilt nur für die aktuelle Sitzung.
SET TimeZone = 'Europe/Berlin';


-- @entitaet:   benutzer
-- @frage:      Wie viele Mitglieder sind je Quartal dazugekommen, und wie groß war die Gemeinschaft danach?
-- @konstrukt:  date_trunc, GROUP BY, SUM() OVER (ORDER BY)
-- @erwartet:   7 Zeilen; erste Zeile: 2025-Q1 | 7 | 7
-- @erklaerung: Die Positionen (verleihend/ausleihend) werden durch eine einzige Personentabelle abgebildet. Die Fensterfunktion liefert den aufsummierten Bestand (je Quartal) ohne eine zweite Abfrage.
SELECT to_char(date_trunc('quarter', registriert_am), 'YYYY"-Q"Q') AS quartal,
       count(*) AS registrierungen,
       -- Fensterfunktion über dem Ergebnis der Gruppierung: sie summiert die
       -- Quartalszahlen in der Sortierreihenfolge auf und ergibt so den
       -- Mitgliederbestand am Ende des jeweiligen Quartals.
       sum(count(*)) OVER (ORDER BY date_trunc('quarter', registriert_am)) AS bestand_kumuliert
  FROM benutzer
 GROUP BY date_trunc('quarter', registriert_am)
 ORDER BY date_trunc('quarter', registriert_am);


-- @entitaet:   adresse
-- @frage:      Welche Mitglieder wohnen im Umkreis von 1,5 km um Mitglied 1, nach Entfernung sortiert?
-- @konstrukt:  ST_DWithin, ST_Distance, GiST-Index idx_adresse_position, Self-Join
-- @erwartet:   11 Zeilen; erste Zeile: 12 | Raymond Kranz | Kettenhofweg | 43b | 60325 | 393
-- @erklaerung: Eine Person hat genau eine Adresse mit einem geografischen Punkt. Durch ST_DWithin wird die Distanz in Metern berechnet und durch den GiST-Index wird der Umkreis indexierbar.
SELECT b.benutzer_id,
       concat_ws(' ', b.vorname, b.nachname) AS mitglied,
       a.strasse, a.hausnummer, a.plz,
       -- ST_Distance rechnet auf geography in Metern; round(...)::int macht
       -- aus der Fließkommazahl eine ablesbare Meterangabe.
       round(ST_Distance(a.position, m.position))::int AS entfernung_m
  -- m ist die Adresse der suchenden Person, a sind alle anderen Adressen:
  -- derselbe Tabellenname zweimal, deshalb die Aliase (Self-Join).
  FROM adresse m
  -- ST_DWithin fragt "liegt a höchstens 1500 m von m entfernt" und kann dafür
  -- den räumlichen GiST-Index nutzen; ST_Distance allein könnte das nicht.
  JOIN adresse a  ON a.benutzer_id <> m.benutzer_id
                 AND ST_DWithin(a.position, m.position, 1500)
  JOIN benutzer b ON b.benutzer_id = a.benutzer_id
 WHERE m.benutzer_id = 1
 ORDER BY entfernung_m;

-- Demonstration (keine Messung — die steht in sql/perf/01_umkreissuche.sql):
-- Der Planer nimmt den GiST-Index für diese Abfrage schon bei den 40 Adressen
-- von sich aus (Index Scan, siehe Kopf von sql/perf/01_umkreissuche.sql).
-- enable_seqscan = off verteuert den Seq Scan zusätzlich künstlich: der Plan
-- unten zeigt also den erzwungenen Fall, nicht den einzigen Weg zum Index.
-- SET LOCAL gilt nur bis zum Ende der Transaktion, ROLLBACK stellt sicher,
-- dass die Sitzung danach wieder unverändert ist.
BEGIN;
SET LOCAL enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT b.benutzer_id,
       concat_ws(' ', b.vorname, b.nachname) AS mitglied,
       a.strasse, a.hausnummer, a.plz,
       round(ST_Distance(a.position, m.position))::int AS entfernung_m
  FROM adresse m
  JOIN adresse a  ON a.benutzer_id <> m.benutzer_id
                 AND ST_DWithin(a.position, m.position, 1500)
  JOIN benutzer b ON b.benutzer_id = a.benutzer_id
 WHERE m.benutzer_id = 1
 ORDER BY entfernung_m;
ROLLBACK;


-- @entitaet:   rolle
-- @frage:      Wie viele Personen hat jede Systemrolle — auch die Rollen ohne Zuordnung?
-- @konstrukt:  LEFT JOIN, count(Spalte) statt count(*)
-- @erwartet:   3 Zeilen; erste Zeile: 1 | Mitglied | Bücher einstellen, anfragen, ausleihen, bewerten | 40
-- @erklaerung: Es gibt drei Rollen für Benutzer: Mitglied, Moderation, Administration. Darum ist die Anzahl bewusst kleiner als 10 gewählt. Da über den LEFT JOIN Personen je Rolle gezählt werden, erscheinen auch Rollen ohne Zuordnung mit 0.
SELECT r.rolle_id, r.bezeichnung, r.beschreibung,
       -- count(br.benutzer_id) zählt nur vorhandene Zuordnungen und liefert
       -- für eine Rolle ohne Personen 0; count(*) würde hier 1 zählen, weil
       -- der LEFT JOIN die Rolle mit lauter NULL-Spalten beibehält.
       count(br.benutzer_id) AS personen
  FROM rolle r
  LEFT JOIN benutzer_rolle br ON br.rolle_id = r.rolle_id
 GROUP BY r.rolle_id, r.bezeichnung, r.beschreibung
 ORDER BY personen DESC, r.bezeichnung;


-- @entitaet:   benutzer_rolle
-- @frage:      Welche Personen haben mehr als eine Rolle, und welche sind es?
-- @konstrukt:  GROUP BY, HAVING, string_agg
-- @erwartet:   4 Zeilen; erste Zeile: 1 | Felicitas Dowerg | 2 | Administration, Mitglied
-- @erklaerung: Durch die n:m-Beziehung kann eine Person mehrere Rollen haben und eine Rolle von mehreren Personen gehalten werden. In dem Testfall mit HAVING wird nach Personen mit mehr als einer Rolle gefiltert. Durch string_agg wird die Rollenliste in einer Spalte lesbar.
SELECT b.benutzer_id,
       concat_ws(' ', b.vorname, b.nachname) AS mitglied,
       count(*) AS rollen,
       -- string_agg macht aus den mehreren Rollenzeilen einer Person eine
       -- lesbare Aufzählung in einer Spalte.
       string_agg(r.bezeichnung, ', ' ORDER BY r.bezeichnung) AS rollenliste
  FROM benutzer_rolle br
  JOIN benutzer b ON b.benutzer_id = br.benutzer_id
  JOIN rolle r    ON r.rolle_id    = br.rolle_id
 GROUP BY b.benutzer_id, b.vorname, b.nachname
-- HAVING filtert nach dem Gruppieren — WHERE könnte die Zahl der Rollen je
-- Person noch gar nicht kennen.
HAVING count(*) > 1
 ORDER BY rollen DESC, b.benutzer_id;
