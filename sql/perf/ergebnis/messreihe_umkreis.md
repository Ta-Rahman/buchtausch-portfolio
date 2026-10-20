# Messreihe: Umkreissuche mit und ohne GiST-Index

- PostgreSQL 16.4 (Debian 16.4-1.pgdg110+2), PostGIS 3.4.3
- Messrechner: Intel Core Ultra 9 185H, 31 GB RAM, Docker Desktop 28.3.2, Windows 11, Container postgis/postgis:16-3.4
- Gemessen am: 2026-10-20 11:30 (Europe/Berlin)
- jit = off, warmer Cache; Serverkonfiguration sonst unverändert (max_parallel_workers_per_gather = 2, shared_buffers = 128MB)
- Median aus fünf Wiederholungen nach einem Aufwärmlauf (die 200k-Textbelege in diesem Ordner zeigen dagegen den zweiten Lauf)
- Wiederholungen ABWEICHEND (Planknoten, Treffer, Buffers hit/read): 1000000 Zeilen mit: Parallel Bitmap Heap Scan 73910 Treffer 15230/185, Parallel Bitmap Heap Scan 73910 Treffer 15415/0, Parallel Bitmap Heap Scan 73910 Treffer 2081/13334; die Tabelle zeigt den Median-Lauf
- Wiederholung: gegenüber dem Lauf vom 2026-10-15 02:11 (Europe/Berlin) sind Planknoten, Treffer und Tabellengrößen identisch. Zeiten, Buffers und Indexgrößen laufabhängig; die Größe des GiST-Index schwankt bei identischen Daten zwischen Läufen, Ursache nicht untersucht. Faktoren nur innerhalb dieser Datei vergleichen.
- Quelle: sql/perf/01_umkreissuche.sql, erzeugt mit tools/run_perf.py — nicht von Hand ändern
- Zahlen mit Dezimalpunkt und Größen in Bytes: messreihe_umkreis.csv

| zeilen | treffer | zeit_ohne_ms | plan_ohne | zeit_mit_ms | plan_mit | faktor | tabelle_groesse | index_groesse | buffers_ohne | buffers_mit |
|---:|---:|---:|---|---:|---|---:|---:|---:|---:|---:|
| 1.000 | 79 | 2,478 | Seq Scan | 0,331 | Bitmap Heap Scan | 7,5 | 112 kB | 72 kB | 14/0 | 21/0 |
| 10.000 | 723 | 27,196 | Seq Scan | 2,680 | Bitmap Heap Scan | 10,1 | 1072 kB | 752 kB | 134/0 | 157/0 |
| 100.000 | 7.224 | 150,051 | Parallel Seq Scan | 48,869 | Parallel Bitmap Heap Scan | 3,1 | 10 MB | 7208 kB | 1.784/0 | 1.897/0 |
| 200.000 | 14.701 | 256,225 | Parallel Seq Scan | 76,893 | Parallel Bitmap Heap Scan | 3,3 | 21 MB | 14 MB | 3.117/0 | 3.364/0 |
| 1.000.000 | 73.910 | 1.017,851 | Parallel Seq Scan | 180,314 | Parallel Bitmap Heap Scan | 5,6 | 104 MB | 69 MB | 14.234/0 | 15.415/0 |
