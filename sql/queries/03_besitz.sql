-- =====================================================================
-- Fachabfragen, Gruppe 3: Besitz & Verfügbarkeit (Phase 2)
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
-- Frage 13 braucht zusätzlich die View v_exemplar_suche aus
-- sql/init/07_views.sql.
-- =====================================================================

-- Zeitstempel liegen in UTC in der Datenbank, die Fachfragen sind in Ortszeit
-- formuliert; die Einstellung gilt nur für die aktuelle Sitzung.
SET TimeZone = 'Europe/Berlin';


-- @entitaet:   zustand
-- @frage:      Wie verteilen sich die Exemplare über die fünf Zustandsstufen?
-- @konstrukt:  LEFT JOIN, GROUP BY, SUM() OVER (), repeat als Textbalken
-- @erwartet:   5 Zeilen; erste Zeile: 1 | neuwertig | 13 | 10.8 | ######
-- @erklaerung: Der Buchzustand wird als eine ordinale Skala von 1 (neuwertig) bis 5 (stark abgenutzt) realisiert und kann dadurch gefiltert und sortiert werden. In dem Testfall wird die Verteilung der Exemplare über die Stufen mit Prozent und einem Textbalken aus repeat() gezeigt.
SELECT z.stufe, z.bezeichnung,
       count(e.exemplar_id) AS exemplare,
       round(100.0 * count(e.exemplar_id) / sum(count(e.exemplar_id)) OVER (), 1) AS anteil_prozent,
       -- repeat zeichnet einen Balken aus so vielen Rauten, wie die Gruppe
       -- ganze Zweierschritte hat — ein Histogramm ohne Grafikwerkzeug.
       repeat('#', (count(e.exemplar_id) / 2)::int) AS balken
  FROM zustand z
  -- LEFT JOIN, damit eine nie vergebene Stufe mit 0 sichtbar bliebe.
  LEFT JOIN exemplar e ON e.zustand_id = z.zustand_id
 GROUP BY z.stufe, z.bezeichnung
 -- Die Stufe ist ordinal (1 neuwertig bis 5 stark abgenutzt), deshalb wird
 -- nach ihr sortiert und nicht nach der Häufigkeit.
 ORDER BY z.stufe;


-- @entitaet:   exemplar
-- @frage:      Welche verfügbaren Exemplare von "Tintenherz" liegen im Umkreis von 2 km um Mitglied 7?
-- @konstrukt:  CTE, JOIN über 5 Tabellen, ST_DWithin, ST_Distance, partieller Index idx_exemplar_verfuegbar
-- @erwartet:   2 Zeilen; erste Zeile: 6 | Tintenherz | Juan Bolzmann | gebraucht | 21 | f | 1387
-- @erklaerung: Das Exemplar wird beschrieben als das Buch, das eine Person besitzt und ist somit die physische Leiheinheit, wobei das Werk nur der Titel ist. Der Standort der suchenden Person wird einmal von der CTE geholt. Es wird ein JOIN über fünf Tabellen gemacht: ST_DWithin 2 km, eigene Exemplare ausgeschlossen.
-- Die CTE (WITH-Abfrage) benennt den Standpunkt der suchenden Person einmal
-- und macht ihn im Rest der Abfrage wie eine Tabelle verfügbar.
WITH suchender AS (
    SELECT position FROM adresse WHERE benutzer_id = 7
)
SELECT e.exemplar_id, w.titel,
       concat_ws(' ', b.vorname, b.nachname) AS besitzer,
       z.bezeichnung AS zustand,
       e.max_leihdauer_tage, e.versand_moeglich,
       round(ST_Distance(ad.position, s.position))::int AS entfernung_m
  FROM suchender s
  JOIN adresse ad  ON ST_DWithin(ad.position, s.position, 2000)
  JOIN benutzer b  ON b.benutzer_id = ad.benutzer_id
  -- status = 'verfuegbar' bedient der partielle Index idx_exemplar_verfuegbar:
  -- pausierte und entfernte Exemplare stehen gar nicht erst darin.
  JOIN exemplar e  ON e.besitzer_id = b.benutzer_id AND e.status = 'verfuegbar'
  JOIN werk w      ON w.werk_id     = e.werk_id
  JOIN zustand z   ON z.zustand_id  = e.zustand_id
 WHERE w.titel = 'Tintenherz'
   -- Die eigenen Bücher leiht man nicht aus; ohne diese Zeile stünde das
   -- eigene Exemplar mit 0 m an erster Stelle.
   AND b.benutzer_id <> 7
 ORDER BY entfernung_m;

-- Dieselbe Frage über die View v_exemplar_suche (sql/init/07_views.sql):
-- die vier Joins und der Filter auf verfügbare Exemplare stecken schon in der
-- View, übrig bleibt die Umkreisbedingung.
SELECT v.exemplar_id, v.titel, v.autoren, v.besitzer, v.zustand,
       round(ST_Distance(v.besitzer_position, s.position))::int AS entfernung_m
  FROM v_exemplar_suche v
  JOIN adresse s ON s.benutzer_id = 7
 WHERE v.titel = 'Tintenherz'
   AND v.besitzer_id <> 7
   AND ST_DWithin(v.besitzer_position, s.position, 2000)
 ORDER BY entfernung_m;


