#!/usr/bin/env python3
"""
Führt die Fachabfragen aus sql/queries/ aus und schreibt die Ergebnisbelege.

Aufruf:   python3 tools/run_queries.py        (von überall; braucht nur die
          Standardbibliothek und einen laufenden Container buchtausch-db)

Warum ein eigenes Werkzeug? Die Dateien in sql/queries/ sollen portables SQL
bleiben: sie gehen als .sql-Datei in die Abgabe und müssen sich auch in DBeaver
oder pgAdmin am Stück ausführen lassen. Eine psql-Metaanweisung wie \\o würde
dort das Skript abbrechen. Die Aufteilung in einzelne Abfragen und das
Schreiben der Belegdateien übernimmt deshalb dieses Skript.

Format der Abfragedateien (Kopfblock je Abfrage, maschinenlesbar):
    -- @entitaet:   benutzer
    -- @frage:      ...
    -- @konstrukt:  ...
    -- @erwartet:   ...
    -- @erklaerung: (Tanzin)
    SELECT ...;
Ein Block beginnt bei "-- @entitaet:" und reicht bis zum nächsten "-- @entitaet:"
oder zum Dateiende.

parse_queries() ist bewusst als Funktion herausgezogen: der Folien-Generator
liest dasselbe Format und importiert den Parser, statt ihn nachzubauen.
"""
import re
import subprocess
import sys
from pathlib import Path

WURZEL = Path(__file__).resolve().parent.parent
QUELLE = WURZEL / "sql" / "queries"
ZIEL = QUELLE / "ergebnis"

CONTAINER = "buchtausch-db"
DB = "buchtausch"

# Anzeigezeitzone der Sitzung. Steht auch im Kopf jeder Abfragedatei; hier ist
# sie nötig, weil dieses Skript die Blöcke einzeln und ohne Dateikopf schickt.
ZEITZONE = "SET TimeZone = 'Europe/Berlin';"

# "-- @schluessel: wert" — der Kopfblock einer Abfrage.
KOPFZEILE = re.compile(r"^--\s*@(\w+):\s*(.*?)\s*$")


def parse_queries(pfad):
    """Zerlegt eine Abfragedatei in Blöcke.

    Rückgabe: Liste von dicts mit den Kopffeldern (entitaet, frage, konstrukt,
    erwartet, erklaerung), dazu 'sql' (der SQL-Text des Blocks), 'datei' und
    'zeile' (1-basierte Zeilennummer des "-- @entitaet:"-Kopfes).
    """
    pfad = Path(pfad)
    bloecke = []
    aktuell = None
    for nr, zeile in enumerate(pfad.read_text(encoding="utf-8").splitlines(), start=1):
        treffer = KOPFZEILE.match(zeile)
        if treffer and treffer.group(1) == "entitaet":
            # Neuer Block: der vorige ist damit abgeschlossen.
            aktuell = {"datei": pfad.name, "zeile": nr, "entitaet": treffer.group(2),
                       "sql_zeilen": []}
            bloecke.append(aktuell)
        elif aktuell is None:
            continue                      # Dateikopf vor der ersten Abfrage
        elif treffer and not aktuell["sql_zeilen"]:
            # Weitere Kopfzeilen gehören zum Block, solange noch kein SQL kam.
            aktuell[treffer.group(1)] = treffer.group(2)
        else:
            aktuell["sql_zeilen"].append(zeile)

    for block in bloecke:
        block["sql"] = "\n".join(block.pop("sql_zeilen")).strip() + "\n"
    return bloecke


def fuehre_aus(sql):
    """Schickt SQL über stdin an psql im Container; gibt (rc, stdout, stderr)."""
    befehl = ["docker", "exec", "-i", CONTAINER,
              "psql", "-U", DB, "-d", DB, "-X", "-v", "ON_ERROR_STOP=1"]
    # Kein Shell-Aufruf und keine Umleitung: der Text geht direkt in stdin,
    # damit die Umleitungszeichen der Windows-Shell keine Rolle spielen.
    lauf = subprocess.run(befehl, input=f"{ZEITZONE}\n{sql}",
                          capture_output=True, text=True, encoding="utf-8")
    return lauf.returncode, lauf.stdout, lauf.stderr


def main():
    dateien = sorted(QUELLE.glob("[0-9][0-9]_*.sql"))
    if not dateien:
        sys.exit(f"Keine Abfragedateien in {QUELLE}")
    ZIEL.mkdir(exist_ok=True)

    nummer = 0
    fehler = 0
    for datei in dateien:
        for block in parse_queries(datei):
            nummer += 1
            entitaet = block["entitaet"]
            rc, ausgabe, meldung = fuehre_aus(block["sql"])
            if rc != 0:
                # Fehlerhafte Abfrage benennen, aber die übrigen weiterlaufen
                # lassen — so zeigt ein Lauf alle Probleme auf einmal.
                print(f"FEHLER in {datei.name}, Zeile {block['zeile']} "
                      f"(@entitaet: {entitaet}):\n{meldung.strip()}", file=sys.stderr)
                fehler += 1
                continue

            beleg = ZIEL / f"{nummer:02d}_{entitaet}.txt"
            kopf = (f"-- Frage: {block.get('frage', '')}\n"
                    f"-- Quelle: sql/queries/{datei.name} (@entitaet: {entitaet}), "
                    f"erzeugt mit tools/run_queries.py\n\n")
            # newline='\n': die Belege behalten unter Windows Unix-Zeilenenden,
            # wie alle anderen Dateien im Repository.
            beleg.write_text(kopf + ausgabe, encoding="utf-8", newline="\n")
            zeilen = [z for z in ausgabe.splitlines() if z.strip().endswith("rows)")
                      or z.strip().endswith("row)")]
            print(f"{beleg.name:<28} {zeilen[-1].strip() if zeilen else ''}")

    if fehler:
        sys.exit(f"{fehler} von {nummer} Abfragen fehlgeschlagen.")
    print(f"\n{nummer} Abfragen, {nummer} Belege in {ZIEL.relative_to(WURZEL)}")


if __name__ == "__main__":
    main()
