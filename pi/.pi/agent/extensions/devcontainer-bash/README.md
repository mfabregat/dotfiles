# devcontainer-bash

Route pi's `bash` tool (and `!` commands) into a running devcontainer via
`docker exec`. pi itself stays on the host — native config, API keys, sessions,
packages — while every command executes inside the container's exact toolchain.

Nothing is hardcoded. Everything is discovered from your project or your
container:

| What | Where it comes from |
|---|---|
| Workspace root | Walk up from pi's cwd to the nearest `.devcontainer/` |
| Container | `devcontainer.local_folder` label → container name == workspace folder name → `<folder>-…` prefix (compose) → `container` config |
| Exec user | `user` config → `remoteUser`/`containerUser` in devcontainer.json (`${localEnv:X}`/`${env:X}` substituted from the host, e.g. `"${localEnv:USER}"`) → `docker inspect Config.User` |
| Extra env | `remoteEnv` in devcontainer.json (`${localEnv:X}` supported) + `env` config |
| Shell | `bash -ic` by default (loads `~/.bashrc`, faithful interactive shell); job-control stderr noise is filtered |
| Host↔container path | `workspaceFolder` in devcontainer.json (`${localWorkspaceFolder}` supported); same-path bind mounts map 1:1 |
| Timeout / abort | The command's in-container process group is killed (killing only the docker CLI would leave it running in the container) |
| Status | TUI footer indicator: `🐳 g1_ws · devcontainer (marc)` (blue) when routed, `○ g1_ws · host shell (no container)` (dim) when the container isn't running; nothing is shown when routing is off or outside a devcontainer workspace |

## Install

```bash
mkdir -p ~/.pi/agent/extensions
cp -R <this dir> ~/.pi/agent/extensions/devcontainer-bash
```

Then start pi in your devcontainer's workspace. No flags needed — it
auto-detects. Changes are hot-reloaded with `/reload`.

## Turning it on / off

- **Auto-detect**: yes. On each bash call it looks for a running container for
  the current workspace (cached ~5s). Start the devcontainer after pi and
  routing kicks in automatically.
- **Per project**: `.pi/devcontainer-bash.json` → `{ "enabled": false }`
- **Globally**: `~/.pi/agent/extensions/devcontainer-bash.json` → `{ "enabled": false }`
- **One run**: `pi --no-devcontainer-bash`
- **Interactive**: `/devcontainer-bash status | recheck | on | off | toggle`
  (`on`/`off`/`toggle` persist `enabled` to the project's `.pi/devcontainer-bash.json`,
  so the choice survives restarts; `status` prints the full routing details,
  `recheck` forces container detection)
- **Status indicator**: the TUI footer shows the live routing state — a blue
  `🐳 g1_ws · devcontainer (marc)` when bash runs inside the container, a dim
  `○ g1_ws · host shell (no container)` when the devcontainer exists but isn't
  running. Nothing is displayed when routing is switched off or in workspaces
  without a devcontainer config. The indicator is refreshed at session start,
  at each turn, and on every bash call.
- **No container running**: bash falls back to the host shell
  (`whenNoContainer: "pass-through"`, default) or fails loudly
  (`"error"`), and re-detects automatically once the container starts.

## Configuration

Merged: defaults < global (`~/.pi/agent/extensions/devcontainer-bash.json`) <
project (`<workspace>/.pi/devcontainer-bash.json`).

```jsonc
{
  "enabled": true,
  "container": "auto",                // "auto" | name | id
  "user": "auto",                     // "auto" | "marc" | "root" | uid
  "workspaceFolder": null,            // force the container workspace path
  "interactive": true,                // bash -ic (loads ~/.bashrc) vs bash -lc
  "filterJobControlNoise": true,      // strip bash -i stderr noise
  "whenNoContainer": "pass-through",  // "pass-through" | "error"
  "env": { "SSH_AUTH_SOCK": null },   // extra env; null = copy from host
  "recheckIntervalMs": 5000
}
```

## Notes & limitations

- Only `bash` + `!`/`!!` are routed. File tools (`read`, `write`, `edit`,
  `grep`, `find`, `ls`) run on host files — which are the same files the
  container sees via the bind mount.
- Subagents run in the same pi process, so they inherit container routing.
- Host environment (PATH etc.) is deliberately NOT forwarded; the container's
  own env + `remoteEnv`/`env` apply.
- Requires `docker` CLI on the host and the devcontainer running. On
  non-POSIX hosts (Windows), set `workspaceFolder` and `user` explicitly.
