# Local Claude Code First — Determinant AI Roblox Studio Plugin Implementation Plan (Single MD)

This plan is **only** about getting the **local Claude Code workflow working end-to-end first**:
- Studio plugin can **export all scripts** (including open editor buffers) into a **local repo**
- You can use **Claude Code + bash tools** on that repo
- Plugin can **pull file changes** from local and **sync them back** into Studio safely (preview → apply → undo)

Dynamic UI (chat/inspector) is included only where it directly supports the local workflow.

---

## 1) Target workflow (what “v1” must do)

### A) Export → Local
1. In Studio, click **Export Scripts**.
2. Plugin enumerates all Lua scripts (Script/LocalScript/ModuleScript).
3. Plugin reads text:
   - If a script is open in the editor, export the current buffer via ScriptEditorService.
   - Otherwise export from stored Source.
4. Plugin sends one snapshot to a **local daemon** on `localhost`.
5. Daemon writes scripts into a local repo with a stable mapping file.

### B) Edit locally with Claude Code + bash
6. You open the repo in your local tools.
7. Run Claude Code tasks that change files.
8. Daemon watches the repo and tracks changed files.

### C) Import → Studio
9. In Studio, click **Pull Changes** (or auto-poll).
10. Plugin requests changes since last revision.
11. Plugin shows a **Diff Preview** (in chat or sync panel).
12. Click **Apply** → plugin writes updated sources back into the correct scripts.
13. Everything is grouped into one **Undo** step.

### D) Conflicts
14. If the same script changed in Studio and locally since last sync:
   - show a conflict card (Use Local / Keep Studio / Open Diff)
   - don’t auto-apply.

---

## 2) Architecture

### 2.1 Studio Plugin (Determinant AI)
**Responsibilities**
- Enumerate scripts in the DataModel
- Read script text (prefer editor buffer if open)
- Maintain a stable ID per script (attribute)
- Push snapshot to daemon
- Pull changes from daemon
- Preview/apply changes back into Studio
- Conflict detection + resolution UI
- Undo grouping

### 2.2 Local Daemon (runs on your machine)
**Responsibilities**
- Own the filesystem repo
- Write snapshot to disk
- Maintain mapping manifest
- Watch repo for file changes
- Serve changes to Studio
- Provide a command runner endpoint (bash + Claude Code)

### 2.3 Local Repo
- A readable, Rojo-like layout (familiar for Roblox projects)
- A manifest that maps `DetAI_Id` ↔ Roblox instance path ↔ file path

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
  detai.manifest.json
  detai.session.json
  README.md
```

### 3.2 File naming conventions
- `Script` → `.server.lua`
- `LocalScript` → `.client.lua`
- `ModuleScript` → `.lua`

### 3.3 Stable script identity
Each script instance stores:
- Attribute: `DetAI_Id = "<uuid>"` (create if missing)
Optional attributes (nice to have):
- `DetAI_FilePath`
- `DetAI_LastHash`

The manifest becomes the source of truth for round-trip mapping.

---

## 4) Local daemon HTTP API (minimum viable)

All calls are to `http://127.0.0.1:<port>` with `Authorization: Bearer <token>`.

### Health
- `GET /health` → `{ ok: true, version: "0.1" }`

### Push full snapshot (Studio → Local)
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

### Pull changes since revision (Studio ← Local)
- `POST /sync/pullChanges`
Body:
```json
{ "sinceRevision": 12 }
```
Returns:
```json
{
  "revision": 13,
  "changes": [
    { "detaiId": "uuid", "filePath": "...", "hash": "sha1", "text": "..." }
  ]
}
```

### Run command (Claude Code / bash)
- `POST /exec/run`
Body:
```json
{ "cwd": "your-game-repo", "cmd": "claude", "args": ["..."] }
```
Returns:
```json
{ "ok": true, "runId": "abc" }
```

(Optional later)
- `GET /exec/logs?runId=abc` → stream logs (poll or SSE)

---

## 5) Studio plugin: export implementation details

### 5.1 Enumerate scripts
Traverse common containers:
- Workspace
- ReplicatedStorage
- ServerScriptService
- StarterPlayer
- StarterGui
- any other game services you care about

Collect any instance that is a `LuaSourceContainer`:
- Script, LocalScript, ModuleScript

### 5.2 Read script text (prefer open editor buffer)
For each script:
1) If it has a ScriptDocument open:
   - read via ScriptEditorService/ScriptDocument text getter
2) Else:
   - read from `script.Source`

Store:
- `detaiId`
- `robloxPath`
- `className`
- `text`
- `hash(text)`

### 5.3 Build and push snapshot
Send one payload to `/sync/pushSnapshot`.
Update plugin-side state:
- `lastRevision = response.revision` (or 0 for initial)
- per-script `DetAI_LastHash = hash`

---

## 6) Local daemon: write snapshot + watch changes

