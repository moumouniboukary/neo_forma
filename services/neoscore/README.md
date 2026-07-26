# Service ML NeoScore

Charge `DAMINA&POESAM_2026/NeoForma_NeoScore_Model.py` pour l’entraînement batch.

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Le **score runtime** de l’API utilise `@neoforma/neoscore` (TypeScript).
