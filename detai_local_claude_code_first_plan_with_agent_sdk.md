# Local Claude Code First (with Claude Agent SDK) — Determinant AI Roblox Studio Plugin Plan

This plan builds the **end-to-end “local Claude Code first” workflow** and explicitly includes how the **Claude Code SDK** (now **Claude Agent SDK**) fits in, via a local daemon.

**You will end up with:**
- Studio plugin can **export all scripts** to a local repo
- Local daemon can run **Claude Agent SDK** tasks **inside that repo** (plus bash tools)
- Studio plugin can **pull changes** and **sync them back** to Studio with preview/apply/undo and conflict handling

---

## 1) Target workflow (v1)

### A) Export → Local
1) In Studio, click **Export Scripts**  
2) Plugin enumerates all `Script`, `LocalScript`, `ModuleScript`  
3) Plugin reads text:
   - if a script is open in the editor: export the live editor buffer
   - otherwise: export stored source
4) Plugin pushes a snapshot to **local daemon** (`localhost`)
5) Daemon writes files into repo and updates a manifest

### B) Run Claude Agent SDK locally (and bash tools)
6) In Studio, click **Run Claude Task** (or use chat command)  
7) Plugin sends:
   - task instruction (natural language)
   - optional “scope” (includePaths / focusFiles)
   - optional selection context
8) Daemon runs Claude Agent SDK with cwd = repo root, allowing tools to read/edit files
9) Daemon writes changes to disk, updates revision, and returns a summary + changed files

### C) Import → Studio
10) Plugin pulls changes (manual or auto poll)
11) Plugin shows Diff Preview (list of scripts changed)
12) Click **Apply** → plugin syncs updated sources back into the correct scripts
13) All changes land in one Undo step

### D) Conflicts
14) If local and Studio changed the same script since last sync:
- show conflict UI: **Use Local / Keep Studio / Open Diff**
- do not auto-apply

---

## 2) Architecture

### 2.1 Studio Plugin
**Responsibilities**
- enumerate scripts + read text
- stable id per script (attribute)
- push snapshot → daemon
- request agent runs → daemon
- pull changed files → daemon
- preview/apply changes back to Studio
- conflicts + undo grouping + basic status UI

### 2.2 Local Daemon
**Responsibilities**
- own filesystem repo + manifest
- accept full snapshots from Studio
- watch repo for changes and track revisions
- run Claude Agent SDK tasks in repo
- provide changed-file payloads back to Studio
- stream logs (optional)

### 2.3 Local Repo
A readable layout + a mapping manifest:
- Rojo-like layout is recommended for clarity/diffs
- `detai.manifest.json` maps Roblox path ↔ file path ↔ DetAI id

---

## 3) Repo layout + mapping

### 3.1 Repo layout (recommended)
```
your-game-repo/
  src/
    Workspace/...
    ReplicatedStorage/...
    ServerScriptService/...
    StarterPlayer/...
    StarterGui/...
  detai.manifest.json
  detai.session.json
  README.md
```

### 3.2 File naming conventions
- `Script` → `.server.lua`
- `LocalScript` → `.client.lua`
- `ModuleScript` → `.lua`

### 3.3 Stable identity
Each script instance stores:
- `DetAI_Id = "<uuid>"` (attribute; create if missing)

Optional attributes (handy):
- `DetAI_FilePath`
- `DetAI_LastHash`

The manifest is the round-trip mapping.

---

## 4) Local daemon HTTP API (v1)

All requests:
- Base: `http://127.0.0.1:<port>`
- Auth: `Authorization: Bearer <token>`

### 4.1 Health
- `GET /health` → `{ ok: true, version: "0.1" }`

### 4.2 Push full snapshot (Studio → Local)
- `POST /sync/pushSnapshot`

Body:
```json
{
  "projectId": "optional",
  "scripts": [
    {
      "detaiId": "uuid",
      "robloxPath": "ReplicatedStorage/Shared/Util",
      "className": "ModuleScript",
      "filePath": "src/ReplicatedStorage/Shared/Util.lua",
      "hash": "sha1",
      "text": "..."
    }
  ]
}
```

Response:
```json
{ "ok": true, "revision": 1, "scriptCount": 142 }
```

### 4.3 Pull changes since a revision (Studio ← Local)
- `POST /sync/pullChanges`

Body:
```json
{ "sinceRevision": 1 }
```

Response:
```json
{
  "revision": 2,
  "changes": [
    { "detaiId": "uuid", "filePath": "src/...", "hash": "sha1", "text": "..." }
  ]
}
```

### 4.4 Run Claude Agent SDK (Studio → Local)
- `POST /agent/run`

Body:
```json
{
  "repoRoot": "/abs/path/to/your-game-repo",
  "task": "Add a lock+key requirement to all door controllers. Update shared modules and add basic tests if present.",
  "scope": {
    "includePaths": ["src/"],
    "focusFiles": ["src/Workspace/Building/DoorController.server.lua"]
  },
  "context": {
    "selection": ["Workspace/Building/Door01"],
    "notes": "Prefer minimal diff. Do not rename public APIs."
  }
}
```

Response:
```json
{ "ok": true, "runId": "run_123", "startedAt": 1730000000 }
```

### 4.5 Get run status/logs (optional but recommended)
- `GET /agent/status?runId=run_123` → `{ state:"running|done|error", summary:"..." }`
- `GET /agent/logs?runId=run_123&cursor=...` → `{ lines:[...], nextCursor:"..." }`

### 4.6 Cancel a run (best effort)
- `POST /agent/cancel` body `{ runId:"run_123" }`

---

## 5) Claude Agent SDK integration (how the daemon uses it)

