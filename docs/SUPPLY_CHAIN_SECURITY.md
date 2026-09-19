# 🛡️ Aegis Supply Chain Security: Cosign Signing & SBOM Attestation

Questo modulo implementa la sicurezza crittografica della **Software Supply Chain** conforme allo standard **SLSA Level 3** e alle linee guida **NIST SSDF**.

---

## 1. Architettura della Supply Chain

```
   ┌───────────────────────┐
   │  GitHub Actions CI    │
   │  (Backend & Frontend) │
   └──────────┬────────────┘
              │ 1. Build & Trivy Scan
              ▼
   ┌───────────────────────┐
   │ Generate CycloneDX    │
   │ SBOM (JSON)           │
   └──────────┬────────────┘
              │ 2. Cosign Sign & Attest
              ▼
   ┌───────────────────────┐
   │ OCI Registry          │ ◀─── Signed Image + OCI Signature Layer + SBOM Attestation
   │ (Docker Hub / GHCR)   │
   └──────────┬────────────┘
              │
              │ 3. Admission Request (Deploy)
              ▼
   ┌────────────────────────────────────────┐
   │ Kubernetes Admission Control (Kyverno) │
   │ • Verifies Cosign Cryptographic Sig    │
   │ • Verifies CycloneDX SBOM Predicate    │
   └──────────────────┬─────────────────────┘
                      │
           ┌──────────┴──────────┐
           │                     │
      ✅ Valid Sig          ❌ Missing / Unsigned
           ▼                     ▼
   🚀 Pod Started       🚫 403 Forbidden (Blocked)
```

---

## 2. Configurazione GitHub Secrets

Nei repository **`aegis-backend`** e **`aegis-frontend`**, configurare i seguenti Secrets (`Settings -> Secrets and variables -> Actions`):

| Secret | Descrizione | Valore |
|---|---|---|
| `COSIGN_PRIVATE_KEY` | Chiave privata Cosign crittografata | Contenuto del file `cosign.key` |
| `COSIGN_PASSWORD` | Passphrase della chiave privata | `aegis-enterprise-secret-2026` |
| `COSIGN_PUBLIC_KEY` | Chiave pubblica per verifiche | Contenuto del file `cosign.pub` |

---

## 3. Policy di Ammissione Kyverno (`k8s/12-kyverno-image-verify.yaml`)

Nel cluster Kubernetes, il controller Kyverno intercetta le richieste di creazione Pod nel namespace `aegis` e convalida che:
1. L'immagine provenga dal registry autorizzato (`oxiys/*`).
2. Sia presente una firma valida firmata dalla chiave pubblica aziendale `cosign.pub`.
3. Qualsiasi immagine non firmata (es. `nginx:alpine` o immagini di terze parti non verificate) viene bloccata all'ingresso prima che i nodi eseguano il pull.

---

## 4. Verifica Manuale da Terminale

Per verificare localmente l'integrità e la firma di qualsiasi immagine:

```powershell
# Verifica di un'immagine non firmata (Viene rifiutata)
.\scripts\verify-signatures.ps1 -Image "nginx:alpine"

# Verifica di un'immagine autentica firmata
.\scripts\verify-signatures.ps1 -Image "oxiys/backend:<tag>" -CheckAttestation
```
