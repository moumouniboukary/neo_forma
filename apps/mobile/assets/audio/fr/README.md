# Audio français

48 fichiers `.wav` générés (voix système Windows / `System.Speech`).

Régénérer :

```powershell
powershell -File scripts/generate-fr-audio.ps1
```

Alternative edge-tts (si disponible) :

```bash
pip install edge-tts
node scripts/generate-fr-audio.mjs
```
