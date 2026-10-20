// Finale Abgabedatei Konzeptionsphase — Layout identisch zu tools/build_template.js,
// Hinweiskästen entfernt, Platzhalter durch die abgenommenen Texte ersetzt.
const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, PageOrientation,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle, ImageRun,
  Footer, PageNumber, convertMillimetersToTwip,
} = require('docx');

const FONT = 'Arial';
const dict = JSON.parse(fs.readFileSync('dict_data.json', 'utf8'));
const TXT = JSON.parse(fs.readFileSync('texte.json', 'utf8'));

const t = (text, o = {}) => new TextRun({ text, font: FONT, size: o.size ?? 22, ...o });

const body = (text, o = {}) =>
  new Paragraph({
    alignment: o.align ?? AlignmentType.JUSTIFIED,
    spacing: { after: o.after ?? 80, line: 258 },
    children: [t(text, o)],
  });

const runIn = (titel, text) => new Paragraph({
  alignment: AlignmentType.JUSTIFIED, spacing: { before: 80, after: 80, line: 264 },
  children: [t(`${titel}  `, { bold: true, color: '2F5597' }), t(text)],
});

const runInRuns = (titel, runs) => new Paragraph({
  alignment: AlignmentType.JUSTIFIED, spacing: { before: 80, after: 80, line: 264 },
  children: [t(`${titel}  `, { bold: true, color: '2F5597' }), ...runs],
});

const h1 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_1, spacing: { before: 150, after: 60 },
  children: [t(text, { bold: true, size: 26, color: '1F3864' })],
});

const h2 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_2, spacing: { before: 110, after: 40 },
  children: [t(text, { bold: true, size: 24, color: '2F5597' })],
});

// ---------- Deckzeile -------------------------------------------------------
const kopf = [
  new Paragraph({
    spacing: { after: 40 },
    children: [t('[Nachname, Vorname]  ·  Matrikelnummer [XXXXXXXX]  ·  DLBDSPBDM01_D  ·  [Datum]',
      { size: 18, color: '555555' })],
  }),
  new Paragraph({
    border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: '1F3864', space: 4 } },
    spacing: { after: 120 }, children: [t('')],
  }),
  new Paragraph({
    spacing: { after: 60 },
    children: [t('Portfolio – Konzeptionsphase', { bold: true, size: 28, color: '1F3864' })],
  }),
  new Paragraph({
    spacing: { after: 180 },
    children: [t('Data-Mart-Erstellung in SQL: Datenbank für eine Buchtausch-App',
      { size: 24, color: '444444' })],
  }),
];

// ---------- Teil A ----------------------------------------------------------
const rollen = Object.keys(TXT.A4);

const teilA = [
  h1('Teil A – Anforderungsspezifikation'),

  h2('A1 Ausgangslage und Problemstellung'),
  body(TXT.A1, { after: 200 }),

  h2('A2 Zielsetzung und Abgrenzung'),
  body(TXT.A2, { after: 200 }),

  h2('A3 Rollen'),
  body(TXT.A3, { after: 200 }),

  h2('A4 Aktionen je Rolle'),
  ...rollen.map((r) => new Paragraph({
    alignment: AlignmentType.JUSTIFIED, spacing: { after: 50, line: 252 },
    children: [t(`${r}:  `, { bold: true }), t(TXT.A4[r])],
  })),
  new Paragraph({ spacing: { after: 80 }, children: [t('')] }),

  h2('A5 Erforderliche Daten und Funktionen'),
  body(TXT.A5, { after: 200 }),

  h2('A6 Zentrale Geschäftsregeln'),
  body(TXT.A6_intro, { after: 40 }),
  ...TXT.A6_regeln.map((r) => new Paragraph({
    alignment: AlignmentType.JUSTIFIED, spacing: { after: 30, line: 252 },
    indent: { left: 240 },
    children: [t(r)],
  })),
  body(TXT.A6_schluss, { after: 200 }),
];

