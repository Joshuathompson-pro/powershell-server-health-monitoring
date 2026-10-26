Describe "Server health monitoring demo" {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $reportDirectory = Join-Path $TestDrive "reports"
        $statePath = Join-Path $TestDrive "state\health-state.json"
        $result = & (Join-Path $projectRoot "src\Invoke-ServerHealthCheck.ps1") -UseSampleData -OutputDirectory $reportDirectory -StatePath $statePath
    }

    It "checks every sample server" {
        (Get-Content -LiteralPath $result.JsonPath -Raw | ConvertFrom-Json).Count | Should -Be 3
    }

    It "exports JSON and CSV reports" {
        $result.JsonPath | Should -Exist
        $result.CsvPath | Should -Exist
    }

    It "classifies the sample data without using real infrastructure" {
        $result.Warning | Should -BeGreaterThan 0
        $result.Critical | Should -BeGreaterThan 0
    }
}

