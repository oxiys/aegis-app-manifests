# AEGIS Mock App

Applicazione three-layer minimale per testare la pipeline CI/CD **AEGIS**.

```
Frontend (HTML/JS/Nginx) → Backend (Flask API) → Database (PostgreSQL)
```

## Dev Locale

```bash
docker-compose up --build
```

App su [http://localhost:3000](http://localhost:3000), API su [http://localhost:5000](http://localhost:5000).

## Deploy K8s

```bash
# Sostituisci ghcr.io/OWNER con il tuo registry
kubectl apply -f k8s/aegis.yaml
```

## Pipeline CI/CD

La pipeline GitHub Actions (`.github/workflows/aegis-pipeline.yml`) esegue:

1. **Lint** — flake8 sul backend
2. **SAST** — Bandit (analisi statica sicurezza Python)
3. **Build** — Docker build backend + frontend
4. **Scan** — Trivy vulnerability scan sulle immagini
5. **Push** — Push su GHCR (solo su `main`)
6. **Deploy** — `kubectl apply` su cluster K8s (solo su `main`)

### Secrets richiesti

| Secret | Descrizione |
|---|---|
| `GITHUB_TOKEN` | Automatico, usato per GHCR |
| `KUBECONFIG` | Kubeconfig base64-encoded per il cluster target |
