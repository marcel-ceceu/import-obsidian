# Handler local do protocolo msgm-folder://
# Abre apenas subpastas do destino oficial RESULTADOSGERAL.

param(
  [Parameter(Mandatory = $false)]
  [string]$Uri
)

$ErrorActionPreference = 'Stop'

$baseDir = 'C:\Users\Windows\Desktop\Area Trabalho\RESULTADOSGERAL'

function Show-Error($message) {
  Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
  [System.Windows.MessageBox]::Show($message, 'msgm-folder', 'OK', 'Error') | Out-Null
}

try {
  if ([string]::IsNullOrWhiteSpace($Uri)) {
    throw 'URI vazia.'
  }

  $raw = $Uri
  $prefix = 'msgm-folder://open/'
  if ($raw.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $leaf = $raw.Substring($prefix.Length)
  } elseif ($raw.StartsWith('msgm-folder:', [System.StringComparison]::OrdinalIgnoreCase)) {
    $leaf = $raw.Substring('msgm-folder:'.Length).TrimStart('/', '\')
  } else {
    throw "Protocolo invalido: $raw"
  }

  $leaf = [System.Uri]::UnescapeDataString($leaf)

  if ($leaf -notmatch '^\d{6}-\d{4}_msgm_obsidian$') {
    throw "Nome de pasta nao permitido: $leaf"
  }

  $target = Join-Path $baseDir $leaf
  $resolvedBase = [System.IO.Path]::GetFullPath($baseDir)
  $resolvedTarget = [System.IO.Path]::GetFullPath($target)

  if (-not $resolvedTarget.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destino fora da pasta oficial.'
  }

  if (-not (Test-Path -LiteralPath $resolvedTarget -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedTarget -Force | Out-Null
  }

  Start-Process explorer.exe -ArgumentList "`"$resolvedTarget`""
} catch {
  Show-Error $_.Exception.Message
  exit 1
}
