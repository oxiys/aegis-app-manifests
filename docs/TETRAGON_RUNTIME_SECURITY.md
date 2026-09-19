# 🧠 Aegis Kernel Runtime Security: Cilium Tetragon eBPF & Sigkill Enforcement

Questo modulo implementa la sicurezza a livello **Kernel Linux** all'interno dell'Aegis Platform Engine, utilizzando **Cilium Tetragon** e programmi **eBPF nativi**.

---

## 1. Architettura della Sicurezza Runtime

Mentre **Cilium CNI** protegge la superficie di attacco di **Rete** (L3/L4/L7), **Tetragon** monitora e protegge l'**interno dei container** a livello di chiamate di sistema (system call), accessi a file e ciclo di vita dei processi.

```
   ┌─────────────────────────────────────────────────────────────┐
   │                     POD (Namespace: aegis)                  │
   │                                                             │
   │   Attaccante / Script malevolo tenta:                       │
   │   $ cat /etc/shadow  (Tentativo furto credenziali)           │
   │         │                                                   │
   │         ▼ sys_openat("/etc/shadow")                         │
   ├─────────┼───────────────────────────────────────────────────┤
   │         ▼                                                   │
   │   LINUX KERNEL (eBPF Sensors: kprobe / tracepoints)         │
   │                                                             │
   │   ⚡ Cilium Tetragon intercetta la syscall prima            │
   │      che il file venga aperto                               │
   │                                                             │
   │   ⚡ Azione Kernel Immediata: SIGKILL                       │
   │      (Invia segnale 9 terminando il processo in microsec)   │
   │                                                             │
   │   ❌ Processo Terminato con Exit Code 137                   │
   │   📊 Evento emesso su Prometheus (tetragon_policy_events)   │
   │   🚨 Gate 5 su Grafana si illumina di ROSSO                 │
   └─────────────────────────────────────────────────────────────┘
```

---

## 2. Le TracingPolicy Implementate (`k8s/13-tetragon-tracing-policy.yaml`)

Le policy utilizzano il formato **`TracingPolicyNamespaced`**, garantendo uno **scoping rigoroso al solo namespace `aegis`**: i processi di sistema (`kube-system`, `argocd`, ecc.) e del cluster Kind non vengono impattati.

### A. `block-credential-theft` (Enforcement Rigido: Sigkill)
- **Syscall monitorata**: `sys_openat`
- **File sensibili**: `/etc/shadow`, `/etc/gshadow`
- **Azione**: **`Sigkill`** (terminazione istantanea del processo chiamante).

### B. `monitor-privilege-escalation` (Observability & Alerting)
- **Syscall monitorate**: `sys_setuid` e `sys_execve` (con target `/sudo`, `/su`).
- **Azione**: **`Post`** (audit, telemetria ed emissione metrica verso Prometheus per tracciare tentativi anomali senza rischiare blocchi a carichi legittimi).

---

## 3. Simulazione Live per Demo (LinkedIn Video)

### Test: Furto Credenziali Intercettato dal Kernel

Esegui questo comando nel terminale PowerShell:

```powershell
kubectl exec -n aegis deploy/backend -c backend -- cat /etc/shadow
```

**Risultato Immediato**:
```text
command terminated with exit code 137
```

> **Nota tecnica**: L'exit code `137` corrisponde a `128 + 9` (SIGKILL). Il processo `cat` è stato abbattuto dal kernel Linux prima ancora di poter leggere un singolo byte del file.

### Ispezione degli Eventi eBPF in Tempo Reale

Puoi visualizzare il flusso di eventi registrato dal demone Tetragon:

```powershell
kubectl exec -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact
```

Output:
```text
💥 kill aegis/backend-xxx /bin/cat /etc/shadow SIGKILL
```

---

## 4. Visualizzazione su Grafana (`http://localhost:3000`)

Sulla dashboard di Aegis:
* **`Gate 5: Kernel Security (Tetragon)`** nell'Executive Status in alto scatta istantaneamente in **ROSSO** con la dicitura:
  **`TERMINATED (Sigkill)`**
* Nel pannello inferiore **Tetragon Kernel Enforcement & Syscall Alerts**, la metrica `block-credential-theft` registra l'impennata di violazioni neutralizzate.