// ---------- Querformat-Abschnitt: ER-Diagramm -------------------------------
const bild = fs.readFileSync('ER-Modell_Buchtausch.png');
const teilDiagramm = [
  h1('Entity-Relationship-Modell'),
  new Paragraph({
    alignment: AlignmentType.CENTER, spacing: { after: 80 },
    children: [new ImageRun({ type: 'png', data: bild, transformation: { width: 745, height: 541 } })],
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER, spacing: { after: 60 },
    children: [t('Abbildung 1: Datenmodell der Buchtausch-App in Krähenfuß-Notation. '
      + '21 Entitäten, 29 Beziehungen, drei Dreifachbeziehungen (verfuegbarkeit, uebergabe, bewertung_person). '
      + 'PK/FK/UK = Primär-, Fremd-, eindeutiger Schlüssel; vollständige Attribute siehe Datenwörterbuch. '
      + 'Farben: blau = Personen, grün = Stammdaten, orange = Besitz, rot = Transaktion, violett = Community.', { size: 17, color: '444444' })],
  }),
];

// ---------- Datenwörterbuch -------------------------------------------------
const woerterbuch = [
  h1('Datenwörterbuch (Kompaktfassung)'),
  new Paragraph({
    spacing: { after: 120 },
    children: [
      t('21 Entitäten, 108 Attribute. ', { size: 17 }),
      t('Fett', { size: 17, bold: true }), t(' = Primärschlüssel, ', { size: 17 }),
      t('kursiv', { size: 17, italics: true }), t(' = Fremdschlüssel, ° = eindeutig. ', { size: 17 }),
      t('Datentypen für PostgreSQL. Die ausführliche Fassung mit Beschreibung jedes Attributs liegt im GitHub-Repository.', { size: 17 }),
    ],
  }),
];

for (const g of dict) {
  woerterbuch.push(new Paragraph({
    spacing: { before: 46, after: 20 },
    children: [t(g.gruppe, { bold: true, size: 18, color: '2F5597' })],
  }));
  for (const e of g.entitaeten) {
    const runs = [
      t(e.name, { bold: true, size: 17 }),
      t(e.ternaer ? ' ⟨3er⟩' : '', { size: 15, color: '94355A' }),
      t(': ', { size: 17, color: '444444' }),
    ];
    e.attrs.forEach((a, i) => {
      const isPK = a.k.includes('PK');
      const isFK = a.k.includes('FK');
      runs.push(t(a.n + (a.k.includes('UK') ? '°' : ''),
        { size: 17, bold: isPK, italics: isFK && !isPK }));
      runs.push(t(` ${a.t}`, { size: 14, color: '666666' }));
      if (i < e.attrs.length - 1) runs.push(t(' · ', { size: 17, color: '999999' }));
    });
    woerterbuch.push(new Paragraph({
      alignment: AlignmentType.JUSTIFIED, spacing: { after: 18 }, children: runs,
    }));
  }
}

// ---------- Teil B ----------------------------------------------------------
const b5runs = TXT.B5.flatMap(([name, rest]) => [t(name, { bold: true }), t(rest)]);

const teilB = [
  h1('Teil B – Beschreibung der Arbeit und der Arbeitsschritte'),
  runIn('B1 Ziel der Arbeit', TXT.B1),
  runIn('B2 Idee und ihre Tragfähigkeit', TXT.B2),
  runIn('B3 Konzept der Arbeit', TXT.B3),
  runIn('B4 Geplantes Vorgehen', TXT.B4),
  runInRuns('B5 Methodik und Werkzeugwahl', b5runs),
  runIn('B6 Ergebnis dieser Phase und Ausblick', TXT.B6),
];

// ---------- Dokument --------------------------------------------------------
const M = convertMillimetersToTwip(20);
const fussz = {
  default: new Footer({
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [t('Seite ', { size: 16, color: '888888' }),
        new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 16, color: '888888' }),
        t(' von ', { size: 16, color: '888888' }),
        new TextRun({ children: [PageNumber.TOTAL_PAGES], font: FONT, size: 16, color: '888888' })],
    })],
  }),
};

const doc = new Document({
  creator: '[Nachname, Vorname]',
  title: 'Portfolio Konzeptionsphase – DLBDSPBDM01_D',
  styles: { default: { document: { run: { font: FONT, size: 22 } } } },
  sections: [
    { properties: { page: { margin: { top: M, bottom: M, left: M, right: M } } },
      footers: fussz, children: [...kopf, ...teilA, ...woerterbuch, ...teilB] },
    { properties: { page: { margin: { top: M, bottom: M, left: M, right: M },
        size: { orientation: PageOrientation.LANDSCAPE } } },
      footers: fussz, children: teilDiagramm },
  ],
});

Packer.toBuffer(doc).then((b) => {
  fs.writeFileSync('Konzeptionsphase_AB.docx', b);
  console.log('Konzeptionsphase_AB.docx geschrieben');
});
