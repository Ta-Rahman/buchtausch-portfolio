#!/usr/bin/env python3
"""
Messreihe der beiden Performance-Skripte über fünf Datenmengen.

Aufruf:   python3 tools/run_perf.py        (von überall; braucht nur die
          Standardbibliothek und einen laufenden Container buchtausch-db;
          Dauer einige Minuten)

Je Skript aus sql/perf/ und je Stufe (1.000 bis 1.000.000 Zeilen) läuft eine
psql-Sitzung mit genau dem Text, der als Teil C in der SQL-Abgabe steht: die
psql-Metabefehle (\\o, \\qecho) werden mit derselben Regel entfernt wie in
build_sql.py. Danach ändert dieses Skript vier Dinge, jedes mit Prüfung:

  1. die Zahl 200000 in generate_series(1, 200000) wird durch die Stufe ersetzt,
  2. EXPLAIN (ANALYZE, BUFFERS) gibt den Plan als JSON statt als Text aus,
  3. die Messung nach dem Aufwärmlauf steht fünfmal statt einmal da,
  4. vor dem abschließenden DROP TABLE fragt eine Zeile die Größen in Bytes ab.

Abfragetext und Ablauf (Aufwärmlauf, Messung, Index, ANALYZE, …) kommen damit
aus dem Skript und stehen hier nicht ein zweites Mal. Gezählt wird der Median
der fünf Messungen (warmer Cache, jit = off); die 200.000er-Belege zeigen
dagegen den zweiten Lauf. Einzelzeiten unter etwa 10 ms schwanken zwischen
Läufen stark, der Median dämpft Ausreißer.
Kein enable_seqscan: der Planer entscheidet bei jeder Größe selbst.

Ergebnis in sql/perf/ergebnis/, eine Zeile je Stufe:
  messreihe_umkreis.csv / .md   aus 01_umkreissuche.sql
  messreihe_trigram.csv / .md   aus 02_trigramsuche.sql
CSV mit Dezimalpunkt (für Diagramme), Markdown mit Dezimalkomma (zum Lesen).
Liegt schon eine CSV vor, vergleicht das Skript die laufunabhängigen Spalten
mit dem neuen Lauf und schreibt das Ergebnis in den Dateikopf.
Die 200.000er-Textbelege (0*.txt) bleiben unberührt.
"""
import csv
import json
import re
import subprocess
import sys
import time
from pathlib import Path

# Dieselbe Filterregel wie Teil C der SQL-Abgabe, nicht nachgebaut.
from build_sql import ist_metabefehl, zeilen_lesen

WURZEL = Path(__file__).resolve().parent.parent
PERF = WURZEL / "sql" / "perf"
ZIEL = PERF / "ergebnis"

CONTAINER = "buchtausch-db"
DB = "buchtausch"

STUFEN = [1_000, 10_000, 100_000, 200_000, 1_000_000]
WIEDERHOLUNGEN = 5

# (Kurzname der Ausgabedateien, Skript, Überschrift der Markdown-Datei,
#  zusätzlich laufunabhängige Spalten, Satz zur Laufabhängigkeit im Dateikopf)
SKRIPTE = [
    ("umkreis", "01_umkreissuche.sql", "Umkreissuche mit und ohne GiST-Index", [],
     "Zeiten, Buffers und Indexgrößen laufabhängig; die Größe des GiST-Index schwankt bei "
     "identischen Daten zwischen Läufen, Ursache nicht untersucht"),
    ("trigram", "02_trigramsuche.sql", "Titelsuche mitten im Wort mit und ohne GIN-Index (pg_trgm)",
     ["index_groesse"], "Zeiten und Buffers laufabhängig"),
]

ZEILENZAHL = "generate_series(1, 200000)"
EXPLAIN_TEXT = "EXPLAIN (ANALYZE, BUFFERS)"
EXPLAIN_JSON = "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)"
INDEX = re.compile(r"CREATE INDEX (\w+) ON (\w+)")

# Messrechner: steht im Kopf der 200.000er-Belege und wird von dort gelesen.
RECHNER_BELEG = ZIEL / "01a_umkreissuche_ohne_index.txt"

