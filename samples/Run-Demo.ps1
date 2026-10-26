$projectRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $projectRoot "src\Invoke-ServerHealthCheck.ps1") -UseSampleData -OutputDirectory (Join-Path $projectRoot "reports")

