#!/usr/bin/env python3
"""
Erzeugt aus model.py:
  sql/init/02_schema.sql   CREATE TABLE + Constraints + COMMENT ON
  sql/init/03_indexes.sql  FK-Indizes (automatisch) + fachliche Indizes (INDEXES)

Aufruf:  python3 build_ddl.py            (aus dem Ordner tools/)
Regel:   Schema nie von Hand ändern — Änderung in model.py, dann neu erzeugen.

Was das Skript prüft, bevor es schreibt (bricht sonst mit Fehler ab):
  - jede Fremdschlüssel-Zieltabelle existiert und wird VOR der Tabelle angelegt
  - jede Angabe in NULLABLE / DEFAULTS / ON_DELETE zeigt auf eine echte Spalte
  - ein FK, dessen Beziehung in R mit 0..1 beginnt, ist auch als NULLABLE erklärt
"""
import sys
from pathlib import Path
from model import (E, R, TERNAER, GROUPS, NULLABLE, FK_ZIEL, ON_DELETE,
                   DEFAULTS, STATUS, CONSTRAINTS, INDEXES)

INIT = Path(__file__).resolve().parent.parent / "sql" / "init"
OUT = INIT / "02_schema.sql"
OUT_IDX = INIT / "03_indexes.sql"


def fehler(msg):
    print("FEHLER:", msg, file=sys.stderr)
    sys.exit(1)


def sq(s):
    """Einfache Anführungszeichen für SQL-Stringliterale maskieren."""
    return s.replace("'", "''")


def pk_spalten(tab):
    return [a for a, _t, k, _d in E[tab][2] if "PK" in k.split()]


def fk_ziel(spalte):
    """Zieltabelle eines Fremdschlüssels: Ausnahmeliste, sonst Konvention <tab>_id."""
    if spalte in FK_ZIEL:
        return FK_ZIEL[spalte]
    if spalte.endswith("_id") and spalte[:-3] in E:
        return spalte[:-3]
    fehler(f"Fremdschlüssel {spalte}: Zieltabelle nicht ableitbar (FK_ZIEL ergänzen)")


# ---------------------------------------------------------------- Prüfungen
alle_spalten = {(t, a) for t, (_g, _z, attrs) in E.items() for a, *_ in attrs}
for name, menge in (("NULLABLE", NULLABLE), ("DEFAULTS", DEFAULTS), ("ON_DELETE", ON_DELETE)):
    for key in menge:
        if key not in alle_spalten:
            fehler(f"{name} verweist auf unbekannte Spalte {key}")
for key in STATUS:
    t, a = key.split(".")
    if (t, a) not in alle_spalten:
        fehler(f"STATUS verweist auf unbekannte Spalte {key}")
for t in CONSTRAINTS:
    if t not in E:
        fehler(f"CONSTRAINTS verweist auf unbekannte Tabelle {t}")

# Beziehungen, die mit 0..1 beginnen -> der FK in der Zieltabelle muss NULL erlauben
for von, nach, _lbl, k_von, _k_nach in R:
    if k_von == "0..1":
        fks = [a for a, _t, k, _d in E[nach][2] if "FK" in k.split() and fk_ziel(a) == von]
        for a in fks:
            if (nach, a) not in NULLABLE:
                fehler(f"Beziehung {von} 0..1 -> {nach}: Spalte {nach}.{a} muss in NULLABLE stehen")

angelegt = []
# ---------------------------------------------------------------- Ausgabe
out = [
    "-- =====================================================================",
    "-- Schema der Buchtausch-App — ERZEUGT aus tools/model.py durch tools/build_ddl.py",
    "-- Nicht von Hand ändern: Änderung in model.py, dann `python3 build_ddl.py`.",
    "-- Läuft beim ersten Containerstart nach 01_extensions.sql (Docker-Entrypoint).",
    "--",
    f"-- {len(E)} Tabellen, {len(R)} Beziehungen, {len(TERNAER)} Dreifachbeziehungen.",
    "-- Fremdschlüssel: ON DELETE RESTRICT als Standard (Konten werden deaktiviert,",
    "-- nie gelöscht); CASCADE nur bei n:m-Auflösungstabellen; SET NULL bei optionalem Bezug.",
    "-- =====================================================================",
    "",
]

n_fk = n_chk = n_uq = n_excl = 0

