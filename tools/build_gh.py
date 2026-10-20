#!/usr/bin/env python3
"""Link zum GitHub-Repository (_GH) der Abschlussphase als Word-Datei.

Schreibt abgabe/03_Finalisierungsphase/Abschlussphase_GH.docx: eine Seite im
Layout von build_kz.py (A4, 2 cm Rand, Arial 11, Kopfzeile Name ·
Matrikelnummer · Modul · Datum) mit Titel, Name, Matrikelnummer, Kurs, der
Repository-URL als anklickbarem Hyperlink und als reinem Text, Inhaltszeile
und Erstellungsdatum. Der PDF-Export erfolgt aus Word (ExportAsFixedFormat),
der Hyperlink wird dabei zur Link-Annotation im PDF.

Aufruf: python tools/build_gh.py
"""
import datetime
from pathlib import Path

from docx import Document
from docx.opc.constants import RELATIONSHIP_TYPE as RT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

from build_kz import BLAU, GRAU, SCHRIFT, absatz, linie
from build_sqlpdf import titel_daten

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "abgabe" / "03_Finalisierungsphase" / "Abschlussphase_GH.docx"

URL = "https://github.com/Ta-Rahman/buchtausch-portfolio"
KURS = "DLBDSPBDM01_D – Data-Mart-Erstellung in SQL"
INHALT = "Code, SQL, Berichte, README mit Installationsanleitung"
LINK_FARBE = RGBColor(0x05, 0x63, 0xC1)


def run(p, text, bold=False):
    r = p.add_run(text)
    r.font.name = SCHRIFT
    r.font.size = Pt(11)
    r.font.bold = bold
    return r


def hyperlink(p, url):
    """Externer Hyperlink: Run in w:hyperlink mit Beziehung auf die URL, blau unterstrichen."""
    rid = p.part.relate_to(url, RT.HYPERLINK, is_external=True)
    r = run(p, url)
    r.font.color.rgb = LINK_FARBE
    r.font.underline = True
    h = OxmlElement("w:hyperlink")
    h.set(qn("r:id"), rid)
    r._r.addprevious(h)
    h.append(r._r)


def zeile(doc, beschriftung, wert=None, link=None):
    """Eine Angabe: fette Beschriftung, dann Wert als Text oder als Hyperlink."""
    p = absatz(doc, f"{beschriftung}: ", size=11, bold=True, after=6)
    if link:
        hyperlink(p, link)
    else:
        run(p, wert)


def main():
    ti = titel_daten()
    datum = datetime.date.today().strftime("%d.%m.%Y")

    doc = Document()
    sec = doc.sections[0]
    sec.page_height, sec.page_width = Cm(29.7), Cm(21.0)
    for seite in ("top_margin", "bottom_margin", "left_margin", "right_margin"):
        setattr(sec, seite, Cm(2.0))
    doc.styles["Normal"].font.name = SCHRIFT
    doc.styles["Normal"].font.size = Pt(11)
    doc.core_properties.author = ti["name"]
    doc.core_properties.title = "Link zum GitHub-Repository"

    # Kopfzeile wie build_kz.py: Nachname, Vorname(n) · Matrikelnummer · Modul · Datum
    teile = ti["name"].split()
    kopfname = f"{teile[-1]}, {' '.join(teile[:-1])}" if len(teile) > 1 else ti["name"]
    kopf = absatz(doc, f"{kopfname}  ·  Matrikelnummer {ti['matrikel']}  ·  DLBDSPBDM01_D  ·  {datum}",
                  size=8.5, color=GRAU, after=2)
    linie(kopf)
    absatz(doc, "Portfolio – Abschlussphase", size=14, bold=True, color=BLAU, after=3)
    absatz(doc, "Link zum GitHub-Repository", size=12, bold=True, after=12)

    zeile(doc, "Name", ti["name"])
    zeile(doc, "Matrikelnummer", ti["matrikel"])
    zeile(doc, "Kurs", KURS)
    zeile(doc, "Repository", link=URL)
    zeile(doc, "URL als Text", URL)
    zeile(doc, "Inhalt", INHALT)
    zeile(doc, "Erstellt am", datum)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUT)
    print(f"geschrieben: {OUT.relative_to(ROOT)}  (Hyperlink {URL})")


if __name__ == "__main__":
    main()
