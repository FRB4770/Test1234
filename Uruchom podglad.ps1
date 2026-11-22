param([switch]$NoBrowser)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$port = 8765
$url = "http://127.0.0.1:$port/"
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)

$mimeTypes = @{
  '.html' = 'text/html; charset=utf-8'
  '.htm'  = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.webp' = 'image/webp'
  '.gif'  = 'image/gif'
  '.ico'  = 'image/x-icon'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
  '.ttf'  = 'font/ttf'
}

try {
  $listener.Start()
  Write-Host ''
  Write-Host 'FRB preview is running on this computer only:' -ForegroundColor Green
  Write-Host $url -ForegroundColor Cyan
  Write-Host 'Keep this window open while testing. Press Ctrl+C here to stop.' -ForegroundColor Yellow
  if (-not $NoBrowser) { Start-Process $url }

  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $requestLine = $reader.ReadLine()
      while (($headerLine = $reader.ReadLine()) -ne $null -and $headerLine -ne '') {}
      if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }

      $requestParts = $requestLine.Split(' ')
      if ($requestParts.Length -lt 2) { continue }
      $method = $requestParts[0]
      $requestPath = [Uri]::UnescapeDataString(($requestParts[1] -split '\?')[0]).TrimStart('/')
      if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = 'index.html' }

      $filePath = [System.IO.Path]::GetFullPath((Join-Path $root $requestPath))
      if (-not $filePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = '403 Forbidden'
        $body = [System.Text.Encoding]::UTF8.GetBytes('Forbidden')
        $contentType = 'text/plain; charset=utf-8'
      } elseif (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $status = '404 Not Found'
        $body = [System.Text.Encoding]::UTF8.GetBytes('Not found')
        $contentType = 'text/plain; charset=utf-8'
      } else {
        $status = '200 OK'
        $body = [System.IO.File]::ReadAllBytes($filePath)
        $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
        $contentType = $mimeTypes[$extension]
        if (-not $contentType) { $contentType = 'application/octet-stream' }
      }

      $crlf = [string][char]13 + [char]10
      $header = "HTTP/1.1 $status" + $crlf + "Content-Type: $contentType" + $crlf + "Content-Length: $($body.Length)" + $crlf + "Cache-Control: no-store" + $crlf + "Connection: close" + $crlf + $crlf
      $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
      $stream.Write($headerBytes, 0, $headerBytes.Length)
      if ($method -ne 'HEAD' -and $body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
      $stream.Flush()
      $reader.Dispose()
      $stream.Dispose()
    } catch {
      Write-Host ('Preview request error: ' + $_.Exception.Message) -ForegroundColor DarkYellow
    } finally {
      $client.Dispose()
    }
  }
} finally {
  $listener.Stop()
}
