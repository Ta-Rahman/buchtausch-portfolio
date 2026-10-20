#!/usr/bin/env python3
"""Erzeugt das Datenwörterbuch (ausführlich + kompakt) aus model.py."""
from model import GROUPS, E, R, TERNAER


def p(s):
    """Pipe-Zeichen maskieren, damit Markdown-Tabellen nicht brechen."""
    return s.replace("|", "\\|")

out = ["# Datenwörterbuch – Buchtausch-App",
       "",
       f"**{len(E)} Entitäten · {sum(len(a) for _g,_z,a in E.values())} Attribute · "
       f"{len(R)} Beziehungen · {len(TERNAER)} Dreifachbeziehungen**",
       "",
       "Legende: **PK** = Primärschlüssel · **FK** = Fremdschlüssel · **UK** = eindeutig (UNIQUE). "
       "Attribute ohne Kennzeichnung sind einfache Datenfelder. Datentypen sind für PostgreSQL angegeben.",
       ""]

for grp, (title, _f, _l) in GROUPS.items():
    out += [f"## {title}", ""]
    for name, (g, zweck, attrs) in E.items():
        if g != grp:
            continue
        marker = "  ⟨Dreifachbeziehung⟩" if name in TERNAER else ""
        out += [f"### `{name}`{marker}", "", f"*{zweck}*", "",
                "| Attribut | Datentyp | Schlüssel | Beschreibung |",
                "|---|---|---|---|"]
        for a, t, k, d in attrs:
            out.append(f"| `{a}` | {p(t)} | {k or '—'} | {p(d)} |")
        out.append("")

out += ["## Beziehungsübersicht", "",
        "Kardinalitäten in der Krähenfuß-Notation; `0..n` bedeutet optional viele, "
        "`1` genau eins, `0..1` optional eins.", "",
        "| Von | Kardinalität | Beziehung | Kardinalität | Nach |",
        "|---|---|---|---|---|"]
for a, b, lbl, tk, hk in R:
    out.append(f"| `{a}` | {tk} | {lbl} | {hk} | `{b}` |")

out += ["", "## Dreifachbeziehungen", "",
        "| Beziehungstabelle | Verknüpfte Entitäten | Fachliche Aussage |",
        "|---|---|---|",
        "| `verfuegbarkeit` | exemplar × zeitslot × uebergabeart | Wann ist welches Exemplar auf welchem Weg übergebbar? |",
        "| `uebergabe` | ausleihe × zeitslot × uebergabeart | Wann und auf welchem Weg wechselt das Exemplar den Besitz? |",
        "| `bewertung_person` | benutzer × benutzer × ausleihe | Wer bewertet wen aufgrund welcher konkreten Ausleihe? |",
        ""]

open("Datenwoerterbuch.md", "w").write("\n".join(out))

# ---------------------------------------------------------------------------
# Kompaktfassung für das 4-seitige Abgabe-PDF.
# Die Aufgabenstellung lässt eine "kurze Beschreibung der Datenattribute und
# Datentypen" ausdrücklich zu — die ausführliche Fassung liegt im Repository.
# ---------------------------------------------------------------------------
kurz = ["# Datenwörterbuch (Kompaktfassung)", "",
        f"{len(E)} Entitäten, {sum(len(a) for _g,_z,a in E.values())} Attribute. "
        "**Fett** = Primärschlüssel, *kursiv* = Fremdschlüssel, ° = eindeutig. "
        "Datentypen für PostgreSQL. Ausführliche Fassung mit Attributbeschreibungen: siehe Repository.",
        ""]
for grp, (title, _f, _l) in GROUPS.items():
    kurz += [f"**{title}**", ""]
    for name, (g, zweck, attrs) in E.items():
        if g != grp:
            continue
        teile = []
        for a, t, k, _d in attrs:
            s = f"**{a}**" if "PK" in k else (f"*{a}*" if "FK" in k else a)
            if "UK" in k:
                s += "°"
            teile.append(f"{s} {t}")
        stern = " ⟨3er⟩" if name in TERNAER else ""
        kurz.append(f"- `{name}`{stern} — {zweck.rstrip('.')}: " + " · ".join(teile))
    kurz.append("")

open("Datenwoerterbuch_kompakt.md", "w").write("\n".join(kurz))
print(f"ausführlich: {len(' '.join(out).split())} Wörter | "
      f"kompakt: {len(' '.join(kurz).split())} Wörter")
