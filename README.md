# Buchtausch-App — Datenbank

Portfolio-Projekt im Modul *Data-Mart-Erstellung in SQL* (DLBDSPBDM01_D), IU Internationale Hochschule.

Eine relationale Datenbank für eine Nachbarschafts-Buchtausch-App: Mitglieder stellen eigene
Bücher zum Verleih ein, andere fragen sie an, die Übergabe erfolgt per Abholung oder Postversand.
21 Entitäten, 29 Beziehungen, drei Dreifachbeziehungen, räumliche Suche über PostGIS.

GitHub: https://github.com/Ta-Rahman/buchtausch-portfolio

## Schnellstart

```bash
docker compose up -d --build
docker exec -it buchtausch-db psql -U buchtausch -d buchtausch -c "SELECT postgis_version();"
```

Zugang vom Host (DBeaver, psql): `localhost:5433`, Datenbank `buchtausch`, Benutzer `buchtausch`, Passwort `buchtausch_dev`.
Der Host-Port ist bewusst 5433, damit ein lokal installiertes PostgreSQL auf 5432 nicht im Weg ist; im Container läuft die Datenbank auf 5432.
Das Passwort ist ein reines Entwicklungspasswort für die lokale Containerinstanz.

Reset auf den definierten Ausgangszustand: `docker compose down -v && docker compose up -d --build`

Die acht Init-Skripte aus `sql/init/` werden beim Bauen ins Image kopiert (siehe `Dockerfile`) und laufen
beim ersten Start automatisch; ein Bind-Mount entfällt, damit der Aufbau unabhängig vom Dateisystem des
Rechners und von den Freigabeeinstellungen in Docker Desktop reproduzierbar bleibt — deshalb `--build`.

```bash
# healthy = pg_isready über TCP und Abschlusszeile in meta.init_status (schreibt erst das letzte Init-Skript)
docker inspect --format '{{.State.Health.Status}}' buchtausch-db
# Ergebnis der Geschäftsregel-Tests aus 06_tests.sql: „alle 23 Fälle bestanden“
docker compose logs db | grep "Fälle bestanden"
```

Tests, Abfragen, Messungen und Metadaten (Container läuft, Wurzelverzeichnis des Repos, Git Bash, Python 3 mit Standardbibliothek):

```bash
# nur Git Bash: Containerpfade wie /tmp/… nicht in Windows-Pfade umschreiben
export MSYS_NO_PATHCONV=1
# Geschäftsregel-Tests erneut ausführen (eine Transaktion mit ROLLBACK, Zeilen bleiben unverändert)
docker exec -i buchtausch-db psql -U buchtausch -d buchtausch -f /docker-entrypoint-initdb.d/06_tests.sql
# Nebenläufigkeitstest mit zwei psql-Sitzungen, Transkript in docs/belege/nebenlaeufigkeit.txt
bash tools/test_nebenlaeufigkeit.sh
# 21 Fachabfragen, Ergebnisbelege in sql/queries/ergebnis/
python tools/run_queries.py
# Messreihe 1.000 bis 1.000.000 Zeilen, Ergebnis in sql/perf/ergebnis/messreihe_*.md
# (Einzelmessung mit 200.000 Zeilen: Befehle im Kopf von sql/perf/01_umkreissuche.sql und 02_trigramsuche.sql)
python tools/run_perf.py
# Metadaten (Tabellen, Zeilen, Größen, Zähler), Beleg in docs/belege/metadaten.txt
docker cp sql/meta/metadaten.sql buchtausch-db:/tmp/metadaten.sql
docker exec buchtausch-db psql -U buchtausch -d buchtausch -X -q -v ON_ERROR_STOP=1 -f /tmp/metadaten.sql -o /tmp/metadaten.txt
docker cp buchtausch-db:/tmp/metadaten.txt docs/belege/metadaten.txt
```

## Aufbau

