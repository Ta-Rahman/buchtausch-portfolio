const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, PageOrientation,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle, ImageRun,
  Footer, PageNumber, convertMillimetersToTwip,
} = require('docx');

const FONT = 'Arial';
const dict = JSON.parse(fs.readFileSync('dict_data.json', 'utf8'));

// TEST-Modus: Hinweiskästen weglassen und Platzhalter durch Blindtext in
// Zielwortzahl ersetzen — so lässt sich die reale Seitenzahl der Abgabe prüfen.
const TEST = process.env.MODE === 'test';
const LOREM = ('Die Anwendung ermöglicht es Mitgliedern einer Nachbarschaft ihre eigenen Bücher '
  + 'zeitweise zu verleihen und im Gegenzug Titel anderer Mitglieder auszuleihen wobei jeder '
  + 'Vorgang nachvollziehbar dokumentiert wird und die Datenbank die fachlichen Regeln selbst '
  + 'durchsetzt anstatt sie der Anwendungsschicht zu überlassen was Konsistenz auch dann '
  + 'sicherstellt wenn mehrere Zugriffswege existieren ').split(' ').filter(Boolean);
const filler = (n) => Array.from({ length: n }, (_, i) => LOREM[i % LOREM.length]).join(' ') + '.';

// ---------- Bausteine -------------------------------------------------------
const t = (text, o = {}) => new TextRun({ text, font: FONT, size: o.size ?? 22, ...o });

const body = (text, o = {}) =>
  new Paragraph({
    alignment: o.align ?? AlignmentType.JUSTIFIED,
    spacing: { after: 80, line: 258 },
    children: [t(text, o)],
  });

/** Grau hinterlegter Hinweiskasten – vom Studierenden zu löschen. */
const hint = (lines, budget) => TEST ? new Paragraph({ children: [] }) :
  new Paragraph({
    spacing: { before: 60, after: 200 },
    shading: { type: ShadingType.CLEAR, fill: 'F2F4F7' },
    border: { left: { style: BorderStyle.SINGLE, size: 18, color: '9AA5B1', space: 8 } },
    indent: { left: 140 },
    children: [
      t(budget ? `► ${budget}   ` : '► ', { bold: true, size: 17, color: '3A4A5A' }),
      ...lines.flatMap((l, i) => [
        t(l, { size: 17, italics: true, color: '3A4A5A' }),
        ...(i < lines.length - 1 ? [new TextRun({ break: 1 })] : []),
      ]),
    ],
  });

const placeholder = (woerter = 0) => TEST && woerter
  ? body(filler(woerter))
  : new Paragraph({
    spacing: { after: 200 },
    children: [t('[Hier deinen Text einfügen — diesen Platzhalter überschreiben.]',
      { color: 'B00020', italics: true })],
  });


