# Note — ajout des outils KG au serveur vanilla (2026-08-05)

Migration du serveur MCP `revit` de l'hôte `poc-baseline/server` vers cet hôte **vanilla**
(`revit-mcp.mcp-servers-for-revit/server`). Voir aussi `revit-kg/NOTE-REPRISE.md` point 10.

## Changements (purement additifs — aucun fichier suivi modifié)

19 fichiers **nouveaux**, copiés à l'identique depuis `poc-baseline/server` :

**`server/src/kg/`** (socle de transport, nouveau dossier)
- `mode.ts` — gate d'activation des outils kg (défaut = activé ; env `KG_BENCH_MODE`/`KG_TOOLS`)
- `socket.ts` — `kgSend`/`kgResult`/`kgError`, forward socket via `utils/ConnectionManager`
  (déjà présent, **identique** au poc-baseline)

**`server/src/tools/`** — 16 forwarders `kg_*` + 1 alias
- Lecture/écriture graphe : `kg_query`, `kg_annotate`, `kg_create_node`, `kg_modify_node`,
  `kg_delete_node`, `kg_get_by_revit_id`, `kg_traverse`, `kg_diff_since`, `kg_session_info`
- Drift + cycle : `kg_detect_drift`, `kg_resolve_drift`, `kg_update`, `kg_export`
- Dérivées : `kg_compute_adjacency`, `kg_compute_connects`, `kg_compute_containment`
- `revit_execute` — alias arbitraire-C# de `send_code_to_revit`

## Pourquoi c'est léger

- `server/src/tools/register.ts` **scanne le dossier dynamiquement** → les nouveaux outils
  s'enregistrent seuls, sans modifier `index.ts` ni le core.
- Surface totale : **47 outils** (30 vanilla d'origine + 17 ajoutés).

## Découplage add-in ↔ serveur (invariant)

- **Add-in Revit non touché** : le plugin C# + les commandsets (`RevitMCPCommandSet.KG.dll`,
  `BimKg.Core/Runtime`) ne sont **pas** rebuildés. Le socle `socket.ts` forwarde une commande
  socket **par son nom** au handler Revit existant. Ajouter/retirer un forwarder ne requiert
  **aucun** rebuild ni redéploiement de l'add-in, tant que le handler existe côté Revit.
- **Mais dépend du build du serveur node** : un forwarder `.ts` doit être compilé (`tsc`,
  `npm run build`) en `.js` pour être chargé. `server/build/` est **gitignored** — seul `src/`
  compte pour le dépôt.

## Côté Revit — déjà en place (rien à faire)

`mcp-servers-for-revit.addin` → `revit_mcp_plugin` (hôte vanilla actif) ;
`commandRegistry.json` référence déjà les 16 commandes `kg_*` → `RevitMCPCommandSet.KG.dll` ;
DLLs (`BimKg.Core/Runtime` + cset) déployées sous `…/Addins/2025/revit_mcp_plugin/Commands/`.

## Installation — `install.ps1` (le repo EST le pack)

Cloner ce repo puis : `powershell -ExecutionPolicy Bypass -File .\install.ps1`. Idempotent,
rejouable, sauvegarde avant chaque écriture. Fait les 3 étapes qui ne sont PAS de simples copies :
1. **build** node (`tsc` ; prépend le dossier node au PATH pour le cycle `prebuild/clean`) ;
2. **registry** — fusionne les 16 commandes `kg_*` dans le `commandRegistry.json` **central** du plugin,
   lues **depuis** le `command.json` du cset KG déployé (upsert par `commandName`, pas de liste en dur) ;
   saute proprement si le cset n'est pas déployé (→ `DeployCommandSet` du repo B) ;
3. **config** — repointe `~/.claude.json` serveur `revit` → `server/build/index.js` de ce repo
   (remplacement chirurgical, formatage préservé ; NOOP si déjà bon).

Params : `-RevitVersion -AddinsRoot -ClaudeConfig -ServerName -NodeExe -SkipBuild -SkipRegistry -SkipConfig`.
Les `.ts` (`kg/`, `kg_*`, `revit_execute`) sont déjà dans le repo — rien à copier. Les DLLs du cset
restent du ressort du repo B. Redémarrer Claude Code après pour charger le build.

## Config MCP

`~/.claude.json`, serveur `revit` : `poc-baseline\server\build\index.js`
→ `revit-mcp.mcp-servers-for-revit\server\build\index.js`.
Backup : `~/.claude.json.bak-vanilla-migration`. Rollback = restaurer ce backup (ou reflipper
le chemin). `env: KG_V2_TOOLS=on` laissé (inerte — `mode.ts` ne le lit pas, défaut = activé).