| Pfad | Inhalt |
|---|---|
| `tools/model.py` | **Einzige Quelle der Wahrheit** des Datenmodells (Entitäten, Beziehungen, Nullability, Constraints, Indizes) |
| `tools/build_ddl.py` | Erzeugt `sql/init/02_schema.sql` und `03_indexes.sql` |
| `tools/build_seed.py` | Erzeugt `sql/init/05_seed.sql` (Faker de_DE, fester Seed, fester Stichtag) |
| `tools/build_erm.py` | Erzeugt das ER-Diagramm (Graphviz) |
| `tools/build_dict.py` | Erzeugt das Datenwörterbuch |
| `tools/run_queries.py` | Führt die Abfragen aus `sql/queries/` einzeln aus und schreibt die Ergebnisbelege |
| `tools/run_perf.py` | Messreihe der beiden Perf-Skripte über 1.000 bis 1.000.000 Zeilen (Skripttext wie in der SQL-Abgabe mit anderer Zeilenzahl, Pläne als EXPLAIN JSON, Median aus fünf Wiederholungen nach einem Aufwärmlauf), schreibt `sql/perf/ergebnis/messreihe_*.csv` und `.md` |
| `tools/test_nebenlaeufigkeit.sh` | Nebenläufigkeitsnachweis zur Doppelbuchung mit zwei `psql`-Sitzungen (Git Bash), Transkript in `docs/belege/nebenlaeufigkeit.txt` |
| `tools/build_template.js`, `build_final.js`, `build_docx_data.py` | Word-Vorlage und Abgabedatei der Phase 1 (docx-js; Datenwörterbuch als JSON) |
| `tools/build_slides.py` | Erzeugt das Foliendeck der Phase 2 (python-pptx) aus `tools/texte_phase2.json`, `sql/` und `docs/belege/` |
| `tools/build_kz.py` | Erzeugt die Kurzzusammenfassung (`_KZ`) der Phase 2 als Word-Datei aus demselben Text wie Folie 35/36 |
| `tools/build_sql.py` | Erzeugt die SQL-Abgabedatei (`abgabe/03_Finalisierungsphase/Abschlussphase_SQL.sql`): Teil A `sql/init/`, Teil B `sql/queries/` und Teil D `sql/meta/` verbatim, Teil C `sql/perf/` ohne psql-Metabefehle |
| `tools/build_sqlpdf.py` | Erzeugt die SQL-Dokumentation mit Installationsanleitung (`_SQL`) als Word-Datei aus README-Schnellstart, `sql/` und `docs/belege/`; Inhaltsverzeichnis und PDF über Word |
| `tools/titel_lokal.json` | **Nicht im Repo** (gitignoriert): `{"matrikel": "…"}` für Titelfolie, KZ- und SQL-Dokumentations-Kopfzeile; fehlt die Datei, zeigt das Deck einen Platzhalter, `build_kz.py` und `build_sqlpdf.py` brechen ab |
| `sql/init/` | Läuft beim ersten Containerstart automatisch, in Nummernreihenfolge (s. u.) |
| `sql/queries/` | Je Entität eine dokumentierte Fachabfrage mit Kopfblock, Ergebnisbelege in `sql/queries/ergebnis/` |
| `Dockerfile` | Basis-Image `postgis/postgis:16-3.4` plus die Init-Kette aus `sql/init/` |
| `docs/` | Diagramm, Datenwörterbuch, Belege in `docs/belege/` (Init-Log, Tests, Healthcheck, Nebenläufigkeit, Metadaten) |
| `abgabe/` | Abgabedokumente je Phase (nicht im Repo) |
| `sql/perf/` | Performance-Belege: Demo-Tabellen mit 200.000 Zeilen, EXPLAIN-Pläne mit/ohne Index in `ergebnis/`; Messreihe über 1.000 bis 1.000.000 Zeilen in `ergebnis/messreihe_*.csv/.md` (`tools/run_perf.py`) |
| `sql/meta/` | Metadaten-Skript (Tabellen je Schema, Zeilen und Größen je Tabelle, Indizes, Zähler), Beleg in `docs/belege/metadaten.txt` |
| `.dockerignore` | Hält den Build-Kontext auf `sql/init/` beschränkt |

## Init-Kette (`sql/init/`)

| Datei | Inhalt | Herkunft |
|---|---|---|
| `01_extensions.sql` | postgis, btree_gist, pg_trgm | Hand |
| `02_schema.sql` | 21 Tabellen, PK/FK/UNIQUE/CHECK, EXCLUDE gegen Doppelbuchung, COMMENT ON | generiert |
| `03_indexes.sql` | FK-Indizes + fachliche Indizes (GiST, GIN/pg_trgm, partiell) mit Begründung | generiert |
| `04_regeln.sql` | Trigger für Leihdauer, Statusübergänge, Bewertungsberechtigung | Hand |
| `05_seed.sql` | Deterministische Dummy-Daten (Frankfurt am Main) | generiert |
| `06_tests.sql` | 23 Positiv-/Negativtests der vier Geschäftsregeln, auch bei UPDATE, an Randtagen und für die Löschregeln der Fremdschlüssel; bricht den Start ab, wenn eine Regel verletzt ist | Hand |
| `07_views.sql` | View `v_exemplar_suche`: je verfügbarem Exemplar eine Zeile für die Suche (Titel, Autor:innen, Zustand, Position) | Hand |
| `08_init_abschluss.sql` | Schema `meta` mit Tabelle `init_status`: Abschlussmarker, den der Healthcheck zusätzlich zu `pg_isready` prüft | Hand |

Neu erzeugen: `cd tools && pip install -r requirements.txt && python build_ddl.py && python build_seed.py`

Modelländerungen immer in `model.py` vornehmen und die Artefakte neu erzeugen —
nie einzeln nachpflegen.
