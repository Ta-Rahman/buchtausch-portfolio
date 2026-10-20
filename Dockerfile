# Eigenes Image für die Entwicklungsdatenbank der Buchtausch-App.
#
# Warum ein eigenes Image statt des fertigen postgis/postgis-Images mit einem
# Bind-Mount auf ./sql/init? Das Repository liegt auf X:, einem als Dev Drive
# (ReFS) formatierten Laufwerk. Docker Desktop reicht dieses Dateisystem nicht
# zuverlässig durch: das Verzeichnis /docker-entrypoint-initdb.d kam im
# Container leer an, der Entrypoint übersprang die Init-Kette, und der
# Reproduzierbarkeitsnachweis war nur noch von Hand zu führen. Die acht
# Skripte werden deshalb beim Bauen ins Image kopiert. Sie reisen damit mit dem
# Image statt mit dem Dateisystem, und der Aufbau funktioniert auch dann, wenn
# beim Prüfer die Dateifreigabe von Docker Desktop anders eingestellt ist.
#
# Folge: nach jeder Änderung in sql/init/ muss das Image neu gebaut werden
# (docker compose up -d --build), sonst läuft die alte Init-Kette.

FROM postgis/postgis:16-3.4

# Das Basis-Image bringt ein eigenes Init-Skript mit (10_postgis.sh), das neben
# postgis noch postgis_topology, fuzzystrmatch und postgis_tiger_geocoder
# einspielt und eine zusätzliche Datenbank template_postgis anlegt. Der frühere
# Bind-Mount hat das ganze Verzeichnis ersetzt, das Skript lief also auch bisher
# nie mit; 01_extensions.sql lädt genau die drei Erweiterungen, die das Modell
# braucht. Das Entfernen hält die Datenbank damit exakt auf dem Stand des Laufs
# vom 18.09. (\dx zeigt vier Erweiterungen).
RUN rm -f /docker-entrypoint-initdb.d/10_postgis.sh

# Die acht Skripte laufen beim ERSTEN Start automatisch, in alphabetischer
# Reihenfolge - dafür sind die Nummernpräfixe da.
COPY sql/init/ /docker-entrypoint-initdb.d/
