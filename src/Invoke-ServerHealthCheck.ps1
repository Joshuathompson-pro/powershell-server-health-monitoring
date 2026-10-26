[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config\servers.example.json"),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\reports"),
    [string]$StatePath = (Join-Path $PSScriptRoot "..\state\health-state.json"),
    [switch]$UseSampleData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StatusLevel {
    param(
        [bool]$Reachable,
        [double]$CpuPercent,
        [double]$MemoryPercent,
        [double]$HighestDiskPercent,
        [int]$StoppedServiceCount,
        [pscustomobject]$Thresholds
    )

    if (-not $Reachable -or $HighestDiskPercent -ge $Thresholds.diskCriticalPercent) { return "Critical" }
    if ($CpuPercent -ge $Thresholds.cpuWarningPercent -or
        $MemoryPercent -ge $Thresholds.memoryWarningPercent -or
        $HighestDiskPercent -ge $Thresholds.diskWarningPercent -or
        $StoppedServiceCount -gt 0) { return "Warning" }
    return "Healthy"
}

function Get-SampleHealthData {
    param([pscustomobject]$Server)

    $sampleValues = @{
        "LAB-DC01"   = @{ Cpu = 18; Memory = 54; Disk = 61; Uptime = 18; Services = @() }
        "LAB-APP01"  = @{ Cpu = 42; Memory = 71; Disk = 84; Uptime = 9; Services = @() }
        "LAB-FILE01" = @{ Cpu = 23; Memory = 62; Disk = 92; Uptime = 31; Services = @("LanmanServer") }
    }
    $values = $sampleValues[$Server.name]
    if (-not $values) { $values = @{ Cpu = 20; Memory = 50; Disk = 60; Uptime = 7; Services = @() } }

    [pscustomobject]@{
        Reachable          = $true
        CpuPercent         = [double]$values.Cpu
        MemoryPercent      = [double]$values.Memory
        HighestDiskPercent = [double]$values.Disk
        UptimeDays         = [int]$values.Uptime
        StoppedServices    = @($values.Services)
        CollectionError    = $null
    }
}

function Get-RemoteHealthData {
    param([pscustomobject]$Server)

    $reachable = Test-Connection -TargetName $Server.name -Count 1 -TimeoutSeconds 2 -Quiet
    if (-not $reachable) {
        return [pscustomobject]@{ Reachable = $false; CpuPercent = 0; MemoryPercent = 0; HighestDiskPercent = 0; UptimeDays = 0; StoppedServices = @(); CollectionError = "Host did not respond to ICMP." }
    }

    try {
        $data = Invoke-Command -ComputerName $Server.name -ScriptBlock {
            param($ServiceNames)
            $os = Get-CimInstance Win32_OperatingSystem
            $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
            $memoryUsed = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100
            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
                if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) }
            }
            $stopped = foreach ($serviceName in $ServiceNames) {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if (-not $service -or $service.Status -ne "Running") { $serviceName }
            }
            [pscustomobject]@{
                CpuPercent         = [math]::Round($cpu, 1)
                MemoryPercent      = [math]::Round($memoryUsed, 1)
                HighestDiskPercent = [math]::Round(($disks | Measure-Object -Maximum).Maximum, 1)
                UptimeDays         = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
                StoppedServices    = @($stopped)
            }
        } -ArgumentList (, @($Server.criticalServices))

        [pscustomobject]@{
            Reachable          = $true
            CpuPercent         = $data.CpuPercent
            MemoryPercent      = $data.MemoryPercent
            HighestDiskPercent = $data.HighestDiskPercent
            UptimeDays         = $data.UptimeDays
            StoppedServices    = @($data.StoppedServices)
            CollectionError    = $null
        }
    }
    catch {
        [pscustomobject]@{ Reachable = $true; CpuPercent = 0; MemoryPercent = 0; HighestDiskPercent = 0; UptimeDays = 0; StoppedServices = @(); CollectionError = "Remote collection failed. Confirm WinRM and permissions." }
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Configuration file not found: $ConfigPath" }
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$reportTime = Get-Date

$results = foreach ($server in $config.servers) {
    $health = if ($UseSampleData) { Get-SampleHealthData -Server $server } else { Get-RemoteHealthData -Server $server }
    $status = Get-StatusLevel -Reachable $health.Reachable -CpuPercent $health.CpuPercent -MemoryPercent $health.MemoryPercent -HighestDiskPercent $health.HighestDiskPercent -StoppedServiceCount @($health.StoppedServices).Count -Thresholds $config.thresholds
    if ($health.CollectionError) { $status = "Critical" }

    [pscustomobject]@{
        CheckedAt          = $reportTime.ToString("s")
        Server             = $server.name
        Role               = $server.role
        Status             = $status
        Reachable          = $health.Reachable
        CpuPercent         = $health.CpuPercent
        MemoryPercent      = $health.MemoryPercent
        HighestDiskPercent = $health.HighestDiskPercent
        UptimeDays         = $health.UptimeDays
        StoppedServices    = (@($health.StoppedServices) -join ", ")
        CollectionError    = $health.CollectionError
    }
}

$null = New-Item -ItemType Directory -Force -Path $OutputDirectory
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StatePath)
$timestamp = $reportTime.ToString("yyyyMMdd-HHmmss")
$jsonPath = Join-Path $OutputDirectory "health-report-$timestamp.json"
$csvPath = Join-Path $OutputDirectory "health-report-$timestamp.csv"
$latestPath = Join-Path $OutputDirectory "health-report-latest.json"

$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $latestPath -Encoding utf8
$results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8

$previousState = @{}
if (Test-Path -LiteralPath $StatePath) {
    foreach ($entry in (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)) { $previousState[$entry.Server] = [int]$entry.ConsecutiveFailures }
}

$state = foreach ($result in $results) {
    $failures = if ($result.Status -eq "Critical") { 1 + [int]($previousState[$result.Server] ?? 0) } else { 0 }
    [pscustomobject]@{ Server = $result.Server; ConsecutiveFailures = $failures; LastStatus = $result.Status; LastCheckedAt = $result.CheckedAt }
}
$state | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $StatePath -Encoding utf8

$alerts = $state | Where-Object { $_.ConsecutiveFailures -ge $config.thresholds.consecutiveFailuresBeforeAlert }

Write-Host "`nSERVER HEALTH SUMMARY" -ForegroundColor Cyan
$results | Format-Table Server, Role, Status, CpuPercent, MemoryPercent, HighestDiskPercent, StoppedServices -AutoSize
Write-Host "Reports written to: $OutputDirectory"
if ($alerts) {
    Write-Warning ("Alert threshold reached for: " + (($alerts.Server) -join ", "))
}

[pscustomobject]@{
    CheckedAt = $reportTime
    Healthy   = @($results | Where-Object Status -eq "Healthy").Count
    Warning   = @($results | Where-Object Status -eq "Warning").Count
    Critical  = @($results | Where-Object Status -eq "Critical").Count
    Alerts    = @($alerts).Count
    JsonPath  = $jsonPath
    CsvPath   = $csvPath
}

