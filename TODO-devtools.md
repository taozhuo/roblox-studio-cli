# DevTools Feature TODO

Features to add to match Chrome DevTools and game dev debugging tools.

## Context Notification System (Like Claude Code)

Claude Code pushes notifications into AI context when background tasks complete. We could do similar:

### How Claude Code Does It
```
1. Background task runs
2. Task completes/errors
3. CLI injects <task-notification> into conversation
4. AI sees it on next turn
```

### What We Could Add
```javascript
// Tauri app listens to daemon WebSocket
daemon.onEvent("error-log", (data) => {
  conversation.inject(`<studio-notification>
    <type>error</type>
    <message>${data.message}</message>
  </studio-notification>`)
})

daemon.onEvent("remote-spike", (data) => {
  conversation.inject(`<studio-notification>
    <type>remote-spike</type>
    <summary>${data.count} events from "${data.name}" in 1s</summary>
  </studio-notification>`)
})
```

### Notification Types to Consider
- [ ] Error logs (immediate alert)
- [ ] RemoteEvent spikes (spam detection)
- [ ] Memory threshold exceeded
- [ ] Playtest started/stopped
- [ ] Script changed externally

### Requirements
- Tauri app must control conversation context
- Daemon pushes events via WebSocket (already have)
- Tauri injects into messages before API call

---

## High Priority (Needs Plugin Work)

### 1. Input Recording/Replay
- [ ] `studio.input.startRecording` - capture player inputs (WASD, mouse, jumps)
- [ ] `studio.input.stopRecording` - stop and return input sequence
- [ ] `studio.input.replay` - replay captured inputs on character
- [ ] `studio.input.exportTest` - generate TestService code from recording

### 2. Replication Debugging
- [ ] `studio.network.getOwnership` - get network owner of part(s)
- [ ] `studio.network.setOwnership` - set network owner
- [ ] `studio.network.getRemoteHistory` - log RemoteEvent/Function calls
- [ ] `studio.network.startRemoteCapture` - begin monitoring remotes
- [ ] `studio.network.stopRemoteCapture` - stop monitoring, return log
- [ ] `studio.network.measureLatency` - round-trip time measurement

### 3. Animation State Inspection
- [ ] `studio.animation.getPlaying` - list playing animations on humanoid/animator
- [ ] `studio.animation.getTracks` - get all animation tracks
- [ ] `studio.animation.getTrackInfo` - get track weight, speed, position, length
- [ ] `studio.animation.setTrackTime` - scrub to specific time
- [ ] `studio.animation.pause` - pause animation track
- [ ] `studio.animation.resume` - resume animation track

---

## Medium Priority (Scriptable via Eval)

### 4. Physics Panel
- [ ] `studio.physics.getContacts` - get collision contact points
- [ ] `studio.physics.visualize` - toggle `ShowCollisionGeometry`
- [ ] `studio.physics.raycastDebug` - cast ray and return hit info
- [ ] `studio.physics.getConstraints` - list constraints on selection
- [ ] `studio.physics.getAssemblies` - list physics assemblies

### 5. Memory Snapshots
- [ ] `studio.memory.snapshot` - capture instance count by ClassName
- [ ] `studio.memory.diff` - compare two snapshots (find leaks)
- [ ] `studio.memory.getTopClasses` - classes with most instances
- [ ] `studio.memory.trackInstance` - watch specific instance for GC

### 6. Rendering Debug
- [ ] `studio.render.setMode` - wireframe, normal, lighting-only
- [ ] `studio.render.getStats` - draw calls, triangles, instances
- [ ] `studio.render.toggleStreamingDebug` - show streaming regions
- [ ] `studio.render.getCamera` - camera position, FOV, etc.

### 7. Audit Tools (Lighthouse Equivalent)
- [ ] `studio.audit.performance` - find expensive scripts (profile + report)
- [ ] `studio.audit.memory` - find memory hogs
- [ ] `studio.audit.remotes` - find chatty RemoteEvents
- [ ] `studio.audit.deprecated` - find deprecated API usage in scripts
- [ ] `studio.audit.security` - find RemoteEvent vulnerabilities (no validation)

---

## Lower Priority

### 8. AI/Navigation Debug
- [ ] `studio.nav.computePath` - compute path between two points
- [ ] `studio.nav.visualizePath` - show path with debug parts
- [ ] `studio.nav.getWaypoints` - get path waypoints

### 9. DataStore Viewer (Application Panel Equivalent)
- [ ] `studio.datastore.preview` - read DataStore in Studio (mock)
- [ ] `studio.datastore.listKeys` - list keys in a DataStore
- [ ] `studio.datastore.inspect` - view value at key

### 10. Code Coverage
- [ ] `studio.coverage.start` - begin tracking executed lines
- [ ] `studio.coverage.stop` - stop and return coverage report
- [ ] `studio.coverage.getReport` - which lines were executed

---

## Already Have (Reference)

| Chrome DevTools | Our Tool | Status |
|-----------------|----------|--------|
| Elements | `studio.instances.tree`, `studio.selection` | ✅ |
| Console | `studio.logs`, `studio.eval` | ✅ |
| Sources | `studio.scripts`, `studio.debug.*` | ✅ |
| Network (HTTP) | `runtime.http.capture*` | ✅ |
| Performance | `runtime.perf.*` | ✅ |
| Memory (basic) | `runtime.memory.*` | ✅ |
| Application | `cloud.datastore.*` | ✅ |
| Recorder (viewport) | `studio.recording.*` | ✅ |

---

## Notes

- Input recording requires hooking `UserInputService` and `ContextActionService`
- RemoteEvent monitoring requires wrapping or hooking `.OnServerEvent`/`.OnClientEvent`
- Animation inspection uses `Humanoid:GetPlayingAnimationTracks()` or `Animator:GetPlayingAnimationTracks()`
- Physics visualization uses `workspace:SetAttribute("CollisionGeometry", true)` or similar debug settings
- Memory snapshots just iterate `GetDescendants()` and count by ClassName
