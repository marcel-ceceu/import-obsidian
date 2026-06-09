# Handler local do protocolo msgm-folder://
# Abre pastas no Explorer usando o destino configurado pelo PWA Vault Copy.

param(
  [Parameter(Mandatory = $false)]
  [string]$Uri
)

$ErrorActionPreference = 'Stop'

$defaultBaseDir = 'C:\Users\Windows\Desktop\Area Trabalho\RESULTADOSGERAL'
$configDir = Join-Path $env:LOCALAPPDATA 'import-obsidian'
$configFile = Join-Path $configDir 'dest-base.txt'

function Get-DestBaseDir {
  if (Test-Path -LiteralPath $configFile) {
    $saved = (Get-Content -LiteralPath $configFile -Raw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($saved)) {
      return [System.IO.Path]::GetFullPath($saved)
    }
  }
  return [System.IO.Path]::GetFullPath($defaultBaseDir)
}

function Show-Error($message) {
  Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
  [System.Windows.MessageBox]::Show($message, 'msgm-folder', 'OK', 'Error') | Out-Null
}

function Open-Folder($folderPath) {
  $resolved = [System.IO.Path]::GetFullPath($folderPath)
  if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
    New-Item -ItemType Directory -Path $resolved -Force | Out-Null
  }
  Start-Process explorer.exe -ArgumentList "`"$resolved`""
}

function Get-QueryParam($raw, $name) {
  if ($raw -notmatch '\?') { return $null }
  $query = $raw.Substring($raw.IndexOf('?') + 1)
  foreach ($pair in $query.Split('&')) {
    if ([string]::IsNullOrWhiteSpace($pair)) { continue }
    $parts = $pair.Split('=', 2)
    if ($parts.Length -eq 2 -and $parts[0].Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
      return [System.Uri]::UnescapeDataString($parts[1])
    }
  }
  return $null
}

try {
  if ([string]::IsNullOrWhiteSpace($Uri)) {
    throw 'URI vazia.'
  }

  $raw = $Uri
  $fullPathParam = Get-QueryParam $raw 'p'
  if (-not [string]::IsNullOrWhiteSpace($fullPathParam)) {
    if (-not [System.IO.Path]::IsPathRooted($fullPathParam)) {
      throw 'Caminho absoluto obrigatorio.'
    }
    Open-Folder $fullPathParam
    exit 0
  }

  $prefix = 'msgm-folder://open/'
  if ($raw.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $leaf = $raw.Substring($prefix.Length)
    if ($leaf.Contains('?')) {
      $leaf = $leaf.Substring(0, $leaf.IndexOf('?'))
    }
  } elseif ($raw.StartsWith('msgm-folder:', [System.StringComparison]::OrdinalIgnoreCase)) {
    $leaf = $raw.Substring('msgm-folder:'.Length).TrimStart('/', '\')
    if ($leaf.Contains('?')) {
      $leaf = $leaf.Substring(0, $leaf.IndexOf('?'))
    }
  } else {
    throw "Protocolo invalido: $raw"
  }

  $leaf = [System.Uri]::UnescapeDataString($leaf)
  $baseDir = Get-DestBaseDir
  $resolvedBase = [System.IO.Path]::GetFullPath($baseDir)

  if ($leaf -eq 'RESULTADOSGERAL' -or [string]::IsNullOrWhiteSpace($leaf)) {
    Open-Folder $resolvedBase
    exit 0
  }

  if ($leaf -notmatch '^\d{6}-\d{4}_msgm_obsidian$') {
    throw "Nome de pasta nao permitido: $leaf"
  }

  $target = Join-Path $baseDir $leaf
  $resolvedTarget = [System.IO.Path]::GetFullPath($target)

  if (-not $resolvedTarget.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destino fora da pasta configurada.'
  }

  Open-Folder $resolvedTarget
} catch {
  Show-Error $_.Exception.Message
  exit 1
}
