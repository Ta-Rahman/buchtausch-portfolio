#!/usr/bin/env bash
# =====================================================================
# Nebenläufigkeitsnachweis für Geschäftsregel 1 (EXCLUDE excl_ausleihe_doppelbuchung)
#
# Sitzung 1 bestätigt eine Ausleihe und hält ihre Transaktion offen; Sitzung 2
# will einen überlappenden Zeitraum desselben Exemplars bestätigen und muss auf
# Sitzung 1 warten, bis lock_timeout nach 3 s abbricht (SQLSTATE 55P03).
# Nach dem COMMIT von Sitzung 1 scheitert derselbe Versuch von Sitzung 2 sofort
# am EXCLUDE (SQLSTATE 23P01), es können also nie beide Buchungen bestehen.
#
# Aufruf aus dem Wurzelverzeichnis des Repos in Git Bash, Container läuft:
#   bash tools/test_nebenlaeufigkeit.sh
# Ergebnis: docs/belege/nebenlaeufigkeit.txt. Am Ende werden Buchung und
# Testexemplar wieder gelöscht, die Zeilenzahlen stimmen danach (1.357), nur die
# Sequenzen von ausleihe und exemplar bleiben bis zum nächsten Reset weitergezählt.
#
# Ablauf: je Sitzung ein psql-Prozess, dessen Eingabe das Skript Zeile für
# Zeile schreibt; an den Wartepunkten wartet die Eingabe auf eine Signaldatei.
# Jede Ausgabezeile bekommt die Uhrzeit (UTC) und die Sitzung vorangestellt.
# Außerhalb der Init-Kette, weil der Nachweis zwei gleichzeitige Verbindungen
# braucht.
# =====================================================================

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

export TZ=UTC
BELEG=docs/belege/nebenlaeufigkeit.txt
TMP=$(mktemp -d)
PSQL=(docker exec -i buchtausch-db psql -X -U buchtausch -d buchtausch)
# -e zeigt jede Anweisung vor ihrer Ausführung, VERBOSITY=verbose den SQLSTATE im Fehler
SITZUNG=("${PSQL[@]}" -e -v VERBOSITY=verbose)

log() { printf '%s\n' "$@" >> "$BELEG"; }
abbruch() { echo "Abbruch: $*" >&2; exit 1; }

# stempel S: setzt vor jede Zeile Uhrzeit mit Millisekunden und Sitzung S.
# $EPOCHREALTIME ist die Uhr der Bash selbst; anders als date startet sie
# keinen Prozess je Zeile und verschiebt die Zeitstempel deshalb nicht.
stempel() {
    local zeile t
    while IFS= read -r zeile; do
        t=$EPOCHREALTIME
        printf '%(%H:%M:%S)T.%s [%s] %s\n' "${t%[.,]*}" "${t: -6:3}" "$1" "$zeile"
    done
}

# warte_auf DATEI MUSTER: wartet höchstens 30 s, bis MUSTER in DATEI steht.
warte_auf() {
    local i
    for i in $(seq 300); do
        grep -q -- "$2" "$1" 2>/dev/null && return 0
        sleep 0.1
    done
    echo "Zeitüberschreitung: '$2' nicht in $1" >&2
    return 1
}

# zeilen: Fachtabellen und ihre exakten Zeilen wie in sql/meta/metadaten.sql
# (count(*) je Tabelle, ohne die Tabellen der Erweiterungen).
zeilen() {
    "${PSQL[@]}" -qAt <<'SQL'
CREATE FUNCTION pg_temp.zeilen(t regclass) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
    EXECUTE format('SELECT count(*) FROM %s', t) INTO n;
    RETURN n;
END $$;
SELECT count(*) || ' Tabellen, ' || sum(pg_temp.zeilen(c.oid)) || ' Zeilen'
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
   AND NOT EXISTS (SELECT 1 FROM pg_depend d
                    WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e');
SQL
}

# ende: bei einem Abbruch Sitzungen beenden und Testdaten löschen; immer das Temp-Verzeichnis löschen.
ende() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        kill $(jobs -p) 2>/dev/null
        if [ -n "${EX:-}" ]; then
            "${PSQL[@]}" -c "DELETE FROM ausleihe WHERE exemplar_id = $EX" \
                         -c "DELETE FROM exemplar WHERE exemplar_id = $EX" >&2
        fi
    fi
    rm -rf "$TMP"
}
trap ende EXIT

# ---------------------------------------------------------------------
# Vorher zählen, Testexemplar anlegen
# ---------------------------------------------------------------------
{
    echo "-- Beleg: Nebenläufigkeit bei Geschäftsregel 1 mit zwei psql-Sitzungen (Phase 3)"
    echo "-- Erhoben $(date -u '+%Y-%m-%d %H:%M') UTC mit tools/test_nebenlaeufigkeit.sh; Zeitstempel UTC beim Eintreffen der Zeile"
    echo
    echo '$ bash tools/test_nebenlaeufigkeit.sh'
} > "$BELEG"