Claude Code “SDK” is now the **Claude Agent SDK**. You can implement the daemon in **TypeScript** or **Python**.

### 5.1 TypeScript option
Install:
```bash
npm install @anthropic-ai/claude-agent-sdk
```

Daemon run behavior:
- set `cwd = repoRoot`
- give agent access to tools it needs (file read/write/search, bash)
- run the task instruction
- wait until completion
- compute changed files (via watcher or git diff)
- bump revision and serve changes via `/sync/pullChanges`

### 5.2 Python option
Install:
```bash
pip install claude-agent-sdk
```

Same behavior as TS:
- `cwd = repoRoot`
- run agent task
- report changed files + summary

### 5.3 Auth strategy (daemon side)
Support both:
- `ANTHROPIC_API_KEY` in environment (daemon reads it)
- or use existing Claude Code auth if your environment supports it

### 5.4 Tool permissions (tight scope)
For safety and predictable diffs, the daemon should restrict tools:
- file read/write only under `repoRoot/src`
- optional bash tool only inside repoRoot
- optional “ripgrep” search for speed

### 5.5 Output contract back to Studio
After the agent run, daemon should produce:
- `run summary` (short)
- `changed file list` (paths)
- rely on `/sync/pullChanges` for the full changed texts (keeps one data path)

---

## 6) Studio plugin: Export implementation

### 6.1 Enumerate scripts
Traverse:
- Workspace
- ReplicatedStorage
- ServerScriptService
- StarterPlayer
- StarterGui

Collect any `LuaSourceContainer`:
- Script / LocalScript / ModuleScript

### 6.2 Read text (prefer open editor buffer)
For each script:
- Ensure `DetAI_Id` attribute exists
- Compute Roblox path (`Service/Descendant/...`)
- Determine file extension by class
- Read text:
  - if open in editor: read current buffer
  - else: read stored source
- Compute hash (sha1) for conflict tracking

### 6.3 Push snapshot
Call `/sync/pushSnapshot`.
Store:
- `lastRevision`
- per-script `DetAI_LastHash = hash`

---

## 7) Studio plugin: Pull + Preview + Apply

### 7.1 Pull changes
Call `/sync/pullChanges` with `sinceRevision = lastRevision`.

### 7.2 Preview UI (minimal v1)
In a Sync dock widget (or chat card):
- “N scripts changed”
- list: RobloxPath + filePath
- buttons: **Apply**, **Cancel**
- if conflicts: show conflict list instead

### 7.3 Conflict detection
Conflict if:
- current Studio hash != stored `DetAI_LastHash`
- and incoming local hash != stored `DetAI_LastHash`

For conflicts:
- show per-file resolution options:
  - Use Local (overwrite Studio)
  - Keep Studio (discard local for now)
  - Open Diff (optional future)

### 7.4 Apply changes
When Apply clicked:
- group all edits into one undo step (ChangeHistoryService)
- for each non-conflict file:
  - locate script by `DetAI_Id`
  - write updated text back
  - update `DetAI_LastHash`
- update `lastRevision`

---

## 8) Studio plugin: “Run Claude Task” flow (the UX loop)

### 8.1 Minimal UI (Sync widget only)
Buttons:
- Connect daemon (token)
- Export Scripts
- Pull Changes
- Run Claude Task (text box + optional scope)
- Apply

### 8.2 Optional Chat integration (nice but not required for v1)
Chat cards:
- TaskCard: instruction + scope + Run
- ProgressCard: streaming logs
- ResultCard: changed files + Pull Changes button
- DiffCard: preview + Apply

---

## 9) Daemon: filesystem + watcher

### 9.1 Write snapshot
- create repo if missing
- write files to `src/...`
- write/update `detai.manifest.json`
- set revision = 1

### 9.2 Watch for changes
- watch `src/**`
- on change:
  - compute hash
  - store changed file content (cache) or read on-demand
  - bump revision
  - update manifest

---

## 10) Reliability + safety

### 10.1 Auth token
- daemon prints token on startup
- plugin stores token in plugin settings

### 10.2 Safe apply policy (v1)
- only update script contents
- do not delete/move instances automatically
- conflicts must be resolved explicitly

### 10.3 Logging
- daemon logs: revision bumps, changed files, agent runs, errors
- plugin logs: export counts, pull counts, apply counts, conflicts

---

## 11) Milestones (local Claude Code first + Agent SDK)

### Phase 1 — Daemon snapshot (fast)
- [ ] /health
- [ ] /sync/pushSnapshot → writes repo + manifest

### Phase 2 — Plugin export
- [ ] enumerate scripts
- [ ] stable ids + hash
- [ ] push snapshot
- [ ] basic Sync widget UI

### Phase 3 — Daemon watcher + /sync/pullChanges
- [ ] watcher
- [ ] revision tracking
- [ ] pull changes

### Phase 4 — Plugin import + apply + conflicts
- [ ] pull changes UI
- [ ] conflict detection + resolution
- [ ] apply + undo grouping

### Phase 5 — Claude Agent SDK
- [ ] implement /agent/run using SDK
- [ ] optional /agent/logs
- [ ] plugin “Run Claude Task” button
- [ ] loop: run → pull → preview → apply

---

## 12) “First demo” checklist
- [ ] Export 100+ scripts to local repo
- [ ] Run Claude Agent SDK task that changes 2–10 scripts
- [ ] Pull changes into Studio
- [ ] Preview list is correct
- [ ] Apply updates + Undo works
- [ ] Conflict scenario produces a conflict UI

---

## 13) Decisions to lock now
1) Daemon language: TypeScript or Python
2) Repo root: set in daemon config (absolute path)
3) Apply strategy for scripts open in editor (write into editor buffer vs stored source) — you can start simple and refine later