SPALTEN = ["zeilen", "treffer", "zeit_ohne_ms", "plan_ohne", "zeit_mit_ms", "plan_mit", "faktor",
           "tabelle_groesse", "index_groesse", "hit_ohne", "read_ohne", "hit_mit", "read_mit"]
# Gleiche Daten und gleicher Plan ergeben in jedem Lauf dieselben Werte; Zeiten
# und Buffers hängen vom Zustand des Rechners und des Caches ab. Die Indexgröße
# wird nur beim GIN-Index mitverglichen (Spalten je Skript in SKRIPTE): die Größe
# des GiST-Index schwankt bei identischen Daten zwischen Läufen.
STABIL = ["zeilen", "treffer", "plan_ohne", "plan_mit", "tabelle_groesse"]


def psql(sql):
    """Schickt SQL über stdin an psql im Container; gibt stdout zurück.

    -A -t: nur Werte, ohne Rahmen und Spaltenköpfe; -q: ohne Meldungen wie
    CREATE TABLE. Ein Fehler bricht die Sitzung ab (ON_ERROR_STOP).
    """
    befehl = ["docker", "exec", "-i", CONTAINER, "psql", "-U", DB, "-d", DB,
              "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"]
    lauf = subprocess.run(befehl, input=sql, capture_output=True, text=True, encoding="utf-8")
    if lauf.returncode != 0:
        raise RuntimeError(lauf.stderr.strip())
    return lauf.stdout


def pruefe(bedingung, meldung):
    if not bedingung:
        raise RuntimeError(meldung)


def vorbereiten(datei, zeilen):
    """Skripttext wie in der SQL-Abgabe, mit anderer Zeilenzahl und JSON-Plänen.

    Rückgabe: (SQL-Text, Demo-Tabelle).
    """
    text = "\n".join(z for z in zeilen_lesen(datei) if not ist_metabefehl(z)) + "\n"

    pruefe(text.count(ZEILENZAHL) == 1, f"{datei.name}: '{ZEILENZAHL}' nicht genau einmal")
    pruefe(text.count(EXPLAIN_TEXT) == 4, f"{datei.name}: nicht genau vier EXPLAIN-Anweisungen")
    # Aufwärmlauf und Messung, je ohne und mit Index: viermal dieselbe Abfrage.
    abfragen = {teil.split(";")[0].strip() for teil in text.split(EXPLAIN_TEXT)[1:]}
    pruefe(len(abfragen) == 1, f"{datei.name}: die vier EXPLAIN-Abfragen unterscheiden sich")

    treffer = INDEX.search(text)
    pruefe(treffer is not None, f"{datei.name}: kein CREATE INDEX")
    index, tabelle = treffer.groups()
    schluss = f"DROP TABLE {tabelle};"
    pruefe(text.rstrip().endswith(schluss), f"{datei.name}: endet nicht mit '{schluss}'")

    text = text.replace(ZEILENZAHL, f"generate_series(1, {zeilen})")
    # Im Skript steht EXPLAIN viermal: Aufwärmlauf und Messung ohne Index,
    # Aufwärmlauf und Messung mit Index. Jede Messung (2. und 4.) wird
    # wiederholt, die Aufwärmläufe (1. und 3.) bleiben einfach.
    teile = text.split(EXPLAIN_TEXT)
    text = teile[0]
    for nr, teil in enumerate(teile[1:], start=1):
        abfrage, rest = teil.split(";", 1)
        anzahl = WIEDERHOLUNGEN if nr in (2, 4) else 1
        text += "\n".join([EXPLAIN_JSON + abfrage + ";"] * anzahl) + rest
    groesse =(f"SELECT 'groesse', pg_relation_size('{tabelle}'), pg_relation_size('{index}'),\n"
               f"       pg_size_pretty(pg_relation_size('{tabelle}')),\n"
               f"       pg_size_pretty(pg_relation_size('{index}'));\n")
    text = text.rstrip()[:-len(schluss)] + groesse + schluss + "\n"
    return text, tabelle


def scanknoten(knoten):
    """Oberster Scan-Knoten des Plans, benannt wie im Text-EXPLAIN.

    Über einem parallelen Scan steht ein Gather-Knoten; er wird übersprungen,
    das Präfix „Parallel“ zeigt ihn an.
    """
    if knoten["Node Type"].endswith("Scan"):
        return ("Parallel " if knoten.get("Parallel Aware") else "") + knoten["Node Type"]
    for kind in knoten.get("Plans", []):
        name = scanknoten(kind)
        if name:
            return name
    return None


