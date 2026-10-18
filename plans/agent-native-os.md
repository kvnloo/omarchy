# Research plan: an AI-native Omarchy, without a second OS

> Downstream design exploration; **not** an approved upstream roadmap, issue, or pull request. Dated 2026-10-18. Do not enable agents or remote access automatically.

## Thesis

Omarchy is already *agentic*: `omarchy agent prompt` dispatches a selected coding agent, the agents panel integrates multiple subscriptions, Hermes/OMP launch paths already exist, and `omarchy-shell` provides first-party IPC into Quickshell. The winning next step is **safe agent interaction with desktop state**, not a new orchestration daemon, agent harness, menu, or window manager.

The product question: can a user say *"prepare a workspace for reviewing this PR"* and get a fast, visible, revocable plan that controls windows, apps, workspaces, and remote sessions without silently taking over the local desktop?

Keep the existing division: Hyprland owns windows and focus; Quickshell owns the shell UI; Omarchy commands own setup/lifecycle; a user's chosen agent (Hermes, OMP, Codex, etc.) interprets intent. Models stay interchangeable. The OS exposes a **small deterministic contract**, not an LLM dependency.

## Inventory before implementation

Canonical sources:
- [Omarchy AI manual](../manual/17-ai.md): agent selection, launching, first-party agents panel.
- [Shell architecture](../docs/omarchy-shell.md): `omarchy-shell` IPC, plugin kinds, capability-scoped facades, startup/idle budgets, third-party plugin threat limits.
- [Agent development guides](../AGENTS.md): first-party helpers, event-driven services, CLI metadata/tests, visual/VM verification.
- [Remote](remote.md): planned Sunshine/Moonlight virtual outputs and paired clients.
- [Dots](dots.md), [Backup](backup.md), [Server](server.md): multi-device state, recovery, and headless editions.

**Important existing security contract:** third-party shell plugins are unsandboxed QML running with the user's privileges. Their facades constrain accidental or advertised API access but are **not** a sandbox. Do not treat an agent-facing QML plugin as a security enforcement boundary, or automatically install/enable a remote agent plugin.

## Product boundary: observe → prepare → confirm → commit

A single opt-in task flow, not a resident AI copilot:

1. **Observe.** User initiates a local task. Read only the state explicitly required: selected workspace, monitor layout, focused window class/ID, relevant app list, and the user's request. No default screenshot, keystroke capture, clipboard export, access tokens, shell history or notifications. Reuse trusted Omarchy/Hyprland readers; do not enumerate other applications' contents.
2. **Prepare.** Agent chooses from a typed registry of existing, bounded operations (launch app, move a *specific* window to a workspace, focus an existing workspace, open an Omarchy menu, arrange approved project terminals, optionally ask for a private remote display). Preview affected surfaces and intended operations.
3. **Confirm.** Before mutating focus, opening privileged UI, moving a user's window, crossing devices or changing network exposure, present a visible local approval with a bounded scope. A user may elect an explicitly time-limited capability for repetitive safe actions; approval expires automatically and is not transferable between workspaces or users. Decline means no side effects.
4. **Commit.** Recheck that targets and focus have not changed, execute a short serial plan, return a structured receipt with action result, errors and any reversible previous state. Never turn a stale preview into an action. No arbitrary bash command hidden behind a structured operation.

This is a **contract prototype** (not a settled API). Illustrative intent/receipt:

```json
{
  "version": 1,
  "intent": "prepare_review_workspace",
  "targets": [
    {"kind": "workspace", "name": "review"},
    {"kind": "application", "desktopId": "org.wezfurlong.wezterm.desktop"}
  ],
  "requestedCapabilities": ["workspace.focus", "app.launch"],
  "approval": "required"
}
```

```json
{
  "version": 1,
  "status": "needs_approval",
  "commitToken": null,
  "preview": ["Focus review workspace", "Open terminal"]
}
```

Neither the example format nor the operation names should enter Omarchy core before maintainer agreement. Avoid executing external data serialized into a shell command. Use fixed executables and validated argv arrays at the boundary.

## Two implementation locations

**User-space experiment (first):** a standalone opt-in CLI/plugin in the fork (or a separate plugin repo), reading only documented OS state and presenting a non-privileged preview. It must work without Hermes, ChatGPT, or any installed model. Probe the existing `omarchy-shell` IPC before adding methods.

