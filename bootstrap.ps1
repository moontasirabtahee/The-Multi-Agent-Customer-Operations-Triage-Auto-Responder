<#
.SYNOPSIS
    One-command bring-up of the Multi-Agent Triage RAG pipeline on a fresh PC.

.DESCRIPTION
    Provisions and runs EVERYTHING the local workstation needs, in order:
      1. Verifies prerequisites (Python, Docker) and that Ollama is running with the
         required models pulled. Ollama install / `ollama pull` is the USER's job.
      2. Creates the .venv and installs requirements.txt.
      3. Creates backend/.env from the template and generates a Django SECRET_KEY.
      4. Launches the pgvector PostgreSQL container (idempotent).
      5. Runs Django migrations and seeds the knowledge base into pgvector.
      6. Starts the Django RAG API and runs a smoke test, writing a results log to
         .\logs\  (this is the artifact you commit as portfolio "proof of run").

.PARAMETER Port
    Port for the Django RAG API. Default 8000.

.PARAMETER Serve
    Leave the Django server running in the foreground (for live use / tunneling)
    instead of running the smoke test and shutting down.

.PARAMETER Reseed
    Force re-seeding the vector store even if it already contains rows.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1
    powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Serve -Port 8520
#>
param(
    [int]$Port = 8000,
    [switch]$Serve,
    [switch]$Reseed
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

function Info($m)  { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)   { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

Write-Host "=========================================================================" -ForegroundColor Magenta
Write-Host "   Multi-Agent Triage Pipeline - Bootstrap ($Stamp)" -ForegroundColor Magenta
Write-Host "=========================================================================" -ForegroundColor Magenta

# ---------------------------------------------------------------------------
# 1. Prerequisites (Python + Docker). Ollama is checked after we read .env.
# ---------------------------------------------------------------------------
Info "Checking prerequisites..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { Die "Python not found on PATH. Install Python 3.10+ and retry." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die "Docker not found on PATH. Install Docker Desktop and retry." }
try { docker info *> $null } catch { Die "Docker engine is not running. Start Docker Desktop and retry." }
Ok "Python and Docker are available."

# ---------------------------------------------------------------------------
# 2. .venv + dependencies
# ---------------------------------------------------------------------------
if (-not (Test-Path $Py)) {
    Info "Creating virtual environment (.venv)..."
    python -m venv (Join-Path $Root ".venv")
}
Info "Installing dependencies from requirements.txt..."
& $Py -m pip install --upgrade pip --quiet
& $Pip install -r (Join-Path $Root "requirements.txt") --quiet
Ok "Dependencies installed."

# ---------------------------------------------------------------------------
# 3. .env (create + generate SECRET_KEY)
# ---------------------------------------------------------------------------
if (-not (Test-Path $EnvFile)) {
    Info "Creating backend/.env from template..."
    Copy-Item $EnvSample $EnvFile
}
if ((Get-Content $EnvFile -Raw) -match "SECRET_KEY=django-insecure-change-me") {
    Info "Generating a Django SECRET_KEY..."
    $newKey = & $Py -c "from django.core.management.utils import get_random_secret_key as g; print(g())"
    (Get-Content $EnvFile) | ForEach-Object {
        if ($_ -match "^SECRET_KEY=") { "SECRET_KEY=$newKey" } else { $_ }
    } | Set-Content $EnvFile -Encoding UTF8
    Ok "SECRET_KEY generated."
}

# Parse the values we need out of .env
$cfg = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match "^\s*([A-Z_]+)\s*=\s*(.*)\s*$") { $cfg[$Matches[1]] = $Matches[2].Trim() }
}
$DbName = $cfg["DB_NAME"];     $DbUser = $cfg["DB_USER"]
$DbPass = $cfg["DB_PASSWORD"]; $DbPort = $cfg["DB_PORT"]
$OllamaHost = $cfg["OLLAMA_HOST"]; $LlmModel = $cfg["OLLAMA_LLM_MODEL"]; $EmbedModel = $cfg["OLLAMA_EMBED_MODEL"]

# ---------------------------------------------------------------------------
# 4. Ollama check (running + models pulled). NOT installed by this script.
# ---------------------------------------------------------------------------
Info "Checking Ollama at $OllamaHost ..."
try {
    $tags = Invoke-RestMethod -Uri "$OllamaHost/api/tags" -TimeoutSec 5
} catch {
    Die "Ollama is not reachable at $OllamaHost. Install Ollama, then run:`n      ollama serve`n      ollama pull $LlmModel`n      ollama pull $EmbedModel"
}
$have = @($tags.models | ForEach-Object { $_.name })
function HasModel($want) { foreach ($n in $have) { if ($n -eq $want -or $n -like "${want}:*") { return $true } } return $false }
$missing = @()
if (-not (HasModel $LlmModel))   { $missing += $LlmModel }
if (-not (HasModel $EmbedModel)) { $missing += $EmbedModel }
if ($missing.Count -gt 0) {
    Die "Ollama is running but these models are missing: $($missing -join ', ').`n      Pull them yourself:  $($missing | ForEach-Object { "ollama pull $_" } | Out-String)"
}
Ok "Ollama is running with '$LlmModel' and '$EmbedModel'."

