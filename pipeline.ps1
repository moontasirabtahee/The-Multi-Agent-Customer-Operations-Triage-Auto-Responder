<#
.SYNOPSIS
    Single entry point that sets up and runs the ENTIRE local pipeline, or stops it.

.DESCRIPTION
    START (default):
      1. Verifies prerequisites (Python, Docker, cloudflared) and starts Ollama if
         it is not already running. Ollama install / `ollama pull` stays the USER's job.
      2. Creates the .venv + installs requirements.txt.
      3. Creates backend/.env from the template and generates a Django SECRET_KEY.
      4. Launches the pgvector PostgreSQL container (idempotent).
      5. Runs migrations and seeds the knowledge base into pgvector.
      6. Starts the Django RAG API (background), runs a smoke test, and logs to .\logs\.
      7. Opens two Cloudflare quick tunnels (Django + Ollama) and prints the exact
         values you must paste into the n8n workflow.

    STOP:
      .\pipeline.ps1 -Stop   tears down Django, both tunnels, and the DB container
      (Ollama is left running).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\pipeline.ps1
    powershell -ExecutionPolicy Bypass -File .\pipeline.ps1 -Port 8520
    powershell -ExecutionPolicy Bypass -File .\pipeline.ps1 -NoTunnel
    powershell -ExecutionPolicy Bypass -File .\pipeline.ps1 -Stop
