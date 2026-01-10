---
name: build-verify
description: Always verify after building. Use vlm.verify after creating/modifying anything visual.
---

# Build-Verify Loop

After ANY visual change (GUI, parts, models, lighting):

1. Make the change
2. Call `vlm.verify` with appropriate criteria
3. If failed, fix issues and verify again
4. Only report done when verification passes

## Criteria Keys

- `gui-basic` - any ScreenGui
- `gui-shop` - shop/store UI
- `gui-inventory` - inventory UI
- `scene-basic` - 3D parts/models
- `scene-lighting` - lighting setup
- `animation` - character poses

## Example

```
// After creating a shop UI
vlm.verify({ criteria: "gui-shop" })

// Custom requirements
vlm.verify({ requirements: ["red button visible", "title says 'Shop'"] })
```

## Before/After Changes

```
// Take snapshot before
snapshot = vlm.snapshot()

// Make change
...

// Verify change happened
vlm.compare({ before: snapshot.base64, expectedChange: "button is now blue" })
```
