<#
.SYNOPSIS
  Branche CE repo comme hote MCP "revit" (vanilla + outils KG) sur le poste. Idempotent.

.DESCRIPTION
  Le repo EST le pack d'installation. Ce script fait les 3 etapes qui ne sont PAS
  de simples copier-coller :

    1. BUILD  du serveur node (tsc) -> server/build/  (register.ts auto-enregistre les kg_*)
    2. REGISTRY  fusion des 16 commandes kg_* dans le commandRegistry.json CENTRAL du plugin
                 (lues depuis le command.json du cset KG deploye ; upsert par commandName)
    3. CONFIG  pointe ~/.claude.json serveur "revit" -> server/build/index.js de CE repo

  Ce qui reste des copies de fichiers (hors script) :
    - les .ts kg_*/kg/ sont deja dans ce repo (server/src)  -> rien a copier
    - les DLLs du cset KG (RevitMCPCommandSet.KG + BimKg.*) sont deployees par le repo B
      (revit-mcp.cset.kg -> DeployCommandSet). Ce script les VERIFIE, ne les copie pas.

  Rejouable sans risque : chaque etape est idempotente et sauvegarde avant d'ecrire.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -RevitVersion 2025 -SkipRegistry
#>
[CmdletBinding()]
param(
  [string]$RevitVersion = "2025",
  [string]$AddinsRoot   = "$env:APPDATA\Autodesk\Revit\Addins",
  [string]$ClaudeConfig = "$env:USERPROFILE\.claude.json",
  [string]$ServerName   = "revit",
  [string]$NodeExe,
  [switch]$SkipBuild,
  [switch]$SkipRegistry,
  [switch]$SkipConfig
)

$ErrorActionPreference = "Stop"
$RepoRoot   = $PSScriptRoot
$ServerDir  = Join-Path $RepoRoot "server"
$BuildIndex = Join-Path $ServerDir "build\index.js"
$CommandsDir = Join-Path $AddinsRoot "$RevitVersion\revit_mcp_plugin\Commands"
$Stamp = (Get-Date -Format "yyyyMMdd-HHmmss")

