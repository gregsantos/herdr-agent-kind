#!/bin/sh
# Test suite for publish-kind.sh. Run it directly from anywhere:
#
#   ./tests/run.sh
#   TEST_SHELL=bash ./tests/run.sh      # or dash, or zsh
#
# The plugin's real risk surface is the shape of the JSON it parses: the output
# of `herdr agent list` and the pane.agent_detected event payload. Both arrive
# from a Herdr version we do not control, so each case below pins one shape and
# asserts on the exact `pane report-metadata` calls it produces. The Herdr
# binary itself is replaced by tests/mock-herdr.sh through HERDR_BIN_PATH, so
# nothing here touches a running Herdr server.
#
# Deliberately -u without -e: assertions are chained with &&, and -e applies
# to the last command of an AND-OR list, so the first failure would abort the
# run before the summary printed instead of reporting every failing case.
set -u

tests_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "$tests_dir/.." && pwd)"
mock_herdr="$tests_dir/mock-herdr.sh"
script_under_test="$plugin_root/publish-kind.sh"
manifest="$plugin_root/herdr-plugin.toml"
test_shell="${TEST_SHELL:-/bin/sh}"

tests_run=0
tests_failed=0
current_case=""
case_dir=""
plugin_exit=0
plugin_stderr=""
work_root=""

cleanup() {
    [ -n "$work_root" ] && rm -rf "$work_root"
    return 0
}
trap cleanup EXIT
work_root="$(mktemp -d "${TMPDIR:-/tmp}/agent-kind-tests.XXXXXX")" || exit 1
[ -d "$work_root" ] || { echo "could not create a work directory" >&2; exit 1; }

# --- harness -----------------------------------------------------------------

# Fresh case directory and a clean environment. A case overrides a default by
# assigning after this returns; everything is already exported.
begin_case() {
    current_case="$1"
    tests_run=$((tests_run + 1))
    case_dir="$work_root/case-$tests_run"
    mkdir -p "$case_dir/config" "$case_dir/state" "$case_dir/empty-bin"
    : >"$case_dir/calls"

    MOCK_HERDR_CALLS="$case_dir/calls"
    MOCK_AGENT_LIST_JSON=""
    MOCK_AGENT_LIST_EXIT=0
    MOCK_REPORT_EXIT=0
    HERDR_BIN_PATH="$mock_herdr"
    HERDR_PLUGIN_CONFIG_DIR="$case_dir/config"
    HERDR_PLUGIN_STATE_DIR="$case_dir/state"
    HERDR_PLUGIN_EVENT=""
    HERDR_PLUGIN_EVENT_JSON=""
    HERDR_PLUGIN_ACTION_ID=""
    HERDR_AGENT_KIND_DEBUG=""
    export MOCK_HERDR_CALLS MOCK_AGENT_LIST_JSON MOCK_AGENT_LIST_EXIT \
        MOCK_REPORT_EXIT HERDR_BIN_PATH HERDR_PLUGIN_CONFIG_DIR \
        HERDR_PLUGIN_STATE_DIR HERDR_PLUGIN_EVENT HERDR_PLUGIN_EVENT_JSON \
        HERDR_PLUGIN_ACTION_ID HERDR_AGENT_KIND_DEBUG
    plugin_exit=0
    plugin_stderr=""
}

# Canned `herdr agent list` output for this case.
given_agent_list() {
    MOCK_AGENT_LIST_JSON="$case_dir/agent-list.json"
    cat >"$MOCK_AGENT_LIST_JSON"
}

# Two agents of different kinds -- the common fixture for sweep assertions.
given_two_agents() {
    given_agent_list <<'JSON'
{"id":"cli:agent:list","result":{"agents":[
  {"agent":"claude","agent_status":"working","pane_id":"w1:p1","workspace_id":"w1"},
  {"agent":"codex","agent_status":"idle","pane_id":"w1:p2","workspace_id":"w1"}
],"type":"agent_list"}}
JSON
}

run_plugin() {
    plugin_stderr="$case_dir/stderr"
    plugin_exit=0
    ( cd "${1:-$plugin_root}" && "$test_shell" "${2:-$script_under_test}" ) \
        >"$case_dir/stdout" 2>"$plugin_stderr" || plugin_exit=$?
}

fail() {
    tests_failed=$((tests_failed + 1))
    printf 'FAIL %s\n' "$current_case"
    printf '%s\n' "$1" | sed 's/^/     /'
    if [ -n "$plugin_stderr" ] && [ -s "$plugin_stderr" ]; then
        sed 's/^/     stderr: /' "$plugin_stderr"
    fi
}

pass() {
    printf 'ok   %s\n' "$current_case"
}

assert_exit() {
    if [ "$plugin_exit" != "$1" ]; then
        fail "expected exit $1, got $plugin_exit"
        return 1
    fi
}