-- @entitaet:   zeitslot
-- @frage:      Welche Zeitfenster überschneiden sich mit dem 15.10.2026 von 17 bis 19 Uhr?
-- @konstrukt:  tstzrange, Überlappungsoperator, GiST-Index idx_zeitslot_zeitraum, LEFT JOIN
-- @erwartet:   2 Zeilen; erste Zeile: 64 | 2026-10-15 17:00:00+02 | 2026-10-15 19:00:00+02 | 1
-- @erklaerung: Es gibt ein konkretes Zeitfenster mit Beginn und Ende (als Zeitstempel mit Zeitzone) und es gilt Ende > Beginn (für Verfügbarkeit und Übergabetermin). Der Testfall findet durch tstzrange(beginn, ende) && tstzrange(…) Fenster, die sich mit einem Termin (15.10.2026, 17–19 Uhr) überschneiden.
SELECT z.zeitslot_id, z.beginn, z.ende,
       count(v.verfuegbarkeit_id) AS angebote
  FROM zeitslot z
  -- LEFT JOIN: ein überschneidendes Fenster wird auch dann gezeigt, wenn
  -- gerade kein Exemplar darin angeboten wird.
  LEFT JOIN verfuegbarkeit v ON v.zeitslot_id = z.zeitslot_id
 -- tstzrange baut aus Beginn und Ende einen Zeitbereich; der Operator zwischen
 -- den beiden Bereichen ist wahr, sobald sie sich überlappen. Genau ihn
 -- bedient der GiST-Index idx_zeitslot_zeitraum, ein B-Baum könnte das nicht.
 -- Die Bereiche sind halboffen: ein Fenster, das erst um 19:00 Uhr beginnt,
 -- überschneidet sich nicht mehr.
 WHERE tstzrange(z.beginn, z.ende)
       && tstzrange(TIMESTAMPTZ '2026-10-15 17:00+02', TIMESTAMPTZ '2026-10-15 19:00+02')
 GROUP BY z.zeitslot_id, z.beginn, z.ende
 ORDER BY z.beginn, z.zeitslot_id;


-- @entitaet:   uebergabeart
-- @frage:      Wie verteilen sich die erfolgten Übergaben auf Abholung und Postversand, und was kostet der Versand im Schnitt?
-- @konstrukt:  LEFT JOIN, Aggregat mit FILTER, AVG, SUM() OVER ()
-- @erwartet:   2 Zeilen; erste Zeile: Abholung | 71 | 85.5 |
-- @erklaerung: Für die Übergabeart gibt es genau zwei Werte (Abholung und Postversand). Durch die Art wird bestimmt, was in uebergabe belegt sein muss (Abholung → Zeitslot, Postversand → Sendungsnummer). Der Testfall zählt je Übergabeart. AVG(versandkosten) FILTER (WHERE …) mittelt nur über Postversand.
SELECT ua.bezeichnung AS uebergabeart,
       -- FILTER zählt nur die Zeilen, bei denen die Übergabe wirklich
       -- stattgefunden hat; erfolgt_am ist bis dahin NULL.
       count(*) FILTER (WHERE u.erfolgt_am IS NOT NULL) AS erfolgte_uebergaben,
       round(100.0 * count(*) FILTER (WHERE u.erfolgt_am IS NOT NULL)
             / sum(count(*) FILTER (WHERE u.erfolgt_am IS NOT NULL)) OVER (), 1) AS anteil_prozent,
       -- Versandkosten fallen nur beim Postversand an; avg übergeht NULL-Werte,
       -- die Abholung bleibt deshalb leer statt 0,00 zu zeigen.
       round(avg(u.versandkosten) FILTER (WHERE u.erfolgt_am IS NOT NULL), 2) AS versandkosten_schnitt
  FROM uebergabeart ua
  LEFT JOIN uebergabe u ON u.uebergabeart_id = ua.uebergabeart_id
 GROUP BY ua.bezeichnung
 ORDER BY erfolgte_uebergaben DESC;


-- @entitaet:   verfuegbarkeit
-- @frage:      Wann und auf welchem Weg ist Exemplar 68 in den vier Wochen ab dem Stichtag 19.09.2026 übergebbar?
-- @konstrukt:  JOIN über die Dreifachbeziehung Exemplar/Zeitslot/Übergabeart, Bereichsfilter mit INTERVAL
-- @erwartet:   3 Zeilen; erste Zeile: 106 | 2026-10-08 16:00:00+02 | 2026-10-08 18:00:00+02 | Abholung | L'Étranger | Siegbert Sontag
-- @erklaerung: Es wird eine Dreifachbeziehung benötigt, da bei der Frage nach wann welches Exemplar auf welchem Weg übergeben werden kann (Exemplar × Zeitslot × Übergabeart) jede der Fragen einen Fremdschlüssel benötigt. In dem Testfall wird ein JOIN über die drei Partner für Fenster von Exemplar 68 gemacht.
SELECT v.verfuegbarkeit_id,
       z.beginn, z.ende,
       ua.bezeichnung AS uebergabeart,
       w.titel,
       concat_ws(' ', b.vorname, b.nachname) AS besitzer
  FROM verfuegbarkeit v
  -- Die Dreifachbeziehung verbindet drei Entitäten gleichzeitig: welches
  -- Exemplar, in welchem Zeitfenster, auf welchem Übergabeweg.
  JOIN zeitslot z      ON z.zeitslot_id     = v.zeitslot_id
  JOIN uebergabeart ua ON ua.uebergabeart_id = v.uebergabeart_id
  JOIN exemplar e      ON e.exemplar_id     = v.exemplar_id
  JOIN werk w          ON w.werk_id         = e.werk_id
  JOIN benutzer b      ON b.benutzer_id     = e.besitzer_id
 WHERE v.exemplar_id = 68
   -- Fester Stichtag statt now(): der Seed ist auf den 19.09.2026 gerechnet,
   -- damit die Abfrage jederzeit dasselbe Ergebnis liefert.
   AND z.beginn >= DATE '2026-09-19'
   AND z.beginn <  DATE '2026-09-19' + INTERVAL '4 weeks'
 ORDER BY z.beginn, ua.bezeichnung;
