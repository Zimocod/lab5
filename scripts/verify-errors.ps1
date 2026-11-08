# Run from PowerShell: .\scripts\verify-errors.ps1
# Uses isolated caches and a test-only copy of main.js for upstream fault injection.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Push-Location (Split-Path $PSScriptRoot -Parent)
$folder = './test-output/stage7-' + [guid]::NewGuid().ToString('N')
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$script:checks = 0
$script:failures = 0
$script:requests = 0
$script:logWriter = [System.IO.StreamWriter]::new(
    (Join-Path (Get-Location).Path 'test.txt'), $true, [System.Text.UTF8Encoding]::new($false))
$script:logWriter.AutoFlush = $true

function Log([string]$Text) {
    $script:logWriter.WriteLine($Text)
}

function Check([bool]$Condition, [string]$Description) {
    $script:checks++
    if (-not $Condition) { $script:failures++ }
    Log "# PASS=$Condition : $Description"
    Write-Host "PASS=$Condition : $Description"
}

function Save-Utf8([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText((Join-Path (Get-Location).Path $Path), $Text,
        [System.Text.UTF8Encoding]::new($false))
}

function Final-Status([string]$Headers) {
    # Large uploads may have an interim 100 Continue before the final response.
    $statusLines = [regex]::Matches($Headers, '(?m)^HTTP/\S+ (\d{3}) ')
    if ($statusLines.Count -eq 0) { return 0 }
    return [int]$statusLines[$statusLines.Count - 1].Groups[1].Value
}

function Start-TestNode([string]$Label, [string[]]$NodeArgs) {
    $quoted = @()
    foreach ($argument in $NodeArgs) { $quoted += "'" + $argument + "'" }
    Log ("# Start hidden process: node " + ($quoted -join ' '))
    $process = Start-Process -FilePath (Get-Command node).Source -ArgumentList $NodeArgs `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput "$folder/$Label.log" `
        -RedirectStandardError "$folder/$Label.errors.log"
    $processes.Add($process)
    Start-Sleep -Milliseconds 800
    Check (-not $process.HasExited) "$Label started"
    if ($process.HasExited) { throw "$Label failed to start; see $folder" }
}

function Request {
    param([string]$Method, [string]$Route, [string]$Label, [int]$Status,
        [string]$Upload = '', [int]$Port = 32159, [string]$Source = '',
        [string[]]$Extra = @(), [int]$ExpectedCurl = 0)
    $headerFile = "$folder/$Label.headers"
    $bodyFile = "$folder/$Label.body"
    $curlArgs = @('--silent', '--show-error', '--stderr', "$folder/$Label.curl-errors",
        '--max-time', '20', '--noproxy', '*', '--path-as-is', '--request', $Method,
        '--dump-header', $headerFile, '--output', $bodyFile)
    if ($Upload) { $curlArgs += @('--header', 'Content-Type: image/jpeg', '--data-binary', "@$Upload") }
    $curlArgs += $Extra
    $curlArgs += "http://127.0.0.1:$Port$Route"
    $quoted = @()
    foreach ($argument in $curlArgs) { $quoted += "'" + $argument.Replace("'", "''") + "'" }
    Log ('curl.exe ' + ($quoted -join ' '))
    & curl.exe @curlArgs
    $curlCode = $LASTEXITCODE
    $script:requests++
    Check ($curlCode -eq $ExpectedCurl) "$Label curl=$curlCode expected=$ExpectedCurl"
    $headers = Get-Content -LiteralPath $headerFile -Raw
    Log "Get-Content -LiteralPath '$headerFile'"
    foreach ($line in ($headers -split "`r?`n")) { Log ('# ' + $line) }
    foreach ($line in (Get-Content -LiteralPath "$folder/$Label.curl-errors")) { Log ('# ' + $line) }
    if ($Status -gt 0) {
        Check ((Final-Status $headers) -eq $Status) "$Label HTTP $Status"
        if ($Source) {
            Check ($headers -match '(?im)^Content-Type: image/jpeg\r?$') "$Label JPEG"
            Check ($headers -match "(?im)^X-Image-Source: $([regex]::Escape($Source))\r?$") "$Label source=$Source"
        } else {
            Check ($headers -match '(?im)^Content-Type: text/plain; charset=utf-8\r?$') "$Label text"
            Log "Get-Content -LiteralPath '$bodyFile' -Encoding UTF8"
            Log ('# ' + (Get-Content -LiteralPath $bodyFile -Raw -Encoding UTF8))
        }
        if ($Status -eq 405) {
            Check ($headers -match '(?im)^Allow: GET, PUT, DELETE\r?$') "$Label Allow header"
        }
    }
}

function Check-Path([string]$Path, [bool]$Expected) {
    Log "Test-Path -LiteralPath '$Path'"
    Check ((Test-Path -LiteralPath $Path) -eq $Expected) "exists($Path)=$Expected"
}

function Check-Bytes([string]$Expected, [string]$Actual) {
    Log "Get-FileHash -LiteralPath '$Expected', '$Actual' -Algorithm SHA256"
    $hashes = @(Get-FileHash -LiteralPath $Expected, $Actual -Algorithm SHA256)
    foreach ($hash in $hashes) { Log ('# ' + $hash.Hash + ' ' + $hash.Path) }
    Check ($hashes[0].Hash -eq $hashes[1].Hash) "identical bytes: $Actual"
}

try {
    New-Item -ItemType Directory -Path "$folder/cache" -Force | Out-Null
    Log "`r`nStage 7: powershell.exe -NoProfile -File .\scripts\verify-errors.ps1"
    Log "# Artifacts: $folder; setup and assertions are in scripts/verify-errors.ps1."
    $originalHash = (Get-FileHash -LiteralPath './cati.jpg').Hash
    Start-TestNode 'main' @('main.js', '-h', '127.0.0.1', '-p', '32159', '-c', "$folder/cache")

    Request PUT /432 seed 201 -Upload './cati.jpg'
    Request GET /432 seed-get 200 -Source cache
    Check-Bytes './cati.jpg' "$folder/seed-get.body"
    Request PUT /432 empty 400
    Check-Bytes './cati.jpg' "$folder/cache/432.jpg"

    # The tail bytes test storage integrity, not JPEG decoding.
    $large = New-Object byte[] (16 * 1024 * 1024)
    $photo = [System.IO.File]::ReadAllBytes((Join-Path (Get-Location).Path 'output/custom/432.jpg'))
    [Array]::Copy($photo, $large, $photo.Length)
    [System.IO.File]::WriteAllBytes((Join-Path (Get-Location).Path "$folder/large.jpg"), $large)
    $oversized = New-Object byte[] (20 * 1024 * 1024 + 1)
    [System.IO.File]::WriteAllBytes((Join-Path (Get-Location).Path "$folder/oversized.bin"), $oversized)
    Request PUT /432 too-large 413 -Upload "$folder/oversized.bin"
    Check-Bytes './cati.jpg' "$folder/cache/432.jpg"
    Request PUT /433 too-large-chunked 413 -Upload "$folder/oversized.bin" -Extra @('-H', 'Transfer-Encoding: chunked')
    Check-Path "$folder/cache/433.jpg" $false
    Request PUT /432 interrupted 0 -Upload "$folder/large.jpg" -Extra @('--limit-rate', '32k', '--max-time', '0.2') -ExpectedCurl 28
    Request GET /432 after-interrupt 200 -Source cache
    Check-Bytes './cati.jpg' "$folder/after-interrupt.body"
    Request PUT /433 interrupted-new 0 -Upload "$folder/large.jpg" -Extra @('--limit-rate', '32k', '--max-time', '0.2') -ExpectedCurl 28
    Check-Path "$folder/cache/433.jpg" $false

    $invalidRoutes = @('/', '/abc', '/99', '/600', '/../cati.jpg', '/%2e%2e/cati.jpg', '/200?x=1')
    for ($i = 0; $i -lt $invalidRoutes.Count; $i++) {
        Request GET $invalidRoutes[$i] "invalid-$i" 400
    }
    Request POST /432 unsupported 405
    New-Item -ItemType Directory -Path "$folder/cache/418.jpg" | Out-Null
    Log "New-Item -ItemType Directory -Path '$folder/cache/418.jpg' | Out-Null"
    Request GET /418 read-error 500
    Request PUT /418 replace-error 500 -Upload './cati.jpg'
    Request DELETE /418 delete-error 500
    Check-Path "$folder/cache/418.jpg" $true
    Request GET /432 after-disk-errors 200 -Source cache
    Check-Bytes './cati.jpg' "$folder/after-disk-errors.body"

    # Concurrent PUT/GET must only return complete old or new file contents.
    $config = @()
    for ($i = 0; $i -lt 20; $i++) {
        if ($i -gt 0) { $config += 'next' }
        $config += 'url = "http://127.0.0.1:32159/432"'
        $config += 'noproxy = "*"'
        $config += 'max-time = 20'
        if ($i % 2 -eq 0) {
            $config += 'request = "PUT"'
            $config += 'data-binary = "@' + $folder + '/large.jpg"'
        } else { $config += 'request = "GET"' }
        $config += 'output = "' + $folder + '/race-' + $i + '.body"'
        $config += 'dump-header = "' + $folder + '/race-' + $i + '.headers"'
    }
    Save-Utf8 "$folder/race.curl" ($config -join "`n")
    Log "Get-Content -LiteralPath '$folder/race.curl'"
    foreach ($line in $config) { Log ('# ' + $line) }
    Log "curl.exe --silent --show-error --parallel --parallel-immediate --parallel-max 8 --config '$folder/race.curl'"
    curl.exe --silent --show-error --parallel --parallel-immediate --parallel-max 8 --config "$folder/race.curl"
    Check ($LASTEXITCODE -eq 0) 'parallel curl completed'
    $script:requests += 20
    $allowedHashes = @($originalHash, (Get-FileHash -LiteralPath "$folder/large.jpg").Hash)
    for ($i = 0; $i -lt 20; $i++) {
        $expected = 200
        if ($i % 2 -eq 0) { $expected = 201 }
        $headers = Get-Content -LiteralPath "$folder/race-$i.headers" -Raw
        Check ((Final-Status $headers) -eq $expected) "parallel request $i HTTP $expected"
        if ($i % 2 -eq 1) {
            $hash = (Get-FileHash -LiteralPath "$folder/race-$i.body").Hash
            Log "# parallel GET $i SHA256: $hash"
            Check ($allowedHashes -contains $hash) "parallel GET $i is a complete image"
        }
    }
    Check-Bytes "$folder/large.jpg" "$folder/cache/432.jpg"
    Check (@(Get-ChildItem -LiteralPath "$folder/cache" -Directory -Filter '.write-*').Count -eq 0) 'temporary directories cleaned after success and failure'
    Request DELETE /432 delete 200
    Request DELETE /432 delete-again 404

    # Fault injection changes only the source URL in an isolated copy of main.js.
    $mainText = Get-Content -LiteralPath main.js -Raw -Encoding UTF8
    if (-not $mainText.Contains('https://http.cat/')) { throw 'Source URL not found for fault injection.' }
    Save-Utf8 "$folder/main-under-test.mjs" ($mainText.Replace('https://http.cat/', 'http://127.0.0.1:32160/'))
    Save-Utf8 "$folder/source.mjs" @'
import http from 'node:http';
import { readFile } from 'node:fs/promises';
const image = await readFile('./output/custom/432.jpg');
const server = http.createServer(async (request, response) => {
  if (request.url === '/203') return; // No response: exercise the response timeout.
  if (request.url === '/201') {
    response.writeHead(200, { 'Content-Type': 'text/html' });
    response.end('<html>not an image</html>');
    return;
  }
  if (request.url === '/202' || request.url === '/204') {
    response.writeHead(200, { 'Content-Type': 'image/jpeg' });
    response.end(request.url === '/204' ? image : Buffer.alloc(0));
    return;
  }
  response.writeHead(request.url === '/200' ? 503 : 404);
  response.end('upstream failure');
});
server.listen(32160, '127.0.0.1');
'@
    Start-TestNode 'source' @("$folder/source.mjs")
    Start-TestNode 'proxy' @("$folder/main-under-test.mjs", '-h', '127.0.0.1', '-p', '32161', '-c', "$folder/upstream-cache")
    foreach ($code in @(200, 201, 202, 203, 205)) {
        Request GET "/$code" "upstream-$code" 404 -Port 32161
        Check-Path "$folder/upstream-cache/$code.jpg" $false
    }
    Request GET /204 upstream-good 200 -Port 32161 -Source 'http.cat'
    Check-Bytes './output/custom/432.jpg' "$folder/upstream-good.body"
    Check-Bytes './output/custom/432.jpg' "$folder/upstream-cache/204.jpg"
    Log '# Stop the local source to simulate connection refusal.'
    Stop-Process -Id $processes[1].Id
    Request GET /206 source-offline 404 -Port 32161
    Check-Path "$folder/upstream-cache/206.jpg" $false
    Request GET /204 cache-offline 200 -Port 32161 -Source cache
    Check-Bytes './output/custom/432.jpg' "$folder/cache-offline.body"
    Check ((Get-FileHash -LiteralPath './cati.jpg').Hash -eq $originalHash) 'original photo unchanged'
    foreach ($index in @(0, 2)) {
        $processes[$index].Refresh()
        Check (-not $processes[$index].HasExited) "server $index survived errors"
    }
    Log "# Requests=$script:requests; checks=$script:checks; failures=$script:failures"
    Write-Host "Requests=$script:requests; checks=$script:checks; failures=$script:failures; artifacts=$folder"
    if ($script:failures -gt 0) { throw "$script:failures checks failed." }
} finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    }
    foreach ($logFile in (Get-ChildItem -LiteralPath $folder -Filter '*.errors.log' -ErrorAction SilentlyContinue)) {
        Log ("# Server errors: " + $logFile.Name)
        foreach ($line in (Get-Content -LiteralPath $logFile.FullName -Encoding UTF8)) { Log ('# ' + $line) }
    }
    Log '# All test processes stopped; working cache was not modified.'
    $script:logWriter.Dispose()
    Pop-Location
}
