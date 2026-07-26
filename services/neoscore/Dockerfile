# NeoForma NeoScore ML — solvabilité (inférence + entraînement)
FROM python:3.12-slim

# libgomp requis par scikit-learn au runtime (sinon exit 1 à l'import)
RUN apt-get update \
  && apt-get install -y --no-install-recommends libgomp1 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY pipeline.py main.py ./
RUN mkdir -p artifacts

ENV PORT=10000
EXPOSE 10000
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-10000}"]
