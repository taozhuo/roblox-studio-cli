# Determinant AI Studio Plugin — “All Dynamic UI Things” + Local Claude Code Workflow (Implementation Plan)

This plan expands the earlier “local Claude Code first” sync approach into a **full dynamic Studio UX**:
- **Contextual Inspector** (selection-aware action surfacing + forms)
- **Slack-like Chat** (cards + timeline + approvals + progress)
- **Viewport Overlays** (3D gizmos/adornments + click targets)
- **Multi-panel layout** (dock widgets + optional floating palette)
- **AI-generated UI** via a **safe UI schema** + **action registry**
- **Local repo + bash/Claude Code** bridge for editing and syncing scripts back to Studio

---

## 0) Outcomes (what “done” looks like)

### UX outcomes
- Selecting anything in Studio instantly updates an **Inspector** with:
  - *Recommended actions* (top 3–6) + “why”
  - *Issues* (lint) + one-click fixes
  - *Metadata* (tags + AI workflow config)
  - *History* (what AI changed here)
- A **Chat** panel that feels like Slack:
  - short messages by default
  - expandable cards for plans/diffs/results
  - one primary action per card (Preview/Apply/Fix)
- **Viewport overlay** shows:
  - hinge axis + open direction for doors
  - grip frame for tools
  - perception rays / LOS hits for NPCs
  - clickable handles to adjust parameters (angle/axis/offset)

### Workflow outcomes
- One-click: **Export scripts → local repo → run Claude Code → import changes back**
- Change application is grouped into a single **Undo** step.
- Conflicts (Studio edits vs local edits) are surfaced as a **Conflict Card** with resolution actions.

---

## 1) System architecture (end-to-end)

### 1.1 Studio Plugin
**Responsibilities**
- Build live **Context Snapshot** from Selection + scene signals.
- Render UI from a **UIModel** (cards/sections/forms/tabs).
- Maintain a **Message Timeline** (chat) with structured cards.
- Manage **actions**: preview/apply/undo/run/local-run.
- Sync engine:
  - export script text (including open editor buffers)
  - apply incoming patches back into scripts
  - handle conflicts, approvals

### 1.2 Local Bridge Daemon
**Responsibilities**
- Own filesystem repo and manifest mapping
- Run bash / Claude Code tasks in repo
- Watch repo for changes and publish patches for Studio to pull
- Provide a local HTTP API:
  - push snapshot
  - pull changes
  - run command
  - stream logs (optional SSE / chunked)

### 1.3 Local Workspace Repo
- Rojo-like structure for readability:
  - `src/Workspace/...`
  - `src/ReplicatedStorage/...`
  - `src/StarterPlayer/...`
- `detai.manifest.json`: mapping between file paths and DataModel instances
- `detai.changes/`: optional patch artifacts (diffs, logs, snapshots)

---

## 2) Multi-panel UI layout in Studio

Create **multiple dock widgets** (users can dock near Explorer, Output, etc.):

1) **DetAI — Inspector** (primary)
- Header: selection breadcrumb + badges
- Recommended actions
- Tabs: Actions / Issues / Metadata / History

2) **DetAI — Chat** (primary)
- Slack-like feed with cards
- Composer with /commands and attachments

3) **DetAI — Sync** (supporting)
- Connection status to local daemon
- Export/import buttons
- File list, conflicts, last sync

Optional:
4) **DetAI — Palette (floating)**
- Command palette (Ctrl/Cmd+K)
- Quick actions + search

### Viewport overlay (not a widget)
Use 3D viewport elements:
- Adornments, Handles, ArcHandles, BillboardGuis
- Selection highlights + labeled anchors
- Click interactions that update inspector fields (angle/axis/etc.)

---

## 3) “AI drives UI” design (safe + powerful)

### 3.1 Context Snapshot (what the AI sees)
Build a compact context object every selection change:

```json
{
  "selection": [
    {"id":"uuid","path":"Workspace/Building/Door01","class":"Model","tags":["DoorCandidate"]}
  ],
  "primary": {"id":"uuid","class":"Model"},
  "signals": {
    "isDoorCandidate": true,
    "hasHinge": false,
    "hasPrompt": false,
    "isNpcRig": false,
    "isToolCandidate": false
  },
  "props": {
    "anchored": true,
    "size": [4.0, 8.0, 0.4]
  },
  "recentOutput": {
    "errors": ["..."],
    "warnings": []
  },
  "pluginState": {
    "busy": false,
    "lastPlanId": null
  }
}
```

**Notes**
- Keep it small (avoid dumping huge hierarchies).
- Include “signals” you compute (door-ish, npc-ish, etc.).
- Include only a few properties that matter.

### 3.2 UIModel schema (what the AI outputs)
AI produces **UIModel** (or a patch) using a whitelist of component types.

Allowed component types (v1):
- `Header`
- `Banner`
- `Section`
- `ActionCard`
- `IssuesList`
- `Tabs`
- `Form` (schema-driven)
- `List`
- `Divider`

