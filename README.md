# herdr-agent-kind

A [Herdr](https://herdr.dev) plugin that publishes each pane's detected agent
kind as a `$kind` sidebar token.

```text
 ○ idle
   reviewing auth · claude
   myrepo · main
```

## Why

Herdr's built-in `agent` sidebar token renders the **Herdr agent name** whenever
one is set, and falls back to the kind (`claude`, `codex`, …) only when none is.
So the moment you name an agent — which `herdr agent start <name>` always does —
you can no longer tell from the sidebar which kind of agent is running.

This plugin publishes the kind as a separate `$kind` token, so the name and the
kind never compete for the same slot. It decides only what the token *contains*;
colour, weight and placement belong to your Herdr config.

## Install

```sh
herdr plugin install gregsantos/herdr-agent-kind
# or, from a local checkout:
herdr plugin link /path/to/herdr-agent-kind
```

Then reference `$kind` in your agent rows:

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", "state_text"],
  [{ token = "terminal_title_stripped", bold = true }, { token = "$kind", dim = true }],
  [{ token = "workspace", dim = true }, { token = "tab", dim = true }],
]
```

## How it works

Pane metadata in Herdr is runtime-only — it is not written to `session.json` and
does not survive a server restart. The plugin therefore publishes on two hooks:

- `[[startup]]` — sweeps every pane hosting a detected agent, which is what
  restores the tokens after a restart.
- `[[events]] on = "pane.agent_detected"` — publishes for a single pane as soon
  as Herdr detects an agent in it, including on session restore.

Both paths shell out to `herdr pane report-metadata <pane> --source agent-kind
--token kind=<kind>`. No compiled binary, no polling.

## Requirements

- Herdr >= 0.7.5 — the version that introduced custom sidebar tokens,
  `pane report-metadata`, and `[[startup]]` hooks. Developed and tested against
  **0.8.2**; compatibility with releases older than that is untested.
- `python3` for JSON parsing.
- macOS or Linux.

## Troubleshooting

Diagnostics are off by default, because this runs on every agent detection and
an always-on log means constant file churn for a case that only matters when
something is broken. Enable it per machine:

```sh
touch "$(herdr plugin config-dir gregsantos.agent-kind)/debug"
# or, for a one-off:  HERDR_AGENT_KIND_DEBUG=1
```

Each invocation then appends the event name, raw payload, and the outcome of
every publish to `$HERDR_PLUGIN_STATE_DIR/agent-kind.log`.

```sh
herdr plugin list --plugin gregsantos.agent-kind
herdr plugin log list --plugin gregsantos.agent-kind
herdr pane get <pane_id>   # look for "tokens": {"kind": "..."}
```

## Known limitations

- If an agent exits and its pane becomes a plain shell, the pane keeps a stale
  `kind` token. Harmless in practice: the agents sidebar only lists panes that
  currently host an agent, so a stale token on a shell pane is never rendered.
- Publish failures are swallowed rather than failing the hook, since a non-zero
  plugin exit is noise the user cannot act on mid-session. Enable diagnostics to
  see them.

## License

MIT