# Every report-metadata call as a sorted "pane=<id> kind=<kind>" line.
observed_publishes() {
    sed -n \
        's/^pane report-metadata \([^ ]*\) --source agent-kind --token agent_kind=\(.*\)$/pane=\1 kind=\2/p' \
        "$case_dir/calls" | sort
}

# Asserts the complete set of publishes, so an extra call fails too.
assert_publishes() {
    expected="$(printf '%s\n' "$@" | sed '/^$/d' | sort)"
    actual="$(observed_publishes)"
    if [ "$expected" != "$actual" ]; then
        fail "publishes did not match
  expected: [$(printf '%s' "$expected" | tr '\n' ';')]
  actual:   [$(printf '%s' "$actual" | tr '\n' ';')]"
        return 1
    fi
}

assert_stderr_contains() {
    if ! grep -q "$1" "$plugin_stderr" 2>/dev/null; then
        fail "expected stderr to mention '$1'"
        return 1
    fi
}

debug_log="agent-kind.log"

assert_debug_log_exists() {
    if [ ! -s "$case_dir/state/$debug_log" ]; then
        fail "expected diagnostics at state/$debug_log"
        return 1
    fi
}

assert_no_debug_log() {
    if [ -e "$case_dir/state/$debug_log" ]; then
        fail "expected no diagnostics, found state/$debug_log"
        return 1
    fi
}

# --- dispatch: what each trigger means ---------------------------------------

begin_case "startup sweeps every detected agent"
HERDR_PLUGIN_EVENT=startup
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

begin_case "the refresh action sweeps every detected agent"
HERDR_PLUGIN_ACTION_ID=refresh
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

begin_case "agent_detected publishes only the event's pane, never a sweep"
HERDR_PLUGIN_EVENT=pane.agent_detected
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p9","agent":"codex"}'
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p9 kind=codex" && pass

# --- dispatch: event payload shapes -----------------------------------------

begin_case "the pane is found inside a notification envelope"
HERDR_PLUGIN_EVENT=pane.agent_detected
HERDR_PLUGIN_EVENT_JSON='{"type":"pane.agent_detected","params":{"event":{"workspace_id":"w1","pane_id":"w1:p3","agent":"claude"}}}'
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p3 kind=claude" && pass

# agent_session carries "agent" with no pane_id and sorts before the real pane
# object, so a walk that matched on "agent" alone would publish the wrong kind
# against no pane at all. Requiring both keys is what prevents that.
begin_case "agent_session is skipped in favour of the object carrying both keys"
HERDR_PLUGIN_EVENT=pane.agent_detected
HERDR_PLUGIN_EVENT_JSON='{"result":{"agent_session":{"agent":"claude","kind":"id","value":"abc"},"pane":{"pane_id":"w1:p4","agent":"codex"}}}'
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p4 kind=codex" && pass

begin_case "a payload with a pane but no kind falls back to a sweep"
HERDR_PLUGIN_EVENT=pane.agent_detected
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p5"}'
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

begin_case "a malformed payload falls back to a sweep"
HERDR_PLUGIN_EVENT=pane.agent_detected
HERDR_PLUGIN_EVENT_JSON='this is not json'
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

begin_case "an empty payload falls back to a sweep"
HERDR_PLUGIN_EVENT=pane.agent_detected
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

begin_case "a non-string kind is rejected rather than published"
HERDR_PLUGIN_EVENT=pane.agent_detected
HERDR_PLUGIN_EVENT_JSON='{"pane_id":"w1:p6","agent":{"nested":"object"}}'
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

# --- agent list shapes -------------------------------------------------------

begin_case "agents missing a pane or a kind are skipped, not published blank"
HERDR_PLUGIN_EVENT=startup
given_agent_list <<'JSON'
{"id":"cli:agent:list","result":{"agents":[
  {"agent":"claude","pane_id":"w1:p1"},
  {"agent":"claude"},
  {"pane_id":"w1:p7"},
  {}
],"type":"agent_list"}}
JSON
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" && pass

begin_case "an unparseable agent list publishes nothing and still exits 0"
HERDR_PLUGIN_EVENT=startup
given_agent_list <<'JSON'
<html>not json</html>
JSON
run_plugin
assert_exit 0 && assert_publishes && pass

begin_case "an agent list without the expected keys publishes nothing"
HERDR_PLUGIN_EVENT=startup
given_agent_list <<'JSON'
{"id":"cli:agent:list","result":{"type":"agent_list"}}
JSON
run_plugin
assert_exit 0 && assert_publishes && pass

begin_case "a failing agent list command publishes nothing and still exits 0"
HERDR_PLUGIN_EVENT=startup
MOCK_AGENT_LIST_EXIT=1
given_two_agents
run_plugin
assert_exit 0 && assert_publishes && pass

