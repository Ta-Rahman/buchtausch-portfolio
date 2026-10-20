-- =====================================================================
-- Fachabfragen, Gruppe 5: Community (Phase 2)
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


-- @entitaet:   bewertung_werk
-- @frage:      Welche Werke mit mindestens zwei Bewertungen stehen am besten da?
-- @konstrukt:  AVG, HAVING, RANK() OVER (ORDER BY …)
-- @erwartet:   4 Zeilen; erste Zeile: 1 | 11 | Der Zauberberg | 2 | 5.00
-- @erklaerung: Nach einer abgeschlossenen eigenen Ausleihe sind Sterne und Kommentare zu Werken (nicht Exemplaren) möglich. ausleihe_id ist der Berechtigungsnachweis. Im Testfall werden bestbewertete Werke mit mindestens zwei Bewertungen mit einem Rang versehen, damit Gleichstand denselben Rang bekommt.
SELECT
       -- RANK() vergibt den Rang über dem Ergebnis der Gruppierung und teilt
       -- sich bei gleichem Schnitt denselben Platz (danach entsteht eine Lücke).
       RANK() OVER (ORDER BY avg(bw.sterne) DESC) AS rang,
       w.werk_id, w.titel,
       count(*) AS bewertungen,
       round(avg(bw.sterne), 2) AS schnitt
  FROM bewertung_werk bw
  JOIN werk w ON w.werk_id = bw.werk_id
 GROUP BY w.werk_id, w.titel
-- Mindestens zwei Bewertungen: ein einzelner Fünf-Sterne-Eintrag wäre kein
-- belastbarer Spitzenplatz.
HAVING count(*) >= 2
 ORDER BY rang, w.titel;


-- @entitaet:   bewertung_person
-- @frage:      Wie wird jedes Mitglied im Schnitt bewertet — als verleihende und als ausleihende Person?
-- @konstrukt:  JOIN über die Dreifachbeziehung, CASE im Aggregat, JOIN auf exemplar.besitzer_id
-- @erwartet:   20 Zeilen; erste Zeile: 1 | Felicitas Dowerg | 3.00 | 1 | 5.00 | 1
-- @erklaerung: Die Personenbewertung ist durch eine Dreifachbeziehung realisiert; es wird beantwortet, wer wen bewertet und aufgrund von welcher Ausleihe. Es gibt zwei Fremdschlüssel auf benutzer. Im Testfall wird die Durchschnittsbewertung je Mitglied als verleihende und als ausleihende Person getrennt.
SELECT b.benutzer_id,
       concat_ws(' ', b.vorname, b.nachname) AS mitglied,
       -- Welche Rolle die bewertete Person in der Ausleihe hatte, steht nicht
       -- in der Bewertung: sie ergibt sich aus dem Vergleich mit der
       -- besitzenden Person des Exemplars und der ausleihenden Person der
       -- Ausleihe. CASE im Aggregat trennt die beiden Fälle in zwei Spalten.
       round(avg(CASE WHEN bp.bewerteter_id = e.besitzer_id THEN bp.sterne END), 2) AS schnitt_verleihend,
       count(CASE WHEN bp.bewerteter_id = e.besitzer_id THEN 1 END) AS bewertungen_verleihend,
       round(avg(CASE WHEN bp.bewerteter_id = al.ausleiher_id THEN bp.sterne END), 2) AS schnitt_ausleihend,
       count(CASE WHEN bp.bewerteter_id = al.ausleiher_id THEN 1 END) AS bewertungen_ausleihend
  FROM bewertung_person bp
  -- Die Ausleihe ist der Berechtigungsnachweis der Bewertung und zugleich der
  -- Weg zu den beiden Parteien.
  JOIN ausleihe al ON al.ausleihe_id = bp.ausleihe_id
  JOIN exemplar e  ON e.exemplar_id  = al.exemplar_id
  JOIN benutzer b  ON b.benutzer_id  = bp.bewerteter_id
 GROUP BY b.benutzer_id, b.vorname, b.nachname
 ORDER BY b.benutzer_id;


-- @entitaet:   nachricht
-- @frage:      Wie sieht der Posteingang aus: wer hat wie viele ungelesene Nachrichten, und welche ist die neueste?
-- @konstrukt:  DISTINCT ON, count() OVER (PARTITION BY …), partieller Index idx_nachricht_ungelesen
-- @erwartet:   9 Zeilen; erste Zeile: 4 | Maja Beyer | 2 | 2026-10-02 07:37:00+02 | Passt, dann bis 18.10.!
-- @erklaerung: Es gibt Direktnachrichten zwischen Personen mit optionalem Bezug zu einer Ausleihe. Im Testfall wird je Empfänger:in die Anzahl ungelesener Nachrichten angeschaut und die neueste davon genommen. Mit passender Sortierung holt DISTINCT ON (empfaenger_id) genau eine Zeile je Person.
-- DISTINCT ON behält je Empfänger:in genau die erste Zeile der Sortierung —
-- zusammen mit ORDER BY gesendet_am DESC also die neueste Nachricht.
SELECT DISTINCT ON (n.empfaenger_id)
       n.empfaenger_id,
       concat_ws(' ', b.vorname, b.nachname) AS empfaenger_in,
       -- Die Fensterfunktion zählt innerhalb der Empfänger:in und wird vor
       -- DISTINCT ON berechnet, sieht also noch alle ungelesenen Zeilen.
       count(*) OVER (PARTITION BY n.empfaenger_id) AS ungelesen,
       n.gesendet_am AS neueste_am,
       left(n.text, 45) AS neueste_nachricht
  FROM nachricht n
  JOIN benutzer b ON b.benutzer_id = n.empfaenger_id
 -- Genau dieser Filter steht auch im partiellen Index idx_nachricht_ungelesen,
 -- der deshalb nur die Minderheit der ungelesenen Nachrichten enthält.
 WHERE NOT n.gelesen
 ORDER BY n.empfaenger_id, n.gesendet_am DESC;
