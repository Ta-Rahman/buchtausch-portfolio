-- Erweiterungen, die beim ersten Start des Containers geladen werden.
-- Geodaten für die Umkreissuche ("Bücher in meiner Nähe")
CREATE EXTENSION IF NOT EXISTS postgis;
-- Erlaubt EXCLUDE-Constraints über Zeiträume (verhindert Doppelausleihen)
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- Ähnlichkeitssuche für Titel und Autorennamen
CREATE EXTENSION IF NOT EXISTS pg_trgm;
