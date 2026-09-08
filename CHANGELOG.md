# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions are
[semantic](https://semver.org/spec/v2.0.0.html).

Because the plugin's whole job is to publish one sidebar token, entries record
*why* a change was made — the token's shape and the failure policy are the parts
that affect anyone's config.

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

[0.5.1]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/gregsantos/herdr-agent-kind/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gregsantos/herdr-agent-kind/releases/tag/v0.1.0
