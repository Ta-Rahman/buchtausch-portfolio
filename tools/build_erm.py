#!/usr/bin/env python3
"""Erzeugt das ER-Diagramm (Krähenfuß-Notation) aus model.py."""
import subprocess
from model import GROUPS, E, R

ARROW = {"1": "tee", "0..1": "teeodot", "n": "crow", "0..n": "crowodot"}


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def node(name):
    grp, _zweck, attrs = E[name]
    _, fill, line = GROUPS[grp]
    rows = [f'<TR><TD BGCOLOR="{line}" COLSPAN="2" ALIGN="CENTER">'
            f'<FONT COLOR="white" POINT-SIZE="15"><B>{esc(name)}</B></FONT></TD></TR>']
    # Nur Schlüsselattribute: bei 21 Entitäten wären alle 108 Attribute auf A4
    # unlesbar klein. Die vollständige Attributliste steht im Datenwörterbuch.
    keys = [(a, t, k) for a, t, k, _d in attrs if k]
    rest = len(attrs) - len(keys)
    for a, t, k in keys:
        b0, b1 = ("<B>", "</B>") if "PK" in k else ("", "")
        rows.append(f'<TR><TD ALIGN="LEFT" PORT="{a}">{b0}{esc(a)}{b1}</TD>'
                    f'<TD ALIGN="LEFT"><FONT POINT-SIZE="11"><B>{k}</B></FONT></TD></TR>')
    if rest:
        rows.append(f'<TR><TD ALIGN="LEFT" COLSPAN="2">'
                    f'<FONT POINT-SIZE="11" COLOR="#777777">+ {rest} weitere Attribute</FONT>'
                    f'</TD></TR>')
    return (f'  {name} [fillcolor="{fill}", label=<<TABLE BORDER="0" CELLBORDER="0" '
            f'CELLSPACING="0" CELLPADDING="3">{"".join(rows)}</TABLE>>];')


lines = ['digraph ERM {',
         '  graph [rankdir=TB, splines=spline, overlap=false, nodesep=0.28, ranksep=0.75,',
         '         fontname="Helvetica", bgcolor="white", pad=0.4];',
         '  node  [shape=box, style="filled,rounded", color="#888888", penwidth=1.1,',
         '         fontname="Helvetica", fontsize=13];',
         '  edge  [fontname="Helvetica", fontsize=11, color="#666666", dir=both, penwidth=1.0];', '']

# Bewusst OHNE Cluster-Rahmen: die gestrichelten Gruppenkästen zwingen dot zu
# einer Anordnung, die das Diagramm auf 72 cm Breite aufbläht (Schrift danach
# 5,3 pt auf A4). Ohne sie sind es 42 cm und 8,4 pt. Die Gruppenzugehörigkeit
# bleibt über die Füllfarben erkennbar; die Legende steht in der Bildunterschrift.
for grp, (title, fill, line) in GROUPS.items():
    lines += [node(n) for n, (g, _z, _a) in E.items() if g == grp]
lines.append('')

for a, b, lbl, tk, hk in R:
    lines.append(f'  {a} -> {b} [arrowtail={ARROW[tk]}, arrowhead={ARROW[hk]}, '
                 f'taillabel="{tk}", headlabel="{hk}", labeldistance=1.7, labelangle=14, '
                 f'labelfontsize=10, labelfontcolor="#333333"];')
lines.append('}')

open("erm.dot", "w").write("\n".join(lines))
for fmt in ("png", "svg", "pdf"):
    subprocess.run(["dot", f"-T{fmt}", "erm.dot", "-o", f"ER-Modell_Buchtausch.{fmt}"], check=True)

attr_count = sum(len(a) for _g, _z, a in E.values())
print(f"Entitäten: {len(E)} | Beziehungen: {len(R)} | Attribute: {attr_count}")
