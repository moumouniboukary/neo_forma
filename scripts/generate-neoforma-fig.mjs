/**
 * NeoForma — complete native Figma .fig (22 screens + design system + flows)
 * Usage: node generate-neoforma-fig.mjs
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import sharp from "sharp";
import { Zstd } from "@hpcc-js/wasm-zstd";
import {
  createEmptyFigDoc,
  encodeFigParts,
  assembleCanvasFig,
  createFigZip,
  makeSolidPaint,
  parseFig,
} from "openfig-core";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(__dirname, "..", "DAMINA&POESAM_2026", "NeoForma_App.fig");

const C = {
  bg: "#07140F",
  surface: "#0F3D2E",
  card: "#1A4D38",
  card2: "#0F2D22",
  elevated: "#245C46",
  green: "#1D9E75",
  greenLt: "#5DCAA5",
  greenXs: "#9FE1CB",
  text: "#E1F5EE",
  dim: "#5DCAA5",
  amber: "#EF9F27",
  coral: "#D85A30",
  border: "#1D4D38",
  black: "#050D09",
  ok: "#3DBF8C",
};

const PHONE_W = 390;
const PHONE_H = 844;
const GAP_X = 64;
const GAP_Y = 96;
const COLS = 4;

let localId = 10;
const nextGuid = () => ({ sessionID: 1, localID: localId++ });

function posGen() {
  let n = 0;
  const chars = [];
  for (let i = 33; i < 127; i++) chars.push(String.fromCharCode(i));
  return () => {
    const a = chars[Math.floor(n / chars.length) % chars.length];
    const b = chars[n % chars.length];
    n++;
    return a + b;
  };
}

const t = (x, y) => ({ m00: 1, m01: 0, m02: x, m10: 0, m11: 1, m12: y });
const paint = (hex) => makeSolidPaint(hex);

function hexToRgb(hex) {
  const h = hex.replace("#", "");
  return {
    r: parseInt(h.slice(0, 2), 16) / 255,
    g: parseInt(h.slice(2, 4), 16) / 255,
    b: parseInt(h.slice(4, 6), 16) / 255,
    a: 1,
  };
}

function frame(parent, name, x, y, w, h, opts = {}) {
  const guid = nextGuid();
  const node = {
    guid,
    phase: "CREATED",
    type: "FRAME",
    name,
    parentIndex: { guid: parent, position: opts.pos },
    visible: true,
    opacity: 1,
    size: { x: w, y: h },
    transform: t(x, y),
    fillPaints: opts.fill ? [paint(opts.fill)] : [],
    cornerRadius: opts.radius ?? 0,
    frameMaskDisabled: opts.clip === false,
  };
  if (opts.stroke) {
    node.strokePaints = [paint(opts.stroke)];
    node.strokeWeight = opts.strokeWeight ?? 1.5;
    node.strokeAlign = "INSIDE";
  }
  return node;
}

function rect(parent, name, x, y, w, h, opts = {}) {
  return {
    guid: nextGuid(),
    phase: "CREATED",
    type: "ROUNDED_RECTANGLE",
    name,
    parentIndex: { guid: parent, position: opts.pos },
    visible: true,
    opacity: opts.opacity ?? 1,
    size: { x: w, y: h },
    transform: t(x, y),
    fillPaints: opts.fill ? [paint(opts.fill)] : [],
    cornerRadius: opts.radius ?? 0,
    strokeWeight: opts.stroke ? opts.strokeWeight ?? 1.5 : 0,
    strokeAlign: "INSIDE",
    strokePaints: opts.stroke ? [paint(opts.stroke)] : [],
  };
}

function ellipse(parent, name, x, y, w, h, opts = {}) {
  return {
    guid: nextGuid(),
    phase: "CREATED",
    type: "ELLIPSE",
    name,
    parentIndex: { guid: parent, position: opts.pos },
    visible: true,
    opacity: opts.opacity ?? 1,
    size: { x: w, y: h },
    transform: t(x, y),
    fillPaints: opts.fill ? [paint(opts.fill)] : [],
    strokeWeight: opts.stroke ? opts.strokeWeight ?? 2 : 0,
    strokePaints: opts.stroke ? [paint(opts.stroke)] : [],
  };
}

function text(parent, name, characters, x, y, w, h, opts = {}) {
  const weight = opts.bold ? "Bold" : opts.medium ? "Medium" : "Regular";
  const family = opts.mono ? "Roboto Mono" : "Inter";
  const post = opts.mono
    ? weight === "Bold"
      ? "RobotoMono-Bold"
      : "RobotoMono-Regular"
    : weight === "Bold"
      ? "Inter-Bold"
      : weight === "Medium"
        ? "Inter-Medium"
        : "Inter-Regular";
  return {
    guid: nextGuid(),
    phase: "CREATED",
    type: "TEXT",
    name,
    parentIndex: { guid: parent, position: opts.pos },
    visible: true,
    opacity: 1,
    size: { x: w, y: h },
    transform: t(x, y),
    textData: { characters: String(characters) },
    fontSize: opts.size ?? 14,
    fontName: { family, style: weight, postscript: post },
    fillPaints: [paint(opts.color ?? C.text)],
    textAlignHorizontal: opts.align ?? "LEFT",
    textAlignVertical: "CENTER",
    textAutoResize: "NONE",
  };
}

function addCanvas(doc, name, position) {
  const guid = nextGuid();
  doc.message.nodeChanges.push({
    guid,
    phase: "CREATED",
    type: "CANVAS",
    name,
    parentIndex: { guid: { sessionID: 0, localID: 0 }, position },
    visible: true,
    backgroundColor: hexToRgb(C.bg),
    backgroundEnabled: true,
  });
  return guid;
}

function hdr(root, title, cy, p, nodes, opts = {}) {
  nodes.push(rect(root, "hdr", 0, cy, PHONE_W, 52, { pos: p(), fill: C.card2 }));
  if (opts.back !== false) {
    nodes.push(
      rect(root, "back", 14, cy + 14, 24, 24, {
        pos: p(),
        fill: C.elevated,
        radius: 6,
      })
    );
    nodes.push(
      text(root, "back-t", "‹", 14, cy + 14, 24, 24, {
        pos: p(),
        size: 16,
        color: C.greenLt,
        align: "CENTER",
      })
    );
  }
  nodes.push(
    text(root, "ht", title, opts.back === false ? 20 : 48, cy + 14, 240, 24, {
      pos: p(),
      size: 16,
      bold: true,
      color: C.greenXs,
    })
  );
  if (opts.pill) {
    nodes.push(
      rect(root, "pill", 300, cy + 14, 70, 24, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
        radius: 999,
      })
    );
    nodes.push(
      text(root, "pill-t", opts.pill, 300, cy + 14, 70, 24, {
        pos: p(),
        size: 10,
        bold: true,
        color: C.greenLt,
        align: "CENTER",
      })
    );
  }
}

function btn(parent, label, x, y, w, primary, p, nodes) {
  nodes.push(
    rect(parent, `btn-${label}`, x, y, w, 48, {
      pos: p(),
      fill: primary ? C.green : C.card2,
      stroke: primary ? undefined : C.green,
      strokeWeight: 1.5,
      radius: 12,
    })
  );
  nodes.push(
    text(parent, `btn-t-${label}`, label, x, y, w, 48, {
      pos: p(),
      size: 14,
      bold: true,
      color: primary ? C.text : C.greenLt,
      align: "CENTER",
    })
  );
}

function seg(parent, items, active, x, y, w, p, nodes, prefix) {
  const bw = Math.floor(w / items.length);
  items.forEach((it, i) => {
    const on = i === active;
    nodes.push(
      rect(parent, `${prefix}-${i}`, x + i * bw, y, bw - 4, 40, {
        pos: p(),
        fill: on ? C.green : C.card2,
        radius: 10,
      })
    );
    nodes.push(
      text(parent, `${prefix}-t-${i}`, it, x + i * bw, y, bw - 4, 40, {
        pos: p(),
        size: 12,
        bold: true,
        color: on ? C.text : C.dim,
        align: "CENTER",
      })
    );
  });
}

function steps(root, cy, active, total, p, nodes) {
  const gap = 8;
  const w = (PHONE_W - 40 - gap * (total - 1)) / total;
  for (let i = 0; i < total; i++) {
    nodes.push(
      rect(root, `step-${i}`, 20 + i * (w + gap), cy, w, 4, {
        pos: p(),
        fill: i <= active ? C.green : C.border,
        radius: 2,
      })
    );
  }
}

function navBar(parent, active, y, p, nodes) {
  const items = ["Accueil", "Ventes", "Dettes", "Profil"];
  nodes.push(rect(parent, "nav", 0, y, PHONE_W, 72, { pos: p(), fill: C.card2 }));
  const w = PHONE_W / 4;
  items.forEach((it, i) => {
    const on = it === active;
    nodes.push(
      text(parent, `nav-${it}`, it, i * w, y + 28, w, 20, {
        pos: p(),
        size: 10,
        medium: true,
        color: on ? C.green : C.dim,
        align: "CENTER",
      })
    );
    if (on) {
      nodes.push(
        ellipse(parent, `nav-dot-${it}`, i * w + w / 2 - 2, y + 18, 4, 4, {
          pos: p(),
          fill: C.green,
        })
      );
    }
  });
}

function keypad(root, cy, p, nodes) {
  const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0", "⌫"];
  keys.forEach((k, i) => {
    const x = 16 + (i % 3) * 120;
    const y = cy + Math.floor(i / 3) * 52;
    nodes.push(
      rect(root, `k-${i}`, x, y, 112, 44, { pos: p(), fill: C.card, radius: 10 })
    );
    nodes.push(
      text(root, `kt-${i}`, k, x, y, 112, 44, {
        pos: p(),
        size: 16,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
  });
}

function buildPhone(pageGuid, label, ox, oy, buildContent, nodes) {
  const p = posGen();
  const outer = frame(pageGuid, label, ox, oy, PHONE_W, PHONE_H, {
    pos: p(),
    fill: C.surface,
    radius: 44,
    stroke: C.border,
    strokeWeight: 2,
  });
  nodes.push(outer);
  const root = outer.guid;

  nodes.push(rect(root, "status-bg", 0, 0, PHONE_W, 54, { pos: p(), fill: C.card2 }));
  nodes.push(
    text(root, "time", "9:41", 24, 18, 60, 20, {
      pos: p(),
      size: 13,
      bold: true,
      color: C.greenXs,
    })
  );
  nodes.push(
    text(root, "signal", "●●● ▮", 310, 18, 60, 20, {
      pos: p(),
      size: 11,
      color: C.greenXs,
      align: "RIGHT",
    })
  );
  nodes.push(rect(root, "notch", 145, 0, 100, 28, { pos: p(), fill: C.black }));
  nodes.push(
    rect(root, "notch-cap", 145, 18, 100, 14, { pos: p(), fill: C.black, radius: 12 })
  );

  const cy = 54;
  const ch = PHONE_H - 54 - 8;
  buildContent(root, cy, ch, p, nodes);

  nodes.push(
    rect(root, "home-ind", 145, PHONE_H - 14, 100, 5, {
      pos: p(),
      fill: C.greenLt,
      radius: 3,
      opacity: 0.35,
    })
  );
  nodes.push(
    text(pageGuid, `label-${label}`, label, ox, oy + PHONE_H + 18, PHONE_W, 22, {
      pos: p(),
      size: 11,
      mono: true,
      color: C.dim,
      align: "CENTER",
    })
  );
}

function placeScreens(pageGuid, screens, nodes, startY = 100) {
  screens.forEach((screen, i) => {
    const col = i % COLS;
    const row = Math.floor(i / COLS);
    const ox = 48 + col * (PHONE_W + GAP_X);
    const oy = startY + row * (PHONE_H + GAP_Y);
    buildPhone(pageGuid, screen.id, ox, oy, screen.build, nodes);
  });
}

function pageTitle(pageGuid, title, subtitle, nodes) {
  const p = posGen();
  nodes.push(
    text(pageGuid, "page-title", title, 48, 36, 900, 36, {
      pos: p(),
      size: 28,
      bold: true,
      mono: true,
      color: C.greenXs,
    })
  );
  if (subtitle) {
    nodes.push(
      text(pageGuid, "page-sub", subtitle, 48, 76, 900, 22, {
        pos: p(),
        size: 13,
        color: C.dim,
      })
    );
  }
}

/* ═══════════════════════ SCREEN BUILDERS ═══════════════════════ */

