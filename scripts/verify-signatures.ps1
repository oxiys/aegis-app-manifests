# ==============================================================================
# Aegis DevSecOps: Cosign Cryptographic Signature & SBOM Verification Script
# Validates container image integrity against the Aegis Enterprise Public Key
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Image = "oxiys/backend:f589e5950f4d46c9a3f230ff1c49ba46fa45ac19",
    [string]$PublicKey = "$PSScriptRoot\..\cosign.pub",
    [switch]$CheckAttestation
)

$ErrorActionPreference = "Stop"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "🛡️  Aegis Supply Chain Security: Cryptographic Verification" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# Locate Cosign binary
$cosignBin = Get-Command "cosign" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $cosignBin) {
    $localCosign = Join-Path (Resolve-Path "$PSScriptRoot\..") "cosign.exe"
    if (Test-Path $localCosign) {
        $cosignBin = $localCosign
    } else {
        Write-Error "Cosign binary not found in PATH or repo root. Run setup or place cosign.exe in repo root."
    }
}

Write-Host "Using Cosign binary: $cosignBin" -ForegroundColor Gray
Write-Host "Public Key: $PublicKey" -ForegroundColor Gray
Write-Host "Target Image: $Image" -ForegroundColor Yellow
Write-Host ""

if (-not (Test-Path $PublicKey)) {
    Write-Error "Public key file not found at: $PublicKey"
}

# Avoid docker-credential-desktop path issue when reading public images
if (-not (Get-Command "docker-credential-desktop" -ErrorAction SilentlyContinue)) {
    $tempDockerDir = Join-Path $env:TEMP "cosign_temp_docker"
    if (-not (Test-Path $tempDockerDir)) { New-Item -ItemType Directory -Path $tempDockerDir -Force | Out-Null }
    Set-Content -Path (Join-Path $tempDockerDir "config.json") -Value '{"auths":{}}'
    $env:DOCKER_CONFIG = $tempDockerDir
}

Write-Host "Verifying digital signature against Aegis Enterprise Key..." -ForegroundColor Cyan
try {
    $verifyOutput = & $cosignBin verify --key $PublicKey $Image 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ SIGNATURE VERIFIED: Image originates from authentic Aegis CI/CD pipeline!" -ForegroundColor Green
        Write-Host $verifyOutput -ForegroundColor DarkGray
    } else {
        Write-Host "❌ SIGNATURE REJECTED: Image signature is INVALID or MISSING!" -ForegroundColor Red
        Write-Host $verifyOutput -ForegroundColor DarkRed
    }
} catch {
    Write-Host "❌ Verification failed: $_" -ForegroundColor Red
}

if ($CheckAttestation) {
    Write-Host ""
    Write-Host "Verifying CycloneDX SBOM Attestation..." -ForegroundColor Cyan
    try {
        $attestOutput = & $cosignBin verify-attestation --key $PublicKey --type cyclonedx $Image 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ ATTESTATION VERIFIED: Valid CycloneDX SBOM attached to OCI manifest!" -ForegroundColor Green
        } else {
            Write-Host "❌ ATTESTATION NOT FOUND or INVALID!" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Attestation check error: $_" -ForegroundColor Red
    }
}

Write-Host "=================================================================" -ForegroundColor Cyan
