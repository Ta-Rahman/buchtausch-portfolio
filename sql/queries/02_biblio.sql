-- =====================================================================
-- Fachabfragen, Gruppe 2: Bibliografische Stammdaten (Phase 2)
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


-- @entitaet:   autor
-- @frage:      Welche Autor:innen sind mit mehr als einem Werk vertreten, und wie viele Exemplare davon gibt es in der Nachbarschaft?
-- @konstrukt:  JOIN-Kette über 4 Tabellen, LEFT JOIN, count(DISTINCT), HAVING
-- @erwartet:   8 Zeilen; erste Zeile: 12 | Cornelia Funke | 2 | 7
-- @erklaerung: Autor:innen werden getrennt vom Werk gespeichert, damit dieselbe Person nur einmal existiert. Über die Kette Autor → werk_autor → Werk → Exemplar läuft der Testfall und zählt Werke und Exemplare je Autor:in. Bei HAVING werden nur Autor:innen mit mehr als einem Werk durchgelassen.
SELECT a.autor_id,
       concat_ws(' ', a.vorname, a.nachname) AS autor_in,
       -- count(DISTINCT werk_id), weil der LEFT JOIN auf exemplar jedes Werk
       -- so oft wiederholt, wie es Exemplare davon gibt.
       count(DISTINCT w.werk_id) AS werke,
       count(e.exemplar_id)      AS exemplare
  FROM autor a
  -- Nur die verfassende Beteiligung zählt; Übersetzung und Herausgabe stehen
  -- in derselben Tabelle und würden die Werkzahl sonst verfälschen.
  JOIN werk_autor wa ON wa.autor_id = a.autor_id AND wa.beitragsart = 'Autor'
  JOIN werk w        ON w.werk_id   = wa.werk_id
  -- LEFT JOIN: ein Werk ohne Exemplar soll die Autorin trotzdem in der Liste
  -- lassen, es zählt dann 0 Exemplare.
  LEFT JOIN exemplar e ON e.werk_id = w.werk_id
 GROUP BY a.autor_id, a.vorname, a.nachname
HAVING count(DISTINCT w.werk_id) > 1
 ORDER BY werke DESC, exemplare DESC, a.nachname;


-- @entitaet:   verlag
-- @frage:      Wie viele Werke und Exemplare entfallen auf jeden Verlag, auch auf Verlage ohne Exemplar?
-- @konstrukt:  LEFT JOIN über zwei Stufen, count(DISTINCT)
-- @erwartet:   12 Zeilen; erste Zeile: 11 | Penguin Books | London | 11 | 20
-- @erklaerung: Ein Verlag besitzt einen eindeutigen Namen (UNIQUE). Jedes Werk verweist auf genau einen Verlag. In dem Testfall werden Werke und Exemplare je Verlag über zwei LEFT JOINs gezählt. Deshalb bleibt ein Verlag mit 0 Werken sichtbar.
SELECT v.verlag_id, v.name, v.sitz,
       count(DISTINCT w.werk_id)     AS werke,
       count(DISTINCT e.exemplar_id) AS exemplare
  FROM verlag v
  -- Zwei LEFT JOINs hintereinander: ein Verlag ohne Werk und ein Werk ohne
  -- Exemplar sollen beide erhalten bleiben und als 0 erscheinen.
  LEFT JOIN werk w     ON w.verlag_id = v.verlag_id
  LEFT JOIN exemplar e ON e.werk_id   = w.werk_id
 GROUP BY v.verlag_id, v.name, v.sitz
 ORDER BY exemplare DESC, werke DESC, v.name;


-- @entitaet:   sprache
-- @frage:      Wie verteilen sich die Werke prozentual auf die Sprachen?
-- @konstrukt:  GROUP BY, SUM() OVER () als Gesamtsumme, round
-- @erwartet:   7 Zeilen; erste Zeile: de | Deutsch | 43 | 71.7
-- @erklaerung: Jedes Werk ist genau in einer Sprache geschrieben. Der Anteil je Sprache wird vom Testfall in Prozent berechnet, und SUM(COUNT(*)) OVER () holt die Gesamtsumme aus dem Aggregat (ohne zweite Abfrage).
SELECT s.iso_code, s.bezeichnung,
       count(*) AS werke,
       -- sum(count(*)) OVER () ohne PARTITION läuft über alle Gruppen und
       -- liefert die Gesamtzahl der Werke — der Nenner für den Prozentanteil,
       -- ohne dass die Tabelle ein zweites Mal gelesen werden muss.
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS anteil_prozent
  FROM werk w
  JOIN sprache s ON s.sprache_id = w.sprache_id
 GROUP BY s.iso_code, s.bezeichnung
 ORDER BY werke DESC, s.bezeichnung;


-- @entitaet:   genre
-- @frage:      Welche drei Genres wurden am häufigsten tatsächlich ausgeliehen (abgeschlossene Ausleihen)?
-- @konstrukt:  JOIN über 4 Tabellen, GROUP BY, ORDER BY … LIMIT
-- @erwartet:   3 Zeilen; erste Zeile: Roman | 19
-- @erklaerung: Durch werk_genre kann ein Werk mehrere Genres besitzen. Der Testfall misst Beliebtheit an abgeschlossenen Ausleihen anstatt über den Bestand durch JOIN über vier Tabellen mit WHERE status = 'abgeschlossen'. Die drei beliebtesten Genres werden durch ORDER BY … LIMIT 3 geliefert.
SELECT g.bezeichnung AS genre,
       count(*) AS abgeschlossene_ausleihen
  FROM ausleihe al
  -- Der Weg vom Vorgang zum Genre führt über das physische Exemplar und das
  -- bibliografische Werk: ausleihe -> exemplar -> werk_genre -> genre.
  JOIN exemplar e   ON e.exemplar_id = al.exemplar_id
  JOIN werk_genre wg ON wg.werk_id   = e.werk_id
  JOIN genre g       ON g.genre_id   = wg.genre_id
 -- Nur abgeschlossene Vorgänge: angefragte oder abgelehnte sagen nichts über
 -- die tatsächliche Beliebtheit aus.
 WHERE al.status = 'abgeschlossen'
 GROUP BY g.bezeichnung
 ORDER BY abgeschlossene_ausleihen DESC, g.bezeichnung
 LIMIT 3;


