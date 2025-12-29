# studioctl (Mac) — Roblox Studio automation CLI plan

This document describes a pragmatic way to control Roblox Studio **from a CLI on macOS** for:
- opening a place
- starting/stopping **Run** mode (server-only simulation)
- streaming Output logs to your terminal
- sending basic commands to Studio

It avoids brittle UI automation and instead uses a **Studio plugin** + **local WebSocket bridge**.

> Scope: This targets **Run mode** (`RunService:Run()`), which runs server scripts but **does not spawn a client/player**, so LocalScripts generally won’t run.

---

## 0) What you get (MVP)

### MVP commands
- `studioctl open <path_to_rbxlx>`
- `studioctl run`
- `studioctl stop`
- `studioctl pause`
- `studioctl logs --follow`

### MVP behavior
- CLI can open Studio with your place file
- Studio plugin connects back to your local tool (WebSocket)
- CLI sends JSON commands → plugin executes RunService actions
- Plugin streams Output (`LogService.MessageOut`) back to CLI in real time
- CLI also supports tailing Studio’s on-disk logs as a fallback

---

## 1) Architecture

```
+----------------------+                +---------------------------+
| studioctl (CLI)      |  WebSocket     | studioctl-server (local)  |
| - send cmd JSON ---->|--------------->| - routes cmd to Studio     |
| - print logs <-------|<---------------| - broadcasts logs to CLIs  |
+----------------------+                +---------------------------+
                                               ^
                                               |
                                               | WebSocket
                                               v
                                    +---------------------------+
                                    | Roblox Studio Plugin      |
                                    | - connects to localhost   |
                                    | - RunService:Run/Stop     |
                                    | - streams LogService      |
                                    +---------------------------+
```

### Why this is robust on macOS
- No AppleScript/UI scripting needed
- You can keep the plugin always-on
- WebSocket is bidirectional and low-latency
- Works with multiple terminals connected at once

---

## 2) Requirements

### On macOS
- Roblox Studio installed
- Node.js 18+ (or Bun; Node is fine)
- A Studio plugin (local dev plugin is best)

### Notes about permissions
- Roblox Studio may prompt for **network permission** for plugin HTTP/WebStream usage the first time.
- Prefer `ws://localhost:PORT/...` (some environments behave differently for `127.0.0.1`).

---

## 3) Component plan

### 3.1 `studioctl-server` (local router)

**Responsibilities**
- Accept WebSocket connections on `ws://localhost:4848/ws`
- Assign roles:
  - first connection that identifies as `"role":"studio"` becomes the Studio endpoint
  - others are `"role":"cli"`
- Route:
  - CLI `{"type":"cmd","cmd":"run"}` → Studio
  - Studio `{"type":"log"...}` → all CLIs

**MVP features**
- One Studio instance at a time
- Multiple CLI clients supported
- Basic status events (`connected`, `disconnected`)
- Optional auth token (recommended)

**Implementation steps**
1. Create a Node project:
   - deps: `ws`, optionally `express`
2. Implement WebSocket server:
   - `path=/ws`
3. Store:
   - `studioSocket`
   - `cliSockets:Set`
4. Broadcast logs/results to all `cliSockets`
5. Add simple auth:
   - require `token` in first message from Studio/CLI
   - reject otherwise

**Future**
- Support multiple Studio instances (tag by `studioId` or `placeId`)
- Persist recent logs for new CLI clients
- JSON schema validation

---

### 3.2 Studio plugin (controller + logger)

**Responsibilities**
- Connect to WebSocket
- Execute `RunService` commands:
  - `RunService:Run()` — start server simulation
  - `RunService:Stop()` — stop simulation
  - `RunService:Pause()` — pause simulation
- Stream logs:
  - `LogService.MessageOut` for Output
  - optionally `ScriptContext.Error` for error stack traces
- Send structured “result” messages back to CLI

**MVP plugin design**
- Auto-connect on plugin load
- Reconnect loop with backoff if server not running
- Safe JSON encode/decode using `HttpService`
- Always guard calls with `pcall` (Studio APIs throw)

**Command handling**
- Input: `{ "type":"cmd", "cmd":"run" }`
- Output: `{ "type":"result", "cmd":"run", "ok":true, "info":null }`
- Logs: `{ "type":"log", "level":"MessageOutput", "text":"..." }`

**Run vs LocalScripts**
- In `RunService:Run()` mode:
  - server scripts run
  - there is no player / client
  - LocalScripts typically do not run because there is no `LocalPlayer`
- For client testing, you need “Play” modes; those are not exposed cleanly via RunService.

**Future**
- Add a toolbar UI in Studio (connect status, buttons)
- Add `exec` command:
  - run an approved module / script snippet on server
  - return output/values as JSON
- Add test runner hooks:
  - trigger TestService / custom test harness

---

### 3.3 `studioctl` CLI

**Responsibilities**
- Provide a clean UX:
  - `open`, `run`, `stop`, `pause`, `logs`
- Connect to the WebSocket router as a CLI client
- Send commands and print results
- Print streaming logs in `logs --follow` mode

**UX plan**
- `studioctl run`
  - connect
  - send `{type:"cmd",cmd:"run"}`
  - wait for `{type:"result",cmd:"run"...}`
- `studioctl logs --follow`
  - connect
  - keep process alive
  - print log messages as they arrive

