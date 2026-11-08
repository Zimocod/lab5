# Verifies the collection's HTTP order via curl, not the Postman runtime.
param([int]$Port = 3001)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Push-Location (Split-Path $PSScriptRoot -Parent)
$folder = './test-output/postman-sequence-' + [guid]::NewGuid().ToString('N')
$server = $null
$writer = [System.IO.StreamWriter]::new((Join-Path (Get-Location).Path 'test.txt'),
    $true, [System.Text.UTF8Encoding]::new($false))
$writer.AutoFlush = $true
$failures = 0
try {
    New-Item -ItemType Directory -Path $folder | Out-Null
    $collection = Get-Content -LiteralPath './postman/lab5.postman_collection.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($collection.item.Count -ne 11) { throw 'Review expected statuses for the changed collection.' }
    $baseUrl = $collection.variable[0].value
    if ($baseUrl -ne 'http://127.0.0.1:3001') { throw 'This script expects the default local test server.' }
    $baseUrl = "http://127.0.0.1:$Port"
    $expectedStatuses = @(@(200,404), @(200,404), @(200), @(200), @(201), @(200), @(200), @(404), @(404), @(405), @(200))
    $expectedSources = @('', '', 'http.cat', 'cache', '', 'cache', '', '', '', '', '')
    $writer.WriteLine("`r`nStage 8: two curl runs of the Postman collection's HTTP sequence.")
    $writer.WriteLine("powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\postman\check-sequence.ps1 -Port $Port")
    $writer.WriteLine("# Isolated cache: $folder/cache; actual Postman scripts/Runner are NOT executed here.")
    $writer.WriteLine("# Start hidden process: node main.js -h 127.0.0.1 -p $Port -c $folder/cache")
    $server = Start-Process -FilePath (Get-Command node).Source -ArgumentList @('main.js', '-h', '127.0.0.1', '-p', "$Port", '-c', "$folder/cache") `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput "$folder/server.log" -RedirectStandardError "$folder/errors.log"
    Start-Sleep -Milliseconds 800
    if ($server.HasExited) { throw "Test server did not start; check port $Port." }
    for ($run = 1; $run -le 2; $run++) {
        $times = @{}
        for ($i = 0; $i -lt $collection.item.Count; $i++) {
            $item = $collection.item[$i]
            $rawUrl = $item.request.url
            if ($rawUrl -isnot [string]) { $rawUrl = $rawUrl.raw }
            $url = $rawUrl.Replace('{{baseUrl}}', $baseUrl)
            $prefix = "$folder/run-$run-request-$i"
            $curlArgs = @('--silent', '--show-error', '--stderr', "$prefix.curl-errors", '--noproxy', '*', '--max-time', '25',
                '--request', $item.request.method, '--dump-header', "$prefix.headers", '--output', "$prefix.body", '--write-out', '%{time_total}')
            foreach ($header in $item.request.header) { $curlArgs += @('--header', ($header.key + ': ' + $header.value)) }
            if ($item.request.method -eq 'PUT') { $curlArgs += @('--data-binary', ('@' + $item.request.body.file.src)) }
            $curlArgs += $url
            $quoted = @()
            foreach ($argument in $curlArgs) { $quoted += "'" + $argument.Replace("'", "''") + "'" }
            $writer.WriteLine('curl.exe ' + ($quoted -join ' '))
            $timeOutput = & curl.exe @curlArgs
            $curlCode = $LASTEXITCODE
            $seconds = [double]::Parse(($timeOutput -join '').Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
            $headers = Get-Content -LiteralPath "$prefix.headers" -Raw
            $statuses = [regex]::Matches($headers, '(?m)^HTTP/\S+ (\d{3}) ')
            $status = 0
            if ($statuses.Count -gt 0) { $status = [int]$statuses[$statuses.Count - 1].Groups[1].Value }
            $passed = $curlCode -eq 0 -and $expectedStatuses[$i] -contains $status
            $source = $expectedSources[$i]
            if ($source) {
                $passed = $passed -and $headers -match '(?im)^Content-Type: image/jpeg\r?$'
                $passed = $passed -and $headers -match "(?im)^X-Image-Source: $([regex]::Escape($source))\r?$"
            } else {
                $passed = $passed -and $headers -match '(?im)^Content-Type: text/plain; charset=utf-8\r?$'
            }
            if ($i -eq 8) { $passed = $passed -and $headers -notmatch '(?im)^X-Image-Source:' }
            if ($i -eq 9) { $passed = $passed -and $headers -match '(?im)^Allow: GET, PUT, DELETE\r?$' }
            if ($i -eq 5) {
                $expectedHash = (Get-FileHash -LiteralPath 'output/custom/432.jpg').Hash
                $actualHash = (Get-FileHash -LiteralPath "$prefix.body").Hash
                $passed = $passed -and $expectedHash -eq $actualHash
                $writer.WriteLine("# Own JPEG SHA256: expected=$expectedHash actual=$actualHash")
            }
            $writer.WriteLine("Get-Content -LiteralPath '$prefix.headers'")
            foreach ($line in ($headers -split "`r?`n")) { $writer.WriteLine('# ' + $line) }
            foreach ($line in (Get-Content -LiteralPath "$prefix.curl-errors")) { $writer.WriteLine('# ' + $line) }
            $writer.WriteLine("# Run=$run; request=$i; HTTP=$status; curl=$curlCode; seconds=$seconds; passed=$passed")
            Write-Host "run=$run request=$i HTTP=$status passed=$passed"
            if (-not $passed) { $failures++ }
            if ($i -eq 2) { $times['source'] = $seconds * 1000 }
            if ($i -eq 3) { $times['cache'] = $seconds * 1000 }
        }
        $writer.WriteLine("# CURL timing only: run=$run; sourceMs=$($times['source']); cacheMs=$($times['cache'])")
        Write-Host "CURL timings: source=$($times['source']) ms; cache=$($times['cache']) ms"
    }
    $writer.WriteLine("# 22 HTTP requests; failures=$failures. This script does not execute Postman Runner or capture browser screenshots.")
    Write-Host "22 HTTP requests; failures=$failures; artifacts=$folder"
    if ($failures -gt 0) { throw "$failures HTTP checks failed." }
} finally {
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id }
    $writer.WriteLine('# Test server stopped; working cache was not modified.')
    $writer.Dispose()
    Pop-Location
}
