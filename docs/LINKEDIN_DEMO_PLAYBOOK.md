# 🎬 Aegis DevSecOps Control Plane: LinkedIn Demo Playbook

Questa guida ti accompagna passo-passo nella registrazione di un video demo ad alto impatto (durata consigliata: **45-60 secondi**) per mostrare su LinkedIn l'architettura **Aegis**, i suoi **4 Security Gates** e la **Dashboard Unificata su Grafana**.

---

## 🛠️ 1. Preparazione dell'Ambiente

Prima di avviare la registrazione, assicurati che il cluster sia attivo e funzionante:

```powershell
# Esegui lo script automatico (su PowerShell):
.\scripts\setup-cluster.ps1
```

Apri sul tuo browser le seguenti schede:
1. **Dashboard Grafana**: `http://localhost:3000` (già configurata con Dark Mode e auto-login come Admin).
2. **Argo CD**: `http://localhost:8081` (per mostrare la sincronizzazione dell'applicazione).
3. **Hubble UI** (opzionale se avviato con `cilium hubble ui`).
4. **Terminale / IDE**: per mostrare i comandi di trigger.

---

## 🎥 2. Scaletta di Registrazione (Storyboarding)

### SCENA 1: Panoramica del Control Plane (00:00 - 00:15)
* **Cosa inquadrare**: La dashboard **Aegis DevSecOps Control Plane** a schermo intero su Grafana.
* **Cosa mostrare**:
  * I 4 badge verdi in alto (**Gate 1: TruffleHog**, **Gate 2: Trivy**, **Gate 3: Gatekeeper**, **Gate 4: Cilium**).
  * La tabella delle **GitHub Actions** in tempo reale che mostra le ultime esecuzioni riuscite dei microservizi.
  * Il grafico di rete Cilium con zero pacchetti scartati (traffico legittimo tra Frontend, Backend e Postgres).
* **Narrativa / Didascalia**:
  > *"Single Pane of Glass: come orchestrare e visualizzare in tempo reale lo stato di sicurezza dall'ambiente di sviluppo (CI) fino al runtime eBPF (CD)."*

---

### SCENA 2: Trigger del Gate 1 (Secret Leak Prevention) (00:15 - 00:30)
* **Cosa fare**:
  1. Nel file `aegis-app-manifests/k8s/05-database-secret.yaml`, inserisci una chiave API fittizia ma con pattern riconoscibile (es. un token AWS o GitHub fittizio).
  2. Fai commit e push verso GitHub.
* **Cosa mostrare**:
  1. Nel tab GitHub Actions / Grafana: il workflow passa a 🟡 `In Progress`.
  2. **TruffleHog intercetta il secret**: lo step fallisce immediatamente con exit code 1.
  3. Il badge **Gate 1** in Grafana si accende di **ROSSO**.
  4. Mostra che la pipeline si arresta: l'immagine Docker **non viene compilata**, il commit sul manifest GitOps **non avviene** e ArgoCD **non effettua alcun rollout**.

---

### SCENA 3: Trigger del Gate 3 (Admission Control OPA Gatekeeper) (00:30 - 00:45)
* **Cosa fare**:
  Prova ad applicare a mano o via PR un deployment insicuro che tenta di disabilitare il filesystem in sola lettura:

  ```bash
  kubectl apply -f - <<EOF
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: rogue-pod
    namespace: aegis
  spec:
    replicas: 1
    selector:
      matchLabels:
        app: rogue
    template:
      metadata:
        labels:
          app: rogue
      spec:
        containers:
          - name: rogue
            image: nginx:alpine
            securityContext:
              readOnlyRootFilesystem: false
  EOF
  ```

* **Cosa mostrare**:
  * Il terminale mostra il rifiuto immediato del Webhook di ammissione di Kubernetes:
    ```
    Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
    Security Violation: Container 'rogue' must have securityContext.readOnlyRootFilesystem set to true.
    ```
  * In Grafana, il contatore **OPA Gatekeeper Violations** si incrementa in diretta.

---

### SCENA 4: Trigger del Gate 4 (Zero-Trust Network Drop con Cilium) (00:45 - 01:00)
* **Cosa fare**:
  Simula un attaccante o un componente compromesso che tenta di esfiltrare dati da PostgreSQL verso l'esterno o verso un IP arbitrario:

  ```bash
  # Entra nel pod Postgres ed effettua una chiamata di rete non autorizzata:
  kubectl exec -it -n aegis statefulset/postgres -c postgres -- ping -c 2 8.8.8.8
  ```

* **Cosa mostrare**:
  * La richiesta va in timeout (100% packet loss) perché la `CiliumNetworkPolicy` applica il default-deny sull'egress di Postgres.
  * In Grafana, il grafico **Cilium Dropped Network Packets** schizza verso l'alto con un picco colorato che segnala l'intervento del layer eBPF!

---

## 📝 3. Testo Consigliato per il Post LinkedIn (Copywriting)

Copia, adatta e pubblica questo testo accompagnato dal video:

```markdown
🛡️ Non un'altra Todo-App: Come ho costruito un'architettura DevSecOps & GitOps con 4 Security Gates e Dashboard Unificata.

Spesso sentiamo parlare di "Shift-Left", ma come appare nella realtà quando dobbiamo garantire che una vulnerabilità o un secret non raggiungano mai la produzione?

Per rispondere a questa domanda ho progettato "Aegis", un'architettura cloud-native a microservizi divisa in 3 repository e governata da una Single Pane of Glass su Grafana:

🔴 GATE 1 (Pre-Build & Secrets): TruffleHog blocca qualsiasi secret leak prima che inizi la build.
🔴 GATE 2 (Container Supply Chain): Trivy scansiona codice, Dockerfile e immagine generata. Solo le immagini prive di CVE High/Critical ricevono il tag GitOps SHA.
🔴 GATE 3 (Admission Control): OPA Gatekeeper verifica a livello cluster che ogni Pod rispetti lo standard PSS Restricted (read-only rootfs, zero automount dei token).
🔴 GATE 4 (Runtime Zero-Trust): Cilium (eBPF) blocca a livello kernel qualsiasi traffico di rete est-ovest o egress non esplicitamente dichiarato dalle Network Policies.

📊 In questo video potete vedere in tempo reale:
1. Il blocco preventivo della pipeline GitHub Actions al rilevamento di un segreto.
2. Il rifiuto immediato da parte di Gatekeeper di un manifest non conforme.
3. Il grafico eBPF di Cilium che intercetta e scarta in diretta tentativi di connessione egress non autorizzati.

Tecnologie utilizzate: Kubernetes, Kind, Cilium eBPF, Hubble, OPA Gatekeeper, Argo CD, Prometheus, Grafana, Trivy, TruffleHog, Docker, Python/Flask, Nginx.

I repository del progetto sono interamente open source:
👉 Manifests & Observability: https://github.com/oxiys/aegis-app-manifests
👉 Backend API: https://github.com/oxiys/aegis-backend
👉 Frontend Web: https://github.com/oxiys/aegis-frontend

Cosa ne pensate dell'approccio eBPF unito all'Admission Control? Come gestite i Security Gates nelle vostre pipeline?

#DevSecOps #Kubernetes #GitOps #Cilium #eBPF #Grafana #ArgoCD #CyberSecurity #CloudNative #DevOps
```
