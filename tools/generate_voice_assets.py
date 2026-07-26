# -*- coding: utf-8 -*-
"""Génère les fichiers audio mooré pour l'app mobile.

Utilise le modèle Meta MMS-TTS (facebook/mms-tts-mos).
Sortie : apps/mobile/assets/audio/mr/{key}.wav
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
import scipy.io.wavfile
import torch
from transformers import AutoTokenizer, VitsModel

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_BASE = os.path.join(ROOT, "apps", "mobile", "assets", "audio")

# Textes repris de apps/mobile/lib/core/l10n/strings.dart
# (les clés avec variables {x} sont adaptées en phrase générique)
MR = {
    "hello": "Ne y yibeogo",
    "helloName": "Ne y yibeogo",
    "home": "Yĩnga",
    "ledger": "Gom-nate",
    "debts": "Sẽga",
    "profile": "Menga",
    "register": "Sõng-n yẽ",
    "newAccount": "Konti paalga",
    "phone": "Telefon",
    "smsCode": "SMS kode",
    "pinCode": "PIN kode",
    "displayName": "Yũure",
    "createAccount": "Maana konti",
    "receiveCode": "De kode",
    "continue": "Tõoke",
    "language": "Goama",
    "iconMode": "Bũumbu mode",
    "salesMonth": "Kõeesgo wãtẽ",
    "toCollect": "Sẽga n de",
    "overdue": "Yẽnde",
    "quickActions": "Tõe-tõe",
    "record": "Gom-nate",
    "credit": "Kredit",
    "neoscore": "NeoScore",
    "yourActivity": "Fõ tõe",
    "activateScore": "Neoge NeoScore",
    "save": "Jãnga",
    "logout": "Yi",
    "shareImf": "IMF tõe",
    "allow": "Sõnga",
    "deny": "Tõe ye",
    "sale": "Kõeesgo",
    "stock": "Stock",
    "receivable": "Sẽga",
    "expense": "Rẽem",
    "confirm": "Tõe",
    "amount": "Ligdi",
    "client": "Kient",
    "entrepreneur": "Tõe-soba",
    "chooseLanguage": "Baasa goama",
    "next": "Tõoke",
    "back": "Lebge",
    "voiceAssist": "Goama n wʋm",
    "listen": "Wʋm",
    "login": "Kẽ",
    "eligible": "Sõma",
    "notEligible": "Pa sõma yee",
    "submitCredit": "Tõe kredit",
}

LANGS = {
    "mr": ("facebook/mms-tts-mos", MR),
}


def generate(lang_dir: str, model_id: str, texts: dict) -> None:
    print(f"== {lang_dir}: chargement du modèle {model_id} ...", flush=True)
    tokenizer = AutoTokenizer.from_pretrained(model_id)
    model = VitsModel.from_pretrained(model_id)
    model.eval()
    out_dir = os.path.join(OUT_BASE, lang_dir)
    os.makedirs(out_dir, exist_ok=True)
    rate = model.config.sampling_rate
    for key, text in texts.items():
        inputs = tokenizer(text, return_tensors="pt")
        if inputs["input_ids"].shape[-1] == 0:
            print(f"  !! {key}: texte non tokenizable ({text!r}), ignoré", flush=True)
            continue
        with torch.no_grad():
            waveform = model(**inputs).waveform[0].numpy()
        pcm = np.clip(waveform, -1.0, 1.0)
        pcm16 = (pcm * 32767).astype(np.int16)
        path = os.path.join(out_dir, f"{key}.wav")
        scipy.io.wavfile.write(path, rate, pcm16)
        print(f"  ok {key}.wav ({len(pcm16) / rate:.1f}s) : {text}", flush=True)


if __name__ == "__main__":
    only = sys.argv[1] if len(sys.argv) > 1 else None
    for lang_dir, (model_id, texts) in LANGS.items():
        if only and lang_dir != only:
            continue
        generate(lang_dir, model_id, texts)
    print("GENERATION_DONE", flush=True)