-- @entitaet:   werk
-- @frage:      Findet die Titelsuche das Werk auch bei Tippfehlern ("Stepenwolf", "Kanguru-Chroniken")?
-- @konstrukt:  pg_trgm similarity, Operator %, GIN-Index idx_werk_titel_trgm, VALUES-Liste
-- @erwartet:   2 Zeilen; erste Zeile: Kanguru-Chroniken | 18 | Die Känguru-Chroniken | 0.600
-- @erklaerung: Ein Werk ist beschrieben als die bibliografische Einheit (Titel, ISBN, Jahr, Verlag, Sprache), unabhängig davon, wie viele physische Bücher (Exemplare) existieren. Der Testfall findet durch similarity() trotz Tippfehler Titel (der Operator % schlägt ab Schwellwert 0,3 an). Durch den GIN-Index idx_werk_titel_trgm wird es indexierbar.
SELECT s.suchbegriff, w.werk_id, w.titel,
       -- similarity zählt die gemeinsamen Dreibuchstabenfolgen (Trigramme)
       -- beider Texte und liefert 0 (nichts gemeinsam) bis 1 (identisch).
       round(similarity(w.titel, s.suchbegriff)::numeric, 3) AS aehnlichkeit
  -- Zwei Suchbegriffe als kleine Werteliste, damit beide Tippfehler in einer
  -- Abfrage geprüft werden.
  FROM (VALUES ('Stepenwolf'), ('Kanguru-Chroniken')) AS s(suchbegriff)
  -- Der Operator % ist wahr, sobald similarity über dem Schwellwert der
  -- Sitzung liegt (Standard 0,3); genau diesen Operator bedient der GIN-Index.
  JOIN werk w ON w.titel % s.suchbegriff
 ORDER BY s.suchbegriff, aehnlichkeit DESC;


-- @entitaet:   werk_autor
-- @frage:      Welche Werke haben neben der Verfasserschaft eine Übersetzung oder Herausgabe, und wer steht jeweils dahinter?
-- @konstrukt:  string_agg … FILTER, GROUP BY, HAVING
-- @erwartet:   13 Zeilen; erste Zeile: 30 | Buch der Lieder | Heinrich Heine | Minna Ebert |
-- @erklaerung: Durch die n:m-Beziehung können mehrere Autor:innen zu einem Werk gehören und eine Autor:in zu mehreren Werken. Durch das Attribut beitragsart kann eine Tabelle genutzt werden statt je beitragsart eine eigene. Die drei Beitragsarten werden vom Testfall durch FILTER je Werk in drei Spalten gelegt.
SELECT w.werk_id, w.titel,
       -- Dieselbe Aggregatfunktion dreimal mit unterschiedlichem FILTER: aus
       -- den Zeilen der Beteiligungstabelle werden so drei Spalten.
       string_agg(concat_ws(' ', a.vorname, a.nachname), ', ' ORDER BY a.nachname)
           FILTER (WHERE wa.beitragsart = 'Autor')       AS verfasst_von,
       string_agg(concat_ws(' ', a.vorname, a.nachname), ', ' ORDER BY a.nachname)
           FILTER (WHERE wa.beitragsart = 'Herausgeber') AS herausgegeben_von,
       string_agg(concat_ws(' ', a.vorname, a.nachname), ', ' ORDER BY a.nachname)
           FILTER (WHERE wa.beitragsart = 'Übersetzung') AS uebersetzt_von
  FROM werk w
  JOIN werk_autor wa ON wa.werk_id = w.werk_id
  JOIN autor a       ON a.autor_id = wa.autor_id
 GROUP BY w.werk_id, w.titel
-- Nur Werke, an denen jemand anderes als die verfassende Person beteiligt ist.
HAVING count(*) FILTER (WHERE wa.beitragsart <> 'Autor') > 0
 ORDER BY w.werk_id;


-- @entitaet:   werk_genre
-- @frage:      Welche Werke sind in mehr als einem Genre eingeordnet?
-- @konstrukt:  GROUP BY, HAVING, string_agg
-- @erwartet:   13 Zeilen; erste Zeile: 44 | 1984 | 2 | Roman, Science-Fiction
-- @erklaerung: Da ein Werk in mehreren Genres eingeordnet sein kann, ist es keine Spalte in werk, sondern eine Tabelle. HAVING count(*) > 1 zeigt genau die Werke, für die die Tabelle existiert. Die Genres werden durch string_agg gelistet.
SELECT w.werk_id, w.titel,
       count(*) AS genres,
       string_agg(g.bezeichnung, ', ' ORDER BY g.bezeichnung) AS genreliste
  FROM werk_genre wg
  JOIN werk w  ON w.werk_id  = wg.werk_id
  JOIN genre g ON g.genre_id = wg.genre_id
 GROUP BY w.werk_id, w.titel
-- Die n:m-Tabelle erlaubt beliebig viele Genres je Werk; HAVING zeigt, wo von
-- dieser Möglichkeit Gebrauch gemacht wurde.
HAVING count(*) > 1
 ORDER BY genres DESC, w.titel;
