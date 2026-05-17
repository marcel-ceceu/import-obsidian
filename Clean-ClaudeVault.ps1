# ============================================================
# Clean-ClaudeVault.ps1  -  v5.0 MVP
# ------------------------------------------------------------
# Pipeline completo Claude.ai -> Obsidian (PC casa)
#
# v5.0 MVP: limpeza minima
#   - Remove SO blocos "This block is not supported on your current device yet"
#   - NAO remove thinking em ingles (preservado pra busca/contexto)
# v4.1: fix encoding UTF-8 (resolve crash do rich/emoji do claude-vault
#       no Windows legacy console quando rodado via powershell -File)
#
# PASSOS:
#   PRE   : valida vault, CLI, tagging.py
#   0     : detecta ZIP do Claude em Downloads + extrai
#   A     : aplica patch tagging.py (idempotente, skip se ja patched)
#   B     : claude-vault sync (incremental, UUID-based, sem duplicata)
#   C     : limpa .md modificados pelo sync (blocks + thinking ingles)
#   POS   : validacao final + log em Desktop
#
# Flags opcionais:
#   -SkipPatch  : nao re-aplica patch (assume que ja esta)
#   -SkipClean  : pula limpeza dos .md
#
# Pre-requisitos (instalados uma vez no PC casa):
#   - Python 3.13 + Git
#   - Repo claude-vault clonado em %USERPROFILE%\claude-vault
#   - venv criado + pip install -e .
#   - Vault Obsidian em %USERPROFILE%\Documents\ClaudeMsgm
#
# Rollback do patch (pra regenerar tags via Ollama):
#   Copy-Item "%USERPROFILE%\claude-vault\claude_vault\tagging.py.bak" `
#             "%USERPROFILE%\claude-vault\claude_vault\tagging.py" -Force
#   ollama serve  (em outra janela)
#   claude-vault retag --force
# ============================================================

[CmdletBinding()]
param(
    [switch]$SkipPatch,
    [switch]$SkipClean
)

$ErrorActionPreference = "Continue"

# --- Encoding fix (resolve crash do rich/emoji no Windows legacy console) ---
# Forca o stdout do Python pra UTF-8, evitando UnicodeEncodeError em cp1252
$env:PYTHONIOENCODING = "utf-8"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
} catch {}

# --- Caminhos (PC casa hardcoded) ---
$VaultPath       = "$env:USERPROFILE\Documents\ClaudeMsgm"
$ConvDir         = Join-Path $VaultPath "conversations"
$DownloadsPath   = "$env:USERPROFILE\Downloads"
$ExportDir       = "$env:USERPROFILE\Desktop\claude-export"
$ConvJsonPath    = "$ExportDir\conversations.json"
$RepoPath        = "$env:USERPROFILE\claude-vault"
$VenvActivate    = "$RepoPath\venv\Scripts\Activate.ps1"
$ClaudeVaultExe  = "$RepoPath\venv\Scripts\claude-vault.exe"
$TaggingPy       = "$RepoPath\claude_vault\tagging.py"
$TaggingPyBak    = "$RepoPath\claude_vault\tagging.py.bak"

