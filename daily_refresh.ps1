#!/usr/bin/env pwsh
# Compatibility entry point. The maintained implementation lives under bin/.
& (Join-Path $PSScriptRoot "bin\daily-refresh.ps1") @args
exit $LASTEXITCODE
