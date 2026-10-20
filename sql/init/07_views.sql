-- =====================================================================
-- Views der Buchtausch-App (Phase 2)
-- Läuft beim ersten Containerstart nach 06_tests.sql, vor 08_init_abschluss.sql.
-- Handgeschrieben.
--
-- Eine View ist eine gespeicherte Abfrage, die sich wie eine Tabelle
-- ansprechen lässt: v_exemplar_suche bündelt genau die Spalten, die die
-- Suchansicht der App je Treffer anzeigt, und nimmt jeder Abfrage zwei
-- wiederkehrende Aufgaben ab — die vier Joins zu Werk, Person, Zustand und
-- Adresse und den Filter auf status = 'verfuegbar'. Pausierte und entfernte
-- Exemplare können damit gar nicht erst in einem Suchergebnis auftauchen.
-- Verwendet in sql/queries/03_besitz.sql (Frage 13).
-- =====================================================================

CREATE VIEW v_exemplar_suche AS
SELECT e.exemplar_id,
       w.titel,
       -- Die Autor:innen eines Werks stehen in werk_autor als mehrere Zeilen.
       -- Die Unterabfrage fasst sie zu einer Zeichenkette zusammen, damit die
       -- View je Exemplar genau eine Zeile liefert und kein GROUP BY über
       -- alle Ausgabespalten nötig wird. concat_ws lässt einen fehlenden
       -- Vornamen (einnamige Autor:innen) einfach weg, statt NULL zu liefern.
       (SELECT string_agg(concat_ws(' ', a.vorname, a.nachname), ', ' ORDER BY a.nachname)
          FROM werk_autor wa
          JOIN autor a ON a.autor_id = wa.autor_id
         WHERE wa.werk_id = w.werk_id
           AND wa.beitragsart = 'Autor')  AS autoren,
       b.benutzer_id                      AS besitzer_id,
       concat_ws(' ', b.vorname, b.nachname) AS besitzer,
       z.bezeichnung                      AS zustand,
       e.max_leihdauer_tage,
       e.versand_moeglich,
       -- Übergabeort ist die Adresse der besitzenden Person (Entscheidung aus
       -- Phase 1: genau eine Adresse je Benutzer), deshalb reicht ein Join auf
       -- adresse, um die View direkt für ST_DWithin nutzbar zu machen.
       ad.position                        AS besitzer_position
  FROM exemplar e
  JOIN werk w     ON w.werk_id      = e.werk_id
  JOIN benutzer b ON b.benutzer_id  = e.besitzer_id
  JOIN zustand z  ON z.zustand_id   = e.zustand_id
  JOIN adresse ad ON ad.benutzer_id = e.besitzer_id
 WHERE e.status = 'verfuegbar';

COMMENT ON VIEW v_exemplar_suche IS
  'Suchsicht der App: je verfügbarem Exemplar eine Zeile mit Titel, Autor:innen, besitzender Person, Zustand, Leihbedingungen und der Position der besitzenden Person für die Umkreissuche.';