#>
param(
    [int]$Port = 8520,
    [switch]$Stop,
    [switch]$Reseed,
    [switch]$NoTunnel
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$Py        = Join-Path $Root ".venv\Scripts\python.exe"
$Pip       = Join-Path $Root ".venv\Scripts\pip.exe"
$EnvFile   = Join-Path $Root "backend\.env"
$EnvSample = Join-Path $Root "backend\.env.example"
$Container = "triage_pgvector"
$LogDir    = Join-Path $Root "logs"
$Stamp     = Get-Date -Format "yyyyMMdd_HHmmss"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Info($m) { Write-Host "[*] $m"  -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m"  -ForegroundColor Yellow }
function Die($m)  { Write-Host "[X] $m"  -ForegroundColor Red; exit 1 }

# Resolve cloudflared (PATH, then the winget install location).
function Get-Cloudflared {
    $c = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$env:ProgramFiles (x86)\cloudflared\cloudflared.exe","$env:ProgramFiles\cloudflared\cloudflared.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

# ===========================================================================
# STOP MODE
# ===========================================================================
if ($Stop) {
    Info "Stopping the pipeline (Ollama is left running)..."
    $dj = (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).OwningProcess | Select-Object -Unique
    foreach ($procId in $dj) { try { Stop-Process -Id $procId -Force -ErrorAction Stop; Ok "Stopped Django (PID $procId)" } catch {} }
    Get-Process cloudflared -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force; Ok "Stopped tunnel (PID $($_.Id))" }
    try { docker stop $Container *> $null; Ok "Stopped container '$Container'" } catch { Warn "Container not running." }
    Ok "Pipeline stopped."
    exit 0
}

Write-Host "=========================================================================" -ForegroundColor Magenta
Write-Host "   Multi-Agent Triage Pipeline - START ($Stamp)" -ForegroundColor Magenta
Write-Host "=========================================================================" -ForegroundColor Magenta

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
Info "Checking prerequisites..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { Die "Python not found. Install Python 3.10+." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die "Docker not found. Install Docker Desktop." }
try { docker info *> $null } catch { Die "Docker engine not running. Start Docker Desktop and retry." }
$Cf = Get-Cloudflared
if (-not $NoTunnel -and -not $Cf) {
    Warn "cloudflared not found - skipping tunnels. Install it (winget install Cloudflare.cloudflared) or run with -NoTunnel."
    $NoTunnel = $true
}
Ok "Python + Docker ready."

# ---------------------------------------------------------------------------
# 2. .env (create + SECRET_KEY) and read config
# ---------------------------------------------------------------------------
if (-not (Test-Path $EnvFile)) { Info "Creating backend/.env from template..."; Copy-Item $EnvSample $EnvFile }

# venv first (needed to generate SECRET_KEY)
if (-not (Test-Path $Py)) { Info "Creating virtual environment (.venv)..."; python -m venv (Join-Path $Root ".venv") }
Info "Installing dependencies..."
& $Py -m pip install --upgrade pip --quiet
& $Pip install -r (Join-Path $Root "requirements.txt") --quiet
Ok "Dependencies installed."

if ((Get-Content $EnvFile -Raw) -match "SECRET_KEY=django-insecure-change-me") {
    Info "Generating a Django SECRET_KEY..."
    $newKey = & $Py -c "from django.core.management.utils import get_random_secret_key as g; print(g())"
    (Get-Content $EnvFile) | ForEach-Object { if ($_ -match "^SECRET_KEY=") { "SECRET_KEY=$newKey" } else { $_ } } | Set-Content $EnvFile -Encoding UTF8
    Ok "SECRET_KEY generated."
}

$cfg = @{}
Get-Content $EnvFile | ForEach-Object { if ($_ -match "^\s*([A-Z_]+)\s*=\s*(.*)\s*$") { $cfg[$Matches[1]] = $Matches[2].Trim() } }
$DbName = $cfg["DB_NAME"]; $DbUser = $cfg["DB_USER"]; $DbPass = $cfg["DB_PASSWORD"]; $DbPort = $cfg["DB_PORT"]
$OllamaHost = $cfg["OLLAMA_HOST"]; $LlmModel = $cfg["OLLAMA_LLM_MODEL"]; $EmbedModel = $cfg["OLLAMA_EMBED_MODEL"]

# ---------------------------------------------------------------------------
# 3. Ollama: start if needed, then verify the models are present
# ---------------------------------------------------------------------------
Info "Checking Ollama at $OllamaHost ..."
function Test-Ollama { try { Invoke-RestMethod -Uri "$OllamaHost/api/tags" -TimeoutSec 4 } catch { $null } }
$tags = Test-Ollama
if (-not $tags) {
    if (Get-Command ollama -ErrorAction SilentlyContinue) {
        Info "Ollama not responding - starting 'ollama serve'..."
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden | Out-Null
        for ($i = 0; $i -lt 15; $i++) { Start-Sleep 2; $tags = Test-Ollama; if ($tags) { break } }
    }
}
if (-not $tags) { Die "Ollama is not reachable at $OllamaHost. Install/start Ollama, then: ollama pull $LlmModel ; ollama pull $EmbedModel" }

$have = @($tags.models | ForEach-Object { $_.name })
function HasModel($want) { foreach ($n in $have) { if ($n -eq $want -or $n -like "${want}:*") { return $true } } return $false }
$missing = @()
if (-not (HasModel $LlmModel))   { $missing += $LlmModel }
if (-not (HasModel $EmbedModel)) { $missing += $EmbedModel }
if ($missing.Count -gt 0) { Die "Ollama is running but missing model(s): $($missing -join ', '). Pull them: $($missing | ForEach-Object { "`n      ollama pull $_" })" }
Ok "Ollama is up with '$LlmModel' + '$EmbedModel'."

# ---------------------------------------------------------------------------
# 4. pgvector container
# ---------------------------------------------------------------------------
$exists = (docker ps -a --filter "name=^/$Container$" --format "{{.Names}}")
if ($exists -eq $Container) { Info "Starting pgvector container..."; docker start $Container | Out-Null }
else {
    Info "Creating pgvector container on host port $DbPort..."
    docker run -d --name $Container -e POSTGRES_PASSWORD=$DbPass -e POSTGRES_DB=$DbName -p "$($DbPort):5432" pgvector/pgvector:pg17 | Out-Null
}
Info "Waiting for PostgreSQL..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) { docker exec $Container pg_isready -U $DbUser *> $null; if ($LASTEXITCODE -eq 0) { $ready = $true; break }; Start-Sleep 2 }
if (-not $ready) { Die "PostgreSQL did not become ready." }
Ok "pgvector ready on port $DbPort."

# ---------------------------------------------------------------------------
# 5. Migrate + seed
# ---------------------------------------------------------------------------
Info "Running migrations..."
Push-Location (Join-Path $Root "backend"); & $Py manage.py migrate --noinput; Pop-Location

$countSql = "SELECT CASE WHEN to_regclass('public.data_enterprise_knowledge_matrix') IS NULL THEN 0 ELSE (SELECT count(*) FROM data_enterprise_knowledge_matrix) END"
$rowRaw = (docker exec $Container psql -U $DbUser -d $DbName -tAc $countSql) 2>$null
$rowCount = 0; [void][int]::TryParse(("$rowRaw").Trim(), [ref]$rowCount)
if ($Reseed -or $rowCount -eq 0) {
    Info "Seeding knowledge base (embeddings via Ollama)..."
    Push-Location (Join-Path $Root "backend"); & $Py triage_api\seed_db.py; Pop-Location
    Ok "Knowledge base seeded."
} else { Ok "Vector store already has $rowCount rows (use -Reseed to rebuild)." }

# ---------------------------------------------------------------------------
# 6. Start Django + smoke test
# ---------------------------------------------------------------------------
$djangoLog = Join-Path $LogDir "django_$Stamp.log"
Info "Starting Django RAG API on 127.0.0.1:$Port ..."
$django = Start-Process -FilePath $Py `
    -ArgumentList "manage.py","runserver","127.0.0.1:$Port","--noreload" `
    -WorkingDirectory (Join-Path $Root "backend") `
    -RedirectStandardOutput $djangoLog -RedirectStandardError "$djangoLog.err" `
    -PassThru -WindowStyle Hidden
$up = $false
for ($i = 0; $i -lt 20; $i++) { $t = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue; if ($t.TcpTestSucceeded) { $up = $true; break }; Start-Sleep 1 }
if ($up) { Ok "Django serving on http://127.0.0.1:$Port (PID $($django.Id))" } else { Warn "Django health check failed - see $djangoLog" }

$resultLog = Join-Path $LogDir "pipeline_result_$Stamp.log"
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/v1/triage/rag/" -Method POST -Body (@{ text = "What is your refund policy if server uptime falls below 99.9% in a quarter?" } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 180
    $line = "Smoke test ($Stamp) model=$LlmModel : status=$($r.status) sources=$($r.sources_matched)`nDraft: $($r.generated_draft)"
    $line | Out-File -FilePath $resultLog -Encoding utf8
    Ok "Smoke test passed (sources matched: $($r.sources_matched)). Log: $resultLog"
} catch { Warn "Smoke test error: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
# 7. Cloudflare tunnels
# ---------------------------------------------------------------------------
$djUrl = $null; $olUrl = $null
function Start-QuickTunnel($name, $localUrl, $hostHeader) {
    $errLog = Join-Path $LogDir "tunnel_$name`_$Stamp.err"
    $cfArgs = @("tunnel","--url",$localUrl)
    if ($hostHeader) { $cfArgs += @("--http-host-header",$hostHeader) }
    Start-Process -FilePath $Cf -ArgumentList $cfArgs -RedirectStandardOutput "$errLog.out" -RedirectStandardError $errLog -WindowStyle Hidden | Out-Null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep 2
        $u = Select-String -Path $errLog,"$errLog.out" -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -ErrorAction SilentlyContinue |
             ForEach-Object { $_.Matches.Value } | Select-Object -First 1
        if ($u) { return $u }
    }
    return $null
}
if (-not $NoTunnel) {
    Info "Opening Cloudflare tunnels..."
    $djUrl = Start-QuickTunnel "django" "http://127.0.0.1:$Port" $null
    $olUrl = Start-QuickTunnel "ollama" "http://127.0.0.1:11434" "localhost:11434"
    if ($djUrl) { Ok "Django tunnel:  $djUrl" } else { Warn "Django tunnel URL not captured (check logs)." }
    if ($olUrl) { Ok "Ollama tunnel:  $olUrl" } else { Warn "Ollama tunnel URL not captured (check logs)." }
}

# ---------------------------------------------------------------------------
# Summary + n8n update instructions
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Magenta
Write-Host "   PIPELINE RUNNING" -ForegroundColor Green
Write-Host "=========================================================================" -ForegroundColor Magenta
Write-Host "  Django RAG API : http://127.0.0.1:$Port/api/v1/triage/rag/"
Write-Host "  pgvector DB    : container '$Container' on port $DbPort"
Write-Host "  Ollama model   : $LlmModel"
if (-not $NoTunnel) {
    Write-Host ""
    Write-Host "  UPDATE THESE IN n8n (quick-tunnel URLs change every run):" -ForegroundColor Yellow
    Write-Host "  -----------------------------------------------------------------------"
    Write-Host "  * OpenAI Chat Model + OpenAI Chat Model1  ->  Base URL:"
    Write-Host "        $olUrl/v1"
    Write-Host "  * HTTP Request (RAG call)                 ->  URL:"
    Write-Host "        $djUrl/api/v1/triage/rag/"
    Write-Host "  -----------------------------------------------------------------------"
}
Write-Host ""
Write-Host "  Stop everything with:  powershell -ExecutionPolicy Bypass -File .\pipeline.ps1 -Stop"
Write-Host ""
