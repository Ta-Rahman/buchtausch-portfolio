#!/usr/bin/env python3
"""SQL-Abgabe (_SQL) der Abschlussphase als eine Datei.

Hängt die SQL-Dateien des Repos in fester Reihenfolge aneinander und schreibt
abgabe/03_Finalisierungsphase/Abschlussphase_SQL.sql:

  Teil A  sql/init/0*.sql      Init-Kette, unverändert
  Teil B  sql/queries/0*.sql   Fachabfragen, unverändert
  Teil C  sql/perf/0*.sql      Performance-Belege ohne psql-Metabefehle
  Teil D  sql/meta/*.sql       Metadaten, unverändert

Aus Teil C werden die Zeilen entfernt, die mit „\\“ beginnen (\\o, \\qecho):
damit ist die Datei reines SQL und läuft auch in DBeaver oder pgAdmin; die
EXPLAIN-Pläne erscheinen dann auf der Konsole statt in /tmp/. sql/perf/ selbst
bleibt unverändert und schreibt beim Einzellauf weiter die Belege.

Kein Zeitstempel in der Ausgabe: zwei Läufe ergeben dieselbe Datei.
Die Ausgabe ist erzeugt — Änderungen gehören in die Quelldateien.

Aufruf: python3 tools/build_sql.py   (nur Standardbibliothek)
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "abgabe" / "03_Finalisierungsphase" / "Abschlussphase_SQL.sql"

# (Kennung, Titel, Ordner, Dateimuster, Zusatz in der Übersicht,
#  psql-Metabefehle entfernen)
TEILE = [
    ("A", "Init-Kette", "sql/init", "0*.sql", "im Container automatisch beim ersten Start", False),
    ("B", "Fachabfragen", "sql/queries", "0*.sql", "je Entität eine", False),
    ("C", "Performance-Belege", "sql/perf", "0*.sql", "200.000 Demo-Zeilen je Skript", True),
    ("D", "Metadaten", "sql/meta", "*.sql", "Größen und Zähler nach allen Teilen", False),
]
DOPPEL = "-- " + "=" * 69
STRICH = "-- " + "#" * 69


def zeilen_lesen(pfad):
    """Datei als Zeilenliste, unabhängig von CRLF/LF beim Auschecken."""
    text = pfad.read_text(encoding="utf-8").replace("\r\n", "\n")
    if text.endswith("\n"):
        text = text[:-1]
    return text.split("\n")


def ist_metabefehl(zeile):
    """psql-Metabefehl wie \\o oder \\qecho: steht in sql/perf/ immer in Spalte 1."""
    return zeile.startswith("\\")


def kopf(eintraege):
    """Kopfblock mit Inhaltsverzeichnis; eintraege = [(Kennung, Dateiname, Zeile)]."""
    k = [DOPPEL,
         "-- Buchtausch-App · Abschlussphase · SQL-Abgabe",
         "-- Erzeugt mit tools/build_sql.py aus sql/init/, sql/queries/,",
         "-- sql/perf/ und sql/meta/ — nicht von Hand ändern.",
         "--"]
    for kennung, titel, ordner, _, zusatz, _ in TEILE:
        k.append(f"-- Teil {kennung} — {titel} ({ordner}/), {zusatz}")
        for kn, name, nr in eintraege:
            if kn == kennung:
                k.append(f"--   {name} {'.' * (30 - len(name))} Zeile {nr:>5}")
    k += ["-- Teil C ohne psql-Metabefehle; Pläne erscheinen auf der Konsole.",
          "--",
          "-- Am Stück ausführbar auf einer leeren Datenbank (PostgreSQL 16 +",
          "-- PostGIS 3.4, Rolle mit Recht für CREATE EXTENSION), z. B.:",
          "--   psql -v ON_ERROR_STOP=1 -d <leere_db> -f Abschlussphase_SQL.sql",
          DOPPEL]
    return k


def main():
    rumpf, eintraege, entfernt = [], [], 0
    for kennung, titel, ordner, muster, _, filtern in TEILE:
        dateien = sorted((ROOT / ordner).glob(muster))
        if not dateien:
            raise SystemExit(f"keine SQL-Dateien in {ordner}/")
        for f in dateien:
            zeilen = zeilen_lesen(f)
            info = f"{len(zeilen)} Zeilen"
            if filtern:
                vorher = len(zeilen)
                zeilen = [z for z in zeilen if not ist_metabefehl(z)]
                entfernt += vorher - len(zeilen)
                info = f"psql-Metabefehle entfernt, {len(zeilen)} Zeilen"
            rumpf.append("")
            # Zeilennummer im Kopf zeigt auf den Trennkommentar der Datei
            eintraege.append((kennung, f.name, len(rumpf)))
            rumpf += [STRICH,
                      f"-- Teil {kennung} — {titel} · {ordner}/{f.name} ({info})",
                      STRICH,
                      ""]
            rumpf += zeilen

    # Der Kopf hat eine feste Länge; erst damit stehen die Zeilennummern fest.
    versatz = len(kopf(eintraege))
    eintraege = [(k, n, versatz + i + 1) for k, n, i in eintraege]
    alles = kopf(eintraege) + rumpf

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(alles) + "\n", encoding="utf-8", newline="\n")
    print(f"geschrieben: {OUT.relative_to(ROOT)}  ({len(eintraege)} Dateien, "
          f"{len(alles)} Zeilen, {OUT.stat().st_size} Bytes, {entfernt} psql-Metabefehle aus Teil C entfernt)")


if __name__ == "__main__":
    main()
