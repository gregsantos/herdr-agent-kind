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

A Herdr plugin runs as your user with no sandbox, so it is worth knowing what
one touches before confirming the install. For this plugin that is two Herdr
commands, `python3`, and one opt-in log file — [SECURITY.md](SECURITY.md) lists
all of it and takes two minutes to read.

**Installing alone changes nothing.** The plugin only publishes the value; your
config decides whether it is rendered.

Edit `~/.config/herdr/config.toml` and add `$agent_kind` to the agent rows under
`[ui.sidebar.agents]`. Note that `rows` **replaces** the layout entirely rather
than adding to it, so start from what you already have. Against Herdr's default:

```toml
[ui.sidebar.agents]
# 0.9.0 default:  rows = [["state_icon", "machine", "workspace", "tab"], ["agent"]]
# 0.8.2 default:  rows = [["state_icon", "workspace", "tab"], ["agent"]]
rows = [["state_icon", "machine", "workspace", "tab"], ["agent", "$agent_kind"]]
```

The default gained a `machine` token in 0.9.0, so check yours rather than
copying either line blindly — `rows` replaces the layout, and dropping a token
you had is easy to do by accident.

A fuller layout, showing the session name, the agent name and the kind together:

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

### Colour each kind differently

**Requires Herdr 0.9.0.** Token `rules` are not part of 0.8.2, where an inline
token table accepts only `fg`, `bold` and `dim`. On 0.8.2 give `$agent_kind` a
single fixed style instead — a `rules` key there buys you nothing at best, and
a rejected layout at worst.