function Info($m)  { Write-Host "[install] $m" -ForegroundColor Cyan }
function Ok($m)    { Write-Host "[  ok   ] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "[ warn  ] $m" -ForegroundColor Yellow }

function Resolve-Node {
  if ($NodeExe -and (Test-Path $NodeExe)) { return $NodeExe }
  $c = Get-Command node -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $conda = "$env:LOCALAPPDATA\anaconda3\envs\revitmcp\node.exe"
  if (Test-Path $conda) { return $conda }
  throw "node introuvable sur le PATH ni dans conda revitmcp. Passe -NodeExe <chemin\node.exe>."
}

Info "repo   : $RepoRoot"
Info "revit  : $RevitVersion   addins: $AddinsRoot"
$node = Resolve-Node
Info "node   : $node"

# ------------------------------------------------------------------ 1. BUILD
if ($SkipBuild) { Warn "build ignore (-SkipBuild)" }
else {
  Info "build serveur node (tsc)..."
  $nodeDir = Split-Path $node
  $npmCli = Join-Path $nodeDir "node_modules\npm\bin\npm-cli.js"
  if (-not (Test-Path $npmCli)) { throw "npm-cli.js introuvable a cote de node : $npmCli" }
  # le cycle prebuild/clean rappelle 'npm' en commande nue -> il faut npm.cmd sur le PATH du sous-processus
  Push-Location $ServerDir
  $savedPath = $env:PATH
  try { $env:PATH = "$nodeDir;$env:PATH"; & $node $npmCli run build }
  finally { $env:PATH = $savedPath; Pop-Location }
  if ($LASTEXITCODE -ne 0) { throw "npm run build a echoue (code $LASTEXITCODE)" }
  if (-not (Test-Path $BuildIndex)) { throw "build absent apres tsc : $BuildIndex" }
  Ok "build -> $BuildIndex"
}

# --------------------------------------------------------------- 2. REGISTRY
if ($SkipRegistry) { Warn "registry ignore (-SkipRegistry)" }
else {
  $central = Join-Path $CommandsDir "commandRegistry.json"
  $kgJson  = Join-Path $CommandsDir "RevitMCPCommandSet.KG\command.json"
  $kgDll   = Join-Path $CommandsDir "RevitMCPCommandSet.KG\$RevitVersion\RevitMCPCommandSet.KG.dll"

  if (-not (Test-Path $central)) {
    Warn "commandRegistry.json central absent ($central) -> plugin vanilla pas deploye. Etape sautee."
  }
  elseif (-not (Test-Path $kgJson)) {
    Warn "cset KG pas deploye ($kgJson). Deploie-le d'abord (repo B revit-mcp.cset.kg -> DeployCommandSet). Etape sautee."
  }
  else {
    if (-not (Test-Path $kgDll)) { Warn "DLL cset KG absente ($kgDll) : les commandes seront enregistrees mais ne chargeront pas tant que la DLL n'est pas deployee." }
    Copy-Item $central "$central.bak-install-$Stamp"
    $mergeJs = @'
const fs = require('fs');
const [central, kgjson, ver] = process.argv.slice(1);
const reg = JSON.parse(fs.readFileSync(central, 'utf8'));
const kg  = JSON.parse(fs.readFileSync(kgjson, 'utf8'));
if (!Array.isArray(reg.Commands)) throw new Error('registre central : champ .Commands manquant');
const dev = kg.developer || { name: '', email: '', website: '', organization: '' };
let added = 0, updated = 0;
for (const c of (kg.commands || [])) {
  const entry = {
    commandName: c.commandName,
    assemblyPath: 'RevitMCPCommandSet.KG\\{VERSION}\\RevitMCPCommandSet.KG.dll',
    enabled: true,
    supportedRevitVersions: [ver],
    developer: dev,
    description: c.description || ''
  };
  const i = reg.Commands.findIndex(x => x.commandName === c.commandName);
  if (i >= 0) { reg.Commands[i] = entry; updated++; } else { reg.Commands.push(entry); added++; }
}
fs.writeFileSync(central, JSON.stringify(reg, null, 2));
console.log(`+${added} ajoutees, ${updated} mises a jour (${(kg.commands||[]).length} kg)`);
'@
    $res = & $node -e $mergeJs $central $kgJson $RevitVersion
    if ($LASTEXITCODE -ne 0) { throw "fusion registry echouee" }
    Ok "registry : $res  (backup: commandRegistry.json.bak-install-$Stamp)"
  }
}

# ----------------------------------------------------------------- 3. CONFIG
if ($SkipConfig) { Warn "config ignore (-SkipConfig)" }
elseif (-not (Test-Path $ClaudeConfig)) { Warn ".claude.json introuvable ($ClaudeConfig). Etape sautee." }
else {
  $cfgJs = @'
const fs = require('fs');
const [cfgPath, serverName, indexPath] = process.argv.slice(1);
const txt = fs.readFileSync(cfgPath, 'utf8');
const j = JSON.parse(txt);
const srv = (j.mcpServers || {})[serverName];
if (!srv)            { console.log('MISSING'); process.exit(3); }
const cur = (srv.args || [])[0];
if (cur === indexPath) { console.log('NOOP'); process.exit(0); }
if (!cur)            { console.log('NOARG'); process.exit(4); }
const from = JSON.stringify(cur);        // forme echappee telle qu'ecrite sur disque
const to   = JSON.stringify(indexPath);
if (!txt.includes(from)) { console.log('NOMATCH'); process.exit(5); }
fs.writeFileSync(cfgPath, txt.split(from).join(to));   // remplacement chirurgical, formatage preserve
console.log('UPDATED|' + cur);
process.exit(0);
'@
    Copy-Item $ClaudeConfig "$ClaudeConfig.bak-install-$Stamp"
    $out = & $node -e $cfgJs $ClaudeConfig $ServerName $BuildIndex
    $code = $LASTEXITCODE
    switch ($code) {
      0 {
        if ($out -eq 'NOOP') { Remove-Item "$ClaudeConfig.bak-install-$Stamp"; Ok "config deja a jour (serveur '$ServerName' -> ce repo)" }
        else { Ok "config : serveur '$ServerName' repointe (avant: $($out -replace '^UPDATED\|','')). Backup: .claude.json.bak-install-$Stamp" }
      }
      3 {
        Remove-Item "$ClaudeConfig.bak-install-$Stamp"
        Warn "aucun serveur '$ServerName' dans .claude.json. Ajoute sous mcpServers (slashes '/' acceptes par node sur Windows) :"
        $nodeSlash  = $node -replace '\\','/'
        $indexSlash = $BuildIndex -replace '\\','/'
        Write-Host @"
    "$ServerName": {
      "type": "stdio",
      "command": "$nodeSlash",
      "args": ["$indexSlash"],
      "env": { "KG_TOOLS": "on" }
    }
"@ -ForegroundColor Gray
      }
      default { Remove-Item "$ClaudeConfig.bak-install-$Stamp"; Warn "config non modifiee (code $code / $out) -> a ajuster a la main." }
    }
}

Write-Host ""
Ok "termine. Redemarre Claude Code (ou reconnecte le serveur '$ServerName') pour charger le build vanilla."
Info "verif Revit ouvert + socket 8080 : kg_session_info / kg_detect_drift / revit_execute."