log "" "-- Vorher: Fachtabellen und Zeilen" "\$ ${PSQL[*]} -qAt    # Zählabfrage wie in sql/meta/metadaten.sql"
VORHER=$(zeilen) || abbruch "Zählabfrage vorher"
log "$VORHER"

SQL_EX="INSERT INTO exemplar (werk_id, besitzer_id, zustand_id, max_leihdauer_tage) VALUES (1, 1, 2, 14) RETURNING exemplar_id"
log "" "-- Testexemplar wie die Fixture in 06_tests.sql (Werk 1, Person 1, max. 14 Tage)" "\$ ${PSQL[*]} -qAt -c \"$SQL_EX\""
EX=$("${PSQL[@]}" -qAt -c "$SQL_EX")
[[ $EX =~ ^[0-9]+$ ]] || abbruch "Testexemplar nicht angelegt: $EX"
log "$EX"

# ---------------------------------------------------------------------
# Zwei Sitzungen buchen denselben Zeitraum
# ---------------------------------------------------------------------
INSERT_S1="INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status) VALUES ($EX, 2, '2027-06-01', '2027-06-10', 'bestaetigt');"
INSERT_S2="INSERT INTO ausleihe (exemplar_id, ausleiher_id, zeitraum_von, zeitraum_bis, status) VALUES ($EX, 3, '2027-06-05', '2027-06-12', 'bestaetigt');"

log "" "-- Sitzung 1 [S1] und Sitzung 2 [S2]: je ein psql-Prozess im Hintergrund, Eingabe zeilenweise aus dem Skript" \
    "\$ ${SITZUNG[*]}    # [S1]" \
    "\$ ${SITZUNG[*]}    # [S2]"

# Sitzung 1: bucht 01.–10.06. und hält die Transaktion offen, bis die Signaldatei commit kommt
{
    printf '%s\n' '\timing on' 'BEGIN;' "$INSERT_S1"
    warte_auf "$TMP/commit" los && echo 'COMMIT;'
} | "${SITZUNG[@]}" 2>&1 | stempel S1 > "$TMP/s1.txt" &
PID1=$!
warte_auf "$TMP/s1.txt" 'INSERT 0 1' || exit 1

# Sitzung 2: will 05.–12.06. bestätigen, gibt nach 3 s Warten auf; nach der Signaldatei nochmal
{
    printf '%s\n' '\timing on' "SET lock_timeout = '3s';" "$INSERT_S2"
    warte_auf "$TMP/nochmal" los && echo "$INSERT_S2"
} | "${SITZUNG[@]}" 2>&1 | stempel S2 > "$TMP/s2.txt" &
PID2=$!
warte_auf "$TMP/s2.txt" '55P03' || exit 1

echo los > "$TMP/commit"      # Sitzung 1 sendet COMMIT und endet
wait "$PID1"
echo los > "$TMP/nochmal"     # Sitzung 2 versucht dieselbe Buchung erneut
wait "$PID2"

# beide Ausgaben nach Uhrzeit zusammenführen (-s: gleiche Uhrzeit behält die Reihenfolge)
LC_ALL=C sort -s -k1,1 "$TMP/s1.txt" "$TMP/s2.txt" > "$TMP/sitzungen.txt"
cat "$TMP/sitzungen.txt" >> "$BELEG"
Z55=$(grep -n -m1 '55P03' "$TMP/sitzungen.txt" | cut -d: -f1)
Z23=$(grep -n -m1 '23P01' "$TMP/sitzungen.txt" | cut -d: -f1)
[ -n "$Z55" ] && [ -n "$Z23" ] && [ "$Z55" -lt "$Z23" ] || abbruch "erwartet 55P03 und danach 23P01, siehe $BELEG"

# ---------------------------------------------------------------------
# Aufräumen und nachher zählen
# ---------------------------------------------------------------------
SQL_WEG1="DELETE FROM ausleihe WHERE exemplar_id = $EX"
SQL_WEG2="DELETE FROM exemplar WHERE exemplar_id = $EX"
log "" "-- Aufräumen: Buchung aus Sitzung 1 und Testexemplar löschen" "\$ ${PSQL[*]} -c \"$SQL_WEG1\" -c \"$SQL_WEG2\""
"${PSQL[@]}" -c "$SQL_WEG1" -c "$SQL_WEG2" >> "$BELEG" 2>&1 || exit 1
EX=""

log "" "-- Nachher: Fachtabellen und Zeilen" "\$ ${PSQL[*]} -qAt    # Zählabfrage wie oben"
NACHHER=$(zeilen) || abbruch "Zählabfrage nachher"
log "$NACHHER"
[ "$VORHER" = "$NACHHER" ] || abbruch "Zeilen vorher ($VORHER) und nachher ($NACHHER) verschieden"

echo "Nebenläufigkeit: 55P03, nach dem COMMIT 23P01; vorher und nachher $NACHHER. Beleg: $BELEG"
