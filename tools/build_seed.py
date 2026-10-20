#!/usr/bin/env python3
"""
Erzeugt sql/init/05_seed.sql — deterministische Dummy-Daten für die Buchtausch-App.

Aufruf:   python3 build_seed.py          (aus dem Ordner tools/, braucht Faker: pip install -r requirements.txt)
Prinzip:  fester Zufalls-Seed (SEED) und fester Stichtag (STICHTAG) — jeder Lauf
          erzeugt exakt dieselbe Datei; die Datenbank ist damit reproduzierbar,
          auch wenn das Skript in Monaten erneut läuft.

Fachliche Leitplanken, die der Generator selbst einhält (die Datenbank würde
sie sonst per Constraint/Trigger zurückweisen):
  - Leihdauer (inklusiv) <= max_leihdauer_tage des Exemplars      (Regel 3)
  - keine überlappenden Leihzeiträume je Exemplar                  (Regel 1)
  - Bewertungen nur zu abgeschlossenen Ausleihen, nur durch die
    beteiligten Personen, Werk = Werk des Exemplars                (Regel 2)
  - Ausleihende Person ist nie die besitzende Person
  - Postversand nur bei Exemplaren mit versand_moeglich

Abweichung von „>= 10 Einträge je Tabelle“ (bewusst, dokumentiert):
  rolle (3), uebergabeart (2) und zustand (5) sind Stammdaten mit fachlich
  begrenzter Wertemenge — künstliches Auffüllen würde „sinnvolle Daten“ verletzen.

IDs werden explizit vergeben, damit die Fremdschlüssel im Skript lesbar sind;
die SERIAL-Sequenzen werden am Ende je Tabelle mit setval() nachgezogen.
Bibliografische Angaben (Titel, Autor:in, Jahr) sind echt; ISBNs, Verlagszuordnung
einzelner Ausgaben, Übersetzer:innen-Namen und alle Personen sind fiktiv.
"""
import random
from datetime import date, datetime, timedelta, time
from pathlib import Path
from zoneinfo import ZoneInfo
from faker import Faker

SEED = 42
STICHTAG = date(2026, 9, 19)
TZ = ZoneInfo("Europe/Berlin")
OUT = Path(__file__).resolve().parent.parent / "sql" / "init" / "05_seed.sql"

rnd = random.Random(SEED)
fake = Faker("de_DE")
fake.seed_instance(SEED)


