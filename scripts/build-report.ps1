# Rebuild the report after editing report/REPORT.template.md or collecting evidence.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $template = Get-Content -LiteralPath report/REPORT.template.md -Raw -Encoding UTF8
    $nodeVersion = (& node --version).Trim()
    $npmVersion = (& npm.cmd --version).Trim()
    $commander = Get-Content node_modules/commander/package.json -Raw | ConvertFrom-Json
    $superagent = Get-Content node_modules/superagent/package.json -Raw | ConvertFrom-Json
    $environment = @(
        '| Component | Version |',
        '|---|---|',
        "| Node.js | $nodeVersion |",
        "| npm | $npmVersion |",
        "| commander | $($commander.version) |",
        "| superagent | $($superagent.version) |",
        "| Windows | $([System.Environment]::OSVersion.VersionString) |",
        "| PowerShell | $($PSVersionTable.PSVersion) |"
    ) -join "`n"
    $history = (& git log --oneline) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Git history.' }
    $replacements = [ordered]@{
        '{{ENVIRONMENT}}' = $environment
        '{{GIT_LOG}}' = $history
        '{{PACKAGE_JSON}}' = (Get-Content package.json -Raw -Encoding UTF8).TrimEnd()
        '{{GITIGNORE}}' = (Get-Content .gitignore -Raw -Encoding UTF8).TrimEnd()
        '{{MAIN_JS}}' = (Get-Content main.js -Raw -Encoding UTF8).TrimEnd()
        '{{TEST_LOG}}' = (Get-Content test.txt -Raw -Encoding UTF8).TrimEnd()
    }
    foreach ($key in $replacements.Keys) { $template = $template.Replace($key, $replacements[$key]) }
    if ($template -match '\{\{(?:ENVIRONMENT|GIT_LOG|PACKAGE_JSON|GITIGNORE|MAIN_JS|TEST_LOG)\}\}') {
        throw 'Unresolved report placeholder.'
    }
    [System.IO.File]::WriteAllText((Join-Path (Get-Location).Path 'report/REPORT.md'),
        $template, [System.Text.UTF8Encoding]::new($false))
    Write-Host 'Report written: report/REPORT.md'
} finally { Pop-Location }
