$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$server = Join-Path $root "server"
Push-Location $server
try {
    if (-not (Test-Path -LiteralPath ".venv")) {
        python -m venv .venv
        .\.venv\Scripts\python.exe -m pip install -e ".[dev]"
    }
    $env:AI_MODE = "mock"
    Start-Process -WindowStyle Hidden -FilePath ".\.venv\Scripts\python.exe" -ArgumentList "-m", "app.worker"
    .\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
} finally {
    Pop-Location
}

