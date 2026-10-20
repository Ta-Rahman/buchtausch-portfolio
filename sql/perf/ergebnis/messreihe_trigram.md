# Messreihe: Titelsuche mitten im Wort mit und ohne GIN-Index (pg_trgm)

- PostgreSQL 16.4 (Debian 16.4-1.pgdg110+2), PostGIS 3.4.3
- Messrechner: Intel Core Ultra 9 185H, 31 GB RAM, Docker Desktop 28.3.2, Windows 11, Container postgis/postgis:16-3.4
- Gemessen am: 2026-10-20 11:30 (Europe/Berlin)
- jit = off, warmer Cache; Serverkonfiguration sonst unverändert (max_parallel_workers_per_gather = 2, shared_buffers = 128MB)
- Median aus fünf Wiederholungen nach einem Aufwärmlauf (die 200k-Textbelege in diesem Ordner zeigen dagegen den zweiten Lauf)
- Wiederholungen: Planknoten, Treffer und Buffers je Stufe in allen fünf Messungen gleich
- Wiederholung: gegenüber dem Lauf vom 2026-10-15 02:11 (Europe/Berlin) sind Planknoten, Treffer, Tabellen- und Indexgrößen identisch. Zeiten und Buffers laufabhängig. Faktoren nur innerhalb dieser Datei vergleichen.
- Quelle: sql/perf/02_trigramsuche.sql, erzeugt mit tools/run_perf.py — nicht von Hand ändern
- Zahlen mit Dezimalpunkt und Größen in Bytes: messreihe_trigram.csv

| zeilen | treffer | zeit_ohne_ms | plan_ohne | zeit_mit_ms | plan_mit | faktor | tabelle_groesse | index_groesse | buffers_ohne | buffers_mit |
|---:|---:|---:|---|---:|---|---:|---:|---:|---:|---:|
| 1.000 | 2 | 1,364 | Seq Scan | 1,149 | Seq Scan | 1,2 | 88 kB | 72 kB | 11/0 | 11/0 |
| 10.000 | 24 | 15,874 | Seq Scan | 0,768 | Bitmap Heap Scan | 20,7 | 880 kB | 568 kB | 110/0 | 87/0 |
| 100.000 | 260 | 179,083 | Seq Scan | 17,283 | Bitmap Heap Scan | 10,4 | 8776 kB | 4952 kB | 1.097/0 | 582/0 |
| 200.000 | 522 | 359,443 | Seq Scan | 31,659 | Bitmap Heap Scan | 11,4 | 17 MB | 7832 kB | 2.194/0 | 1.120/0 |
| 1.000.000 | 2.550 | 642,716 | Parallel Seq Scan | 98,524 | Bitmap Heap Scan | 6,5 | 86 MB | 32 MB | 10.967/0 | 5.431/0 |