# ---------------------------------------------------------------- Helfer
def q(v):
    """Python-Wert -> SQL-Literal."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, datetime):
        return "'" + v.astimezone(TZ).strftime("%Y-%m-%d %H:%M:%S%z") + "'"
    if isinstance(v, date):
        return "'" + v.isoformat() + "'"
    if isinstance(v, Raw):
        return v.sql
    return "'" + str(v).replace("'", "''") + "'"


class Raw:
    """SQL-Ausdruck, der unverändert eingesetzt wird (z. B. ST_MakePoint)."""
    def __init__(self, sql):
        self.sql = sql


def ts(d, h, m=0):
    return datetime.combine(d, time(h, m), tzinfo=TZ)


def isbn13():
    """Fiktive, aber prüfziffer-gültige ISBN-13 im deutschen Präfix 978-3."""
    digits = [9, 7, 8, 3] + [rnd.randint(0, 9) for _ in range(8)]
    summe = sum(d * (1 if i % 2 == 0 else 3) for i, d in enumerate(digits))
    digits.append((10 - summe % 10) % 10)
    return "".join(map(str, digits))


def bcrypt_dummy():
    """Sieht aus wie ein bcrypt-Hash (60 Zeichen), ist aber keiner."""
    alphabet = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    return "$2b$12$" + "".join(rnd.choice(alphabet) for _ in range(53))


# ---------------------------------------------------------------- Stammdaten
ROLLEN = [("Mitglied", "Bücher einstellen, anfragen, ausleihen, bewerten"),
          ("Moderation", "gemeldete Bewertungen prüfen, Konten sperren"),
          ("Administration", "Stammdaten pflegen, Rollen vergeben")]
UEBERGABEARTEN = ["Abholung", "Postversand"]
ZUSTAENDE = [(1, "neuwertig", "Wie neu, keine Gebrauchsspuren"),
             (2, "sehr gut", "Minimale Gebrauchsspuren, Seiten sauber"),
             (3, "gut", "Leichte Gebrauchsspuren, evtl. Namenseintrag"),
             (4, "gebraucht", "Deutliche Spuren, Knicke, Anstreichungen möglich"),
             (5, "stark abgenutzt", "Lose Seiten oder beschädigter Einband, vollständig lesbar")]
SPRACHEN = [("de", "Deutsch"), ("en", "Englisch"), ("fr", "Französisch"), ("es", "Spanisch"),
            ("it", "Italienisch"), ("tr", "Türkisch"), ("pl", "Polnisch"), ("ru", "Russisch"),
            ("ar", "Arabisch"), ("nl", "Niederländisch"), ("pt", "Portugiesisch"), ("ja", "Japanisch")]
GENRES = ["Roman", "Krimi", "Sachbuch", "Kinderbuch", "Fantasy", "Science-Fiction",
          "Biografie", "Lyrik", "Ratgeber", "Comic", "Geschichte", "Reise"]
VERLAGE = [("Suhrkamp", "Berlin"), ("S. Fischer", "Frankfurt am Main"), ("dtv", "München"),
           ("Rowohlt", "Hamburg"), ("Hanser", "München"), ("Carlsen", "Hamburg"),
           ("Piper", "München"), ("Diogenes", "Zürich"), ("Kiepenheuer & Witsch", "Köln"),
           ("Ullstein", "Berlin"), ("Penguin Books", "London"), ("Beltz & Gelberg", "Weinheim")]

# (Titel, Untertitel, [(Vorname, Nachname, Geburtsjahr)], Jahr, Sprache, [Genres], übersetzt?)
WERKE = [
 ("Der Steppenwolf", None, [("Hermann", "Hesse", 1877)], 1927, "de", ["Roman"], False),
 ("Die Verwandlung", None, [("Franz", "Kafka", 1883)], 1915, "de", ["Roman"], False),
 ("Der Vorleser", None, [("Bernhard", "Schlink", 1944)], 1995, "de", ["Roman"], False),
 ("Das Parfum", "Die Geschichte eines Mörders", [("Patrick", "Süskind", 1949)], 1985, "de", ["Roman", "Krimi"], False),
 ("Tschick", None, [("Wolfgang", "Herrndorf", 1965)], 2010, "de", ["Roman"], False),
 ("Die unendliche Geschichte", None, [("Michael", "Ende", 1929)], 1979, "de", ["Kinderbuch", "Fantasy"], False),
 ("Momo", None, [("Michael", "Ende", 1929)], 1973, "de", ["Kinderbuch"], False),
 ("Der Schwarm", None, [("Frank", "Schätzing", 1957)], 2004, "de", ["Science-Fiction", "Roman"], False),
 ("Die Blechtrommel", None, [("Günter", "Grass", 1927)], 1959, "de", ["Roman"], False),
 ("Buddenbrooks", "Verfall einer Familie", [("Thomas", "Mann", 1875)], 1901, "de", ["Roman"], False),
 ("Der Zauberberg", None, [("Thomas", "Mann", 1875)], 1924, "de", ["Roman"], False),
 ("Effi Briest", None, [("Theodor", "Fontane", 1819)], 1895, "de", ["Roman"], False),
 ("Faust", "Der Tragödie erster Teil", [("Johann Wolfgang", "Goethe", 1749)], 1808, "de", ["Lyrik"], False),
 ("Die Leiden des jungen Werther", None, [("Johann Wolfgang", "Goethe", 1749)], 1774, "de", ["Roman"], False),
 ("Herr der Diebe", None, [("Cornelia", "Funke", 1958)], 2000, "de", ["Kinderbuch"], False),
 ("Tintenherz", None, [("Cornelia", "Funke", 1958)], 2003, "de", ["Kinderbuch", "Fantasy"], False),
 ("Er ist wieder da", None, [("Timur", "Vermes", 1967)], 2012, "de", ["Roman"], False),
 ("Die Känguru-Chroniken", "Ansichten eines vorlauten Beuteltiers", [("Marc-Uwe", "Kling", 1982)], 2009, "de", ["Roman"], False),
 ("QualityLand", None, [("Marc-Uwe", "Kling", 1982)], 2017, "de", ["Science-Fiction"], False),
 ("Altes Land", None, [("Dörte", "Hansen", 1964)], 2015, "de", ["Roman"], False),
 ("Die Vermessung der Welt", None, [("Daniel", "Kehlmann", 1975)], 2005, "de", ["Roman", "Geschichte"], False),
 ("Der Trafikant", None, [("Robert", "Seethaler", 1966)], 2012, "de", ["Roman"], False),
 ("Ein ganzes Leben", None, [("Robert", "Seethaler", 1966)], 2014, "de", ["Roman"], False),
 ("Tannöd", None, [("Andrea Maria", "Schenkel", 1962)], 2006, "de", ["Krimi"], False),
 ("Die Therapie", None, [("Sebastian", "Fitzek", 1971)], 2006, "de", ["Krimi"], False),
 ("Die Zwerge", None, [("Markus", "Heitz", 1971)], 2003, "de", ["Fantasy"], False),
 ("Darm mit Charme", "Alles über ein unterschätztes Organ", [("Giulia", "Enders", 1990)], 2014, "de", ["Sachbuch"], False),
 ("Der Ernährungskompass", None, [("Bas", "Kast", 1973)], 2018, "de", ["Sachbuch", "Ratgeber"], False),
 ("Ich bin dann mal weg", "Meine Reise auf dem Jakobsweg", [("Hape", "Kerkeling", 1964)], 2006, "de", ["Reise", "Biografie"], False),
 ("Buch der Lieder", None, [("Heinrich", "Heine", 1797)], 1827, "de", ["Lyrik"], False),
 ("Duineser Elegien", None, [("Rainer Maria", "Rilke", 1875)], 1923, "de", ["Lyrik"], False),
 ("Die Schlafwandler", "Wie Europa in den Ersten Weltkrieg zog", [("Christopher", "Clark", 1960)], 2012, "de", ["Geschichte", "Sachbuch"], True),
 ("Eine kurze Geschichte der Menschheit", None, [("Yuval Noah", "Harari", 1976)], 2011, "de", ["Sachbuch", "Geschichte"], True),
 ("Der Marsianer", None, [("Andy", "Weir", 1972)], 2011, "de", ["Science-Fiction"], True),
 ("Kafka am Strand", None, [("Haruki", "Murakami", 1949)], 2002, "de", ["Roman"], True),
 ("Der Hundertjährige, der aus dem Fenster stieg und verschwand", None, [("Jonas", "Jonasson", 1961)], 2009, "de", ["Roman"], True),
 ("Pippi Langstrumpf", None, [("Astrid", "Lindgren", 1907)], 1945, "de", ["Kinderbuch"], True),
 ("Ronja Räubertochter", None, [("Astrid", "Lindgren", 1907)], 1981, "de", ["Kinderbuch"], True),
 ("Der Grüffelo", None, [("Julia", "Donaldson", 1948), ("Axel", "Scheffler", 1957)], 1999, "de", ["Kinderbuch"], True),
 ("Persepolis", "Eine Kindheit im Iran", [("Marjane", "Satrapi", 1969)], 2000, "de", ["Comic", "Biografie"], True),
 ("Maus", "Die Geschichte eines Überlebenden", [("Art", "Spiegelman", 1948)], 1986, "de", ["Comic", "Geschichte"], True),
 ("Mord im Orientexpress", None, [("Agatha", "Christie", 1890)], 1934, "de", ["Krimi"], True),
 ("Der Hund von Baskerville", None, [("Arthur Conan", "Doyle", 1859)], 1902, "de", ["Krimi"], True),
 ("1984", None, [("George", "Orwell", 1903)], 1949, "en", ["Roman", "Science-Fiction"], False),
 ("Animal Farm", "A Fairy Story", [("George", "Orwell", 1903)], 1945, "en", ["Roman"], False),
 ("Pride and Prejudice", None, [("Jane", "Austen", 1775)], 1813, "en", ["Roman"], False),
 ("To Kill a Mockingbird", None, [("Harper", "Lee", 1926)], 1960, "en", ["Roman"], False),
 ("The Great Gatsby", None, [("F. Scott", "Fitzgerald", 1896)], 1925, "en", ["Roman"], False),
 ("Brave New World", None, [("Aldous", "Huxley", 1894)], 1932, "en", ["Science-Fiction"], False),
 ("Dune", None, [("Frank", "Herbert", 1920)], 1965, "en", ["Science-Fiction"], False),
 ("The Hobbit", "or There and Back Again", [("J. R. R.", "Tolkien", 1892)], 1937, "en", ["Fantasy"], False),
 ("Foundation", None, [("Isaac", "Asimov", 1920)], 1951, "en", ["Science-Fiction"], False),
 ("Neuromancer", None, [("William", "Gibson", 1948)], 1984, "en", ["Science-Fiction"], False),
 ("Becoming", None, [("Michelle", "Obama", 1964)], 2018, "en", ["Biografie"], False),
 ("L'Étranger", None, [("Albert", "Camus", 1913)], 1942, "fr", ["Roman"], False),
 ("Le Petit Prince", None, [("Antoine de", "Saint-Exupéry", 1900)], 1943, "fr", ["Kinderbuch"], False),
 ("Cien años de soledad", None, [("Gabriel", "García Márquez", 1927)], 1967, "es", ["Roman"], False),
 ("Il nome della rosa", None, [("Umberto", "Eco", 1932)], 1980, "it", ["Roman", "Krimi"], False),
 ("Kürk Mantolu Madonna", None, [("Sabahattin", "Ali", 1907)], 1943, "tr", ["Roman"], False),
 ("Solaris", None, [("Stanisław", "Lem", 1921)], 1961, "pl", ["Science-Fiction"], False),
]

# Straßen in Frankfurt am Main mit ungefähren Koordinaten (Breite, Länge), PLZ.
# Punkte werden leicht gestreut, damit nicht alle Adressen einer Straße identisch sind.
STRASSEN = [
 ("Oeder Weg", 50.1215, 8.6800, "60318"), ("Glauburgstraße", 50.1265, 8.6875, "60318"),
 ("Nordendstraße", 50.1230, 8.6900, "60318"), ("Eckenheimer Landstraße", 50.1250, 8.6835, "60318"),
 ("Friedberger Landstraße", 50.1240, 8.6960, "60316"), ("Rotlintstraße", 50.1250, 8.6990, "60316"),
 ("Günthersburgallee", 50.1285, 8.7050, "60316"), ("Bornheimer Landstraße", 50.1215, 8.6980, "60316"),
 ("Humboldtstraße", 50.1230, 8.6845, "60318"), ("Holzhausenstraße", 50.1275, 8.6770, "60322"),
 ("Keplerstraße", 50.1255, 8.6800, "60318"), ("Berger Straße", 50.1250, 8.7060, "60385"),
 ("Saalburgstraße", 50.1290, 8.7080, "60385"), ("Wiesenstraße", 50.1280, 8.7130, "60385"),
 ("Heidestraße", 50.1260, 8.7120, "60385"), ("Arnsburger Straße", 50.1225, 8.7090, "60385"),
 ("Höhenstraße", 50.1250, 8.7010, "60385"), ("Burgstraße", 50.1300, 8.7110, "60385"),
 ("Hanauer Landstraße", 50.1130, 8.7100, "60314"), ("Wittelsbacherallee", 50.1215, 8.7120, "60316"),
 ("Habsburgerallee", 50.1190, 8.7150, "60385"), ("Sandweg", 50.1185, 8.7000, "60316"),
 ("Waldschmidtstraße", 50.1160, 8.7050, "60316"), ("Rhönstraße", 50.1200, 8.7050, "60316"),
 ("Ostendstraße", 50.1105, 8.7000, "60314"), ("Zeil", 50.1150, 8.6860, "60313"),
 ("Große Eschenheimer Straße", 50.1160, 8.6790, "60313"), ("Töngesgasse", 50.1130, 8.6840, "60311"),
 ("Bleichstraße", 50.1175, 8.6880, "60313"), ("Schweizer Straße", 50.1020, 8.6800, "60594"),
 ("Textorstraße", 50.1035, 8.6860, "60594"), ("Brückenstraße", 50.1050, 8.6875, "60594"),
 ("Oppenheimer Landstraße", 50.1000, 8.6835, "60594"), ("Darmstädter Landstraße", 50.0990, 8.6910, "60594"),
 ("Mörfelder Landstraße", 50.0980, 8.6780, "60598"), ("Hedderichstraße", 50.1035, 8.6790, "60594"),
 ("Große Rittergasse", 50.1070, 8.6890, "60594"), ("Leipziger Straße", 50.1215, 8.6480, "60487"),
 ("Adalbertstraße", 50.1200, 8.6510, "60486"), ("Kettenhofweg", 50.1150, 8.6650, "60325"),
 ("Bockenheimer Landstraße", 50.1165, 8.6650, "60323"), ("Grüneburgweg", 50.1240, 8.6700, "60323"),
 ("Jordanstraße", 50.1225, 8.6470, "60486"), ("Schloßstraße", 50.1230, 8.6500, "60486"),
 ("Feuerbachstraße", 50.1150, 8.6700, "60325"), ("Kiesstraße", 50.1185, 8.6470, "60486"),
 ("Sophienstraße", 50.1210, 8.6440, "60487"), ("Kaiserstraße", 50.1085, 8.6700, "60329"),
 ("Mainzer Landstraße", 50.1100, 8.6620, "60329"), ("Frankenallee", 50.1040, 8.6520, "60327"),
]

KOMMENTARE_WERK = [
 "Hat mich von der ersten Seite an gepackt.", "Sprachlich wunderschön, inhaltlich etwas langatmig.",
 "Für mich das beste Buch des Jahres.", "Solide Unterhaltung, mehr aber auch nicht.",
 "Die Übersetzung wirkt an manchen Stellen holprig.", "Ein Klassiker, der zu Recht einer ist.",
 "Nach der Hälfte habe ich abgebrochen, zu zäh.", "Gut recherchiert und trotzdem spannend geschrieben.",
 "Perfekt für ein verregnetes Wochenende.", "Der Schluss hat mich enttäuscht.",
 "Meine Kinder wollten jeden Abend weiterlesen.", "Anspruchsvoll, aber lohnend.",
 "Kannte den Film, das Buch ist deutlich besser.", "Leichte Kost, gut für den Zug.",
 "Hat mich zum Nachdenken gebracht.", "Die Figuren bleiben leider blass.",
]
KOMMENTARE_PERSON = [
 "Pünktlich, freundlich, gerne wieder.", "Buch kam sorgfältig verpackt an.",
 "Übergabe hat problemlos geklappt.", "Sehr unkompliziert in der Abstimmung.",
 "Rückgabe leider mit Verspätung, sonst alles gut.", "Buch war in genau dem beschriebenen Zustand.",
 "Nette Nachbarin, kurzes Gespräch über das Buch inklusive.", "Antwortet schnell auf Nachrichten.",
 "Zuverlässig wie beim letzten Mal.", "Abholtermin musste zweimal verschoben werden.",
]
NACHRICHTEN = [
 "Hallo, ist das Buch im genannten Zeitraum noch verfügbar?",
 "Ja, ist es. Abholung am {tag} zwischen 18 und 19 Uhr würde passen?",
 "Passt, dann bis {tag}!", "Ich stehe vor der Tür, klingle jetzt.",
 "Vielen Dank, das Buch ist gut angekommen.", "Könnte ich es eine Woche länger behalten?",
 "Leider nein, es ist schon wieder angefragt.", "Kein Problem, ich bringe es am {tag} zurück.",
 "Die Sendung ist raus, Sendungsnummer steht in der Übergabe.", "Danke für die Ausleihe, super Buch!",
]

rows = {}          # tabelle -> Liste von dicts (in Einfügereihenfolge)
counts = {}


def add(tab, **werte):
    rows.setdefault(tab, []).append(werte)
    return len(rows[tab])     # = explizite ID (1-basiert), bei Tabellen mit SERIAL


# ---------------------------------------------------------------- Personen & Rollen
for bez, beschr in ROLLEN:
    add("rolle", bezeichnung=bez, beschreibung=beschr)

N_BENUTZER = 40
benutzer = []
emails = set()
for i in range(N_BENUTZER):
    vor, nach = fake.first_name(), fake.last_name()
    basis = f"{vor}.{nach}".lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    email = f"{basis}@{fake.free_email_domain()}"
    while email in emails:
        email = f"{basis}{rnd.randint(2, 99)}@{fake.free_email_domain()}"
    emails.add(email)
    reg = fake.date_between_dates(date(2025, 1, 10), date(2026, 8, 20))
    status = "aktiv"
    if i in (11, 27):
        status = "gesperrt"
    elif i in (33, 38):
        status = "deaktiviert"
    bid = add("benutzer", benutzer_id=i + 1, vorname=vor, nachname=nach, email=email,
              telefon=(fake.phone_number() if rnd.random() < 0.7 else None),
              passwort_hash=bcrypt_dummy(), registriert_am=reg, kontostatus=status)
    benutzer.append({"id": bid, "reg": reg, "status": status, "vor": vor})

strassen = STRASSEN[:]
rnd.shuffle(strassen)
for b in benutzer:
    name, lat, lon, plz = strassen[(b["id"] - 1) % len(strassen)]
    lat += rnd.uniform(-0.0025, 0.0025)
    lon += rnd.uniform(-0.0035, 0.0035)
    hnr = str(rnd.randint(1, 120)) + (rnd.choice(["", "", "", "a", "b"]))
    add("adresse", adresse_id=b["id"], benutzer_id=b["id"], strasse=name, hausnummer=hnr, plz=plz,
        ort="Frankfurt am Main", land="DE",
        position=Raw(f"ST_SetSRID(ST_MakePoint({lon:.6f}, {lat:.6f}), 4326)::geography"))

for b in benutzer:
    add("benutzer_rolle", benutzer_id=b["id"], rolle_id=1, zugewiesen_am=b["reg"])
for bid in (3, 17, 25):
    add("benutzer_rolle", benutzer_id=bid, rolle_id=2, zugewiesen_am=benutzer[bid - 1]["reg"] + timedelta(days=30))
add("benutzer_rolle", benutzer_id=1, rolle_id=3, zugewiesen_am=benutzer[0]["reg"])

# ---------------------------------------------------------------- Bibliografische Stammdaten
autoren = {}   # (vor, nach) -> id
for titel, unter, auts, jahr, spr, genres, uebers in WERKE:
    for vor, nach, geb in auts:
        if (vor, nach) not in autoren:
            autoren[(vor, nach)] = add("autor", autor_id=len(autoren) + 1, vorname=vor, nachname=nach, geburtsjahr=geb)
# einige fiktive Übersetzer:innen
uebersetzer = []
for _ in range(6):
    vor, nach = fake.first_name(), fake.last_name()
    autoren[(vor, nach)] = add("autor", autor_id=len(autoren) + 1, vorname=vor, nachname=nach,
                               geburtsjahr=rnd.randint(1950, 1985))
    uebersetzer.append(autoren[(vor, nach)])

for i, (name, sitz) in enumerate(VERLAGE):
    add("verlag", verlag_id=i + 1, name=name, sitz=sitz)
sprache_id = {}
for i, (code, bez) in enumerate(SPRACHEN):
    sprache_id[code] = add("sprache", sprache_id=i + 1, iso_code=code, bezeichnung=bez)
genre_id = {}
for i, g in enumerate(GENRES):
    genre_id[g] = add("genre", genre_id=i + 1, bezeichnung=g)

werke = []
for i, (titel, unter, auts, jahr, spr, genres, uebers) in enumerate(WERKE):
    verlag = 11 if spr == "en" else rnd.randint(1, 10)
    wid = add("werk", werk_id=i + 1, titel=titel, untertitel=unter,
              isbn13=(isbn13() if jahr >= 1970 or rnd.random() < 0.6 else None),
              erscheinungsjahr=jahr, verlag_id=verlag, sprache_id=sprache_id[spr])
    werke.append({"id": wid, "titel": titel})
    for vor, nach, _ in auts:
        add("werk_autor", werk_id=wid, autor_id=autoren[(vor, nach)], beitragsart="Autor")
    if uebers:
        add("werk_autor", werk_id=wid, autor_id=rnd.choice(uebersetzer), beitragsart="Übersetzung")
    for g in genres:
        add("werk_genre", werk_id=wid, genre_id=genre_id[g])
# ein Sammelband mit Herausgeber:in
add("werk_autor", werk_id=30, autor_id=rnd.choice(uebersetzer), beitragsart="Herausgeber")

# ---------------------------------------------------------------- Besitz & Verfügbarkeit
for stufe, bez, beschr in ZUSTAENDE:
    add("zustand", zustand_id=stufe, stufe=stufe, bezeichnung=bez, beschreibung=beschr)
for i, bez in enumerate(UEBERGABEARTEN):
    add("uebergabeart", uebergabeart_id=i + 1, bezeichnung=bez)
ABHOLUNG, POSTVERSAND = 1, 2

N_EXEMPLARE = 120
exemplare = []
aktive = [b for b in benutzer if b["status"] == "aktiv"]
for i in range(N_EXEMPLARE):
    b = rnd.choice(aktive) if rnd.random() < 0.95 else rnd.choice(benutzer)
    w = rnd.choice(werke)
    eingestellt = fake.date_between_dates(max(b["reg"], date(2025, 6, 1)), date(2026, 9, 1))
    status = rnd.choices(["verfuegbar", "pausiert", "entfernt"], [0.85, 0.10, 0.05])[0]
    eid = add("exemplar", exemplar_id=i + 1, werk_id=w["id"], besitzer_id=b["id"],
              zustand_id=rnd.choices([1, 2, 3, 4, 5], [0.15, 0.35, 0.3, 0.15, 0.05])[0],
              max_leihdauer_tage=rnd.choice([14, 14, 21, 21, 28, 42]),
              versand_moeglich=(rnd.random() < 0.4),
              anmerkung=rnd.choice([None, None, None, "Mit Widmung auf der ersten Seite", "Leichter Wasserschaden am Rand",
                                    "Taschenbuchausgabe", "Anstreichungen mit Bleistift", "Schutzumschlag fehlt"]),
              status=status, eingestellt_am=eingestellt)
    exemplare.append({"id": eid, "werk": w["id"], "besitzer": b["id"], "max": rows["exemplar"][-1]["max_leihdauer_tage"],
                      "versand": rows["exemplar"][-1]["versand_moeglich"], "status": status,
                      "eingestellt": eingestellt, "belegt": []})

zeitslots = []


def neuer_zeitslot(tag, stunde, dauer_h=2):
    zid = add("zeitslot", zeitslot_id=len(rows.get("zeitslot", [])) + 1,
              beginn=ts(tag, stunde), ende=ts(tag, stunde) + timedelta(hours=dauer_h))
    zeitslots.append(zid)
    return zid


# Verfügbarkeitsfenster: je verfügbarem Exemplar 1–2 Zeitfenster
verf_kombis = set()
for e in exemplare:
    if e["status"] != "verfuegbar":
        continue
    for _ in range(rnd.choice([1, 1, 2])):
        tag = fake.date_between_dates(date(2026, 9, 20), date(2026, 11, 30))
        zid = neuer_zeitslot(tag, rnd.choice([10, 16, 17, 18, 19]))
        arten = [ABHOLUNG] + ([POSTVERSAND] if e["versand"] and rnd.random() < 0.6 else [])
        for art in arten:
            if (e["id"], zid, art) not in verf_kombis:
                verf_kombis.add((e["id"], zid, art))
                add("verfuegbarkeit", verfuegbarkeit_id=len(rows["verfuegbarkeit"]) + 1 if "verfuegbarkeit" in rows else 1,
                    exemplar_id=e["id"], zeitslot_id=zid, uebergabeart_id=art)

# ---------------------------------------------------------------- Transaktion
N_AUSLEIHEN = 80
ausleihen = []
versuche = 0
while len(ausleihen) < N_AUSLEIHEN and versuche < 5000:
    versuche += 1
    e = rnd.choice(exemplare)
    if e["status"] == "entfernt":
        continue
    kandidaten = [b for b in benutzer if b["id"] != e["besitzer"] and b["status"] == "aktiv"]
    a = rnd.choice(kandidaten)
    von = fake.date_between_dates(max(e["eingestellt"], date(2026, 1, 5)), date(2026, 10, 25))
    dauer = rnd.randint(5, e["max"])                   # Regel 3: inklusiv <= max
    bis = von + timedelta(days=dauer - 1)
    if any(not (bis < v or von > b_) for v, b_ in e["belegt"]):   # Regel 1: keine Überlappung
        continue
    angefragt = ts(von, rnd.randint(8, 21), rnd.randint(0, 59)) - timedelta(days=rnd.randint(3, 20))
    entschieden = angefragt + timedelta(hours=rnd.randint(2, 70))
    uebergeben = zurueck = None
    if bis < STICHTAG:                                  # Vergangenheit
        status = rnd.choices(["abgeschlossen", "abgelehnt", "storniert", "verspaetet"], [0.78, 0.09, 0.08, 0.05])[0]
    elif von <= STICHTAG <= bis:                        # Gegenwart
        status = rnd.choices(["laufend", "bestaetigt", "angefragt"], [0.7, 0.15, 0.15])[0]
    else:                                               # Zukunft
        status = rnd.choices(["angefragt", "bestaetigt", "abgelehnt", "storniert"], [0.45, 0.4, 0.1, 0.05])[0]
    if status in ("laufend", "abgeschlossen", "verspaetet"):
        uebergeben = von
    if status == "abgeschlossen":
        zurueck = bis - timedelta(days=rnd.choice([0, 0, 0, 1, 2])) if rnd.random() < 0.9 else bis + timedelta(days=rnd.randint(1, 5))
        zurueck = max(zurueck, uebergeben)
    if status == "angefragt":
        entschieden = None
    if status != "abgelehnt" and status != "storniert":
        e["belegt"].append((von, bis))
    aid = add("ausleihe", ausleihe_id=len(ausleihen) + 1, exemplar_id=e["id"], ausleiher_id=a["id"],
              zeitraum_von=von, zeitraum_bis=bis, status=status, angefragt_am=angefragt,
              entschieden_am=entschieden, uebergeben_am=uebergeben, zurueckgegeben_am=zurueck)
    ausleihen.append({"id": aid, "ex": e, "ausleiher": a["id"], "von": von, "bis": bis, "status": status,
                      "angefragt": angefragt, "zurueck": zurueck})

sendungs_nr = 300000000
for al in ausleihen:
    if al["status"] not in ("bestaetigt", "laufend", "abgeschlossen", "verspaetet"):
        continue
    art = POSTVERSAND if (al["ex"]["versand"] and rnd.random() < 0.45) else ABHOLUNG
    kosten = rnd.choice([2.75, 4.50, 5.49, 6.99])
    wege = [("hinweg", al["von"])]
    if al["status"] == "abgeschlossen":
        wege.append(("rueckweg", al["zurueck"]))
    for richtung, tag in wege:
        erfolgt = ts(tag, rnd.randint(9, 20)) if al["status"] != "bestaetigt" else None
        if art == ABHOLUNG:
            zid = neuer_zeitslot(tag, rnd.choice([10, 12, 17, 18, 19]), 1)
            add("uebergabe", uebergabe_id=len(rows.get("uebergabe", [])) + 1, ausleihe_id=al["id"], zeitslot_id=zid,
                uebergabeart_id=ABHOLUNG, richtung=richtung, sendungsnummer=None, versandkosten=None, erfolgt_am=erfolgt)
        else:
            sendungs_nr += rnd.randint(1000, 99999)
            add("uebergabe", uebergabe_id=len(rows.get("uebergabe", [])) + 1, ausleihe_id=al["id"], zeitslot_id=None,
                uebergabeart_id=POSTVERSAND, richtung=richtung, sendungsnummer=f"DHL{sendungs_nr}DE",
                versandkosten=kosten, erfolgt_am=erfolgt)

# ---------------------------------------------------------------- Community
abgeschlossen = [al for al in ausleihen if al["status"] == "abgeschlossen"]
for al in abgeschlossen:
    erstellt = ts(al["zurueck"], rnd.randint(9, 22)) + timedelta(days=rnd.randint(0, 6))
    if rnd.random() < 0.6:                              # Regel 2a: ausleihende Person bewertet das Werk
        add("bewertung_werk", bewertung_werk_id=len(rows.get("bewertung_werk", [])) + 1,
            werk_id=al["ex"]["werk"], verfasser_id=al["ausleiher"], ausleihe_id=al["id"],
            sterne=rnd.choices([1, 2, 3, 4, 5], [0.04, 0.08, 0.2, 0.38, 0.3])[0],
            kommentar=(rnd.choice(KOMMENTARE_WERK) if rnd.random() < 0.7 else None),
            erstellt_am=erstellt, gemeldet=(rnd.random() < 0.05))
    if rnd.random() < 0.65:                             # Regel 2b: Parteien bewerten sich gegenseitig
        paare = [(al["ausleiher"], al["ex"]["besitzer"])]
        if rnd.random() < 0.7:
            paare.append((al["ex"]["besitzer"], al["ausleiher"]))
        for bewertender, bewerteter in paare:
            add("bewertung_person", bewertung_person_id=len(rows.get("bewertung_person", [])) + 1,
                bewertender_id=bewertender, bewerteter_id=bewerteter, ausleihe_id=al["id"],
                sterne=rnd.choices([2, 3, 4, 5], [0.05, 0.15, 0.35, 0.45])[0],
                kommentar=(rnd.choice(KOMMENTARE_PERSON) if rnd.random() < 0.6 else None),
                erstellt_am=erstellt + timedelta(hours=rnd.randint(1, 48)))

for al in rnd.sample(ausleihen, 45):
    a, b = al["ausleiher"], al["ex"]["besitzer"]
    t = al["angefragt"]
    for k, text in enumerate(NACHRICHTEN[:rnd.randint(2, 5)]):
        t += timedelta(minutes=rnd.randint(5, 600))
        add("nachricht", nachricht_id=len(rows.get("nachricht", [])) + 1,
            absender_id=(a if k % 2 == 0 else b), empfaenger_id=(b if k % 2 == 0 else a),
            ausleihe_id=al["id"], text=text.format(tag=al["von"].strftime("%d.%m.")),
            gesendet_am=t, gelesen=(t.date() < STICHTAG - timedelta(days=2) or rnd.random() < 0.5))
for _ in range(8):                                      # Nachrichten ohne Vorgangsbezug
    a, b = rnd.sample(benutzer, 2)
    add("nachricht", nachricht_id=len(rows["nachricht"]) + 1, absender_id=a["id"], empfaenger_id=b["id"],
        ausleihe_id=None, text=rnd.choice(["Hast du zufällig noch andere Bücher von dieser Autorin?",
                                           "Danke für den Tipp neulich!", "Wohnst du auch in Bornheim?",
                                           "Ich suche noch einen Krimi fürs Wochenende, Empfehlung?"]),
        gesendet_am=ts(fake.date_between_dates(date(2026, 3, 1), STICHTAG), rnd.randint(8, 22)), gelesen=(rnd.random() < 0.7))

# ---------------------------------------------------------------- Ausgabe
ORDER = ["rolle", "benutzer", "adresse", "benutzer_rolle", "autor", "verlag", "sprache", "genre", "werk",
         "werk_autor", "werk_genre", "zustand", "exemplar", "zeitslot", "uebergabeart", "verfuegbarkeit",
         "ausleihe", "uebergabe", "bewertung_werk", "bewertung_person", "nachricht"]
SERIAL_PK = {t: t + "_id" for t in ORDER if t not in ("benutzer_rolle", "werk_autor", "werk_genre")}

out = ["-- =====================================================================",
       "-- Dummy-Daten der Buchtausch-App — ERZEUGT durch tools/build_seed.py",
       f"-- Zufalls-Seed {SEED}, Stichtag {STICHTAG} (Statusverteilung der Ausleihen bezieht sich",
       "-- auf diesen festen Tag, nicht auf now(): jeder Lauf erzeugt identische Daten).",
       "-- Nicht von Hand ändern: Änderung im Generator, dann `python3 build_seed.py`.",
       "--",
       "-- Adressen liegen in Frankfurt am Main (Nordend, Bornheim, Ostend, Sachsenhausen,",
       "-- Bockenheim, Innenstadt), damit die Umkreissuche sinnvolle Treffer liefert.",
       "-- Bibliografische Angaben sind echt; ISBNs, Ausgaben-Verlage, Übersetzer:innen und",
       "-- alle Personen sind fiktiv. Passwort-Hashes sind Platzhalter im bcrypt-Format.",
       "--",
       "-- Bewusste Abweichung von „>= 10 Einträge je Tabelle“: rolle (3), uebergabeart (2)",
       "-- und zustand (5) sind Stammdaten mit fachlich begrenzter Wertemenge.",
       "-- =====================================================================", "",
       "BEGIN;", ""]
for tab in ORDER:
    r = rows[tab]
    cols = list(r[0].keys())
    out.append(f"-- {tab}: {len(r)} Zeilen")
    out.append(f"INSERT INTO {tab} ({', '.join(cols)}) VALUES")
    out.append(",\n".join("  (" + ", ".join(q(z[c]) for c in cols) + ")" for z in r) + ";")
    if tab in SERIAL_PK:
        out.append(f"SELECT setval(pg_get_serial_sequence('{tab}', '{SERIAL_PK[tab]}'), {len(r)});")
    out.append("")
    counts[tab] = len(r)
out += ["COMMIT;", "",
        "-- Zeilen je Tabelle:"] + [f"--   {t:<18} {n:>4}" for t, n in counts.items()] + [""]
OUT.write_text("\n".join(out), encoding="utf-8")
print(f"{OUT.name}: {sum(counts.values())} Zeilen in {len(counts)} Tabellen")
for t, n in counts.items():
    print(f"  {t:<18} {n:>4}{'   (<10, Stammdaten, bewusst)' if n < 10 else ''}")