/** Lauftitel: Überschrift und Text im selben Absatz — spart je Abschnitt eine Zeile. */
const runIn = (titel, woerter) => new Paragraph({
  alignment: AlignmentType.JUSTIFIED, spacing: { before: 80, after: 80, line: 264 },
  children: TEST
    ? [t(`${titel}  `, { bold: true, color: '2F5597' }), t(filler(woerter))]
    : [t(`${titel}  `, { bold: true, color: '2F5597' }),
       t('[Hier deinen Text einfügen.]', { color: 'B00020', italics: true })],
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
const rollen = [
  'Gast (nicht angemeldet)',
  'Mitglied – Konto und Profil',
  'Mitglied als Verleiher:in',
  'Mitglied als Ausleiher:in',
  'Moderator:in',
  'Administrator:in',
];

const CW = [3200, 6438]; // Summe 9638 DXA = 17 cm Textbreite
const cell = (children, w, o = {}) => new TableCell({
  width: { size: w, type: WidthType.DXA },
  margins: { top: 60, bottom: 60, left: 100, right: 100 },
  shading: o.fill ? { type: ShadingType.CLEAR, fill: o.fill } : undefined,
  children,
});

const rollenTabelle = new Table({
  columnWidths: CW,
  width: { size: 9638, type: WidthType.DXA },
  rows: [
    new TableRow({
      tableHeader: true,
      children: [
        cell([new Paragraph({ children: [t('Rolle', { bold: true, size: 20 })] })], CW[0], { fill: 'E8EEF7' }),
        cell([new Paragraph({ children: [t('Aktionen', { bold: true, size: 20 })] })], CW[1], { fill: 'E8EEF7' }),
      ],
    }),
    ...rollen.map((r) => new TableRow({
      children: [
        cell([new Paragraph({ children: [t(r, { size: 20 })] })], CW[0]),
        cell([new Paragraph({ children: [TEST
          ? t(filler(28), { size: 20 })
          : t('[deine Aufzählung]', { size: 20, color: 'B00020', italics: true })] })], CW[1]),
      ],
    })),
  ],
});

const teilA = [
  h1('Teil A – Anforderungsspezifikation'),
  hint(['Maximal 2 Seiten. Die Wortbudgets sind gemessen: mit ihnen passt die Abgabe exakt auf 4 Seiten.','Alle grauen Hinweiskästen und roten Platzhalter vor der Abgabe löschen.'], 'Teil A'),

  h2('A1 Ausgangslage und Problemstellung'),
  hint(['Welches konkrete Alltagsproblem löst die Anwendung?',
        'Warum reicht ein Aushang am schwarzen Brett nicht?',
        'Warum braucht es überhaupt eine Datenbank?'], 'A1 · ca. 85 Wörter'),
  placeholder(85),

  h2('A2 Zielsetzung und Abgrenzung'),
  hint(['Was liefert dieses Projekt — und was ausdrücklich nicht?',
        'Ausschlüsse explizit benennen: Zahlungsabwicklung, Frontend, Authentifizierung, Benachrichtigungen.',
        'Eine bewusst gezogene Grenze wirkt souverän; eine unausgesprochene wirkt wie Vergessen.'], 'A2 · ca. 85 Wörter'),
  placeholder(85),

  h2('A3 Rollen'),
  hint(['Welche Rollen gibt es, und warum sind Verleihen und Ausleihen KEINE getrennten Personentypen?',
        'Hier gehört das Normalisierungsargument hin: dieselbe Person ist in der einen Transaktion',
        'Verleiherin, in der anderen Ausleiherin. Das ist ein inhaltlicher Treffer, kein formaler.'], 'A3 · ca. 115 Wörter'),
  placeholder(115),

  h2('A4 Aktionen je Rolle'),
  hint(['Tabelle ausfüllen — spart gegenüber Fließtext viel Platz.',
        'Gesamten Lebenszyklus abdecken: Einstellen → Suchen → Anfragen → Entscheiden → Übergeben → Zurückgeben → Bewerten.'], 'A4 · ca. 25 Wörter je Rolle'),
  // Fließtext durchgehend 11 pt gemäß Aufgabenstellung — auch hier, obwohl
  // 10 pt Platz sparen würde. Der Test zeigt: 11 pt passt noch auf vier Seiten.
  ...rollen.map((r) => new Paragraph({
    alignment: AlignmentType.JUSTIFIED, spacing: { after: 50, line: 252 },
    children: [t(`${r}:  `, { bold: true }),
      TEST ? t(filler(26))
           : t('[deine Aufzählung]', { color: 'B00020', italics: true })],
  })),
  new Paragraph({ spacing: { after: 80 }, children: [t('')] }),

  h2('A5 Erforderliche Daten und Funktionen'),
  hint(['Der wichtigste Absatz des Dokuments: die Trennung von WERK (Titel als bibliografische Einheit)',
        'und EXEMPLAR (physisches Buch einer bestimmten Person). In zwei bis drei Sätzen begründen.',
        'Außerdem: für die Umkreissuche werden Geokoordinaten gebraucht, kein Ortsname als Text.'], 'A5 · ca. 140 Wörter'),
  placeholder(140),

  h2('A6 Zentrale Geschäftsregeln'),
  hint(['Welche Regeln muss die Datenbank erzwingen — nicht die App? Vier Kandidaten:',
        '(1) Kein Exemplar in überlappenden Zeiträumen zweimal verliehen.',
        '(2) Bewertung nur zu einer abgeschlossenen eigenen Ausleihe.',
        '(3) Maximale Leihdauer des Exemplars nicht überschreitbar.',
        '(4) Nur definierte Statusübergänge einer Ausleihe erlaubt.',
        'Diese Regeln sind gleichzeitig deine Testfälle in Phase 2.'], 'A6 · ca. 85 Wörter'),
  placeholder(85),
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
  hint(['Im Fließtext benennen: gewählte Notation, Anzahl Entitäten, die drei Dreifachbeziehungen',
        'und die Trennung Werk/Exemplar. Kardinalitäten stehen an jeder Beziehungslinie.'], 'Seite 3'),
];

// ---------- Datenwörterbuch + Teil B ---------------------------------------
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

const teilB = [
  h1('Teil B – Beschreibung der Arbeit und der Arbeitsschritte'),
  hint(['Nur noch rund 430 Wörter für alle sechs Abschnitte — ein bis zwei Sätze je Leitfrage.',
        'Die Leitfragen stammen wörtlich aus dem Prüfungsleitfaden, deshalb bleiben alle sechs erhalten.',
        'Wenn du kürzen musst: lieber B1 und B3 straffen als B5.'], 'Teil B'),

    hint(['Ein präziser Absatz.'], 'B1 · ca. 40 Wörter'),
  runIn('B1 Ziel der Arbeit', 40),

    hint(['Was spricht für die Idee, was dagegen? Wo liegen die Risiken?',
        'Diese Frage steht wörtlich im Leitfaden und wird von den meisten übersprungen.',
        'Ein ehrlicher Satz über Grenzen wirkt reflektiert und kostet nichts.'], 'B2 · ca. 60 Wörter'),
  runIn('B2 Idee und ihre Tragfähigkeit', 60),

    hint(['Vom Einstellen eines Buchs bis zur Rückgabe in einem Fluss.'], 'B3 · ca. 45 Wörter'),
  runIn('B3 Konzept der Arbeit', 45),

    hint(['Drei Phasen, Zwischenergebnisse, Feedbackschleifen. Zahlt auf „Methodik/Vorgehen" (20 %) ein.'], 'B4 · ca. 45 Wörter'),
  runIn('B4 Geplantes Vorgehen', 45),

    hint(['Der bestbezahlte Abschnitt. Der Leitfaden verlangt die Dokumentation des Werkzeugeinsatzes ausdrücklich.',
        'Je ein Satz: Wahl, Alternative, Entscheidungsgrund — für PostgreSQL, Docker, PostGIS und das Diagrammwerkzeug.',
        'Nüchtern begründen, keine Werbeprosa.'], 'B5 · ca. 85 Wörter'),
  runIn('B5 Methodik und Werkzeugwahl', 85),

    hint(['Was liegt vor (Spezifikation, ERM, Datenwörterbuch), was folgt in Phase 2.'], 'B6 · ca. 30 Wörter'),
  runIn('B6 Ergebnis dieser Phase und Ausblick', 30),
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
    // Querformat-Abschnitt zuletzt: jeder Abschnittswechsel erzwingt einen
    // Seitenumbruch. Am Ende kostet das keine angebrochene Seite.
    { properties: { page: { margin: { top: M, bottom: M, left: M, right: M },
        size: { orientation: PageOrientation.LANDSCAPE } } },
      footers: fussz, children: teilDiagramm },
  ],
});

Packer.toBuffer(doc).then((b) => {
  fs.writeFileSync('Vorlage_Konzeptionsphase.docx', b);
  console.log('Vorlage_Konzeptionsphase.docx geschrieben');
});
