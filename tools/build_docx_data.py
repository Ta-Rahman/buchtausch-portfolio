#!/usr/bin/env python3
"""Exportiert das Datenwörterbuch als JSON für den Word-Generator."""
import json
from model import GROUPS, E, TERNAER

data = []
for grp, (title, _f, _l) in GROUPS.items():
    entries = []
    for name, (g, zweck, attrs) in E.items():
        if g != grp:
            continue
        entries.append({
            "name": name,
            "ternaer": name in TERNAER,
            "zweck": zweck.rstrip("."),
            "attrs": [{"n": a, "t": t, "k": k} for a, t, k, _d in attrs],
        })
    data.append({"gruppe": title, "entitaeten": entries})

json.dump(data, open("dict_data.json", "w"), ensure_ascii=False, indent=1)
print("dict_data.json:", sum(len(g["entitaeten"]) for g in data), "Entitäten")