Text-valued tokens accept up to 16 ordered `rules`, so the kind can carry its
own colour instead of being one more dim word. Each rule takes exactly one
condition — `equals`, `contains`, `starts_with`, `gt` or `lt` — plus optional
`fg`, `bold` and `dim`. The first match wins, and unspecified fields inherit
the token's own style:

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", "state_text", { token = "$agent_kind", dim = true, rules = [
    { equals = "claude", fg = "#fab387", dim = false },
    { equals = "codex", fg = "#74c7ec", dim = false },
  ] }],
  [{ token = "terminal_title_stripped", bold = true }],
  [{ token = "workspace", dim = true }, { token = "tab", dim = true }],
]
```

Kinds you did not name keep the token's default style, so a pane running
something else stays dim rather than borrowing a colour that means "claude".
Match values against Herdr's canonical ids, which are lowercase and which
`herdr server agent-manifests` will list — `claude`, `codex`, `gemini`, `pi`,
`copilot` and so on. `equals` is case-sensitive.

### First run

The plugin publishes when an agent is *detected*, so a fresh install does not
retrofit itself onto agents that are already running — `$agent_kind` stays empty
for existing panes until something triggers a publish. Fill them in without
restarting anything:

```sh
herdr plugin action invoke gregsantos.agent-kind.refresh
```

Starting a new agent or restarting the Herdr server has the same effect.

Two things to know while editing rows:

- **Row 1 should lead with `state_icon`.** Row 1 renders flush left while later
  rows indent past the icon gutter, so a first row that starts with anything
  else leaves the remaining rows hanging.
- Run `herdr server reload-config` to apply. It reports invalid tokens in its
  `diagnostics` array, so an empty array means the rows parsed cleanly.

## Update

There is no `herdr plugin update` in plugin v1. Reinstalling from GitHub
refreshes the managed checkout in place:

```sh
herdr plugin install gregsantos/herdr-agent-kind
```

That is the whole procedure. You do **not** need to uninstall first — the
install reports what it replaces — and you do **not** need `herdr plugin link`,
which is for developing against a local working tree, not for updating.

Reinstalling leaves your setup alone:

- `~/.config/herdr/config.toml` is untouched, so your `rows` stay as they are.
- The plugin's own config and state directories survive, including the `debug`
  marker if you enabled diagnostics.
- Already-published `$agent_kind` tokens stay live, so the sidebar does not
  blink and you do not need to re-run anything.

To see what you have installed, and at which commit:

```sh
herdr plugin list --plugin gregsantos.agent-kind
```

To pin a revision instead of following the default branch:

```sh
herdr plugin install gregsantos/herdr-agent-kind --ref v0.5.3
```

Two cases where an update needs one more step, both flagged in
[CHANGELOG.md](CHANGELOG.md):

- **A release changes what gets published.** `[[startup]]` hooks only run when
  Herdr restores a session, so they do not re-run on reinstall. Reconcile every
  pane without restarting the server:

  ```sh
  herdr plugin action invoke gregsantos.agent-kind.refresh
  ```

- **A release renames the token.** That is breaking: update `rows` in
  `~/.config/herdr/config.toml`, then run `herdr server reload-config`.

If you linked a local checkout for development, `plugin install` is refused
until you `herdr plugin unlink gregsantos.agent-kind` first. See
[CONTRIBUTING.md](CONTRIBUTING.md).

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

- Herdr >= 0.8.2 — verified on **0.8.2 and 0.9.0**, including across an
  in-place upgrade between them. Custom sidebar tokens and `[[startup]]` hooks
  landed earlier (around 0.7.4-0.7.5), but the release that added the
  `pane.agent_detected` plugin event is undocumented, so the floor is set to
  what is actually verified rather than what is likely.
- `python3`, for parsing Herdr's JSON output. If it is missing the plugin
  exits non-zero with a message rather than silently publishing nothing.
- Any POSIX shell — `/bin/sh`. No bash required; verified under dash, bash,
  zsh and macOS `/bin/sh`.
- macOS or Linux

## Troubleshooting

Diagnostics are off by default. To enable them on a machine:

```sh
touch "$(herdr plugin config-dir gregsantos.agent-kind)/debug"
```

Each run then logs the event, its payload, and every publish outcome to
`$HERDR_PLUGIN_STATE_DIR/agent-kind.log`, readable only by you. For a one-off,
set `HERDR_AGENT_KIND_DEBUG=1` instead. The log goes only to the state
directory Herdr provides, so running the script by hand outside Herdr never
writes one.

```sh
herdr plugin list --plugin gregsantos.agent-kind
herdr pane get w1:p2              # look for "tokens": {"agent_kind": "..."}
herdr plugin log list --plugin gregsantos.agent-kind
```

The plugin log is the most useful of the three: Herdr records `exit_code`,
`stdout` and `stderr` for every hook invocation, so a failing run says why.

Two symptoms that look like plugin faults but are not:

- **The sidebar is unchanged, still showing your previous layout.** Herdr reads
  `config.toml` at startup and on `herdr server reload-config`; editing the file
  alone changes nothing. This bites hardest when the config arrives from
  elsewhere — a dotfiles sync onto a second machine — because then there is no
  moment where you would think to reload. Run `herdr server reload-config`.
- **The row renders but the kind is absent**, meaning the layout is live and the
  token is empty. The agent in that pane was already running when the plugin was
  installed; see First run, and run the `refresh` action.

## Uninstall

```sh
herdr plugin uninstall gregsantos.agent-kind
```

Then remove `$agent_kind` from your rows in `~/.config/herdr/config.toml` and run
`herdr server reload-config`. A token left in the config after uninstalling is
harmless — it simply renders as nothing.

Panes keep their last published `agent_kind` value until the Herdr server next
restarts, since pane metadata is runtime-only. To clear it immediately:

```sh
herdr pane report-metadata w1:p2 --source agent-kind --clear-token agent_kind
```

## Limitations

- When an agent exits and its pane returns to a shell, the pane keeps a stale
  `agent_kind` token. It is never rendered, because the agents sidebar only lists
  panes that currently host an agent.
- A failed publish is logged, not raised, so the hook exits 0 and the plugin log
  stays green. Enable diagnostics to see publish failures. The one deliberate
  exception is a missing `python3`, which exits non-zero with a message rather
  than publishing nothing quietly — see [Requirements](#requirements).

## License

MIT