def merkmale(plan):
    """Was bei jeder Wiederholung gleich sein muss: Planknoten, Treffer, Buffers."""
    p = plan["Plan"]
    return (scanknoten(p), p["Actual Rows"], p["Shared Hit Blocks"], p["Shared Read Blocks"])


def median_lauf(plaene, name, zeilen, abweichungen):
    """Die Wiederholung mit der mittleren Ausführungszeit.

    Bei fünf Messungen ist der Median ein tatsächlicher Lauf; Planknoten und
    Buffers in der Tabelle stammen aus genau diesem Lauf. Unterscheiden sich
    die Wiederholungen in Planknoten, Treffern oder Buffers, wird das in
    abweichungen vermerkt (Befund, kein Abbruch).
    """
    verschieden = sorted({merkmale(p) for p in plaene}, key=str)
    if len(verschieden) > 1:
        abweichungen.append(f"{zeilen} Zeilen {name}: " + ", ".join(
            f"{plan} {treffer} Treffer {hit}/{read}" for plan, treffer, hit, read in verschieden))
    return sorted(plaene, key=lambda p: p["Execution Time"])[len(plaene) // 2]


def auswerten(ausgabe, zeilen, abweichungen):
    """Liest aus der psql-Ausgabe die JSON-Pläne und die Größenzeile."""
    plaene, puffer, groesse = [], None, None
    for zeile in ausgabe.splitlines():
        if puffer is None and zeile == "[":
            puffer = []
        if puffer is not None:
            puffer.append(zeile)
            if zeile == "]":
                plaene.append(json.loads("\n".join(puffer))[0])
                puffer = None
        elif zeile.startswith("groesse|"):
            groesse = zeile.split("|")[1:]
    erwartet = 2 + 2 * WIEDERHOLUNGEN
    pruefe(len(plaene) == erwartet, f"{len(plaene)} statt {erwartet} JSON-Pläne in der Ausgabe")
    pruefe(groesse is not None, "keine Größenzeile in der Ausgabe")

    # Reihenfolge wie im Skript: Aufwärmlauf ohne Index, fünf Messungen ohne
    # Index, Aufwärmlauf mit Index, fünf Messungen mit Index.
    ohne = median_lauf(plaene[1:1 + WIEDERHOLUNGEN], "ohne", zeilen, abweichungen)
    mit = median_lauf(plaene[2 + WIEDERHOLUNGEN:], "mit", zeilen, abweichungen)
    treffer = ohne["Plan"]["Actual Rows"]
    pruefe(mit["Plan"]["Actual Rows"] == treffer, "Trefferzahl ohne und mit Index verschieden")
    return {
        "zeilen": zeilen,
        "treffer": treffer,
        "zeit_ohne_ms": ohne["Execution Time"],
        "plan_ohne": scanknoten(ohne["Plan"]),
        "zeit_mit_ms": mit["Execution Time"],
        "plan_mit": scanknoten(mit["Plan"]),
        "faktor": ohne["Execution Time"] / mit["Execution Time"],
        "tabelle_groesse": int(groesse[0]),
        "index_groesse": int(groesse[1]),
        "hit_ohne": ohne["Plan"]["Shared Hit Blocks"],
        "read_ohne": ohne["Plan"]["Shared Read Blocks"],
        "hit_mit": mit["Plan"]["Shared Hit Blocks"],
        "read_mit": mit["Plan"]["Shared Read Blocks"],
        # nur für die Markdown-Datei, gleiche Rundung wie in den Textbelegen
        "tabelle_pretty": groesse[2],
        "index_pretty": groesse[3],
    }


def csv_werte(z):
    """Eine Ergebniszeile als Texte für die CSV (Dezimalpunkt)."""
    werte = {k: str(z[k]) for k in SPALTEN}
    werte["zeit_ohne_ms"] = f"{z['zeit_ohne_ms']:.3f}"
    werte["zeit_mit_ms"] = f"{z['zeit_mit_ms']:.3f}"
    werte["faktor"] = f"{z['faktor']:.1f}"
    return werte


def de(wert, stellen=0):
    """Zahl in deutscher Schreibweise: 1234567.891 -> 1.234.567,891"""
    return f"{wert:,.{stellen}f}".replace(",", "_").replace(".", ",").replace("_", ".")


def vergleich(csv_datei, neu, stabil, laufabhaengig):
    """Vergleicht die laufunabhängigen Spalten mit der vorhandenen CSV.

    stabil: die verglichenen Spalten, laufabhaengig: Satz aus SKRIPTE.
    Rückgabe: Satz für den Dateikopf. Abweichungen werden benannt, aber nicht
    als Fehler behandelt — sie sind selbst ein Befund.
    """
    laufabhaengig += ". Faktoren nur innerhalb dieser Datei vergleichen"
    if "index_groesse" in stabil:
        gleich = "Planknoten, Treffer, Tabellen- und Indexgrößen"
    else:
        gleich = "Planknoten, Treffer und Tabellengrößen"
    if not csv_datei.exists():
        return f"Wiederholung: erster Lauf, kein Vergleich. {laufabhaengig}."
    zeilen = csv_datei.read_text(encoding="utf-8").splitlines()
    datum = next((z.split(":", 1)[1].strip() for z in zeilen if z.startswith("# Gemessen am:")), "?")
    alt = {r["zeilen"]: r for r in csv.DictReader(z for z in zeilen if not z.startswith("#"))}
    abweichungen = []
    for z in neu:
        werte = csv_werte(z)
        vorher = alt.get(werte["zeilen"], {})
        for spalte in stabil:
            if vorher.get(spalte) != werte[spalte]:
                abweichungen.append(f"{werte['zeilen']} Zeilen {spalte} {vorher.get(spalte)} -> {werte[spalte]}")
    if abweichungen:
        return (f"Wiederholung: gegenüber dem Lauf vom {datum} ABWEICHEND: "
                f"{'; '.join(abweichungen)}. {laufabhaengig}.")
    return f"Wiederholung: gegenüber dem Lauf vom {datum} sind {gleich} identisch. {laufabhaengig}."


def schreiben(kurz, datei, titel, stabil, laufabhaengig, kopf, ergebnis, abweichungen):
    csv_datei = ZIEL / f"messreihe_{kurz}.csv"
    md_datei = ZIEL / f"messreihe_{kurz}.md"
    if abweichungen:
        innerhalb = ("Wiederholungen ABWEICHEND (Planknoten, Treffer, Buffers hit/read): "
                     f"{'; '.join(abweichungen)}; die Tabelle zeigt den Median-Lauf")
    else:
        innerhalb = "Wiederholungen: Planknoten, Treffer und Buffers je Stufe in allen fünf Messungen gleich"
    kopfzeilen = kopf + [innerhalb, vergleich(csv_datei, ergebnis, stabil, laufabhaengig),
                         f"Quelle: sql/perf/{datei}, erzeugt mit tools/run_perf.py — nicht von Hand ändern"]

    # CSV: Kopf als #-Kommentarzeilen, dann Spaltenköpfe und eine Zeile je Stufe.
    with csv_datei.open("w", encoding="utf-8", newline="\n") as f:
        for zeile in kopfzeilen:
            f.write(f"# {zeile}\n")
        schreiber = csv.DictWriter(f, fieldnames=SPALTEN, lineterminator="\n")
        schreiber.writeheader()
        for z in ergebnis:
            schreiber.writerow(csv_werte(z))

    # Markdown: Dezimalkomma, Tausenderpunkt, Größen wie pg_size_pretty,
    # Buffers als „hit/read“ je Messung.
    md = [f"# Messreihe: {titel}", ""]
    md += [f"- {zeile}" for zeile in kopfzeilen]
    md += ["- Zahlen mit Dezimalpunkt und Größen in Bytes: " + csv_datei.name, "",
           "| zeilen | treffer | zeit_ohne_ms | plan_ohne | zeit_mit_ms | plan_mit | faktor "
           "| tabelle_groesse | index_groesse | buffers_ohne | buffers_mit |",
           "|---:|---:|---:|---|---:|---|---:|---:|---:|---:|---:|"]
    for z in ergebnis:
        md.append(f"| {de(z['zeilen'])} | {de(z['treffer'])} | {de(z['zeit_ohne_ms'], 3)} | {z['plan_ohne']} "
                  f"| {de(z['zeit_mit_ms'], 3)} | {z['plan_mit']} | {de(z['faktor'], 1)} "
                  f"| {z['tabelle_pretty']} | {z['index_pretty']} "
                  f"| {de(z['hit_ohne'])}/{de(z['read_ohne'])} | {de(z['hit_mit'])}/{de(z['read_mit'])} |")
    md_datei.write_text("\n".join(md) + "\n", encoding="utf-8", newline="\n")
    print(f"geschrieben: {csv_datei.relative_to(WURZEL)}, {md_datei.relative_to(WURZEL)}")


def kopfdaten():
    """Kopfzeilen beider Dateien: Version, Messrechner, Zeitpunkt, Konfiguration."""
    version, postgis, parallel, puffer, zeitpunkt = psql(
        "SELECT current_setting('server_version'), postgis_lib_version(),\n"
        "       current_setting('max_parallel_workers_per_gather'), current_setting('shared_buffers'),\n"
        "       to_char(now() AT TIME ZONE 'Europe/Berlin', 'YYYY-MM-DD HH24:MI');\n").strip().split("|")
    rechner = re.search(r"^-- Messrechner: (.+)$", RECHNER_BELEG.read_text(encoding="utf-8"), re.M)
    pruefe(rechner is not None, f"keine Zeile '-- Messrechner:' in {RECHNER_BELEG.name}")
    return [f"PostgreSQL {version}, PostGIS {postgis}",
            f"Messrechner: {rechner.group(1).strip()}",
            f"Gemessen am: {zeitpunkt} (Europe/Berlin)",
            "jit = off, warmer Cache; Serverkonfiguration sonst unverändert "
            f"(max_parallel_workers_per_gather = {parallel}, shared_buffers = {puffer})",
            "Median aus fünf Wiederholungen nach einem Aufwärmlauf "
            "(die 200k-Textbelege in diesem Ordner zeigen dagegen den zweiten Lauf)"]


def main():
    # Windows-Python schreibt in Pipes und Umleitungen sonst cp1252; Git Bash
    # und Dateien erwarten UTF-8, sonst erscheinen Umlaute als Ersatzzeichen.
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    kopf = kopfdaten()
    tabellen = [vorbereiten(PERF / datei, STUFEN[0])[1] for _, datei, *_ in SKRIPTE]
    ergebnisse, abweichungen = {}, {}
    beginn = time.monotonic()
    try:
        for kurz, datei, *_ in SKRIPTE:
            ergebnisse[kurz], abweichungen[kurz] = [], []
            for zeilen in STUFEN:
                start = time.monotonic()
                sql, _ = vorbereiten(PERF / datei, zeilen)
                vorher = len(abweichungen[kurz])
                z = auswerten(psql(sql), zeilen, abweichungen[kurz])
                ergebnisse[kurz].append(z)
                gleich = "gleich" if len(abweichungen[kurz]) == vorher else "ABWEICHEND"
                print(f"{kurz:<8} {zeilen:>9} Zeilen {time.monotonic() - start:7.1f} s   "
                      f"ohne: {z['plan_ohne']} {z['zeit_ohne_ms']:.3f} ms   "
                      f"mit: {z['plan_mit']} {z['zeit_mit_ms']:.3f} ms   "
                      f"Faktor {z['faktor']:.1f}   Treffer {z['treffer']}   "
                      f"{WIEDERHOLUNGEN}x {gleich}", flush=True)
    except RuntimeError as fehler:
        print(f"ABBRUCH: {fehler}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Auch nach einem Abbruch keine Demo-Tabelle zurücklassen.
        psql(f"DROP TABLE IF EXISTS {', '.join(tabellen)};")

    for kurz, datei, titel, zusatz, laufabhaengig in SKRIPTE:
        schreiben(kurz, datei, titel, STABIL + zusatz, laufabhaengig, kopf, ergebnisse[kurz], abweichungen[kurz])
    print(f"Messreihe vollständig: {len(SKRIPTE)} Skripte x {len(STUFEN)} Stufen "
          f"in {time.monotonic() - beginn:.1f} s")


if __name__ == "__main__":
    main()