**Possible first-party integration (only if invited):** add the minimum missing typed state/action interface as a narrow `omarchy-` command or an existing IPC endpoint. Test that it does not widen third-party plugin privileges. Reuse the menu's current confirmation and terminal patterns; do not create a parallel approvals framework unless current mechanisms demonstrably fail.

Do **not** ship a generic agent-to-shell `eval`, an unrestricted `hyprctl dispatch` endpoint, an unauthenticated localhost server, an always-running listener, or a QML interface promising plugin isolation it cannot provide.

## Milestones: small, independently reviewable

| Phase | Deliverable | Quality proof | Upstream gate |
| --- | --- | --- | --- |
| A: observe | Read-only workspace snapshot with documented redaction/consent, no new service | CLI fixture with synthetic monitor/workspace layouts, privacy deny cases, no idle process spawns | Can live entirely downstream |
| B: preview | Produce local action preview for two fixed verbs (focus workspace, launch app) | Red→green tests for unknown verbs, missing targets, focus changed during preview, no mutation before approval | Maintainer approves any new core verb |
| C: commit | A single visible approval → deterministic operation → receipt | Expired approvals and changed target IDs cause no action; cancellation and rollback behavior tested | Scoped review and VM/Hyprland acceptance |
| D: remote | Optional independent remote workspace instead of stealing the user's focused output | Sunshine/Moonlight test in VM and real client, offline and disconnect recovery | Follows [remote plan](remote.md), no competing remote stack |
| E: companion | Voice/Android/CUA may call the same user-approved verbs over an authenticated user-controlled channel | No incoming-by-default network listener; per-device revoke and local-stop tests | Separate opt-in add-on, not base install |

A/B/C can be prototype-level UI and acceptance harnesses. Do not claim full computer-use parity until actual-focus, multi-monitor, disconnect, prompt-injection, and remote-session testing exists.

## Personalization and UX research questions

- **Low latency.** Measure p50/p95 *observe, preview, commit* separately; no arbitrary "20×" claim until repeated baseline/candidate runs. Do not spawn a process while the shell is idle (see `test/shell.d/shell-idle-spawn-test.sh`).
- **Handsfree.** The user chooses the voice front end and model routing; the OS contract is voice-agnostic. Barge-in cancels a pending *preview*, never implies previously granted privileged access.
- **Flow-preserving UI.** Summon a compact preview in the current desktop; only a meaningful state transition animates; no persistent floating agent overlay by default. A confirmation must show the app/window/workspace receiving the action.
- **Multi-machine.** Reuse dots for curated configuration and backup for durable recovery, neither for live authorization tokens. A remote "workspace lease" must be bound to the correct host, user and display.
- **Device diversity.** Preserve x86/aarch64 behavior and Omarchy's existing hardware-family predicates. Local GPU models, GPU leases, NVIDIA tuning, and K3s are optional accelerators, never baseline requirements.

## Threats and rollback

Prompt injection may arrive in webpages, issues, repository README files, application titles, clipboard contents, screenshots or notification bodies. Treat all of them as untrusted **observations**; never accept requests for tool calls or approval policy embedded inside those surfaces. An agent's interpretation is not user approval.

Enforce scope at a trusted OS/native command boundary, not solely in a Quickshell view or plugin facade. Keep a visible user-level kill/cancel control. Avoid intercepting physical keyboard/mouse or silent clipboard reads. Log only operation IDs, statuses, and safe redacted targets, with explicit retention and no tokens. Ensure workspaces/windows are not moved if their identity changed while the agent was reasoning.

Failure should leave a functioning standard Omarchy desktop: disable/remove the experimental plugin, restore previous bindings, and preserve the user's app data and current input session.

## How this gets merged

Follow Omarchy's actual incentives, not a PR-count target. Start with a reproducer of a **specific missing user capability** in a supported path, compare current `quattro`, ask a maintainer whether it belongs inside first-party Omarchy, and contribute small atomic patches with the matching skill guide and tests. Do not open a broad RFC PR without an explicit green light.

Track accepted upstream commits, meaningful human feedback, exact-head CI/VM evidence and attribution. Do not create overlapping fixes, bypass `omarchybot` classification, or re-open feature requests that maintainers already declined.

**Upstream provenance:** Omarchy is maintained by DHH and its contributor community; Hyprland, Quickshell, Sunshine/Moonlight, Hermes and OMP are distinct upstream projects whose architectures and contributors must be credited independently.