# --- failure handling --------------------------------------------------------

# A publish can fail for reasons the user cannot act on mid-session, so the hook
# swallows it. Losing that would make every transient failure a red plugin log.
begin_case "a failed publish is attempted but does not fail the hook"
HERDR_PLUGIN_EVENT=startup
MOCK_REPORT_EXIT=1
given_two_agents
run_plugin
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

# The opposite policy: without python3 nothing can ever be published, the user
# can fix it, and exiting 0 would be indistinguishable from "no agents".
begin_case "missing python3 exits non-zero with a diagnosable message"
HERDR_PLUGIN_EVENT=startup
given_two_agents
plugin_stderr="$case_dir/stderr"
plugin_exit=0
( cd "$plugin_root" && PATH="$case_dir/empty-bin" "$test_shell" "$script_under_test" ) \
    >"$case_dir/stdout" 2>"$plugin_stderr" || plugin_exit=$?
assert_exit 1 && assert_stderr_contains "python3 not found" && assert_publishes && pass

# --- diagnostics -------------------------------------------------------------

begin_case "diagnostics stay off by default"
HERDR_PLUGIN_EVENT=startup
given_two_agents
run_plugin
assert_exit 0 && assert_no_debug_log && pass

begin_case "the config-dir debug marker turns diagnostics on"
HERDR_PLUGIN_EVENT=startup
given_two_agents
touch "$case_dir/config/debug"
run_plugin
assert_exit 0 && assert_debug_log_exists \
    && { grep -q 'published pane=w1:p1 kind=claude' "$case_dir/state/$debug_log" \
         || fail "expected a published line in the log"; } && pass

begin_case "HERDR_AGENT_KIND_DEBUG=1 turns diagnostics on"
HERDR_PLUGIN_EVENT=startup
HERDR_AGENT_KIND_DEBUG=1
given_two_agents
run_plugin
assert_exit 0 && assert_debug_log_exists && pass

begin_case "a failed publish is recorded in the log"
HERDR_PLUGIN_EVENT=startup
HERDR_AGENT_KIND_DEBUG=1
MOCK_REPORT_EXIT=1
given_two_agents
run_plugin
assert_exit 0 && { grep -q 'FAILED pane=w1:p1 kind=claude' "$case_dir/state/$debug_log" \
    || fail "expected a FAILED line in the log"; } && pass

# --- portability -------------------------------------------------------------

# The manifest invokes the script as ./publish-kind.sh relative to the plugin
# root, which Herdr sets as the working directory. A managed checkout can sit
# under a path containing a space, so that has to survive.
begin_case "the plugin runs from a working directory containing a space"
HERDR_PLUGIN_EVENT=startup
given_two_agents
mkdir -p "$case_dir/plugin dir"
cp "$script_under_test" "$case_dir/plugin dir/publish-kind.sh"
run_plugin "$case_dir/plugin dir" "./publish-kind.sh"
assert_exit 0 && assert_publishes "pane=w1:p1 kind=claude" "pane=w1:p2 kind=codex" && pass

# --- manifest ----------------------------------------------------------------

# Pins the regression the ./publish-kind.sh form fixed: wrapping a hook in
# `sh -c "${HERDR_PLUGIN_ROOT}/..."` leaves the path unquoted, so a plugin root
# containing a space fails at exit 127 before the script ever runs.
begin_case "no manifest hook wraps the script in an unquoted shell expansion"
if grep -q 'HERDR_PLUGIN_ROOT' "$manifest"; then
    fail "a hook command interpolates HERDR_PLUGIN_ROOT; invoke ./publish-kind.sh instead"
else
    pass
fi

begin_case "the manifest declares every field Herdr requires"
if ! python3 - "$manifest" <<'PY'
import pathlib, sys
try:
    import tomllib
except ModuleNotFoundError:
    print("skipped: tomllib needs python 3.11+", file=sys.stderr)
    sys.exit(0)

manifest = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
problems = []
for field in ("id", "name", "version", "min_herdr_version"):
    if not manifest.get(field):
        problems.append(f"missing required field {field}")
for section in ("startup", "events", "actions"):
    for index, entry in enumerate(manifest.get(section, [])):
        command = entry.get("command")
        if not command:
            problems.append(f"{section}[{index}] has no command")
        elif command[0] != "./publish-kind.sh":
            problems.append(f"{section}[{index}] runs {command}, not ./publish-kind.sh")
if problems:
    print("; ".join(problems), file=sys.stderr)
    sys.exit(1)
PY
then
    fail "manifest validation failed"
else
    pass
fi

# --- summary -----------------------------------------------------------------

printf '\n%s: %d cases, %d failed (shell: %s)\n' \
    "$(basename "$0")" "$tests_run" "$tests_failed" "$test_shell"
[ "$tests_failed" -eq 0 ]
