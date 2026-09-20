---
name: hyprland-ui-testing
description: >
  Safely test graphical applications and desktop UI under Hyprland without
  disturbing the user's active workspace, focus, or pointer. Use for headed
  GUI E2E/TDD, window-rule verification, layer-shell checks, virtual-monitor
  testing, screenshots of test-only surfaces, and compositor regressions.
---

# Hyprland UI Testing

Use an isolated display before opening test UI. A test that visibly maps on the
user's desktop, steals focus, moves the pointer, or leaves a temporary output
behind is a failed test even if the application itself behaved correctly.

## Safety invariant

The user's desktop is read-only test context:

- Never move the human pointer with `movecursor`, `ydotool`, computer-use,
  or equivalent automation.
- Never switch the user's focused monitor or workspace with `focusmonitor` or
  an ordinary workspace dispatch just to reach a test surface.
- Never launch a test window normally and move it away afterward. The first
  mapped frame may already have stolen focus.
- Never load an experimental Hyprland plugin into the live human compositor.
  Plugin development belongs in a nested Hyprland session.
- Never call an isolation run successful until the original active workspace
  and focused client still match the baseline.

## 1. Record the baseline

Before creating anything:

```bash
hyprctl version
hyprctl -j activeworkspace
hyprctl -j activewindow
hyprctl -j monitors
hyprctl -j clients
```

Record the focused client address, active workspace, and physical monitor names.

## 2. Create an isolated headless output

Use the reserved Omarchy virtual-output namespace plus a unique suffix so
concurrent agents and stale runs cannot collide. The `OMARCHY-VIRTUAL-`
prefix means "rendering/capture surface, not physical monitor topology" to
Omarchy's monitor recovery logic:

```bash
output="OMARCHY-VIRTUAL-test-$"
hyprctl output create headless "$output"
```

Confirm it exists with `hyprctl -j monitors`. If creation fails, stop. Do not
fall back to the user's physical monitor.

Hyprland supports headless outputs specifically for virtual-display use such as
VNC, RDP, and Sunshine. They are also the correct compositor fixture for
focus-safe GUI testing.

## 3. Map the application there from its first frame

Give the test client a unique class or title. Before launch, install a temporary
window rule that combines all three pieces of isolation:

- `monitor = "<test-output> silent"` — first map belongs to the test output;
- `workspace = "99 silent"` — mapping does not switch the user's workspace;
- `no_initial_focus = true` — the new window cannot take keyboard focus.

Omarchy's Lua configuration uses `hl.window_rule`; follow the loaded
configuration's current API rather than falling back to legacy
`hyprctl keyword`. The rule must exist **before** the application starts.

Then launch the application once. A silent workspace alone is not sufficient:
workspace placement and initial focus are separate Hyprland effects.

Use the target application's class/app-id option when available so the
temporary rule matches only this test process.

Immediately re-read:

```bash
hyprctl -j activeworkspace
hyprctl -j activewindow
hyprctl -j clients
```

The test window must be on the isolated output and the human baseline must be
unchanged. If focus moved, restore the user's prior state and report an
isolation failure. Do not count the run as green.

## 4. Match evidence to the claim

For ordinary windows, use `hyprctl -j clients` to verify monitor, workspace,
geometry, floating state, and class.

For layer-shell surfaces, use `hyprctl -j layers`; they may not appear in
`clients`.

For visual evidence, capture only the test output:

```bash
grim -o "$output" /tmp/omarchy-ui-test.png
```

A screenshot proves rendering. Hyprland state proves placement/focus. Keep those
claims separate.

For Omarchy source development, prefer the repository's existing
`test/acceptance` suite and read `agents/skills/acceptance-tests.md` before
adding a one-off graphical harness.

## 5. Nested Hyprland for compositor/plugin development

If the thing under test is a Hyprland plugin or compositor-internal behavior,
run a nested debug Hyprland instance. Record the live
`HYPRLAND_INSTANCE_SIGNATURE` first and ensure every plugin load/unload targets
the nested instance, never the live one.

A live headless output still shares the human compositor's single seat. It is a
display-isolation fixture, not proof of independent cursors or keyboards.

## 6. Cleanup is part of the test

Stop every test process, then remove the output:

```bash
hyprctl output remove "$output"
```

Finally re-read:

```bash
hyprctl -j clients
hyprctl -j monitors
hyprctl -j activeworkspace
hyprctl -j activewindow
```

A run is complete only when:

- no test process or test client remains;
- the temporary output is gone;
- the user's original workspace is still active;
- the user's original focused client is still focused.

Use a shell `trap` for output/process cleanup whenever a test has more than one
step, so an assertion failure cannot strand a virtual monitor.

## Parallel agents

Concurrent agents must use unique output names, unique client classes/titles,
and separate workspaces. They may share the compositor only as long as none of
them depends on changing the human seat's focus or pointer.

Independent agent pointer/keyboard injection is a stronger capability than a
headless output and must not be inferred from successful display isolation.
