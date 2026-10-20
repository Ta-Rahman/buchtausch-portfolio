-- =====================================================================
-- Fachabfragen, Gruppe 4: Transaktion (Phase 2)
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
-- Die Datei enthält bewusst keine psql-Metabefehle: sie ist portables SQL und
-- lässt sich auch in DBeaver oder pgAdmin am Stück ausführen.
-- =====================================================================

-- Zeitstempel liegen in UTC in der Datenbank, die Fachfragen sind in Ortszeit
-- formuliert; die Einstellung gilt nur für die aktuelle Sitzung.
SET TimeZone = 'Europe/Berlin';


-- @entitaet:   ausleihe
-- @frage:      Welche Ausleihen laufen zum Stichtag 19.09.2026 noch oder sind überfällig, und wie viele Tage bleiben beziehungsweise fehlen?
-- @konstrukt:  CASE, Datumsarithmetik, JOIN über 3 Tabellen, ORDER BY … NULLS LAST
-- @erwartet:   15 Zeilen; erste Zeile: 2 | verspaetet | Altes Land | Gaby Reuter | 2026-02-18 | 2026-03-16 |  | 187
-- @erklaerung: Die Ausleihe ist der Vorgang von der Anfrage bis hin zur Rückgabe. Der Trigger sichert die Statusübergänge und der EXCLUDE-Constraint überlappende Zeiträume. In dem Testfall werden laufende und überfällige Ausleihen zu einem festen Stichtag (19.09.2026, statt now() für Reproduzierbarkeit) überprüft.
SELECT al.ausleihe_id, al.status,
       w.titel,
       concat_ws(' ', b.vorname, b.nachname) AS ausleiher_in,
       al.zeitraum_von, al.zeitraum_bis,
       -- Zwei DATE-Werte voneinander abgezogen ergeben in PostgreSQL eine
       -- ganze Zahl von Tagen; CASE entscheidet, in welche der beiden Spalten
       -- die Differenz gehört.
       CASE WHEN al.zeitraum_bis >= DATE '2026-09-19'
            THEN al.zeitraum_bis - DATE '2026-09-19'
       END AS resttage,
       CASE WHEN al.zeitraum_bis < DATE '2026-09-19'
            THEN DATE '2026-09-19' - al.zeitraum_bis
       END AS ueberzogen_tage
  FROM ausleihe al
  JOIN exemplar e ON e.exemplar_id = al.exemplar_id
  JOIN werk w     ON w.werk_id     = e.werk_id
  JOIN benutzer b ON b.benutzer_id = al.ausleiher_id
 -- 'laufend' ist die planmäßig laufende Ausleihe, 'verspaetet' die überzogene;
 -- beide zusammen sind der offene Bestand des Stichtags.
 WHERE al.status IN ('laufend', 'verspaetet')
 -- NULLS LAST, weil die Spalte ueberzogen_tage bei planmäßigen Ausleihen leer
 -- ist und diese sonst vor den überfälligen stünden.
 ORDER BY ueberzogen_tage DESC NULLS LAST, resttage, al.ausleihe_id;


-- @entitaet:   uebergabe
-- @frage:      Wie sind Hin- und Rückweg je abgeschlossener Ausleihe gelaufen?
-- @konstrukt:  bedingte Aggregation mit FILTER, JOIN über 4 Tabellen, GROUP BY
-- @erwartet:   34 Zeilen; erste Zeile: 1 | Cien años de soledad | Postversand | 2026-08-22 17:00:00+02 | Postversand | 2026-08-27 11:00:00+02
-- @erklaerung: Durch die Dreifachbeziehung wird beschrieben, wann und auf welchem Weg ein Exemplar den Besitz wechselt. Durch UNIQUE (ausleihe_id, richtung) gibt es genau eine Hin- und eine Rückübergabe. Im Testfall werden je abgeschlossener Ausleihe Hin- und Rückweg in eine Zeile gelegt.
SELECT al.ausleihe_id, w.titel,
       -- Hin- und Rückweg stehen als zwei Zeilen in uebergabe. FILTER holt je
       -- Richtung die passende Zeile in eine eigene Spalte; max() ist dabei
       -- nur die Hülle, denn UNIQUE (ausleihe_id, richtung) lässt je Richtung
       -- ohnehin höchstens eine Zeile zu.
       max(ua.bezeichnung) FILTER (WHERE u.richtung = 'hinweg')   AS hinweg_art,
       max(u.erfolgt_am)   FILTER (WHERE u.richtung = 'hinweg')   AS hinweg_am,
       max(ua.bezeichnung) FILTER (WHERE u.richtung = 'rueckweg') AS rueckweg_art,
       max(u.erfolgt_am)   FILTER (WHERE u.richtung = 'rueckweg') AS rueckweg_am
  FROM ausleihe al
  JOIN uebergabe u     ON u.ausleihe_id      = al.ausleihe_id
  JOIN uebergabeart ua ON ua.uebergabeart_id = u.uebergabeart_id
  JOIN exemplar e      ON e.exemplar_id      = al.exemplar_id
  JOIN werk w          ON w.werk_id          = e.werk_id
 WHERE al.status = 'abgeschlossen'
 GROUP BY al.ausleihe_id, w.titel
 ORDER BY al.ausleihe_id;