Card types for chat:
- `PlanCard`
- `DiffCard`
- `ProgressCard`
- `ResultCard`
- `ErrorCard`
- `ConflictCard`
- `ChoiceCard`

Each card can reference only registered actions:
```json
{ "actionId": "makeDoorInteractable", "params": { "openAngle": 90 } }
```

### 3.3 Action Registry (the only “verbs” the UI can invoke)
All UI buttons map to a pre-registered action entry:

```lua
ActionRegistry["makeDoorInteractable"] = {
  title = "Make Interactable Door",
  paramsSchema = { ... },
  preview = function(ctx, params) -> ChangeSet end,
  apply = function(changeset) end,
}
```

### 3.4 AI output contract
AI can influence:
- which action cards are shown
- ordering + grouping
- default parameter values
- brief explanations (“why this action”)

AI does **not**:
- execute changes directly
- invent actions outside registry
- output arbitrary Lua UI code

---

## 4) Dynamic UI features (“all the things”)

### 4.1 Contextual Inspector (selection-aware)
**Header**
- name + class icon
- badges (DoorCandidate / NPC / Tool / UI / HasIssues)
- quick controls: Tag, Focus, Open in Explorer, Copy Path

**Recommended Actions**
- Top 3–6 cards, each with:
  - title, 1-line summary
  - risk label (Safe / Medium / High)
  - primary button (Preview or Run)
  - optional secondary (Details)

**Issues tab**
- Lint findings from rules + AI
- Each issue has a one-click fix action

**Metadata tab**
- CollectionService tags
- DetAI attributes (DetAI_Id, DetAI_Type, config JSON)
- Export/import metadata tools

**History tab**
- Per-object action log
- “Undo last change on this object”
- “Re-run last recipe”

### 4.2 Slack-like Chat (timeline + cards)
**Feed rules**
- Plain text for short responses
- Cards for structured moments:
  - plan
  - change preview
  - apply progress
  - results
  - errors
  - conflicts
- Expanders for details/logs
- Reactions:
  - ✅ applied
  - ⚠️ caution
  - 🔁 rerun

**Composer**
- multi-line input
- /commands autocomplete
- attachments:
  - selection context
  - output errors
  - chosen scripts list
  - “include open script buffers”
- quick chips:
  - “make door interactable”
  - “run tests”
  - “export scripts”
  - “sync from local”

### 4.3 “Plan → Preview → Apply” flow in chat
- When user asks for changes:
  1) PlanCard (steps)
  2) DiffCard (preview changes)
  3) Apply button
  4) ProgressCard
  5) ResultCard + History update

### 4.4 Live progress + cancellation
- Running local commands: show streaming log chunks
- Provide Cancel button (best-effort; stops polling / stops daemon run if supported)

### 4.5 Choice UI (for ambiguity)
When multiple plausible interpretations exist:
- ChoiceCard with 2–6 options
- For each option:
  - label
  - short explanation
  - optional thumbnail (viewport capture)
- Click selects and proceeds

### 4.6 Viewport overlays + interactive gizmos
For selected objects:
- door:
  - hinge axis line + arc showing open range
  - arrow for open direction
  - handle to drag openAngle
- weapon:
  - grip frame axes (RGB)
  - handle to slide grip along handle
- NPC perception:
  - rays (LOS) with hit markers
  - FOV cone visualization

These overlays update when inspector params change.

---

## 5) Local Claude Code first — Script sync system (core workflow)

### 5.1 What gets synced (scope)
- Script, LocalScript, ModuleScript across:
  - Workspace
  - ReplicatedStorage
  - ServerScriptService
  - StarterPlayer/StarterCharacterScripts
  - StarterGui
  - any plugin-owned packages you choose

### 5.2 Export rules
- Each script gets a persistent attribute:
  - `DetAI_Id = uuid`
- File extension:
  - Script → `.server.lua`
  - LocalScript → `.client.lua`
  - ModuleScript → `.lua`
- Prefer exporting the live editor buffer if open (so you don’t lose unsaved edits).

### 5.3 Import rules
- Apply file changes back into matching scripts by `DetAI_Id`.
- Group edits into one undo step.
- If conflicts detected (local and Studio changed since last sync), create ConflictCard.

### 5.4 Local daemon responsibilities
- Write snapshot into repo
- Watch repo changes
- Expose `/exec/run` to run:
  - Claude Code
  - formatters
  - tests
- Return:
  - changed file list
  - diff summary
  - logs

---

## 6) Recipes (dynamic workflows you can ship early)

These become “action cards” in inspector and “/commands” in chat.

### Door recipes
- Make Interactable Door
- Add Proximity Prompt
- Auto hinge pivot / axis guess
- Add sound set
- Add nav blocker toggle (if applicable)

### Weapon recipes
- Add Grip attachment
- Auto grip guess + manual tweak overlay
- Add muzzle/tip attachment
- Add equip/unequip animations hooks

### NPC recipes
- Setup NPC Controller
- Bake world collider (for LOS)
- Add perception debug overlay
- Generate affordances list for selection

