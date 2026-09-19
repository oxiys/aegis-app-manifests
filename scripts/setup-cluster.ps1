<#
.SYNOPSIS
  Automated setup of the Kind cluster with Cilium (eBPF), OPA Gatekeeper, Argo CD,
  and the Aegis DevSecOps Observability Control Plane.
#>

$ErrorActionPreference = "Continue"
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Setting up Aegis DevSecOps Cluster & Control Plane (Kind)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Check prerequisites
$requiredCommands = @("docker", "kind", "kubectl", "helm")
foreach ($cmd in $requiredCommands) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "Error: Required tool '$cmd' is not installed or not in PATH." -ForegroundColor Red
        exit 1
    }
}

# Check if Docker daemon is actually running
Write-Host "Checking Docker daemon status..." -ForegroundColor Yellow
$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker Desktop non e' in esecuzione!" -ForegroundColor Red
    Write-Host "Avvia l'applicazione 'Docker Desktop' dal menu Start e attendi che sia attiva (Engine running)." -ForegroundColor Yellow
    exit 1
}

# 2. Create Kind Cluster
$clusterName = "aegis"
$existing = @()
$clusterCheck = (kind get clusters 2>&1)
if ($clusterCheck) {
    $existing = @($clusterCheck | Where-Object { $_ -notmatch "No kind clusters" })
}

if ($existing -contains $clusterName) {
    Write-Host "Cluster '$clusterName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "Creating Kind cluster '$clusterName' with default CNI disabled..." -ForegroundColor Green
    kind create cluster --name $clusterName --config (Join-Path $PSScriptRoot "..\kind-config.yaml")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Errore durante la creazione del cluster Kind." -ForegroundColor Red
        exit 1
    }
}

# 3. Add Helm Repositories
Write-Host "Configuring Helm repositories..." -ForegroundColor Green
helm repo add cilium https://helm.cilium.io/ 2>$null
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>$null
helm repo add argo https://argoproj.github.io/argo-helm 2>$null
helm repo update

# 4. Install Cilium with eBPF and Hubble drop metrics
Write-Host "Installing Cilium CNI with Hubble metrics (drop, flow, dns, tcp)..." -ForegroundColor Green
helm upgrade --install cilium cilium/cilium `
    --namespace kube-system `
    --set hubble.enabled=true `
    --set hubble.metrics.enabled="{dns,drop,tcp,flow}" `
    --set prometheus.enabled=true `
    --set operator.prometheus.enabled=true

# Wait for Cilium agent pods to be ready
Write-Host "Waiting for Cilium daemonset to become ready..." -ForegroundColor Yellow
kubectl -n kube-system rollout status ds/cilium --timeout=120s

# 5. Install OPA Gatekeeper with Audit metrics
Write-Host "Installing OPA Gatekeeper with Audit metrics enabled..." -ForegroundColor Green
helm upgrade --install gatekeeper gatekeeper/gatekeeper `
    --namespace gatekeeper-system `
    --create-namespace `
    --set audit.metrics.enabled=true `
    --set controllerManager.metrics.enabled=true

# 6. Install Argo CD
Write-Host "Installing Argo CD..." -ForegroundColor Green
helm upgrade --install argocd argo/argo-cd `
    --namespace argocd `
    --create-namespace `
    --set server.service.type=NodePort `
    --set server.service.nodePortHttp=32080 `
    --set metrics.enabled=true `
    --set server.metrics.enabled=true

# 7. Build and load application images into Kind
Write-Host "Building and loading local microservice images into Kind..." -ForegroundColor Green
docker build -t oxiys/backend:f589e5950f4d46c9a3f230ff1c49ba46fa45ac19 (Join-Path $PSScriptRoot "..\..\aegis-backend") > $null 2>&1
docker build -t oxiys/frontend:f589e5950f4d46c9a3f230ff1c49ba46fa45ac19 (Join-Path $PSScriptRoot "..\..\aegis-frontend") > $null 2>&1
kind load docker-image oxiys/backend:f589e5950f4d46c9a3f230ff1c49ba46fa45ac19 --name $clusterName
kind load docker-image oxiys/frontend:f589e5950f4d46c9a3f230ff1c49ba46fa45ac19 --name $clusterName

# 8. Deploy Observability Stack (Prometheus + Grafana)
Write-Host "Deploying Observability Stack (Prometheus & Grafana)..." -ForegroundColor Green
kubectl apply -f (Join-Path $PSScriptRoot "..\k8s\observability")

# 9. Deploy Aegis Application Manifests
Write-Host "Deploying Aegis Application, Policies, and StatefulSet..." -ForegroundColor Green
kubectl apply -f (Join-Path $PSScriptRoot "..\k8s")
Start-Sleep -Seconds 3
kubectl apply -f (Join-Path $PSScriptRoot "..\k8s\11-opa-policies.yaml") > $null 2>&1

# Retrieve Argo CD password
$argoPassword = "admin"
try {
    $b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>$null
    if ($b64) {
        $argoPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
    }
} catch {}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Setup Complete! Access your services:" -ForegroundColor Green
Write-Host '  Grafana Control Plane: http://localhost:3000 (o http://127.0.0.1:3000) [admin / admin]' -ForegroundColor Cyan
Write-Host '  Aegis Frontend App:    http://localhost:8080 (o http://127.0.0.1:8080)' -ForegroundColor Cyan
Write-Host '  Prometheus Server:     http://localhost:9090 (o http://127.0.0.1:9090)' -ForegroundColor Cyan
Write-Host "  Argo CD UI:            http://localhost:8081 [admin / $argoPassword]" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
