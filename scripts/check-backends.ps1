$ErrorActionPreference = 'Stop'
& node (Join-Path $PSScriptRoot 'check-backends.mjs')
exit $LASTEXITCODE