const S = {
  splash(root, cy, ch, p, nodes) {
    nodes.push(rect(root, "bg", 0, cy, PHONE_W, ch, { pos: p(), fill: C.surface }));
    nodes.push(
      rect(root, "logo", 155, cy + 220, 80, 80, { pos: p(), fill: C.green, radius: 22 })
    );
    nodes.push(
      text(root, "brand", "NeoForma", 45, cy + 320, 300, 36, {
        pos: p(),
        size: 28,
        bold: true,
        mono: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(
        root,
        "tag",
        "Ton cahier numérique,\nton passeport financier",
        55,
        cy + 370,
        280,
        48,
        { pos: p(), size: 13, color: C.dim, align: "CENTER" }
      )
    );
    nodes.push(
      rect(root, "loader", 145, cy + 460, 100, 4, { pos: p(), fill: C.border, radius: 2 })
    );
    nodes.push(
      rect(root, "loader-f", 145, cy + 460, 65, 4, { pos: p(), fill: C.green, radius: 2 })
    );
  },

  langue(root, cy, ch, p, nodes) {
    hdr(root, "Choisir la langue", cy, p, nodes, { back: false });
    nodes.push(
      text(
        root,
        "hint",
        "L'app s'adapte à ta langue. Tu pourras changer plus tard.",
        20,
        cy + 70,
        350,
        40,
        { pos: p(), size: 12, color: C.dim }
      )
    );
    [
      ["FR", "Français", true],
      ["MR", "Mooré", false],
      ["DL", "Dioula", false],
      ["FF", "Fulfuldé", false],
    ].forEach(([code, name, on], i) => {
      const x = 20 + (i % 2) * 175;
      const y = cy + 130 + Math.floor(i / 2) * 100;
      nodes.push(
        rect(root, `lang-${code}`, x, y, 160, 84, {
          pos: p(),
          fill: on ? C.elevated : C.card,
          stroke: on ? C.green : C.border,
          radius: 14,
        })
      );
      nodes.push(
        text(root, `lc-${code}`, code, x, y + 18, 160, 28, {
          pos: p(),
          size: 20,
          bold: true,
          mono: true,
          color: C.greenXs,
          align: "CENTER",
        })
      );
      nodes.push(
        text(root, `ln-${code}`, name, x, y + 48, 160, 20, {
          pos: p(),
          size: 12,
          color: C.dim,
          align: "CENTER",
        })
      );
    });
    nodes.push(
      rect(root, "voice", 20, cy + ch - 140, PHONE_W - 40, 44, {
        pos: p(),
        fill: C.card2,
        stroke: C.amber,
        radius: 10,
      })
    );
    nodes.push(
      text(root, "voice-t", "● Mode vocal disponible", 20, cy + ch - 140, PHONE_W - 40, 44, {
        pos: p(),
        size: 11,
        color: C.amber,
        align: "CENTER",
      })
    );
    btn(root, "Continuer", 20, cy + ch - 80, PHONE_W - 40, true, p, nodes);
  },

  valeur(root, cy, ch, p, nodes) {
    steps(root, cy + 24, 1, 3, p, nodes);
    nodes.push(
      rect(root, "ico", 155, cy + 100, 80, 80, {
        pos: p(),
        fill: C.elevated,
        radius: 20,
      })
    );
    nodes.push(
      text(root, "icot", "+", 155, cy + 100, 80, 80, {
        pos: p(),
        size: 36,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "title", "Trois gestes, un score", 40, cy + 210, 310, 32, {
        pos: p(),
        size: 18,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(
        root,
        "body",
        "1. Enregistre tes ventes\n2. Suis tes créances\n3. Construis ton NeoScore",
        50,
        cy + 260,
        290,
        90,
        { pos: p(), size: 14, color: C.dim, align: "CENTER" }
      )
    );
    btn(root, "Créer mon compte", 24, cy + ch - 130, PHONE_W - 48, true, p, nodes);
    btn(root, "J'ai déjà un compte", 24, cy + ch - 70, PHONE_W - 48, false, p, nodes);
  },

  login(root, cy, ch, p, nodes) {
    nodes.push(
      rect(root, "logo", 163, cy + 50, 64, 64, { pos: p(), fill: C.green, radius: 18 })
    );
    nodes.push(
      text(root, "brand", "NeoForma", 45, cy + 130, 300, 32, {
        pos: p(),
        size: 24,
        bold: true,
        mono: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "sub", "Connexion", 45, cy + 166, 300, 20, {
        pos: p(),
        size: 13,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      rect(root, "in1", 24, cy + 220, PHONE_W - 48, 48, {
        pos: p(),
        fill: C.card2,
        stroke: C.green,
        radius: 12,
      })
    );
    nodes.push(
      text(root, "in1t", "+226 70 12 34 56", 40, cy + 220, 280, 48, {
        pos: p(),
        size: 14,
        color: C.greenXs,
      })
    );
    nodes.push(
      rect(root, "in2", 24, cy + 280, PHONE_W - 48, 48, {
        pos: p(),
        fill: C.card2,
        stroke: C.border,
        radius: 12,
      })
    );
    nodes.push(
      text(root, "in2t", "● ● ● ●", 40, cy + 280, 280, 48, {
        pos: p(),
        size: 14,
        color: C.dim,
      })
    );
    btn(root, "Se connecter", 24, cy + 360, PHONE_W - 48, true, p, nodes);
    btn(root, "Créer un compte", 24, cy + 420, PHONE_W - 48, false, p, nodes);
    nodes.push(
      text(root, "forgot", "Code PIN oublié ?", 24, cy + ch - 40, PHONE_W - 48, 20, {
        pos: p(),
        size: 12,
        color: C.dim,
        align: "CENTER",
      })
    );
  },

  otp(root, cy, ch, p, nodes) {
    hdr(root, "Vérification", cy, p, nodes);
    nodes.push(
      text(root, "msg", "Code SMS envoyé\nau +226 70 12 34 56", 40, cy + 90, 310, 48, {
        pos: p(),
        size: 14,
        color: C.dim,
        align: "CENTER",
      })
    );
    ["4", "7", "_", ""].forEach((d, i) => {
      nodes.push(
        rect(root, `otp-${i}`, 55 + i * 70, cy + 170, 56, 64, {
          pos: p(),
          fill: C.card2,
          stroke: i === 2 ? C.green : C.border,
          radius: 12,
        })
      );
      nodes.push(
        text(root, `otpt-${i}`, d, 55 + i * 70, cy + 170, 56, 64, {
          pos: p(),
          size: 22,
          bold: true,
          mono: true,
          color: C.greenXs,
          align: "CENTER",
        })
      );
    });
    nodes.push(
      text(root, "resend", "Renvoyer le code · 0:42", 40, cy + 260, 310, 20, {
        pos: p(),
        size: 12,
        color: C.dim,
        align: "CENTER",
      })
    );
    btn(root, "Valider", 24, cy + ch - 70, PHONE_W - 48, true, p, nodes);
  },

  pin(root, cy, ch, p, nodes) {
    hdr(root, "Créer un PIN", cy, p, nodes);
    nodes.push(
      text(
        root,
        "hint",
        "4 chiffres · facile à retenir,\ndifficile à deviner",
        40,
        cy + 90,
        310,
        48,
        { pos: p(), size: 13, color: C.dim, align: "CENTER" }
      )
    );
    ["●", "●", "●", "|"].forEach((d, i) => {
      nodes.push(
        rect(root, `pin-${i}`, 55 + i * 70, cy + 170, 56, 64, {
          pos: p(),
          fill: C.card2,
          stroke: i === 3 ? C.green : C.border,
          radius: 12,
        })
      );
      nodes.push(
        text(root, `pint-${i}`, d, 55 + i * 70, cy + 170, 56, 64, {
          pos: p(),
          size: 22,
          bold: true,
          mono: true,
          color: C.greenXs,
          align: "CENTER",
        })
      );
    });
    keypad(root, cy + 280, p, nodes);
  },

  metier(root, cy, ch, p, nodes) {
    hdr(root, "Ton activité", cy, p, nodes, { back: false });
    steps(root, cy + 64, 0, 4, p, nodes);
    nodes.push(
      text(root, "l1", "CORPS DE MÉTIER", 24, cy + 90, 200, 16, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    ["Commerce", "Artisanat", "Mécanique"].forEach((m, i) => {
      nodes.push(
        rect(root, `m-${m}`, 20 + i * 118, cy + 114, 110, 36, {
          pos: p(),
          fill: i === 0 ? C.elevated : C.card2,
          stroke: i === 0 ? C.green : C.border,
          radius: 999,
        })
      );
      nodes.push(
        text(root, `mt-${m}`, m, 20 + i * 118, cy + 114, 110, 36, {
          pos: p(),
          size: 11,
          color: i === 0 ? C.greenXs : C.dim,
          align: "CENTER",
        })
      );
    });
    nodes.push(
      text(root, "l2", "ANCIENNETÉ", 24, cy + 180, 200, 16, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    seg(root, ["<1 an", "3–5 ans", ">10 ans"], 1, 20, cy + 204, PHONE_W - 40, p, nodes, "anc");
    nodes.push(
      text(root, "l3", "CA JOURNALIER", 24, cy + 280, 200, 16, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    seg(root, ["<5k", "15–30k", ">60k"], 1, 20, cy + 304, PHONE_W - 40, p, nodes, "ca");
    btn(root, "Suivant", 24, cy + ch - 70, PHONE_W - 48, true, p, nodes);
  },

  tontine(root, cy, ch, p, nodes) {
    hdr(root, "Fiabilité", cy, p, nodes, { back: false });
    steps(root, cy + 64, 1, 4, p, nodes);

    nodes.push(
      rect(root, "c1", 16, cy + 90, PHONE_W - 32, 120, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "t1", "TONTINE", 28, cy + 102, 200, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    seg(root, ["Oui", "Non"], 0, 28, cy + 124, PHONE_W - 72, p, nodes, "ton");
    nodes.push(
      text(root, "t2", "Cotisation / mois", 28, cy + 178, 200, 14, {
        pos: p(),
        size: 11,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "t2v", "5 000 FCFA", 200, cy + 178, 150, 14, {
        pos: p(),
        size: 12,
        bold: true,
        mono: true,
        color: C.greenXs,
        align: "RIGHT",
      })
    );

    nodes.push(
      rect(root, "c2", 16, cy + 226, PHONE_W - 32, 100, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "mm", "MOBILE MONEY", 28, cy + 238, 200, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    seg(root, ["Jamais", "Parfois", "Souvent"], 2, 28, cy + 262, PHONE_W - 72, p, nodes, "mm");

    nodes.push(
      rect(root, "c3", 16, cy + 342, PHONE_W - 32, 90, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "bk", "COMPTE BANCAIRE", 28, cy + 354, 200, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    seg(root, ["Non", "Oui"], 0, 28, cy + 378, PHONE_W - 72, p, nodes, "bk");

    btn(root, "Suivant", 24, cy + ch - 70, PHONE_W - 48, true, p, nodes);
  },

  consent(root, cy, ch, p, nodes) {
    hdr(root, "Consentement", cy, p, nodes, { back: false });
    steps(root, cy + 64, 3, 4, p, nodes);
    nodes.push(
      text(
        root,
        "intro",
        "Tes données construisent ton NeoScore.\nTu contrôles ce qui est partagé.",
        20,
        cy + 90,
        350,
        44,
        { pos: p(), size: 12, color: C.dim }
      )
    );
    const items = [
      ["Données anonymisées", "Pour améliorer le modèle", true],
      ["Partage partenaires crédit", "Uniquement si tu demandes un prêt", true],
      ["Marketing partenaires", "Optionnel", false],
    ];
    nodes.push(
      rect(root, "list", 16, cy + 150, PHONE_W - 32, items.length * 64 + 8, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    items.forEach(([title, sub, on], i) => {
      const y = cy + 162 + i * 64;
      nodes.push(
        rect(root, `chk-${i}`, 28, y + 12, 22, 22, {
          pos: p(),
          fill: on ? C.green : C.card2,
          stroke: C.green,
          radius: 6,
        })
      );
      if (on) {
        nodes.push(
          text(root, `chkt-${i}`, "✓", 28, y + 12, 22, 22, {
            pos: p(),
            size: 12,
            bold: true,
            color: C.text,
            align: "CENTER",
          })
        );
      }
      nodes.push(
        text(root, `ct-${i}`, title, 60, y + 6, 280, 20, {
          pos: p(),
          size: 13,
          bold: true,
          color: C.text,
        })
      );
      nodes.push(
        text(root, `cs-${i}`, sub, 60, y + 28, 280, 18, {
          pos: p(),
          size: 11,
          color: C.dim,
        })
      );
    });
    nodes.push(
      rect(root, "map", 16, cy + 370, PHONE_W - 32, 80, {
        pos: p(),
        fill: C.elevated,
        radius: 12,
      })
    );
    nodes.push(
      text(root, "map-t", "📍 Ouagadougou · Zone 4", 16, cy + 370, PHONE_W - 32, 80, {
        pos: p(),
        size: 13,
        color: C.greenLt,
        align: "CENTER",
      })
    );
    btn(root, "Activer mon NeoScore", 24, cy + ch - 70, PHONE_W - 48, true, p, nodes);
  },

  dashboard(root, cy, ch, p, nodes) {
    nodes.push(rect(root, "hdr", 0, cy, PHONE_W, 72, { pos: p(), fill: C.card2 }));
    nodes.push(
      text(root, "g", "Bonjour,", 20, cy + 14, 120, 16, {
        pos: p(),
        size: 11,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "n", "Aminata K.", 20, cy + 32, 180, 24, {
        pos: p(),
        size: 17,
        bold: true,
        color: C.greenXs,
      })
    );
    nodes.push(
      rect(root, "score-pill", 250, cy + 24, 48, 24, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
        radius: 999,
      })
    );
    nodes.push(
      text(root, "sp", "76", 250, cy + 24, 48, 24, {
        pos: p(),
        size: 12,
        bold: true,
        mono: true,
        color: C.greenLt,
        align: "CENTER",
      })
    );
    nodes.push(ellipse(root, "av", 310, cy + 18, 36, 36, { pos: p(), fill: C.green }));
    nodes.push(
      text(root, "avt", "AK", 310, cy + 18, 36, 36, {
        pos: p(),
        size: 12,
        bold: true,
        color: C.text,
        align: "CENTER",
      })
    );

    nodes.push(
      rect(root, "s1", 16, cy + 88, 172, 78, { pos: p(), fill: C.card, radius: 14 })
    );
    nodes.push(
      text(root, "s1l", "CE MOIS", 28, cy + 98, 140, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "s1v", "147 500", 28, cy + 116, 140, 28, {
        pos: p(),
        size: 18,
        bold: true,
        mono: true,
        color: C.greenXs,
      })
    );
    nodes.push(
      text(root, "s1u", "FCFA de ventes", 28, cy + 146, 140, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    nodes.push(
      rect(root, "s2", 200, cy + 88, 174, 78, { pos: p(), fill: C.card, radius: 14 })
    );
    nodes.push(
      text(root, "s2l", "CRÉANCES", 212, cy + 98, 140, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "s2v", "23 000", 212, cy + 116, 140, 28, {
        pos: p(),
        size: 18,
        bold: true,
        mono: true,
        color: C.amber,
      })
    );
    nodes.push(
      text(root, "s2u", "FCFA à récupérer", 212, cy + 146, 140, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );

    nodes.push(
      rect(root, "chart", 16, cy + 180, PHONE_W - 32, 120, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "cl", "VENTES · 7 JOURS", 28, cy + 190, 200, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    [28, 42, 22, 58, 36, 72, 50].forEach((h, i) => {
      nodes.push(
        rect(root, `bar-${i}`, 36 + i * 46, cy + 280 - h, 28, h, {
          pos: p(),
          fill: i === 3 || i >= 5 ? C.green : C.elevated,
          radius: 4,
        })
      );
    });

    nodes.push(
      rect(root, "txs", 16, cy + 316, PHONE_W - 32, 120, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "txl", "DERNIÈRES OPÉRATIONS", 28, cy + 326, 240, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "tx1", "Vente savon               +1 500", 28, cy + 352, 320, 20, {
        pos: p(),
        size: 13,
        color: C.ok,
      })
    );
    nodes.push(
      text(root, "tx2", "Dette · Koné              −5 000", 28, cy + 384, 320, 20, {
        pos: p(),
        size: 13,
        color: C.coral,
      })
    );

    nodes.push(
      rect(root, "fab", PHONE_W - 72, cy + ch - 150, 52, 52, {
        pos: p(),
        fill: C.green,
        radius: 16,
      })
    );
    nodes.push(
      text(root, "fab+", "+", PHONE_W - 72, cy + ch - 150, 52, 52, {
        pos: p(),
        size: 28,
        bold: true,
        color: C.text,
        align: "CENTER",
      })
    );
    navBar(root, "Accueil", cy + ch - 72, p, nodes);
  },

  vente(root, cy, ch, p, nodes) {
    hdr(root, "Enregistrer", cy, p, nodes);
    ["Vente", "Stock", "Dette"].forEach((label, i) => {
      const on = i === 0;
      nodes.push(
        rect(root, `type-${i}`, 16 + i * 120, cy + 70, 110, 64, {
          pos: p(),
          fill: on ? C.elevated : C.card2,
          stroke: on ? C.green : C.border,
          radius: 12,
        })
      );
      nodes.push(
        text(root, `typet-${i}`, label, 16 + i * 120, cy + 70, 110, 64, {
          pos: p(),
          size: 13,
          bold: true,
          color: on ? C.greenXs : C.dim,
          align: "CENTER",
        })
      );
    });
    nodes.push(
      rect(root, "amt", 16, cy + 150, PHONE_W - 32, 100, {
        pos: p(),
        fill: C.card2,
        stroke: C.border,
        radius: 16,
      })
    );
    nodes.push(
      text(root, "amtl", "MONTANT", 16, cy + 162, PHONE_W - 32, 16, {
        pos: p(),
        size: 10,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "amtv", "2 500", 16, cy + 182, PHONE_W - 32, 40, {
        pos: p(),
        size: 36,
        bold: true,
        mono: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "amtu", "FCFA", 16, cy + 222, PHONE_W - 32, 18, {
        pos: p(),
        size: 12,
        color: C.dim,
        align: "CENTER",
      })
    );
    keypad(root, cy + 270, p, nodes);
    btn(root, "Confirmer la vente", 16, cy + ch - 64, PHONE_W - 32, true, p, nodes);
  },

  dette(root, cy, ch, p, nodes) {
    hdr(root, "Nouvelle dette", cy, p, nodes);
    nodes.push(
      text(root, "l1", "CLIENT", 24, cy + 70, 200, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    nodes.push(
      rect(root, "in", 16, cy + 90, PHONE_W - 32, 48, {
        pos: p(),
        fill: C.card2,
        stroke: C.green,
        radius: 12,
      })
    );
    nodes.push(
      text(root, "int", "Koné Ibrahim", 32, cy + 90, 300, 48, {
        pos: p(),
        size: 14,
        color: C.greenXs,
      })
    );
    nodes.push(
      rect(root, "amt", 16, cy + 156, PHONE_W - 32, 90, {
        pos: p(),
        fill: C.card2,
        stroke: C.border,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "amtv", "5 000", 16, cy + 170, PHONE_W - 32, 40, {
        pos: p(),
        size: 30,
        bold: true,
        mono: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "amtu", "FCFA", 16, cy + 214, PHONE_W - 32, 18, {
        pos: p(),
        size: 12,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "l2", "ÉCHÉANCE", 24, cy + 270, 200, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    seg(root, ["3 j", "7 j", "14 j", "30 j"], 1, 16, cy + 294, PHONE_W - 32, p, nodes, "ech");
    nodes.push(
      rect(root, "voice", 16, cy + 360, PHONE_W - 32, 48, {
        pos: p(),
        fill: C.card2,
        stroke: C.amber,
        radius: 10,
      })
    );
    nodes.push(
      text(
        root,
        "voice-t",
        "● Dicter : « Dette Koné cinq mille »",
        16,
        cy + 360,
        PHONE_W - 32,
        48,
        { pos: p(), size: 11, color: C.amber, align: "CENTER" }
      )
    );
    btn(root, "Enregistrer la dette", 16, cy + ch - 70, PHONE_W - 32, true, p, nodes);
  },

  succes(root, cy, ch, p, nodes) {
    nodes.push(
      ellipse(root, "ok", 145, cy + 140, 100, 100, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
      })
    );
    nodes.push(
      text(root, "okt", "✓", 145, cy + 140, 100, 100, {
        pos: p(),
        size: 40,
        bold: true,
        color: C.green,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "title", "Vente enregistrée", 40, cy + 270, 310, 28, {
        pos: p(),
        size: 18,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "sub", "+2 500 FCFA · NeoScore +0.3", 40, cy + 308, 310, 24, {
        pos: p(),
        size: 13,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      rect(root, "toast", 24, cy + 360, PHONE_W - 48, 48, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
        radius: 12,
      })
    );
    nodes.push(
      text(root, "toastt", "Régularité en hausse cette semaine", 24, cy + 360, PHONE_W - 48, 48, {
        pos: p(),
        size: 12,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    btn(root, "Accueil", 24, cy + ch - 130, (PHONE_W - 56) / 2, false, p, nodes);
    btn(root, "Nouvelle", 32 + (PHONE_W - 56) / 2, cy + ch - 130, (PHONE_W - 56) / 2, true, p, nodes);
  },

  ventes(root, cy, ch, p, nodes) {
    hdr(root, "Ventes", cy, p, nodes, { back: false, pill: "Mars" });
    seg(root, ["Jour", "Semaine", "Mois"], 0, 16, cy + 68, PHONE_W - 32, p, nodes, "per");
    nodes.push(
      rect(root, "sum", 16, cy + 128, PHONE_W - 32, 72, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "sl", "TOTAL AUJOURD'HUI", 28, cy + 138, 200, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "sv", "18 500 FCFA", 28, cy + 158, 280, 28, {
        pos: p(),
        size: 20,
        bold: true,
        mono: true,
        color: C.greenXs,
      })
    );
    const rows = [
      ["Huile 1L", "10:22", "+2 000"],
      ["Savon lot", "09:14", "+1 500"],
      ["Riz 2kg", "08:01", "+3 000"],
      ["Recharge MM", "07:40", "+500"],
    ];
    nodes.push(
      rect(root, "list", 16, cy + 216, PHONE_W - 32, rows.length * 56 + 8, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    rows.forEach(([name, time, amt], i) => {
      const y = cy + 228 + i * 56;
      nodes.push(
        text(root, `vn-${i}`, name, 28, y, 180, 20, {
          pos: p(),
          size: 13,
          bold: true,
          color: C.text,
        })
      );
      nodes.push(
        text(root, `vt-${i}`, time, 28, y + 22, 100, 16, {
          pos: p(),
          size: 11,
          color: C.dim,
        })
      );
      nodes.push(
        text(root, `va-${i}`, amt, 250, y, 100, 40, {
          pos: p(),
          size: 13,
          bold: true,
          mono: true,
          color: C.ok,
          align: "RIGHT",
        })
      );
    });
    navBar(root, "Ventes", cy + ch - 72, p, nodes);
  },

  dettes(root, cy, ch, p, nodes) {
    hdr(root, "Dettes clients", cy, p, nodes, { back: false });
    nodes.push(
      rect(root, "sum", 16, cy + 68, PHONE_W - 32, 90, {
        pos: p(),
        fill: C.card,
        stroke: C.amber,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "sl", "À RÉCUPÉRER", 28, cy + 80, 200, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "sv", "23 000 FCFA", 28, cy + 100, 280, 28, {
        pos: p(),
        size: 20,
        bold: true,
        mono: true,
        color: C.amber,
      })
    );
    nodes.push(
      text(root, "su", "3 dettes ouvertes · 1 en retard", 28, cy + 132, 280, 16, {
        pos: p(),
        size: 11,
        color: C.dim,
      })
    );
    const debts = [
      ["Koné Ibrahim", "Échéance hier", "5 000", C.coral],
      ["Fatou S.", "Dans 3 jours", "8 000", C.amber],
      ["Moussa O.", "Dans 12 jours", "10 000", C.greenXs],
    ];
    debts.forEach(([name, when, amt, col], i) => {
      const y = cy + 180 + i * 72;
      nodes.push(
        rect(root, `d-${i}`, 16, y, PHONE_W - 32, 64, {
          pos: p(),
          fill: C.card,
          radius: 12,
        })
      );
      nodes.push(
        text(root, `dn-${i}`, name, 28, y + 12, 200, 20, {
          pos: p(),
          size: 14,
          bold: true,
          color: C.text,
        })
      );
      nodes.push(
        text(root, `dw-${i}`, when, 28, y + 36, 200, 16, {
          pos: p(),
          size: 11,
          color: C.dim,
        })
      );
      nodes.push(
        text(root, `da-${i}`, amt, 250, y + 12, 110, 40, {
          pos: p(),
          size: 14,
          bold: true,
          mono: true,
          color: col,
          align: "RIGHT",
        })
      );
    });
    btn(root, "Relancer Koné (SMS)", 16, cy + ch - 140, PHONE_W - 32, false, p, nodes);
    navBar(root, "Dettes", cy + ch - 72, p, nodes);
  },

  empty(root, cy, ch, p, nodes) {
    hdr(root, "Ventes", cy, p, nodes, { back: false });
    nodes.push(
      rect(root, "ico", 155, cy + 200, 80, 80, {
        pos: p(),
        fill: C.elevated,
        radius: 20,
      })
    );
    nodes.push(
      text(root, "icot", "∅", 155, cy + 200, 80, 80, {
        pos: p(),
        size: 28,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "title", "Aucune vente aujourd'hui", 40, cy + 310, 310, 28, {
        pos: p(),
        size: 16,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(
        root,
        "sub",
        "Appuie sur + pour enregistrer\nta première opération",
        50,
        cy + 350,
        290,
        48,
        { pos: p(), size: 12, color: C.dim, align: "CENTER" }
      )
    );
    btn(root, "Enregistrer une vente", 24, cy + ch - 150, PHONE_W - 48, true, p, nodes);
    navBar(root, "Ventes", cy + ch - 72, p, nodes);
  },

  neoscore(root, cy, ch, p, nodes) {
    hdr(root, "NeoScore", cy, p, nodes, { pill: "LIVE" });
    nodes.push(
      rect(root, "score-card", 16, cy + 68, PHONE_W - 32, 200, {
        pos: p(),
        fill: C.card,
        radius: 16,
      })
    );
    nodes.push(
      ellipse(root, "ring-bg", 135, cy + 88, 120, 120, {
        pos: p(),
        fill: C.card2,
        stroke: C.border,
      })
    );
    nodes.push(
      ellipse(root, "ring", 145, cy + 98, 100, 100, {
        pos: p(),
        fill: C.card,
        stroke: C.green,
      })
    );
    nodes.push(
      text(root, "score", "76", 145, cy + 98, 100, 100, {
        pos: p(),
        size: 36,
        bold: true,
        mono: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "sl", "Score NeoScore · sur 100", 16, cy + 220, PHONE_W - 32, 18, {
        pos: p(),
        size: 11,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "sb", "✓ Profil fiable · Segment B", 16, cy + 242, PHONE_W - 32, 18, {
        pos: p(),
        size: 12,
        bold: true,
        color: C.green,
        align: "CENTER",
      })
    );

    const crits = [
      ["Régularité", 88],
      ["Volume", 72],
      ["Dettes", 65],
      ["Croissance", 80],
    ];
    nodes.push(
      rect(root, "crits", 16, cy + 284, PHONE_W - 32, 180, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    crits.forEach(([name, pct], i) => {
      const y = cy + 300 + i * 38;
      nodes.push(
        text(root, `cn-${i}`, name, 28, y, 160, 16, {
          pos: p(),
          size: 12,
          color: C.greenXs,
        })
      );
      nodes.push(
        text(root, `cp-${i}`, `${pct}%`, 280, y, 70, 16, {
          pos: p(),
          size: 12,
          mono: true,
          color: C.dim,
          align: "RIGHT",
        })
      );
      nodes.push(
        rect(root, `pb-${i}`, 28, y + 18, PHONE_W - 72, 6, {
          pos: p(),
          fill: C.card2,
          radius: 3,
        })
      );
      nodes.push(
        rect(root, `pf-${i}`, 28, y + 18, ((PHONE_W - 72) * pct) / 100, 6, {
          pos: p(),
          fill: C.green,
          radius: 3,
        })
      );
    });
    btn(root, "Demander un crédit", 16, cy + ch - 70, PHONE_W - 32, true, p, nodes);
  },

  offre(root, cy, ch, p, nodes) {
    hdr(root, "Offre de crédit", cy, p, nodes);
    nodes.push(
      rect(root, "offer", 16, cy + 70, PHONE_W - 32, 140, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
        radius: 16,
      })
    );
    nodes.push(
      text(root, "ol", "MONTANT ESTIMÉ", 28, cy + 86, 200, 14, {
        pos: p(),
        size: 10,
        color: C.greenLt,
      })
    );
    nodes.push(
      text(root, "ov", "150 000", 28, cy + 108, 300, 40, {
        pos: p(),
        size: 32,
        bold: true,
        mono: true,
        color: C.greenXs,
      })
    );
    nodes.push(
      text(root, "ou", "FCFA · pré-approuvé", 28, cy + 152, 280, 18, {
        pos: p(),
        size: 12,
        color: C.greenLt,
      })
    );
    nodes.push(
      text(root, "om", "Durée 3 mois     ·     2,5%/mois", 28, cy + 178, 320, 18, {
        pos: p(),
        size: 11,
        color: C.dim,
      })
    );
    nodes.push(
      rect(root, "slider-card", 16, cy + 230, PHONE_W - 32, 100, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "sl", "AJUSTER LE MONTANT", 28, cy + 244, 240, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    nodes.push(
      text(root, "sr", "50k          150 000          250k", 28, cy + 268, 320, 18, {
        pos: p(),
        size: 12,
        mono: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      rect(root, "track", 28, cy + 300, PHONE_W - 72, 6, {
        pos: p(),
        fill: C.card2,
        radius: 3,
      })
    );
    nodes.push(
      rect(root, "fill", 28, cy + 300, 200, 6, { pos: p(), fill: C.green, radius: 3 })
    );
    nodes.push(
      ellipse(root, "thumb", 216, cy + 294, 18, 18, {
        pos: p(),
        fill: C.text,
        stroke: C.green,
      })
    );
    nodes.push(
      rect(root, "hist", 16, cy + 350, PHONE_W - 32, 110, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    ["Janvier  ·  58", "Février  ·  67", "Mars     ·  76"].forEach((row, i) => {
      nodes.push(
        text(root, `h-${i}`, row, 28, cy + 366 + i * 28, 300, 22, {
          pos: p(),
          size: 13,
          mono: true,
          color: i === 2 ? C.greenXs : C.dim,
        })
      );
    });
    btn(root, "Continuer la demande", 16, cy + ch - 70, PHONE_W - 32, true, p, nodes);
  },

  creditForm(root, cy, ch, p, nodes) {
    hdr(root, "Demande", cy, p, nodes);
    nodes.push(
      text(root, "l1", "USAGE DU CRÉDIT", 24, cy + 70, 240, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    [
      ["Stock", true],
      ["Équipement", false],
      ["Fonds de roulement", false],
      ["Autre", false],
    ].forEach(([label, on], i) => {
      const x = 16 + (i % 2) * 180;
      const y = cy + 94 + Math.floor(i / 2) * 64;
      nodes.push(
        rect(root, `u-${i}`, x, y, 168, 52, {
          pos: p(),
          fill: on ? C.elevated : C.card,
          stroke: on ? C.green : C.border,
          radius: 12,
        })
      );
      nodes.push(
        text(root, `ut-${i}`, label, x, y, 168, 52, {
          pos: p(),
          size: 12,
          bold: true,
          color: on ? C.greenXs : C.dim,
          align: "CENTER",
        })
      );
    });
    nodes.push(
      text(root, "l2", "REMBOURSEMENT", 24, cy + 240, 200, 14, {
        pos: p(),
        size: 10,
        color: C.dim,
      })
    );
    seg(root, ["Hebdo", "Mensuel"], 1, 16, cy + 264, PHONE_W - 32, p, nodes, "rem");
    nodes.push(
      rect(root, "recap", 16, cy + 330, PHONE_W - 32, 120, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "rl", "RÉCAP", 28, cy + 342, 100, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    [
      ["Montant", "150 000"],
      ["Échéances", "3 × 55k"],
      ["1re échéance", "12 août"],
    ].forEach(([k, v], i) => {
      nodes.push(
        text(root, `rk-${i}`, `${k}                    ${v}`, 28, cy + 366 + i * 26, 320, 22, {
          pos: p(),
          size: 13,
          mono: true,
          color: C.greenXs,
        })
      );
    });
    btn(root, "Soumettre", 16, cy + ch - 70, PHONE_W - 32, true, p, nodes);
  },

  confirm(root, cy, ch, p, nodes) {
    nodes.push(
      ellipse(root, "ok", 145, cy + 120, 100, 100, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
      })
    );
    nodes.push(
      text(root, "okt", "OK", 145, cy + 120, 100, 100, {
        pos: p(),
        size: 28,
        bold: true,
        mono: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "title", "Demande envoyée", 40, cy + 240, 310, 28, {
        pos: p(),
        size: 18,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(
        root,
        "sub",
        "Un partenaire étudie ton dossier.\nRéponse sous 24–48 h.",
        40,
        cy + 280,
        310,
        48,
        { pos: p(), size: 13, color: C.dim, align: "CENTER" }
      )
    );
    nodes.push(
      rect(root, "ref", 16, cy + 360, PHONE_W - 32, 120, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    [
      ["Réf.", "NF-2026-0841"],
      ["Montant", "150 000"],
      ["Statut", "En cours"],
    ].forEach(([k, v], i) => {
      nodes.push(
        text(root, `rk-${i}`, `${k}                    ${v}`, 28, cy + 378 + i * 30, 320, 22, {
          pos: p(),
          size: 13,
          mono: true,
          color: i === 2 ? C.amber : C.greenXs,
        })
      );
    });
    btn(root, "Retour à l'accueil", 16, cy + ch - 70, PHONE_W - 32, true, p, nodes);
  },

  profil(root, cy, ch, p, nodes) {
    hdr(root, "Profil", cy, p, nodes, { back: false });
    nodes.push(ellipse(root, "av", 155, cy + 80, 80, 80, { pos: p(), fill: C.green }));
    nodes.push(
      text(root, "avt", "AK", 155, cy + 80, 80, 80, {
        pos: p(),
        size: 22,
        bold: true,
        color: C.text,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "name", "Aminata Kaboré", 40, cy + 175, 310, 28, {
        pos: p(),
        size: 18,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "meta", "Commerce · Ouagadougou", 40, cy + 208, 310, 20, {
        pos: p(),
        size: 12,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      rect(root, "b1", 70, cy + 244, 110, 28, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
        radius: 999,
      })
    );
    nodes.push(
      text(root, "b1t", "NeoScore 76", 70, cy + 244, 110, 28, {
        pos: p(),
        size: 11,
        bold: true,
        color: C.greenLt,
        align: "CENTER",
      })
    );
    nodes.push(
      rect(root, "b2", 190, cy + 244, 110, 28, {
        pos: p(),
        fill: C.card2,
        stroke: C.amber,
        radius: 999,
      })
    );
    nodes.push(
      text(root, "b2t", "Éligible", 190, cy + 244, 110, 28, {
        pos: p(),
        size: 11,
        bold: true,
        color: C.amber,
        align: "CENTER",
      })
    );
    const menus = [
      "Modifier mon activité",
      "Langue                         FR ›",
      "Mode vocal                    ON ›",
      "Confidentialité",
      "Aide & contact",
    ];
    nodes.push(
      rect(root, "menu", 16, cy + 296, PHONE_W - 32, menus.length * 48 + 8, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    menus.forEach((m, i) => {
      nodes.push(
        text(root, `mi-${i}`, m, 32, cy + 308 + i * 48, 320, 40, {
          pos: p(),
          size: 14,
          color: C.text,
        })
      );
    });
    nodes.push(
      rect(root, "logout", 16, cy + ch - 150, PHONE_W - 32, 44, {
        pos: p(),
        fill: C.card2,
        stroke: C.coral,
        radius: 12,
      })
    );
    nodes.push(
      text(root, "logout-t", "Se déconnecter", 16, cy + ch - 150, PHONE_W - 32, 44, {
        pos: p(),
        size: 14,
        bold: true,
        color: C.coral,
        align: "CENTER",
      })
    );
    navBar(root, "Profil", cy + ch - 72, p, nodes);
  },

  nonEligible(root, cy, ch, p, nodes) {
    hdr(root, "Score trop bas", cy, p, nodes);
    nodes.push(
      ellipse(root, "ring", 145, cy + 100, 100, 100, {
        pos: p(),
        fill: C.card2,
        stroke: C.coral,
      })
    );
    nodes.push(
      text(root, "score", "38", 145, cy + 100, 100, 100, {
        pos: p(),
        size: 32,
        bold: true,
        mono: true,
        color: "#F5B9A8",
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "title", "Pas encore éligible", 40, cy + 230, 310, 28, {
        pos: p(),
        size: 16,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(
        root,
        "sub",
        "Seuil à 50. Continue d'enregistrer\ntes ventes 14 jours de plus.",
        40,
        cy + 268,
        310,
        48,
        { pos: p(), size: 13, color: C.dim, align: "CENTER" }
      )
    );
    nodes.push(
      rect(root, "tips", 16, cy + 340, PHONE_W - 32, 140, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(root, "tl", "POUR PROGRESSER", 28, cy + 354, 240, 14, {
        pos: p(),
        size: 9,
        color: C.dim,
      })
    );
    [
      "1 vente / jour minimum",
      "Réduire les impayés clients",
      "Activer Mobile Money",
    ].forEach((tip, i) => {
      nodes.push(
        text(root, `tip-${i}`, `•  ${tip}`, 28, cy + 380 + i * 28, 320, 22, {
          pos: p(),
          size: 13,
          color: C.greenXs,
        })
      );
    });
    btn(root, "Voir mon plan", 16, cy + ch - 70, PHONE_W - 32, true, p, nodes);
  },

  offline(root, cy, ch, p, nodes) {
    hdr(root, "Hors ligne", cy, p, nodes);
    nodes.push(
      rect(root, "ico", 155, cy + 160, 80, 80, {
        pos: p(),
        fill: C.elevated,
        radius: 20,
      })
    );
    nodes.push(
      text(root, "icot", "⌀", 155, cy + 160, 80, 80, {
        pos: p(),
        size: 36,
        color: C.dim,
        align: "CENTER",
      })
    );
    nodes.push(
      text(root, "title", "Mode hors ligne", 40, cy + 270, 310, 28, {
        pos: p(),
        size: 18,
        bold: true,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    nodes.push(
      text(
        root,
        "sub",
        "Tes ventes sont sauvegardées\nsur l'appareil. Sync au retour réseau.",
        40,
        cy + 310,
        310,
        48,
        { pos: p(), size: 13, color: C.dim, align: "CENTER" }
      )
    );
    nodes.push(
      rect(root, "toast", 24, cy + 390, PHONE_W - 48, 48, {
        pos: p(),
        fill: C.elevated,
        stroke: C.green,
        radius: 12,
      })
    );
    nodes.push(
      text(root, "toastt", "3 opérations en attente de sync", 24, cy + 390, PHONE_W - 48, 48, {
        pos: p(),
        size: 12,
        color: C.greenXs,
        align: "CENTER",
      })
    );
    btn(root, "Continuer hors ligne", 24, cy + ch - 70, PHONE_W - 48, true, p, nodes);
  },
};

function buildDesignSystem(pageGuid, nodes) {
  const p = posGen();
  pageTitle(
    pageGuid,
    "NeoForma Design System",
    "Teal Forest · Inclusion financière · Burkina Faso 2026",
    nodes
  );

  const swatches = [
    ["Bg", C.bg],
    ["Surface", C.surface],
    ["Card", C.card],
    ["Card2", C.card2],
    ["Primary", C.green],
    ["Dim", C.dim],
    ["Accent", C.greenXs],
    ["Amber", C.amber],
    ["Coral", C.coral],
    ["OK", C.ok],
    ["Elevated", C.elevated],
    ["Border", C.border],
  ];
  swatches.forEach(([name, hex], i) => {
    const x = 48 + (i % 6) * 150;
    const y = 140 + Math.floor(i / 6) * 130;
    nodes.push(
      rect(pageGuid, `sw-${name}`, x, y, 130, 72, {
        pos: p(),
        fill: hex,
        radius: 12,
        stroke: C.border,
      })
    );
    nodes.push(
      text(pageGuid, `sw-n-${name}`, `${name}\n${hex}`, x, y + 80, 130, 36, {
        pos: p(),
        size: 11,
        mono: true,
        color: C.dim,
        align: "CENTER",
      })
    );
  });

  nodes.push(
    text(pageGuid, "typo-h", "Typographie", 48, 420, 300, 28, {
      pos: p(),
      size: 20,
      bold: true,
      color: C.text,
    })
  );
  nodes.push(
    text(pageGuid, "typo-d", "NeoForma Display", 48, 460, 400, 40, {
      pos: p(),
      size: 32,
      bold: true,
      mono: true,
      color: C.greenXs,
    })
  );
  nodes.push(
    text(pageGuid, "typo-t", "Titre écran · Inter Bold 16", 48, 510, 400, 24, {
      pos: p(),
      size: 16,
      bold: true,
      color: C.text,
    })
  );
  nodes.push(
    text(pageGuid, "typo-b", "Corps · Inter Regular 13 — Ton passeport financier", 48, 544, 500, 20, {
      pos: p(),
      size: 13,
      color: C.dim,
    })
  );

  nodes.push(
    text(pageGuid, "comp-h", "Composants", 48, 600, 300, 28, {
      pos: p(),
      size: 20,
      bold: true,
      color: C.text,
    })
  );
  btn(pageGuid, "Primaire", 48, 650, 160, true, p, nodes);
  btn(pageGuid, "Outline", 228, 650, 160, false, p, nodes);
  nodes.push(
    rect(pageGuid, "pill", 420, 660, 110, 28, {
      pos: p(),
      fill: C.elevated,
      stroke: C.green,
      radius: 999,
    })
  );
  nodes.push(
    text(pageGuid, "pill-t", "LIVE · 76", 420, 660, 110, 28, {
      pos: p(),
      size: 11,
      bold: true,
      color: C.greenLt,
      align: "CENTER",
    })
  );
  nodes.push(ellipse(pageGuid, "av", 560, 654, 40, 40, { pos: p(), fill: C.green }));
  nodes.push(
    text(pageGuid, "av-t", "AK", 560, 654, 40, 40, {
      pos: p(),
      size: 13,
      bold: true,
      color: C.text,
      align: "CENTER",
    })
  );
  nodes.push(
    rect(pageGuid, "input", 48, 720, 320, 48, {
      pos: p(),
      fill: C.card2,
      stroke: C.green,
      radius: 12,
    })
  );
  nodes.push(
    text(pageGuid, "input-t", "+226 70 12 34 56", 64, 720, 280, 48, {
      pos: p(),
      size: 14,
      color: C.greenXs,
    })
  );

  nodes.push(
    text(pageGuid, "states-h", "États", 48, 800, 200, 28, {
      pos: p(),
      size: 20,
      bold: true,
      color: C.text,
    })
  );
  [
    ["Succès", C.ok],
    ["Attention", C.amber],
    ["Erreur / dette", C.coral],
    ["Info", C.greenLt],
  ].forEach(([label, col], i) => {
    nodes.push(
      rect(pageGuid, `st-${i}`, 48 + i * 180, 850, 160, 40, {
        pos: p(),
        fill: C.card,
        stroke: col,
        radius: 10,
      })
    );
    nodes.push(
      text(pageGuid, `stt-${i}`, label, 48 + i * 180, 850, 160, 40, {
        pos: p(),
        size: 12,
        bold: true,
        color: col,
        align: "CENTER",
      })
    );
  });
}

function buildFlows(pageGuid, nodes) {
  const p = posGen();
  pageTitle(
    pageGuid,
    "Parcours utilisateur NeoForma",
    "Flux bout-en-bout · 6 parcours principaux",
    nodes
  );
  const flows = [
    ["A · Onboarding", "Splash → Langue → Valeur → Compte"],
    ["B · Auth", "Login → OTP SMS → Création PIN"],
    ["C · KYC léger", "Métier/CA → Tontine/MM → Consentement"],
    ["D · Cahier numérique", "Dashboard → Vente / Dette → Succès"],
    ["E · Crédit", "NeoScore → Offre → Formulaire → Confirmation"],
    ["F · Edge cases", "Empty · Non-éligible · Offline-first"],
  ];
  flows.forEach(([title, body], i) => {
    const y = 140 + i * 90;
    nodes.push(
      rect(pageGuid, `fl-${i}`, 48, y, 900, 72, {
        pos: p(),
        fill: C.card,
        radius: 14,
      })
    );
    nodes.push(
      text(pageGuid, `flt-${i}`, title, 68, y + 12, 800, 24, {
        pos: p(),
        size: 15,
        bold: true,
        color: C.greenXs,
      })
    );
    nodes.push(
      text(pageGuid, `flb-${i}`, body, 68, y + 40, 800, 22, {
        pos: p(),
        size: 13,
        color: C.dim,
      })
    );
  });
}

function buildAll(doc) {
  const page1 = doc.message.nodeChanges.find(
    (n) => n.type === "CANVAS" && n.name === "Page 1"
  );
  page1.name = "01 · Onboarding & Auth";
  page1.backgroundColor = hexToRgb(C.bg);
  page1.backgroundEnabled = true;

  const dsGuid = addCanvas(doc, "00 · Design System", "!~");
  const kycGuid = addCanvas(doc, "02 · KYC & Home", "!#");
  const creditGuid = addCanvas(doc, "03 · Score & Crédit", "!$");
  const edgeGuid = addCanvas(doc, "04 · Edge & Profil", "!%");
  const flowGuid = addCanvas(doc, "05 · User Flows", "!&");

  const nodes = [];
  buildDesignSystem(dsGuid, nodes);
  buildFlows(flowGuid, nodes);

  // Page 01 — onboarding + auth (6)
  pageTitle(page1.guid, "Onboarding & Authentification", "01.x – 02.x", nodes);
  placeScreens(
    page1.guid,
    [
      { id: "01.1 Splash", build: S.splash },
      { id: "01.2 Langue", build: S.langue },
      { id: "01.3 Valeur", build: S.valeur },
      { id: "02.1 Login", build: S.login },
      { id: "02.2 OTP SMS", build: S.otp },
      { id: "02.3 Création PIN", build: S.pin },
    ],
    nodes
  );

  // Page 02 — KYC + home ops (7)
  pageTitle(kycGuid, "KYC léger & Cahier numérique", "03.x – 04.x", nodes);
  placeScreens(
    kycGuid,
    [
      { id: "03.1 Métier & CA", build: S.metier },
      { id: "03.2 Tontine & MM", build: S.tontine },
      { id: "03.3 Consentement", build: S.consent },
      { id: "04.1 Dashboard", build: S.dashboard },
      { id: "04.2 Saisie vente", build: S.vente },
      { id: "04.3 Dette + vocal", build: S.dette },
      { id: "04.4 Succès", build: S.succes },
    ],
    nodes
  );

  // Page 03 — lists + score + credit (7)
  pageTitle(creditGuid, "Listes, NeoScore & Crédit", "05.x – 06.x", nodes);
  placeScreens(
    creditGuid,
    [
      { id: "05.1 Liste ventes", build: S.ventes },
      { id: "05.2 Dettes", build: S.dettes },
      { id: "05.3 État vide", build: S.empty },
      { id: "06.1 NeoScore", build: S.neoscore },
      { id: "06.2 Offre crédit", build: S.offre },
      { id: "06.3 Formulaire", build: S.creditForm },
      { id: "06.4 Confirmation", build: S.confirm },
    ],
    nodes
  );

  // Page 04 — profile + edges (3)
  pageTitle(edgeGuid, "Profil & cas limites", "07.x", nodes);
  placeScreens(
    edgeGuid,
    [
      { id: "07.1 Profil", build: S.profil },
      { id: "07.2 Non-éligible", build: S.nonEligible },
      { id: "07.3 Offline", build: S.offline },
    ],
    nodes
  );

  doc.message.nodeChanges.push(...nodes);
}

async function makeThumbnail() {
  const svg = `
  <svg width="512" height="512" xmlns="http://www.w3.org/2000/svg">
    <rect width="512" height="512" fill="#0F3D2E"/>
    <rect x="156" y="156" width="200" height="200" rx="48" fill="#1D9E75"/>
    <text x="256" y="280" text-anchor="middle" font-family="Arial" font-size="72" font-weight="700" fill="#E1F5EE">N</text>
    <text x="256" y="420" text-anchor="middle" font-family="Arial" font-size="28" fill="#9FE1CB">NeoForma</text>
  </svg>`;
  return sharp(Buffer.from(svg)).png().toBuffer();
}

async function main() {
  const doc = createEmptyFigDoc();
  doc.meta = {
    file_name: "NeoForma App — Design Complet",
    version: "2",
  };

  buildAll(doc);
  doc.thumbnail = new Uint8Array(await makeThumbnail());

  const parts = encodeFigParts(doc);
  const zstd = await Zstd.load();
  const messageCompressed = zstd.compress(parts.messageRaw, 3);
  const canvasFig = assembleCanvasFig({ ...parts, messageCompressed });
  const figZip = createFigZip({
    canvasFig,
    meta: doc.meta,
    thumbnail: doc.thumbnail,
    images: doc.images,
  });

  fs.writeFileSync(OUT, Buffer.from(figZip));
  const parsed = parseFig(figZip);
  const phoneFrames = parsed.nodes.filter(
    (n) => n.type === "FRAME" && /^\d{2}\.\d/.test(n.name)
  );
  console.log(`Wrote ${OUT}`);
  console.log(`Size: ${(figZip.length / 1024).toFixed(1)} KB`);
  console.log(
    `Pages: ${parsed.nodes.filter((n) => n.type === "CANVAS").length} · Phone screens: ${phoneFrames.length} · Nodes: ${parsed.nodes.length}`
  );
  console.log(phoneFrames.map((n) => n.name).join(" · "));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