**Fallback logs (no plugin)**
- Use on-disk logs:
  - `~/Library/Logs/Roblox/log_*.txt`
- `studioctl logs --tail-disk` tails the latest `log_*.txt`

**Implementation steps**
1. Use Node with `ws` for client mode
2. Use a CLI framework:
   - minimal: parse `process.argv`
   - nicer: `commander` or `yargs`
3. Add subcommands:
   - `open`: uses macOS `open -a "RobloxStudio" --args -localPlaceFile "..."` (best effort)
   - `run/stop/pause/ping`: WebSocket command
   - `logs`: WebSocket stream
4. Format:
   - show timestamps
   - show message type/level
5. Exit codes:
   - non-zero on server not connected / command failure

---

## 4) Security and safety

Even for localhost tooling, treat this like a control surface.

### Minimum protections
- Require a shared token:
  - CLI: `STUDIOCTL_TOKEN=... studioctl run`
  - Plugin: token set in plugin settings (or a module)
- Only bind server to `127.0.0.1`
- Validate messages:
  - only allow known commands
  - drop unknown fields
- Add rate limiting on commands (avoid accidental command spam)

### Optional hardening
- Use a random port per session, print it in terminal, plugin reads it from a file
- Use a Unix domain socket (advanced; not all WS libs support easily)
- Add an allowlist of place IDs

---

## 5) Reliability plan (reconnect + observability)

### Reconnect strategy
- Plugin:
  - if disconnected, retry every 1s, 2s, 4s … up to 30s
  - send status changes as “log” or “status” messages
- CLI:
  - logs mode: auto-reconnect unless user passes `--no-reconnect`

### Observability
- Server prints:
  - when Studio connects/disconnects
  - when CLIs connect/disconnect
  - last command issued + outcome
- CLI can show status:
  - `studioctl status` prints whether Studio is connected

---

## 6) Step-by-step build order

### Phase 1 — baseline (30–60 min)
1. Create `studioctl-server` (WebSocket router)
2. Create the Studio plugin:
   - connect + receive commands
   - implement `RunService:Run/Stop/Pause`
3. Create minimal CLI:
   - `run`, `stop`, `logs`

### Phase 2 — usability (1–2 hrs)
4. Add `open` command (launch Studio with args)
5. Add `status` command
6. Add disk-log fallback mode
7. Add token auth

### Phase 3 — power features (later)
8. Add `exec` command to run a module in server simulation
9. Add `watch` mode:
   - on file changes, auto-run / stop / run
10. Add multi-studio support (id-based routing)

---

## 7) Testing checklist

### Connectivity
- Start server
- Open Studio with plugin enabled
- Confirm:
  - server prints “Studio connected”
  - `studioctl status` shows connected

### Run mode
- Put a Script in `ServerScriptService` that prints “server tick”
- `studioctl run` → should start printing
- `studioctl pause` → prints stop
- `studioctl stop` → simulation ends

### LocalScript non-run (expected)
- Put a LocalScript in `StarterPlayerScripts` printing “client hello”
- In Run mode, it should not print (expected)
- Confirm you understand this is server-only.

### Error capture (optional)
- Add a server script that errors
- Verify error shows up in logs stream

---

## 8) Limitations (important)

- This plan **does not press “Play”** (client+server) in a fully supported way.
- Run mode is server simulation; it’s great for:
  - server systems
  - data pipelines
  - AI NPC server logic
  - validation scripts
- For end-to-end gameplay testing with LocalScripts/UI, you will need:
  - manual Play, or
  - a separate approach (e.g., Open Cloud + test harness, or an internal Roblox testing pipeline)

---

## 9) Suggested command set (final)

### Primary
- `studioctl open <file.rbxlx>`
- `studioctl run`
- `studioctl stop`
- `studioctl pause`
- `studioctl logs --follow`
- `studioctl status`

### Optional
- `studioctl logs --tail-disk`
- `studioctl ping`
- `studioctl exec <moduleName> --json <args>`

---

## 10) Packaging & distribution (Mac)

### Local dev (recommended)
- Keep plugin as a local development plugin in Studio
- Keep server + CLI in a repo
- Add `npm run dev` / `npm run start`

### Shareable
- Package CLI as a single binary:
  - `pkg`, `nexe`, or `bun build --compile`
- Provide install:
  - `brew tap ...` (later)

---

## 11) Troubleshooting

- **Studio doesn’t connect**
  - ensure server is running
  - ensure plugin is enabled
  - ensure URL is `ws://localhost:4848/ws`
  - check if Studio prompted for network permission

- **No logs show**
  - confirm plugin is connected
  - verify `LogService.MessageOut` is firing (print locally in plugin)
  - use disk log tail fallback

- **`run` works but LocalScripts don’t**
  - expected in Run mode; this is server-only

---

## Appendix A — message schema (MVP)

### CLI → Server → Studio
```json
{ "role": "cli", "token": "..." }
{ "type": "cmd", "cmd": "run" }
```

### Studio → Server → CLI
```json
{ "role": "studio", "token": "..." }
{ "type": "result", "cmd": "run", "ok": true, "info": null }
{ "type": "log", "level": "MessageOutput", "text": "Hello", "t": 1730000000 }
{ "type": "status", "studio": "connected" }
```