for grp, (titel, _f, _l) in GROUPS.items():
    out += [f"-- ---------------------------------------------------------------------",
            f"-- {titel}",
            f"-- ---------------------------------------------------------------------", ""]
    for tab, (g, zweck, attrs) in E.items():
        if g != grp:
            continue
        pks = pk_spalten(tab)
        marker = " (Dreifachbeziehung)" if tab in TERNAER else ""
        out.append(f"-- {tab}{marker}: {zweck}")
        out.append(f"CREATE TABLE {tab} (")
        zeilen = []
        for a, typ, k, desc in attrs:
            keys = k.split()
            teile = [f"    {a} {typ}"]
            if "PK" in keys and len(pks) == 1:
                teile.append("PRIMARY KEY")
            elif (tab, a) not in NULLABLE:
                teile.append("NOT NULL")
            if (tab, a) in DEFAULTS:
                teile.append(f"DEFAULT {DEFAULTS[(tab, a)]}")
            if "UK" in keys:
                teile.append("UNIQUE"); n_uq += 1
            if "FK" in keys:
                ziel = fk_ziel(a)
                if ziel not in angelegt:
                    fehler(f"{tab}.{a} verweist auf {ziel}, die noch nicht angelegt ist "
                           f"(Reihenfolge in model.py prüfen)")
                zpk = pk_spalten(ziel)
                if len(zpk) != 1:
                    fehler(f"{ziel} hat keinen einspaltigen Primärschlüssel")
                od = ON_DELETE.get((tab, a), "RESTRICT")
                teile.append(f"REFERENCES {ziel} ({zpk[0]}) ON DELETE {od}"); n_fk += 1
            zeilen.append((" ".join(teile), desc))
        # Statuswerte als CHECK
        for key, werte in STATUS.items():
            t, a = key.split(".")
            if t == tab:
                lst = ", ".join(f"'{sq(w)}'" for w in werte)
                zeilen.append((f"    CONSTRAINT chk_{tab}_{a} CHECK ({a} IN ({lst}))",
                               f"zulässige Werte für {a}"))
                n_chk += 1
        if len(pks) > 1:
            zeilen.append((f"    PRIMARY KEY ({', '.join(pks)})", "zusammengesetzter Primärschlüssel"))
        for cname, csql, cdesc in CONSTRAINTS.get(tab, []):
            zeilen.append((f"    CONSTRAINT {cname} {csql}", cdesc))
            if csql.startswith("CHECK"):
                n_chk += 1
            elif csql.startswith("UNIQUE"):
                n_uq += 1
            elif csql.startswith("EXCLUDE"):
                n_excl += 1
        # Zeilen mit Kommas und Kommentaren ausgeben
        for i, (sql, desc) in enumerate(zeilen):
            komma = "," if i < len(zeilen) - 1 else ""
            out.append(f"{sql}{komma}  -- {desc}")
        out.append(");")
        # Dokumentation in der Datenbank selbst (sichtbar in DBeaver / \d+)
        out.append(f"COMMENT ON TABLE {tab} IS '{sq(zweck)}';")
        for a, _t, _k, desc in attrs:
            out.append(f"COMMENT ON COLUMN {tab}.{a} IS '{sq(desc)}';")
        out.append("")
        angelegt.append(tab)

out += ["-- ---------------------------------------------------------------------",
        f"-- Zusammenfassung: {len(angelegt)} Tabellen, {n_fk} Fremdschlüssel, "
        f"{n_uq} UNIQUE, {n_chk} CHECK, {n_excl} EXCLUDE.",
        "-- ---------------------------------------------------------------------", ""]

OUT.write_text("\n".join(out), encoding="utf-8")
print(f"{OUT.name}: {len(angelegt)} Tabellen, {n_fk} FK, {n_uq} UNIQUE, {n_chk} CHECK, "
      f"{n_excl} EXCLUDE -> {OUT}")


# ============================================================== 03_indexes.sql
import re

def erste_spalte(definition):
    """Erste Spalte einer Indexdefinition wie '(a, b) WHERE …' — None bei GiST/GIN."""
    m = re.match(r"\((\w+)", definition)
    return m.group(1) if m else None

idx = [
    "-- =====================================================================",
    "-- Indizes der Buchtausch-App — ERZEUGT aus tools/model.py durch tools/build_ddl.py",
    "-- Nicht von Hand ändern: Änderung in model.py, dann `python3 build_ddl.py`.",
    "--",
    "-- Teil 1: Ein B-Baum-Index je Fremdschlüssel. PostgreSQL legt FK-Indizes nicht",
    "--         automatisch an; ohne sie wird jeder JOIN und jede ON-DELETE-Prüfung",
    "--         zum Seq Scan. Übersprungen, wenn die Spalte schon vorn in einem",
    "--         Primärschlüssel, UNIQUE oder fachlichen Index steht.",
    "-- Teil 2: Fachliche Indizes (GiST, GIN/pg_trgm, partiell) mit Begründung.",
    "-- =====================================================================",
    "", "-- Teil 1: Fremdschlüssel-Indizes", "",
]
n_fkidx = 0
for tab, (_g, _z, attrs) in E.items():
    pks = pk_spalten(tab)
    abgedeckt = set()
    if pks:
        abgedeckt.add(pks[0])
    for a, _t, k, _d in attrs:
        if "UK" in k.split():
            abgedeckt.add(a)
    for _n, csql, _d in CONSTRAINTS.get(tab, []):
        if csql.startswith("UNIQUE"):
            abgedeckt.add(erste_spalte(csql[len("UNIQUE "):]))
    for _n, t, definition, _b in INDEXES:
        if t == tab and " WHERE " not in definition:
            abgedeckt.add(erste_spalte(definition))
    for a, _t, k, _d in attrs:
        if "FK" in k.split() and a not in abgedeckt:
            idx.append(f"CREATE INDEX idx_{tab}_{a} ON {tab} ({a});")
            n_fkidx += 1
idx += ["", "-- Teil 2: Fachliche Indizes", ""]
for name, tab, definition, begruendung in INDEXES:
    if tab not in E:
        fehler(f"INDEXES verweist auf unbekannte Tabelle {tab}")
    idx.append(f"-- {begruendung}")
    idx.append(f"CREATE INDEX {name} ON {tab} {definition};")
    idx.append("")
idx += [f"-- Zusammenfassung: {n_fkidx} Fremdschlüssel-Indizes, {len(INDEXES)} fachliche Indizes.", ""]
OUT_IDX.write_text("\n".join(idx), encoding="utf-8")
print(f"{OUT_IDX.name}: {n_fkidx} FK-Indizes, {len(INDEXES)} fachliche Indizes")
