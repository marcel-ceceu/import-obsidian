# Claude Vault Sync — Import to Obsidian

> **PWA single-file que orquestra a importação de conversas do Claude.ai pro Obsidian via PowerShell.**
> Stack: HTML/CSS/JS puro, sem build. Servido por Vercel. Script PowerShell consumido via `iwr` direto do raw do GitHub.

---

## 📖 Para o Cursor / LLM que está editando este repo

Leia esta seção **antes** de propor qualquer mudança. Várias decisões aqui parecem "estranhas" mas foram tomadas após validação empírica e tem motivo. **Não as reverta sem entender.**

### O que este projeto FAZ

Resolve um único problema: o pipeline manual de:
1. Pedir export de dados no `claude.ai` (Settings → Privacy → Export data)
2. Aguardar email, baixar ZIP de 40-150 MB
3. Extrair, encontrar `conversations.json`
4. Importar pra um vault Obsidian local sem duplicar conversas já existentes
5. Limpar blocos `This block is not supported on your current device yet` que poluem os `.md`

Existia antes como ~10 horas de trabalho manual fazendo CLI no terminal. Agora: 1 clique no PWA → cola no PowerShell → 3 segundos.

### O que este projeto NÃO FAZ (escopo)

- **Não** automatiza o pedido do export (Anthropic exige clique manual + verificação por email)
- **Não** gera tags via IA nos `.md` (foi removido propositalmente, ver decisão #2 abaixo)
- **Não** sincroniza em tempo real (sync é manual, on-demand)
- **Não** suporta multi-usuário ou multi-PC (caminhos hardcoded pro PC casa do Marcel)

### Decisões arquiteturais que o Cursor NÃO deve reverter

#### 1. HTML/CSS/JS puro, sem React/Vite/build

Foi avaliado e descartado. Justificativa:
- Escopo: 3 telas estáticas, 2 botões, 1 estado
- Bundle: 36KB vs ~150KB do React
- Zero build = zero pontos de falha em deploy
- Migração só justificada se aparecer dashboard com histórico, multi-PC ou logs em tempo real

Se o projeto crescer, **considere Alpine.js (7KB via CDN)** antes de migrar pra React.

#### 2. `Clean-ClaudeVault.ps1` aplica monkey-patch no `tagging.py` do `claude-vault`

Existe a função `OfflineTagGenerator.generate_metadata()` no pacote Python `claude-vault` que rodava pra cada conversa durante o sync. Tanto com Ollama LLM quanto com fallback de keyword extraction (heurística), levava ~2 min por conversa → 10 horas pra 309 conversas.

O script **substitui essa classe inteira por uma versão vazia** que retorna `{"tags": [], "summary": ""}` instantaneamente. Faz backup em `tagging.py.bak` antes. Trade-off: as tags AI são perdidas, mas:
- Busca full-text no Obsidian (`Ctrl+Shift+F` ou Omnisearch) já é excelente sem tags
- Pra reativar tags depois: rollback + `claude-vault retag --force` em background

**Se o LLM tentar "consertar" propondo um path mais limpo (config flag, env var, etc.):** já investigamos. O `claude-vault` não tem flag de config pra desabilitar tagging. O patch é o caminho menos invasivo conhecido.

#### 3. `Clean-ClaudeVault.ps1` é hospedado neste repo, servido via `raw.githubusercontent.com`, **não** via Vercel

O PWA é hospedado no Vercel (HTTPS, manifest, SW). Mas o `.ps1` é servido pelo `raw.githubusercontent.com/marcel-ceceu/import-obsidian/main/Clean-ClaudeVault.ps1`.

Por quê:
- Cada `git push` atualiza o `.ps1` instantaneamente sem trigger de rebuild do Vercel
- O `iwr` do PowerShell consome direto, sem CORS issues
- Vercel não precisa servir `.ps1` (alguns runtimes nem aceitam essa extensão)

#### 4. Caminhos hardcoded no `.ps1` apontam pro PC do Marcel

```powershell
$VaultPath       = "$env:USERPROFILE\Documents\ClaudeMsgm"
$DownloadsPath   = "$env:USERPROFILE\Downloads"
$ExportDir       = "$env:USERPROFILE\Desktop\claude-export"
$RepoPath        = "$env:USERPROFILE\claude-vault"
```

O usuário do Windows nesse PC é `Windows`, então `$env:USERPROFILE = C:\Users\Windows`. Outros PCs do Marcel (trabalho, note) **não** são suportados nesta versão. Parametrização multi-PC fica pra v6+.

#### 5. Encoding UTF-8 sem BOM via `[System.IO.File]::WriteAllText`

`Out-File -Encoding UTF8` no PowerShell 5.1 sempre escreve BOM (`0xEF 0xBB 0xBF`). Isso quebra o parsing JSON do `claude-vault`. A API .NET com `New-Object System.Text.UTF8Encoding($false)` é a única forma confiável.

#### 6. `$env:PYTHONIOENCODING = "utf-8"` no início do script

Resolve `UnicodeEncodeError: 'charmap' codec` quando o `rich` (lib Python usada pelo claude-vault) tenta imprimir emojis (📦) em terminais cp1252. Sem isso, o script funciona em terminal interativo mas crasha quando chamado via `powershell -File`.

---

## 🗂️ Estrutura de arquivos

| Arquivo | Função |
|---|---|
| `index.html` | PWA single-file: tutorial visual + 2 botões copy (one-liner e PS completo embutido) |
| `Clean-ClaudeVault.ps1` | Pipeline: detecta ZIP, extrai, patch tagging.py, sync, limpa `.md`, log |
| `manifest.json` | PWA manifest (instalável na desktop) |
| `service-worker.js` | Cache offline (estratégia cache-first) |
| `icon.svg` | Ícone do PWA (escalável) |
| `icon-192.png`, `icon-512.png` | Ícones PWA fallback pra dispositivos legacy |
| `vercel.json` | Headers e cache do Vercel |
| `.gitignore` | Boas práticas |
| `README.md` | Este arquivo |

---

## 🚀 Deploy passo a passo

### 1. Subir pro GitHub

```bash
cd import-obsidian/
git init
git add .
git commit -m "feat: kit inicial Claude Vault Sync v5.0 MVP"
git branch -M main
git remote add origin https://github.com/marcel-ceceu/import-obsidian.git
git push -u origin main
```

Repo precisa ser **público** (justificativa: o `iwr` do PowerShell não pode autenticar com PAT sem expor o token no HTML do PWA).

### 2. Deploy no Vercel

1. Acessar [vercel.com/new](https://vercel.com/new)
2. Importar `marcel-ceceu/import-obsidian`
3. Framework Preset: **Other** (deploy estático puro)
4. Root Directory: `./` (default)
5. Build Command: vazio
6. Output Directory: vazio
7. Clicar em **Deploy**

URL final: `https://import-obsidian.vercel.app` (ou similar, Vercel atribui)

### 3. Validar PWA

- Abrir a URL final no Chrome/Edge
- Esperado: header com "Claude Vault Sync", 3 fases visíveis, botão "Copiar comando" preto
- DevTools (`F12`) → Application → Manifest: deve mostrar manifest válido e ícones
- DevTools → Application → Service Workers: deve mostrar `service-worker.js` ativo
- Botão "Install" deve aparecer na barra de endereço (Chrome) ou no menu (Edge)

### 4. Testar pipeline end-to-end

No PC do Marcel (Windows):
1. Garantir que o repo `claude-vault` está clonado em `%USERPROFILE%\claude-vault\` com venv ativado e `pip install -e .` rodado
2. Garantir que existe um ZIP do Claude.ai em `~\Downloads\`
3. Abrir o PWA no navegador
4. Clicar em "Copiar comando"
5. Abrir PowerShell, colar (`Ctrl+V`), Enter
6. Esperado: Notepad abre com `LOG-SYNC[ddmmaa-hhmm].txt`, `[OK] Sync concluido em < 5s`, `Ainda com bloco sujo (recent): 0`

---

## 🛠️ Cenários típicos de edição

### Mudar texto do tutorial (ex: passo a passo da Fase 1)

Editar `index.html`. Os blocos relevantes estão em `<section class="phase">`. Tipografia/cores via CSS variables no `:root` no topo.

### Atualizar o script PowerShell

1. Editar `Clean-ClaudeVault.ps1`
2. `git add Clean-ClaudeVault.ps1 && git commit -m "fix: ..." && git push`
3. Automático: próxima vez que alguém clicar "Copiar comando" no PWA, o `iwr` vai baixar a nova versão (sem cache do GitHub raw)
4. Atualizar versão no header: `# Clean-ClaudeVault.ps1 - vX.Y NOME` e `Write-Log "===== ... vX.Y ..."` (2 lugares)

### Adicionar uma nova Fase no tutorial

1. Copiar uma `<section class="phase">` existente no `index.html`
2. Atualizar `<div class="phase-num">04</div>`, título, descrição, steps
3. Atualizar `.status-strip` no topo pra adicionar uma 4ª célula
4. Se a fase tiver botão de cópia, replicar o padrão `<div class="cmd-wrap">` + handler JS

### Trocar a paleta de cores

Tudo via CSS variables no início do `<style>`:

```css
:root {
  --paper: #F8F5F0;      /* fundo */
  --ink: #1A1614;        /* texto principal */
  --accent: #B53D2A;     /* carmesim de carimbo, headlines, hover */
  --ok: #2D6B3F;         /* validação positiva */
}
```

Theme color do navegador também em `<meta name="theme-color">` e em `manifest.json` → `theme_color`.

### Atualizar o icon

1. Editar `icon.svg` (texto/cores)
2. Regerar PNGs:
   ```bash
   python3 -c "import cairosvg; cairosvg.svg2png(url='icon.svg', write_to='icon-512.png', output_width=512, output_height=512)"
   python3 -c "import cairosvg; cairosvg.svg2png(url='icon.svg', write_to='icon-192.png', output_width=192, output_height=192)"
   ```
3. Bump `CACHE_VERSION` em `service-worker.js` pra forçar update no client (de `cv-sync-v1.0.0` pra `v1.0.1` etc.)
4. Commit + push

### Bump de versão sem mudar script

Editar em 3 lugares:
- `Clean-ClaudeVault.ps1` linha 2 (header) e linha do `Write-Log "===== ..."` 
- `index.html`: `<span class="brand-mark">CV · vX.Y MVP</span>`
- `service-worker.js`: `CACHE_VERSION = 'cv-sync-vX.Y.Z'`

---

## 👤 Contexto do usuário (Marcel)

Pra LLM entender melhor o contexto ao propor mudanças:

- **OS**: Windows 11
- **PC alvo**: PC casa (`$env:USERPROFILE = C:\Users\Windows`)
- **Outros PCs do usuário**: trabalho e note (fora de escopo deste repo)
- **Vault Obsidian alvo**: `C:\Users\Windows\Documents\ClaudeMsgm` (~1370 arquivos `.md` no momento)
- **Trabalho profissional**: operações Sankhya APESP/Dismafer (repo separado, privado)
- **Estilo de comunicação**: técnico, direto, sem fluff. Prefere copy-paste de comandos prontos no PowerShell. Aprecia decisões explícitas com tradeoffs e tabelas comparativas.
- **Skill peculiar**: trabalha bem com pipelines complexos mas valoriza simplicidade no resultado final
- **Aversões**: scripts longos com pouca documentação, dependências desnecessárias, "AI slop" estético (purple gradients, Inter font, etc.)

---

## 🧪 Validação de mudanças

Antes de propor qualquer alteração ao Marcel, validar:

1. **Sintaxe PowerShell**: rodar `Test-Path $script` e validar com `[System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)`
2. **HTML válido**: abrir no Chrome, verificar console por erros
3. **Idempotência do script**: rodar 2x, segunda execução deve mostrar `Unchanged: 309` (ou equivalente)
4. **PWA install**: Chrome DevTools → Application → Manifest sem warnings

---

## 📚 Glossário do domínio

| Termo | Significado |
|---|---|
| **vault** | Pasta raiz do Obsidian onde ficam os `.md` |
| **conversations.json** | Export oficial da Anthropic com todas as conversas do usuário |
| **claude-vault CLI** | Tool Python de terceiros (MarioPadilla/claude-vault) que parseia o JSON e gera os `.md` |
| **UUID tracking** | Cada conversa do Claude tem UUID único; o claude-vault usa SQLite interno (`.claude-vault/`) pra rastrear o que já foi sincronizado |
| **4 buckets** | New / Updated / Recreated / Unchanged — classificação que o claude-vault dá pra cada conversa do JSON cruzada contra o vault |
| **thinking em inglês** | Parágrafos de raciocínio interno do modelo que aparecem no export. v5.0 MVP NÃO remove (preserva pra busca/contexto) |
| **block unsupported** | Placeholder `This block is not supported on your current device yet` que aparece no lugar de blocos web_search, tool_use, etc. no export. v5.0 MVP remove. |
| **Ollama** | Runtime local de LLM, usado pelo claude-vault pra gerar tags. Desabilitado no v5.0 MVP via patch. |
| **POP** | Procedimento Operacional Padrão — formato de documentação que o Marcel usa no trabalho dele |

---

## 🔗 Links úteis

- Repo `claude-vault` upstream: [github.com/MarioPadilla/claude-vault](https://github.com/MarioPadilla/claude-vault)
- Doc Obsidian PWA install: [chromewebstore.google.com](https://web.dev/learn/pwa/installation)
- Vercel docs estático: [vercel.com/docs/frameworks/other](https://vercel.com/docs/frameworks/other)

---

*Última atualização: v5.0 MVP — Fase 1 do projeto Claude Vault PWA fechada.*