# ---------------------------------------------------------------------------
# 5. pgvector container (idempotent)
# ---------------------------------------------------------------------------
$exists = (docker ps -a --filter "name=^/$Container$" --format "{{.Names}}")
if ($exists -eq $Container) {
    Info "Starting existing pgvector container '$Container'..."
    docker start $Container | Out-Null
} else {
    Info "Creating pgvector container '$Container' on host port $DbPort..."
    docker run -d --name $Container `
        -e POSTGRES_PASSWORD=$DbPass `
        -e POSTGRES_DB=$DbName `
        -p "$($DbPort):5432" `
        pgvector/pgvector:pg17 | Out-Null
}
Info "Waiting for PostgreSQL to accept connections..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    docker exec $Container pg_isready -U $DbUser *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { Die "PostgreSQL did not become ready in time." }
Ok "pgvector PostgreSQL is ready on port $DbPort."

# ---------------------------------------------------------------------------
# 6. Migrations + seed
# ---------------------------------------------------------------------------
Info "Running Django migrations..."
Push-Location (Join-Path $Root "backend")
& $Py manage.py migrate --noinput
Pop-Location

# Count rows in the vector store via the container's psql (guarded against a
# missing table). LlamaIndex prefixes the physical table with "data_".
$countSql = "SELECT CASE WHEN to_regclass('public.data_enterprise_knowledge_matrix') IS NULL THEN 0 ELSE (SELECT count(*) FROM data_enterprise_knowledge_matrix) END"
$rowRaw = (docker exec $Container psql -U $DbUser -d $DbName -tAc $countSql) 2>$null
$rowCount = 0; [void][int]::TryParse(("$rowRaw").Trim(), [ref]$rowCount)
if ($Reseed -or $rowCount -eq 0) {
    Info "Seeding knowledge base into pgvector (embeddings via Ollama)..."
    Push-Location (Join-Path $Root "backend")
    & $Py triage_api\seed_db.py
    Pop-Location
    Ok "Knowledge base seeded."
} else {
    Ok "Vector store already populated ($rowCount rows). Skipping seed (use -Reseed to force)."
}

# ---------------------------------------------------------------------------
# 7. Run Django (+ smoke test or serve)
# ---------------------------------------------------------------------------
$djangoLog = Join-Path $LogDir "django_$Stamp.log"
Info "Starting Django RAG API on 127.0.0.1:$Port (log: $djangoLog)..."
$django = Start-Process -FilePath $Py `
    -ArgumentList "manage.py","runserver","127.0.0.1:$Port","--noreload" `
    -WorkingDirectory (Join-Path $Root "backend") `
    -RedirectStandardOutput $djangoLog -RedirectStandardError "$djangoLog.err" `
    -PassThru -WindowStyle Hidden

# wait for health
$up = $false
for ($i = 0; $i -lt 20; $i++) {
    try { Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/v1/triage/rag/" -Method POST -Body '{}' -ContentType 'application/json' -TimeoutSec 5 *> $null } catch {}
    try { $t = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue; if ($t.TcpTestSucceeded) { $up = $true; break } } catch {}
    Start-Sleep -Seconds 1
}
if (-not $up) { Warn "Django did not report healthy; check $djangoLog" }
else { Ok "Django is serving on http://127.0.0.1:$Port" }

if ($Serve) {
    Write-Host ""
    Ok "SERVE mode: Django (PID $($django.Id)) is running."
    Write-Host "    RAG endpoint : http://127.0.0.1:$Port/api/v1/triage/rag/"
    Write-Host "    Tunnel it    : cloudflared tunnel --url http://127.0.0.1:$Port"
    Write-Host "    Stop it      : Stop-Process -Id $($django.Id)"
    exit 0
}

# --- Smoke test: produce the portfolio result log ---
$resultLog = Join-Path $LogDir "pipeline_result_$Stamp.log"
Info "Running smoke test -> $resultLog"
$queries = @(
    @{ label = "IN-KB (should answer from knowledge base)"; text = "What is your refund policy if server uptime falls below 99.9% in a quarter?" },
    @{ label = "OUT-OF-KB (should return ESCALATE_TO_HUMAN)"; text = "What color options are available for the mobile app icon?" }
)
$out = @()
$out += "Multi-Agent Triage RAG - Smoke Test Result"
$out += "Run: $Stamp   Model: $LlmModel   Embed: $EmbedModel"
$out += ("=" * 70)
foreach ($q in $queries) {
    $out += ""
    $out += "### $($q.label)"
    $out += "Query: $($q.text)"
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/v1/triage/rag/" -Method POST `
            -Body (@{ text = $q.text } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 180
        $out += "Status: $($resp.status)   Sources matched: $($resp.sources_matched)"
        $out += "Draft : $($resp.generated_draft)"
    } catch {
        $out += "ERROR: $($_.Exception.Message)"
    }
}
$out | ForEach-Object { Write-Host $_ }
$out | Out-File -FilePath $resultLog -Encoding utf8

Info "Stopping Django (smoke test complete)..."
Stop-Process -Id $django.Id -ErrorAction SilentlyContinue

Write-Host ""
Ok "Bootstrap complete. Result log: $resultLog"
Write-Host "    (The pgvector container '$Container' is left running; stop with: docker stop $Container)"
Write-Host "    Re-run live for tunneling with:  .\bootstrap.ps1 -Serve -Port $Port"