### 6.1 Write snapshot
- Create repo if missing.
- Write `detai.manifest.json`:
  - `version`, `projectId`, `revision`
  - list of scripts with mapping fields
- Write each script file to `filePath` (create directories as needed).

### 6.2 Watch filesystem for changes
- Watch under `src/**`.
- On change:
  - compute new hash
  - bump `revision`
  - store updated text in memory cache or on-demand read for `/sync/pullChanges`
  - update manifest

---

## 7) Studio plugin: pull/apply changes back

### 7.1 Poll for changes
On interval (or button click):
- call `/sync/pullChanges` with `sinceRevision = lastRevision`
- if no changes, return
- else render a diff preview

### 7.2 Preview UI (minimal)
In a **Sync** panel or Chat card:
- “N scripts changed”
- list of changed scripts (path + file)
- buttons:
  - **Apply**
  - **Cancel**
  - (if conflicts) “Resolve”

### 7.3 Conflict detection
Treat as conflict if:
- `script` hash in Studio differs from `DetAI_LastHash`
- and incoming local change hash differs from the same `DetAI_LastHash`

For conflicts:
- show Conflict UI with:
  - Use Local
  - Keep Studio
  - Open Diff (optional later)

### 7.4 Apply changes
When user clicks Apply:
- Wrap the batch in one undo step (ChangeHistoryService)
- For each changed script without conflicts:
  - write updated text back (prefer the most editor-friendly update path available in your environment)
  - update `DetAI_LastHash`

Update `lastRevision`.

---

## 8) Minimal UI needed for “local first”

### 8.1 One dock widget: “DetAI Sync”
Start here (don’t overbuild UI first):
- Connection status (daemon online/offline)
- Token entry + connect button
- Buttons:
  - Export Scripts
  - Pull Changes
  - Run Claude (optional)
- Changed files list + Apply

### 8.2 Optional: lightweight chat panel (v1.5)
Add after sync works:
- Timeline cards:
  - Export result
  - Pull result
  - Conflicts
  - Apply result

---

## 9) Security + reliability

### 9.1 Auth token
- Daemon generates a random token on startup
- User copies into plugin once
- Plugin stores token in plugin settings

### 9.2 Safe writes
- Never delete scripts on apply in v1
- Only update contents
- Keep a local “last applied revision” record so you can recover

### 9.3 Logging
- Daemon logs:
  - snapshot size
  - files written
  - revisions
  - exec runs
- Plugin logs:
  - export count
  - pull count
  - conflicts
  - apply success/fail

---

## 10) Implementation milestones (local Claude Code first)

### Phase 1 — Daemon skeleton (1–2 sessions)
- [ ] HTTP server + `/health`
- [ ] Repo init
- [ ] `/sync/pushSnapshot` writes files + manifest

### Phase 2 — Plugin export (1–2 sessions)
- [ ] Enumerate scripts
- [ ] Generate `DetAI_Id`
- [ ] Read open buffers when possible
- [ ] Push snapshot
- [ ] Sync widget UI shows status + counts

### Phase 3 — Daemon watcher + pull changes (1–2 sessions)
- [ ] File watcher under `src/**`
- [ ] Revision tracking
- [ ] `/sync/pullChanges` returns updated file texts

### Phase 4 — Plugin import + apply (1–3 sessions)
- [ ] Pull changes
- [ ] Diff preview list
- [ ] Conflict detection UI
- [ ] Apply updates + group undo

### Phase 5 — Local command runner (Claude Code) (optional but recommended)
- [ ] `/exec/run` to invoke Claude/bashtool tasks
- [ ] Plugin button “Run Claude on repo”
- [ ] Logs + pull/apply loop

---

## 11) Module breakdown (plugin + daemon)

### 11.1 Plugin modules
- `Sync/DaemonClient.lua` (HTTP client)
- `Sync/ExportAllScripts.lua` (enumeration + snapshot)
- `Sync/ImportChanges.lua` (pull + apply)
- `Sync/Conflicts.lua` (hash tracking + resolution)
- `UI/SyncWidget.lua` (dock widget)
- `State/Store.lua` (sync status, revisions, selections)

### 11.2 Daemon modules (Node or Python)
- `server` (routes + auth)
- `repo` (workspace + manifest)
- `watcher` (fs watch + revision)
- `runner` (exec command)
- `utils/hash` (sha1)

---

## 12) “First demo” checklist
- [ ] Export 100+ scripts to local repo
- [ ] Edit a module locally
- [ ] Pull changes into Studio
- [ ] Preview shows the changed script
- [ ] Apply updates in Studio
- [ ] Undo restores original text

---

## 13) Decisions to lock before coding
1) Daemon language:
   - Node.js (fast path for fs + HTTP)
   - Python (also fine)
2) Repo root location:
   - user-chosen folder path in daemon config
3) Poll interval:
   - manual-only at first (button), then add auto-poll
