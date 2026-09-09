# Contributing

Thanks for looking at this. The plugin is deliberately small — one shell script
and a manifest — so the bar for a change is mostly "does it stay small".

## Scope

The plugin decides what the `$agent_kind` token *contains*. Colour, weight and
placement stay in the user's Herdr config, and that split is intentional: a
plugin that also styled the token would fight `[ui.sidebar.agents]` for the same
slot, which is the exact problem the plugin exists to avoid.

Things that are out of scope: rendering, anything that polls, anything that
needs a daemon, and anything that writes to `HERDR_PLUGIN_ROOT`.

## Development loop

Link your working tree instead of installing from GitHub, so edits take effect
immediately:

```sh
herdr plugin link "$(pwd)"
herdr plugin action invoke gregsantos.agent-kind.refresh
herdr pane get w1:p1              # look for "tokens": {"agent_kind": "..."}
herdr plugin log list --plugin gregsantos.agent-kind
```

`herdr plugin unlink gregsantos.agent-kind` when you are done. Installing over a
linked plugin is refused, so unlink before reinstalling from GitHub.

The plugin log is the most useful of those: Herdr records `exit_code`, `stdout`
and `stderr` for every hook invocation, so a failing run says why. Turn on
diagnostics for more detail:

```sh
touch "$(herdr plugin config-dir gregsantos.agent-kind)/debug"
```

## Tests

```sh
./tests/run.sh                    # /bin/sh
TEST_SHELL=/bin/dash ./tests/run.sh
TEST_SHELL=/bin/zsh ./tests/run.sh
```

`tests/mock-herdr.sh` stands in for the real binary through `HERDR_BIN_PATH`, so
the suite never touches a running Herdr server. It exists because the plugin's
real risk surface is the *shape* of the JSON it parses — `herdr agent list`
output and the `pane.agent_detected` payload — and those come from a Herdr
version the plugin does not control. A change that touches either parser needs a
case pinning the shape it handles.

Assertions are on the complete set of `pane report-metadata` calls, so a change
that publishes something extra fails just as loudly as one that publishes
nothing.

There is no Makefile on purpose: every check is already one command.

```sh
shellcheck -s sh publish-kind.sh tests/run.sh tests/mock-herdr.sh
python3 -c 'import pathlib, tomllib; tomllib.loads(pathlib.Path("herdr-plugin.toml").read_text())'
```

CI runs both of those plus the suite across sh, dash, bash and zsh on Linux and
macOS.

## Constraints worth knowing before you edit

- **POSIX `sh`, not bash.** Herdr runs on Linux, where bash is not guaranteed,
  and a bash shebang fails before any check inside the script can report why.
  Keep `shellcheck -s sh` clean.
- **No unquoted word splitting.** zsh does not word-split unquoted expansions.
  This has already silently broken a publish path once; split with parameter
  expansion instead.
- **`python3` is the only dependency beyond a shell**, and only for parsing
  JSON. Adding a second runtime dependency needs a good reason.
- **Two different failure policies, both deliberate.** A failed publish is
  logged and the hook still exits 0, because it can fail for reasons the user
  cannot act on mid-session. A missing `python3` exits non-zero, because it is
  permanent, the user can fix it, and exiting 0 would be indistinguishable from
  "no agents to report".
- **`min_herdr_version` tracks what was actually verified**, not what is likely
  to work. Custom sidebar tokens and `[[startup]]` hooks landed around
  0.7.4-0.7.5, but the release that added the `pane.agent_detected` plugin
  event is undocumented, so the floor is 0.8.2, the oldest version the plugin
  has been run against, including across an in-place upgrade to 0.9.0. Do not
  lower it based on when a feature probably landed.

## Submitting a change

1. Branch off `main`.
2. Add or update tests, and make sure the suite passes under at least `sh` and
   one other shell.
3. Add a `CHANGELOG.md` entry under a new version heading, saying *why* — the
   token's shape and the failure policy are the parts that affect anyone's
   config.
4. Bump `version` in `herdr-plugin.toml`. A change to the token name is
   breaking: users have to edit `rows` and run `herdr server reload-config`.
