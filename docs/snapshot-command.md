# Hermes Agent `/snapshot` Command

`/snapshot` is a Hermes Agent interactive CLI slash command for making and restoring **lightweight snapshots of Hermes’ own config/state**, not your project files.

It is CLI-only and has alias:

```text
/snapshot
/snap
```

## What it is for

Use `/snapshot` when you want a quick “save point” for your Hermes installation/profile before changing things like:

- model/provider config
- API keys / `.env`
- auth state
- cron jobs
- gateway/channel state
- Hermes state database
- process registry state

It is basically the in-session version of:

```bash
hermes backup --quick
```

## Basic syntax

```text
/snapshot                         # list recent snapshots
/snapshot list                    # same as above
/snapshot ls                      # same as above

/snapshot create [label]          # create a snapshot
/snapshot restore <id-or-number>  # restore a snapshot
/snapshot rewind <id-or-number>   # alias for restore

/snapshot prune [N]               # keep only N newest snapshots; default 20
```

Alias:

```text
/snap create pre-model-change
/snap restore 1
```

## Where snapshots are stored

Snapshots are saved under the active Hermes home:

```text
~/.hermes/state-snapshots/
```

For profiles, this is profile-aware, i.e. it uses the current `HERMES_HOME`, not necessarily the global default.

Each snapshot is a timestamped directory, for example:

```text
~/.hermes/state-snapshots/20260425-043210-pre-model-change/
```

Inside it, Hermes stores copies of selected state files plus:

```text
manifest.json
```

The manifest records the snapshot ID, timestamp, label, file count, total size, and included files.

## What files it snapshots

The quick snapshot backend currently targets these critical files relative to `HERMES_HOME`:

```text
state.db
config.yaml
.env
auth.json
cron/jobs.json
gateway_state.json
channel_directory.json
processes.json
```

Important notes:

- `state.db` is copied using SQLite’s backup API when possible, so the snapshot is consistent even if Hermes is running.
- `.env` and `auth.json` may contain secrets/tokens. These snapshots are local state backups, not sanitized exports.
- It does **not** snapshot your current project/workspace files.
- It does **not** snapshot the Hermes source repo, caches, logs, or installed skills as a complete portable backup.

For a full Hermes-home backup, use:

```bash
hermes backup
```

## Listing snapshots

Run:

```text
/snapshot
```

or:

```text
/snapshot list
```

Hermes prints a table like:

```text
State snapshots (~/.hermes/state-snapshots/):

    #  ID                                  Files       Size Label
  ───  ─────────────────────────────────── ───── ────────── ────────────────────
    1  20260425-043210-pre-model-change       6      420 KB pre-model-change
    2  20260424-221030                         5      398 KB
```

The list is most-recent-first.

You can restore by either:

- snapshot ID, e.g. `20260425-043210-pre-model-change`
- row number, e.g. `1`

## Creating a snapshot

```text
/snapshot create
```

creates an unlabeled snapshot.

```text
/snapshot create before-openrouter-change
```

creates a labeled snapshot.

The label becomes part of the snapshot ID:

```text
20260425-043210-before-openrouter-change
```

After creation, Hermes automatically prunes old snapshots beyond the default keep count of 20.

## Restoring a snapshot

Restore by row number:

```text
/snapshot restore 1
```

or by full ID:

```text
/snapshot restore 20260425-043210-before-openrouter-change
```

`rewind` is equivalent:

```text
/snapshot rewind 1
```

Restore behavior:

- Hermes overwrites the current state files with the snapshot’s copies.
- For `.db` files, it does an atomic-ish replace through a temporary file.
- It returns success if at least one file was restored.
- Hermes prints:

```text
Restored state from: <snapshot-id>
Restart recommended for state.db changes to take effect.
```

That restart recommendation matters: if you restored `state.db`, `config.yaml`, auth, cron, or gateway-related files, the currently running process may still have old in-memory state.

## Pruning snapshots

```text
/snapshot prune
```

keeps the newest 20 snapshots.

```text
/snapshot prune 5
```

keeps the newest 5 and deletes older ones.

## `/snapshot` vs `/rollback`

They solve different problems:

| Command | Protects | Storage | Use case |
|---|---|---|---|
| `/snapshot` | Hermes config/state | `~/.hermes/state-snapshots/` | Undo Hermes config/auth/state changes |
| `/rollback` | Project/workspace files changed by tools | `~/.hermes/checkpoints/` shadow git repos | Undo file edits made by the agent |

Use `/snapshot` before changing Hermes itself.

Use `/rollback` after the agent changes files in your repo and you want to revert those code/workspace edits.

## Practical examples

Before changing models/providers:

```text
/snapshot create before-model-switch
/model anthropic/claude-sonnet-4
```

If the config breaks:

```text
/snapshot restore 1
```

Before messing with cron/gateway config:

```text
/snapshot create before-gateway-cron-test
```

Clean up old snapshots:

```text
/snapshot prune 10
```

## Caveats

- It is **CLI-only** according to the command registry.
- It snapshots sensitive files like `.env` and `auth.json`; treat `state-snapshots/` as secret-bearing local data.
- It is not a full migration/export mechanism. For portable backups, use `hermes backup`.
- If you create labels with spaces, the snapshot ID can contain spaces. Restoring by row number, e.g. `/snapshot restore 1`, is safest.
