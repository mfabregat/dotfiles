# devcontainer-bash

Route pi's `bash` tool (and `!` commands) into a running devcontainer via
`docker exec`. pi itself stays on the host — native config, API keys, sessions,
packages — while every command executes inside the container's exact toolchain.

Nothing is hardcoded. Everything is discovered from your project or your
container:

| What | Where it comes from |
|---|---|
| Workspace root | Walk up from pi's cwd to the nearest `.devcontainer/` |
| Container | `devcontainer.local_folder` label → container name == workspace folder name → `container` config |
| Exec user | `user` config → `remoteUser`/`containerUser` in devcontainer.json → `docker inspect Config.User` |
| Extra env | `remoteEnv` in devcontainer.json (`${localEnv:X}` supported) + `env` config |
| Shell | `bash -ic` by default (loads `~/.bashrc`, faithful interactive shell); job-control stderr noise is filtered |
| Host↔container path | `workspaceFolder` in devcontainer.json (`${localWorkspaceFolder}` supported); same-path bind mounts map 1:1 |

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
- **Interactive**: `/devcontainer-bash status | recheck | on | off`
  (`on`/`off` persist `enabled` to the project's `.pi/devcontainer-bash.json`)
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