# --- Log ---
$ts        = Get-Date -Format "ddMMyy-HHmm"
$LogPath   = "$env:USERPROFILE\Desktop\LOG-SYNC$ts.txt"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Log {
    param([string]$Msg, [string]$Color = "White")
    Write-Host $Msg -ForegroundColor $Color
    $Msg | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

Write-Log "===== Clean-ClaudeVault v5.0 MVP  -  $ts =====" Cyan
Write-Log ""

# ============================================================
# PRE-FLIGHT
# ============================================================
Write-Log "[PRE-FLIGHT] Validando..." Cyan
$preflightOk = $true

if (-not (Test-Path $VaultPath)) {
    Write-Log "  [X] Vault nao encontrado: $VaultPath" Red
    $preflightOk = $false
} else {
    Write-Log "  [OK] Vault: $VaultPath" Green
}
if (-not (Test-Path $ClaudeVaultExe)) {
    Write-Log "  [X] claude-vault.exe nao encontrado" Red
    $preflightOk = $false
} else {
    Write-Log "  [OK] CLI: $ClaudeVaultExe" Green
}
if (-not (Test-Path $TaggingPy)) {
    Write-Log "  [X] tagging.py nao encontrado" Red
    $preflightOk = $false
} else {
    Write-Log "  [OK] tagging.py existe" Green
}
if (-not (Test-Path $DownloadsPath)) {
    Write-Log "  [X] Downloads nao encontrado" Red
    $preflightOk = $false
} else {
    Write-Log "  [OK] Downloads: $DownloadsPath" Green
}

if (-not $preflightOk) {
    Write-Log "`n[ABORT] Pre-requisitos faltando. Veja o log." Red
    Start-Process notepad.exe $LogPath
    exit 1
}
Write-Log ""

# ============================================================
# PASSO 0  -  Detectar e extrair ZIP do Claude
# ============================================================
Write-Log "[PASSO 0] Detectando ZIP do Claude em Downloads..." Cyan
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = Get-ChildItem "$DownloadsPath\*.zip" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    ForEach-Object {
        try {
            $h = [IO.Compression.ZipFile]::OpenRead($_.FullName)
            $hit = $h.Entries | Where-Object Name -eq 'conversations.json'
            $h.Dispose()
            if ($hit) { $_ }
        } catch {}
    } | Select-Object -First 1

if (-not $zip) {
    Write-Log "  [X] Nenhum ZIP com conversations.json encontrado em $DownloadsPath" Red
    Write-Log "      Solicite o export em claude.ai -> Settings -> Privacy -> Export data" Yellow
    Write-Log "      Apos receber o email, baixe o ZIP em Downloads e re-execute" Yellow
    Start-Process notepad.exe $LogPath
    exit 2
}

$zipMb = [math]::Round($zip.Length / 1MB, 2)
Write-Log "  [OK] ZIP detectado: $($zip.Name) ($zipMb MB, $($zip.LastWriteTime))" Green

if (Test-Path $ExportDir) {
    Remove-Item $ExportDir -Recurse -Force
}
Expand-Archive -Path $zip.FullName -DestinationPath $ExportDir -Force

if (Test-Path $ConvJsonPath) {
    $jsonMb = [math]::Round((Get-Item $ConvJsonPath).Length / 1MB, 2)
    Write-Log "  [OK] conversations.json extraido: $jsonMb MB" Green
} else {
    Write-Log "  [X] Falha ao extrair conversations.json" Red
    Start-Process notepad.exe $LogPath
    exit 3
}
Write-Log ""

# ============================================================
# PASSO A  -  Patch tagging.py (idempotente)
# ------------------------------------------------------------
# Substitui OfflineTagGenerator por versao vazia.
# Razao: sync original chama generate_metadata() pra cada conv,
# que executa LLM (lento) OU keyword fallback (tambem lento).
# Com patch: sync vira ~1s/100 conversations.
# Pra regerar tags depois, rollback + retag separado.
# ============================================================
if (-not $SkipPatch) {
    Write-Log "[PASSO A] Verificando patch tagging.py..." Cyan
    $patchMarker = "PATCHED tagging.py - skip all tagging during sync"
    $current = Get-Content $TaggingPy -Raw -ErrorAction SilentlyContinue
    $alreadyPatched = $current -and ($current -match $patchMarker)

    if ($alreadyPatched) {
        Write-Log "  [OK] tagging.py ja esta patched" Green
    } else {
        if (-not (Test-Path $TaggingPyBak)) {
            Copy-Item $TaggingPy $TaggingPyBak -Force
            Write-Log "  [OK] Backup criado: $TaggingPyBak" Green
        }

        $patchContent = @'
"""PATCHED tagging.py - skip all tagging during sync for performance.

Restaurar original: Copy-Item tagging.py.bak tagging.py -Force
Regerar tags depois: claude-vault retag --force (com Ollama ligado, apos restore)
"""
from typing import List
from .models import Conversation


class OfflineTagGenerator:
    """PATCHED: returns empty metadata to skip tagging during sync."""

    def __init__(self):
        pass

    def is_available(self) -> bool:
        return False

    def generate_metadata(self, conversation: Conversation) -> dict:
        return {"tags": [], "summary": ""}

    def _fallback_metadata(self, conversation: Conversation) -> dict:
        return {"tags": [], "summary": ""}
'@
        Set-Content -Path $TaggingPy -Value $patchContent -Encoding UTF8
        Write-Log "  [OK] tagging.py patched" Green
    }
} else {
    Write-Log "[PASSO A] Patch - SKIPPED (-SkipPatch)" Yellow
}
Write-Log ""

# ============================================================
# PASSO B  -  Sync incremental
# ------------------------------------------------------------
# UUID + SQLite tracking do claude-vault classifica em 4 buckets:
#   New / Updated / Recreated / Unchanged
# Zero risco de duplicata (nome do .md = UUID + slug deterministico)
# ============================================================
Write-Log "[PASSO B] Sync incremental..." Cyan

$antes = (Get-ChildItem $ConvDir -Filter *.md -File -ErrorAction SilentlyContinue).Count
$syncStart = Get-Date

try {
    & $VenvActivate
    Push-Location $VaultPath
    & $ClaudeVaultExe sync $ConvJsonPath 2>&1 | ForEach-Object {
        Write-Log "  $_"
    }
    Pop-Location
} catch {
    Write-Log "  [X] Falha no sync: $_" Red
    Start-Process notepad.exe $LogPath
    exit 4
}

$syncDur = [math]::Round(((Get-Date) - $syncStart).TotalSeconds, 1)
$depois = (Get-ChildItem $ConvDir -Filter *.md -File).Count
$diff = $depois - $antes

Write-Log ""
Write-Log "  [OK] Sync concluido em $syncDur s" Green
Write-Log "  .md antes: $antes  |  depois: $depois  |  diferenca: +$diff" Green
Write-Log ""

# ============================================================
# PASSO C  -  Limpeza MVP dos .md modificados pelo sync
# ------------------------------------------------------------
# Cutoff = inicio do sync. So toca em arquivos novos/atualizados.
# Remove APENAS:
#  - blocos ```\nThis block is not supported on your current device yet.\n```
# Preserva tudo o resto, incluindo thinking em ingles.
# Normaliza: UTF-8 sem BOM, 3+ linhas em branco -> 2
# ============================================================
if (-not $SkipClean) {
    Write-Log "[PASSO C] Limpando blocos quebrados (MVP)..." Cyan

    $mdFiles = Get-ChildItem $ConvDir -Filter *.md -File |
        Where-Object { $_.LastWriteTime -ge $syncStart.AddSeconds(-5) }
    Write-Log "  Arquivos a varrer: $($mdFiles.Count)" White

    $rxBlockUnsupported = '(?ms)^``` *\r?\nThis block is not supported on your current device yet\.\s*\r?\n``` *\r?\n?'

    $filesChanged   = 0
    $blocksRemoved  = 0

    foreach ($f in $mdFiles) {
        try {
            $content = [System.IO.File]::ReadAllText($f.FullName, $utf8NoBom)
        } catch { continue }
        $original = $content

        # Remove blocos "This block is not supported"
        $m1 = [regex]::Matches($content, $rxBlockUnsupported)
        if ($m1.Count -gt 0) {
            $content = [regex]::Replace($content, $rxBlockUnsupported, '')
            $blocksRemoved += $m1.Count
        }

        # Normaliza: 3+ linhas em branco -> 2
        $content = [regex]::Replace($content, '(\r?\n){3,}', "`r`n`r`n")

        if ($content -ne $original) {
            try {
                [System.IO.File]::WriteAllText($f.FullName, $content, $utf8NoBom)
                $filesChanged++
            } catch {}
        }
    }

    Write-Log "  Arquivos modificados : $filesChanged / $($mdFiles.Count)" Green
    Write-Log "  Blocos removidos     : $blocksRemoved" Green
} else {
    Write-Log "[PASSO C] Limpeza - SKIPPED (-SkipClean)" Yellow
}
Write-Log ""

# ============================================================
# POS-FLIGHT  -  Validacao
# ============================================================
Write-Log "[POS-FLIGHT] Validacao..." Cyan

$totalFinal = (Get-ChildItem $ConvDir -Filter *.md -File).Count

$stillDirty = 0
Get-ChildItem $ConvDir -Filter *.md -File |
    Where-Object { $_.LastWriteTime -ge $syncStart.AddSeconds(-5) } |
    ForEach-Object {
        try {
            if ([System.IO.File]::ReadAllText($_.FullName, $utf8NoBom) -match 'This block is not supported') {
                $stillDirty++
            }
        } catch {}
    }

Write-Log "  Total .md no vault           : $totalFinal" Green
$dirtyColor = if ($stillDirty -eq 0) { "Green" } else { "Yellow" }
Write-Log "  Ainda com bloco sujo (recent): $stillDirty" $dirtyColor
Write-Log ""
Write-Log "===== FIM  -  Log em $LogPath =====" Cyan

Start-Process notepad.exe $LogPath
exit 0
