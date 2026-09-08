# Security

## Reporting a vulnerability

Please report privately rather than opening a public issue: use **Security →
Report a vulnerability** on this repository, which opens a private GitHub
security advisory. If private reporting is not available to you, open an issue
asking for a private channel — without the details — and it will be set up.

Expect an acknowledgement within a few days. There is no bounty.

## Supported versions

| Version | Supported |
| ------- | --------- |
| 0.5.x   | yes       |
| < 0.5   | no        |

Fixes land on `main` and go out as a new patch version. There is no
`herdr plugin update` in plugin v1, so upgrading means reinstalling:

```sh
herdr plugin install gregsantos/herdr-agent-kind
```

## What this plugin can do

Herdr's own guidance is worth repeating: a plugin is ordinary code that runs as
your user, inherits your environment, and can call the full Herdr CLI. Herdr
validates the manifest and separates each plugin's config and state, but it does
not sandbox plugin code. So review before you install — and this section exists
to make that review take two minutes.

The whole plugin is `herdr-plugin.toml` plus `publish-kind.sh`. What it actually
does:

- **Runs two Herdr commands, and nothing else.** `herdr agent list` to read
  which panes host an agent, and `herdr pane report-metadata` to publish the
  `agent_kind` token. Both go through `HERDR_BIN_PATH`, the binary Herdr hands
  the plugin.
- **Runs `python3`** to parse Herdr's JSON. That is the only dependency beyond a
  shell.
- **Writes one file, only when you ask it to.** `agent-kind.log` in
  `HERDR_PLUGIN_STATE_DIR`, and only while diagnostics are enabled — off by
  default. Nothing is written to `HERDR_PLUGIN_ROOT`.
- **Reads one file, for its existence only.** `debug` in
  `HERDR_PLUGIN_CONFIG_DIR`. The contents are never read.

What it does not do: no network access of any kind, no reading or writing of
credentials, no files outside its own state directory, no `eval`, and no
persistent process — every hook runs once and exits.

## Handling of event data

`HERDR_PLUGIN_EVENT_JSON` is parsed with `json.loads` and is never executed. The
pane id and agent kind taken from it are passed to the Herdr binary as separate
argv elements, never interpolated into a shell command, so a value containing
shell metacharacters is inert. Since 0.5.1 the manifest invokes
`./publish-kind.sh` directly rather than through `sh -c`, so no shell parses
anything on the plugin's behalf.

The values themselves come from Herdr, not from terminal output, and land in a
display-only pane token — `report-metadata` explicitly does not take over
semantic pane state.

## Diagnostics contain your pane layout

With diagnostics on, the log records each event's full payload, including pane
ids, workspace ids and agent kinds. It is local, in your own state directory,
but scrub it before attaching it to a bug report:

```sh
herdr plugin config-dir gregsantos.agent-kind    # remove the `debug` marker to stop
```
