$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$port = 8743
$prefix = "http://localhost:$port/"

$mimeMap = @{
    ".html" = "text/html; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".svg"  = "image/svg+xml"
    ".png"  = "image/png"
    ".ico"  = "image/x-icon"
}

function Find-Chrome {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return "chrome"
}

# Eén-knop-opstart: dit script ruimt eerst zelf alles van een vorige sessie op (oude
# server.ps1-processen + oud Chrome-appvenster van deze app) voordat het opnieuw start. Zo
# geeft dubbelklikken altijd een schone herstart, in plaats van dat een oude, nog draaiende
# server gewoon blijft hangen en de wijzigingen niet doorkomen.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*server.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*--app=$($prefix)*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 400

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try {
    $listener.Start()
} catch {
    Write-Host "Kon niet starten op poort $port - is die door iets anders in gebruik?" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

Write-Host "Champions Coach draait op $prefix" -ForegroundColor Green
Write-Host "Laat dit venster openstaan zolang je de app gebruikt." -ForegroundColor DarkGray

$chromeExe = Find-Chrome
try {
    $chromeProc = Start-Process -FilePath $chromeExe -ArgumentList "--app=$($prefix)index.html" -PassThru
} catch {
    Write-Host "Kon Chrome niet automatisch openen. Open zelf: $($prefix)Pokemon Champions Coach.html" -ForegroundColor Yellow
    $chromeProc = $null
}

while ($listener.IsListening) {
    if ($chromeProc -and $chromeProc.HasExited) { break }

    $contextTask = $listener.GetContextAsync()
    while (-not $contextTask.Wait(200)) {
        if ($chromeProc -and $chromeProc.HasExited) { break }
    }
    if ($chromeProc -and $chromeProc.HasExited) { break }
    if (-not $contextTask.IsCompleted) { continue }

    $context = $contextTask.Result
    $request = $context.Request
    $response = $context.Response
    try {
        $path = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrEmpty($path)) { $path = "index.html" }
        $filePath = Join-Path $root $path
        $full = [System.IO.Path]::GetFullPath($filePath)
        $rootFull = [System.IO.Path]::GetFullPath($root)

        if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            $response.StatusCode = 403
        } elseif (Test-Path $full -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($full).ToLower()
            $ctype = $mimeMap[$ext]
            if (-not $ctype) { $ctype = "application/octet-stream" }
            $response.ContentType = $ctype
            # Zonder dit koos de browser zelf hoe lang sw.js/html gecachet werd, waardoor een
            # CACHE-versie-bump in sw.js soms niet oppikte ondanks herstarten. Nooit cachen voor
            # deze twee, zodat elke update direct doorkomt.
            if ($ext -eq ".html" -or $path -eq "sw.js") {
                $response.Headers.Add("Cache-Control", "no-store, no-cache, must-revalidate")
                $response.Headers.Add("Pragma", "no-cache")
            }
            $bytes = [System.IO.File]::ReadAllBytes($full)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
        }
    } catch {
    } finally {
        $response.Close()
    }
}

$listener.Stop()
$listener.Close()
Write-Host "Champions Coach is gesloten." -ForegroundColor DarkGray
Start-Sleep -Seconds 1