### Script workflow recipes
- Export scripts
- Pull changes from local
- Run Claude Code on selected scripts
- Run unit tests / playtest hooks
- Create patchset preview and apply

---

## 7) Implementation milestones (do it in slices)

### Phase 1 — Foundation (UI + State + Actions)
- [ ] Plugin scaffolding + 2 dock widgets (Inspector + Chat)
- [ ] Global store:
  - selectionContext
  - uiModel
  - chatMessages
  - currentPlan/diff
  - syncStatus
- [ ] Action registry + no-op actions
- [ ] Basic contextual inspector rendering from a UIModel
- [ ] Chat feed with card renderer + composer

### Phase 2 — Sync v0 (Studio → Local snapshot)
- [ ] Local daemon with:
  - `/health`
  - `/sync/pushSnapshot`
  - repo init + manifest write
- [ ] Plugin export:
  - enumerate scripts
  - generate ids
  - push snapshot
- [ ] Sync widget shows “exported N scripts” + file list

### Phase 3 — Sync v1 (Local → Studio patch apply)
- [ ] Daemon:
  - file watcher
  - `/sync/pullChanges`
- [ ] Plugin:
  - poll changes
  - build DiffCard preview
  - apply into scripts
  - record History entries + undo grouping
- [ ] ConflictCard + resolution actions

### Phase 4 — Claude Code integration
- [ ] Daemon:
  - `/exec/run` (bash)
  - log streaming (optional)
- [ ] Plugin:
  - chat command “Run Claude on selection”
  - show ProgressCard → ResultCard
  - auto pull changes → DiffCard

### Phase 5 — Full dynamic UI
- [ ] “AI UI” endpoint usage:
  - send context snapshot
  - receive UIModel/patch
  - update inspector + chat suggestions
- [ ] ChoiceCards for ambiguity
- [ ] Issues tab with auto-fix actions
- [ ] Viewport overlays for door + grip + perception
- [ ] Command palette window

---

## 8) Data model + file mapping details

### 8.1 detai.manifest.json fields
- `version`
- `projectId`
- `scripts[]`:
  - `detaiId`
  - `robloxPath`
  - `className`
  - `filePath`
  - `hash`
  - `lastSyncRevision`

### 8.2 In-Studio mapping storage
Each script instance stores:
- `DetAI_Id` attribute
- optional:
  - `DetAI_FilePath`
  - `DetAI_LastHash`

This allows mapping without scanning manifest.

---

## 9) Performance and UX guardrails (so “all dynamic UI” stays usable)

### UI limits
- Recommended action cards: max 6
- Visible buttons per card: max 2
- Long logs always collapsed behind “Details”
- Large lists use virtualization (chat feed, file list)

### Update cadence
- Selection updates render instantly
- AI suggestions update after a short debounce (so UI doesn’t thrash when clicking)

### Memory safety
- Centralize event connections
- On re-render, clean up old connections for destroyed UI items
- Keep a stable “message id” per chat card so progress updates replace-in-place

---

## 10) Concrete deliverables (what to build as folders/modules)

### Plugin modules
- `State/Store.lua` (single source of truth)
- `Context/BuildContext.lua` (selection snapshot + signals)
- `UI/UIModel.lua` (types + validation)
- `UI/Renderers/*` (Header, ActionCard, Tabs, ChatCards)
- `Actions/Registry.lua` (actions + param schemas)
- `Actions/Executors/*` (preview/apply/undo)
- `Sync/Client.lua` (daemon HTTP client)
- `Sync/Export.lua` (script enumeration + export)
- `Sync/Import.lua` (apply patches + conflicts)
- `Viewport/Overlays/*` (door, grip, perception)
- `Chat/Commands.lua` (/export, /pull, /run, /makeDoor, etc.)

### Local daemon (Node or Python)
- `server.(js|py)` (HTTP API)
- `repo/` (workspace management)
- `watcher/` (fs watcher)
- `runner/` (bash/claude executor)
- `manifest/` (read/write detai.manifest.json)

---

## 11) First “All Dynamic UI” demo scenario (end-to-end)

1) Select a door model in Workspace
2) Inspector updates:
   - badges: DoorCandidate, NoHinge, NoPrompt
   - recommended: “Make Interactable Door”
3) Click “Make Interactable Door”:
   - Chat posts PlanCard + Preview
4) Preview:
   - Chat posts DiffCard
5) Apply:
   - ProgressCard updates in-place
   - ResultCard shows created instances
6) Export scripts:
   - Chat: “Exported 120 scripts to local repo”
7) Run Claude Code:
   - “Add lock + key requirement to doors”
   - Local edits files, daemon reports changes
8) Chat shows DiffCard for imported changes → Apply → Done

---

## 12) Next decisions (so we can lock the build)
Pick:
1) UI framework preference:
   - (A) Fusion style (signals/reactive)
   - (B) Roact style (component tree)
   - (C) Vanilla Instances with a UIModel renderer
2) Daemon language:
   - (A) Node.js
   - (B) Python

If you pick (C) + (A), you still get “all dynamic UI,” just with a simpler renderer core.
