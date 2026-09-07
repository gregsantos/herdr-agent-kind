# herdr-agent-kind

A [Herdr](https://herdr.dev) plugin that publishes each pane's agent kind as an
`$agent_kind` sidebar token, so you can show an agent's name *and* what it is.

```text
 ○ idle
   reviewing auth · reviewer · claude
   myrepo · api-work
 ◑ working
   porting tests · migrator · codex
   myrepo · api-work
```

## Why

Herdr's built-in `agent` token renders the **Herdr agent name** when one is set,
and falls back to the kind (`claude`, `codex`, …) only when none is. Since
`herdr agent start <name>` always sets a name, naming your agents costs you the
ability to tell from the sidebar which kind each one is.

This plugin publishes the kind as a separate `$agent_kind` token, so the two never
compete for the same slot. It decides only what the token *contains* — colour,
weight and placement stay in your Herdr config.

If you never name agents, you don't need this: `agent` already shows the kind.

## Install

```sh
herdr plugin install gregsantos/herdr-agent-kind
```

**Installing alone changes nothing.** The plugin only publishes the value; your
config decides whether it is shown. Add `$agent_kind` to your agent rows,
alongside `agent` for the name:

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", "state_text"],
  [{ token = "terminal_title_stripped", bold = true },
   { token = "agent", dim = true },
   { token = "$agent_kind", dim = true }],
  [{ token = "workspace", dim = true }, { token = "tab", dim = true }],
]
```

Drop the `agent` token if you'd rather show only the session name and the kind.
Herdr picks the change up on `herdr server reload-config`.

## How it works

Pane metadata in Herdr is runtime-only — it is never written to `session.json`,
so it does not survive a server restart. The plugin publishes on two hooks:

- `[[startup]]` — sweeps every pane hosting an agent. This is what restores the
  tokens after a restart.
- `[[events]] on = "pane.agent_detected"` — publishes for one pane the moment
  Herdr detects an agent in it, including on session restore.

Both shell out to `herdr pane report-metadata <pane> --source agent-kind --token
agent_kind=<kind>`. No compiled binary, no polling, no daemon.

## Requirements

- Herdr >= 0.8.2 — the version this is developed and tested against. Custom
  sidebar tokens and `[[startup]]` hooks landed earlier (around 0.7.4-0.7.5),
  but the release that added the `pane.agent_detected` plugin event is not
  documented, so the floor is set to what is actually verified.
- `python3`
- macOS or Linux

## Troubleshooting

Diagnostics are off by default. To enable them on a machine:

```sh
touch "$(herdr plugin config-dir gregsantos.agent-kind)/debug"
```

Each run then logs the event, its payload, and every publish outcome to
`$HERDR_PLUGIN_STATE_DIR/agent-kind.log`. For a one-off, set
`HERDR_AGENT_KIND_DEBUG=1` instead.

```sh
herdr plugin list --plugin gregsantos.agent-kind
herdr pane get <pane_id>          # look for "tokens": {"agent_kind": "..."}
```

## Limitations

- When an agent exits and its pane returns to a shell, the pane keeps a stale
  `agent_kind` token. It is never rendered, because the agents sidebar only lists
  panes that currently host an agent.
- A failed publish is logged, not raised — the hook always exits 0. Enable
  diagnostics to see failures.

## License

MIT
