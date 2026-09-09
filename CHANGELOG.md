# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions are
[semantic](https://semver.org/spec/v2.0.0.html).

Because the plugin's whole job is to publish one sidebar token, entries record
*why* a change was made — the token's shape and the failure policy are the parts
that affect anyone's config.

## [0.5.2] - 2026-09-09

### Fixed

- Malformed pane ids are rejected instead of being handed to Herdr. A pane id is
  a positional argument to `herdr pane report-metadata` and Herdr's parser does
  not honour a `--` separator, so a dash-leading id is offered to the option
  parser first. Verified on Herdr 0.9.0: `--clear-title` and its siblings fall
  through to the positional and return `pane_not_found`, but `-h` and `--help`
  short-circuit to the help text and exit 0, which this plugin then logged as a
  successful publish that never happened. Ids outside `[A-Za-z0-9:_.-]` are now
  dropped and logged. No effect on real ids, which Herdr generates.
- The agent-list sweep now requires `pane_id` and `agent` to be non-empty
  strings, matching the guard the event path already had. A kind arriving as an
  object was published as its Python repr (`{'kind': 'claude'}`) straight into
  the sidebar.
- Pane ids containing whitespace are dropped by both parsers. The helper protocol
  is line-based and whitespace-separated, so `while read` truncated such an id at
  its first space — `w1 p1` published against pane `w1` — and a newline split one
  agent across two output lines. A kind may still contain spaces; it is the last
  field and survives intact.
- README: the Limitations section claimed "the hook always exits 0", which
  contradicted Requirements, CONTRIBUTING and the script itself — a missing
  `python3` exits non-zero by design.
- README: the per-kind colour section now states that token `rules` require
  Herdr 0.9.0. The plugin floor is 0.8.2, where `rules` do not exist, so a
  0.8.2 user following that section could have had their layout rejected.
- `tests/run.sh` resolves a bare `TEST_SHELL` name to an absolute path. The
  documented `TEST_SHELL=bash ./tests/run.sh` failed one case: the missing-python3
  case empties `PATH`, so a bare shell name could no longer be resolved either
  and the subshell died with 127 before the plugin ran. CI passes absolute
  paths, so it could not catch this.

### Added

- Eight tests: option-shaped pane ids on the event and sweep paths, a
  metacharacter id, a whitespace-bearing id falling back to a sweep, space and
  tab in a pane id, a newline in a pane id, and a non-string kind in the agent
  list.

## [0.5.1] - 2026-09-07

### Fixed

- Manifest hooks invoke `./publish-kind.sh` directly instead of wrapping it in
  `sh -c "${HERDR_PLUGIN_ROOT}/publish-kind.sh"`. The expansion was unquoted, so
  a plugin root containing a space failed at exit 127 before the script ran —
  reproduced against a linked plugin, which is how local development hits it.
  Herdr already runs hook commands with the plugin directory as their working
  directory, so the shell wrapper was doing nothing the cwd did not.
- The event payload's `"pane_id kind"` line is split with parameter expansion
  rather than `set -- $event_output`. zsh does not word-split unquoted
  expansions, so under zsh the whole line became the pane id and every
  `pane.agent_detected` publish silently did nothing. Never reachable through
  Herdr, which honours the `#!/bin/sh` shebang, but the README claimed zsh was
  verified and now it genuinely is.

### Added

- A test suite at `tests/run.sh`, with `tests/mock-herdr.sh` standing in for the
  real binary through `HERDR_BIN_PATH`. It pins the JSON shapes the plugin
  parses — `herdr agent list` output and the `pane.agent_detected` payload —
  because both come from a Herdr version the plugin does not control. Run it
  directly; `TEST_SHELL` picks the shell.
- CI running shellcheck, manifest validation, and the suite across sh, dash,
  bash and zsh on Linux and macOS.

## [0.5.0] - 2026-09-07

### Changed

- Converted to POSIX `sh` and dropped the bash dependency. Herdr runs on Linux,
  where bash is not guaranteed, and a bash shebang fails before any check
  inside the script can report why.

## [0.4.1] - 2026-09-07

### Fixed

- A missing `python3` now exits non-zero with a message instead of exiting 0.
  Without it every publish quietly does nothing, which in the plugin log is
  indistinguishable from "no agents to report" — and unlike a failed publish it
  is permanent and the user can fix it.

## [0.4.0] - 2026-09-07

### Added

- A `refresh` action, so a fresh install can retrofit tokens onto agents that
  were already running without restarting the Herdr server. Pane metadata is
  runtime-only, so nothing else fills those in until an agent is next detected.
- Uninstall instructions, including clearing a token that outlives the plugin.

## [0.3.0] - 2026-09-07

### Changed

- **Breaking:** the token is now `$agent_kind`, renamed from `$kind`. Update
  `rows` under `[ui.sidebar.agents]` and run `herdr server reload-config`.

### Added

- The README states that installing alone changes nothing: the plugin publishes
  the value, and the config decides whether it renders.

## [0.2.1] - 2026-09-07

### Changed

- `min_herdr_version` set to 0.8.2, the oldest version actually verified. Custom
  tokens and `[[startup]]` hooks landed around 0.7.4-0.7.5, but the release that
  added the `pane.agent_detected` event is undocumented, so the floor reflects
  what was tested rather than what is likely.

## [0.2.0] - 2026-09-07

### Added

- Opt-in diagnostics, via a `debug` marker in the plugin config directory or
  `HERDR_AGENT_KIND_DEBUG=1`. Always-on logging would mean constant file churn
  to serve a case that only matters when debugging.
- Failed publishes are recorded rather than raised, so a transient failure does
  not turn the hook red.
- MIT licence.

## [0.1.0] - 2026-09-07

### Added

- Initial release: publishes each pane's detected agent kind as a sidebar token
  on `[[startup]]` and on `pane.agent_detected`, so a named agent no longer
  hides whether it is claude or codex.

[0.5.2]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gregsantos/herdr-agent-kind/releases/tag/v0.1.0
