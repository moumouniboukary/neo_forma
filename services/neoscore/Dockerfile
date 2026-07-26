# NeoForma NeoScore ML — solvabilité (inférence + entraînement)
# Image légère : pas de matplotlib/pandas (inutiles pour /score).
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY pipeline.py main.py ./
RUN mkdir -p artifacts
ENV PORT=10000
EXPOSE 10000
# Render injecte PORT — écouter 0.0.0.0 immédiatement (health check).
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-10000}"]
