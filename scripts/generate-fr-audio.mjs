/**
 * Génère des WAV FR pour VoiceService (mêmes clés que assets/audio/mr).
 * Prérequis optionnel: pip install edge-tts
 * Sur Windows sans edge-tts : powershell -File scripts/generate-fr-audio.ps1
 *
 * Usage: node scripts/generate-fr-audio.mjs
 *        powershell -File scripts/generate-fr-audio.ps1
 */
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const MR = join(__dirname, "../apps/mobile/assets/audio/mr");
const FR = join(__dirname, "../apps/mobile/assets/audio/fr");

const PHRASES = {
  activateScore: "Activez votre NeoScore",
  allow: "Autoriser",
  amount: "Montant",
  back: "Retour",
  chooseLanguage: "Choisissez votre langue",
  client: "Client",
  confirm: "Confirmer",
  continue: "Continuer",
  createAccount: "Créer un compte",
  credit: "Crédit",
  debts: "Dettes",
  deny: "Refuser",
  displayName: "Nom affiché",
  eligible: "Éligible",
  entrepreneur: "Entrepreneur",
  expense: "Dépense",
  hello: "Bonjour",
  helloName: "Bonjour",
  home: "Accueil",
  iconMode: "Mode icônes",
  language: "Langue",
  ledger: "Cahier",
  listen: "Écouter",
  login: "Connexion",
  logout: "Déconnexion",
  neoscore: "NeoScore",
  newAccount: "Nouveau compte",
  next: "Suivant",
  notEligible: "Non éligible",
  overdue: "En retard",
  phone: "Téléphone",
  pinCode: "Code PIN",
  profile: "Profil",
  quickActions: "Actions rapides",
  receivable: "Créance",
  receiveCode: "Recevoir le code",
  record: "Enregistrer",
  register: "Inscription",
  sale: "Vente",
  salesMonth: "Ventes du mois",
  save: "Enregistrer",
  shareImf: "Partage IMF",
  smsCode: "Code SMS",
  stock: "Stock",
  submitCredit: "Soumettre la demande de crédit",
  toCollect: "À encaisser",
  voiceAssist: "Assistance vocale",
  yourActivity: "Votre activité",
};

mkdirSync(FR, { recursive: true });
writeFileSync(
  join(FR, "README.md"),
  `# Audio FR\n\nPhrases générées ou TTS Flutter.\n\nRégénérer : \`node scripts/generate-fr-audio.mjs\`\n`,
  "utf8"
);

const keys = existsSync(MR)
  ? readdirSync(MR)
      .filter((f) => f.endsWith(".wav"))
      .map((f) => f.replace(/\.wav$/, ""))
  : Object.keys(PHRASES);

let ok = 0;
let skip = 0;
for (const key of keys) {
  const text = PHRASES[key] ?? key;
  const out = join(FR, `${key}.mp3`);
  if (existsSync(out) || existsSync(join(FR, `${key}.wav`))) {
    skip += 1;
    continue;
  }
  const r = spawnSync(
    "edge-tts",
    ["--voice", "fr-FR-DeniseNeural", "--text", text, "--write-media", out],
    { encoding: "utf8" }
  );
  if (r.status === 0 && existsSync(out)) {
    ok += 1;
    console.log("OK", key);
  } else {
    console.warn(
      "SKIP",
      key,
      "— installez edge-tts (pip install edge-tts) ou utilisez le TTS Flutter"
    );
  }
}
console.log(`FR audio: ${ok} générés, ${skip} déjà présents, ${keys.length} clés`);
