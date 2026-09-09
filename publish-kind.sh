#!/bin/sh
# Publishes each pane's detected agent kind as the $agent_kind sidebar token.
#
# Herdr's built-in `agent` token renders the Herdr agent name whenever one is
# set and falls back to the kind only when none is, so a named agent hides
# whether it is claude or codex. This publishes the kind as a separate token
# that never competes with the name.
#
# Pane metadata is runtime-only and is not written to session.json, so the
# [[startup]] hook is what restores tokens after a Herdr server restart.
#
# POSIX sh on purpose: Herdr runs on Linux too, where bash is not guaranteed.
# A bash shebang fails before any check inside this script can report why.
set -eu

herdr_binary="${HERDR_BIN_PATH:-herdr}"
metadata_source="agent-kind"

# Diagnostics are opt-in: this runs on every agent detection, and an always-on
# log would mean constant file churn to serve a case that only matters when
# debugging.
#   touch "$HERDR_PLUGIN_CONFIG_DIR/debug"   # or export HERDR_AGENT_KIND_DEBUG=1
#
# The log records every event payload, which is the user's pane layout, so it
# goes only where Herdr says plugin state belongs. Herdr always hands hooks a
# state directory; a run without one is a manual run from somewhere else, and
# the only alternative would be a shared temp directory under a predictable
# name. Diagnostics stay off in that case rather than write there.
debug_log="${HERDR_PLUGIN_STATE_DIR:+${HERDR_PLUGIN_STATE_DIR}/agent-kind.log}"
debug_enabled=false
if [ -n "$debug_log" ]; then
    if [ "${HERDR_AGENT_KIND_DEBUG:-}" = "1" ]; then
        debug_enabled=true
    elif [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -e "${HERDR_PLUGIN_CONFIG_DIR}/debug" ]; then
        debug_enabled=true
    fi
fi

log_debug() {
    [ "$debug_enabled" = true ] || return 0
    # The log is the only file this script creates; it is owner-only. The umask
    # is set inside a subshell so the Herdr commands this script runs do not
    # inherit it.
    (
        umask 077
        mkdir -p "$(dirname "$debug_log")" 2>/dev/null || exit 0
        printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$debug_log" 2>/dev/null || true
    )
}

# Parsing Herdr's JSON is the only thing this needs beyond a shell. Fail loudly
# rather than exiting 0: without python3 every publish quietly does nothing,
# which in the plugin log is indistinguishable from "no agents to report".
# Unlike a failed publish, this is permanent and the user can fix it.
if ! command -v python3 >/dev/null 2>&1; then
    echo "herdr-agent-kind: python3 not found in PATH; cannot parse Herdr's JSON output" >&2
    log_debug "python3 not found in PATH"
    exit 1
fi

publish_kind() {
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 0
    # The pane id is a positional argument and Herdr's parser does not honour a
    # `--` separator, so a dash-leading id is offered to the option parser
    # first. Verified on 0.9.0: `--clear-title` and friends fall through to the
    # positional and return pane_not_found, but `-h` and `--help` short-circuit
    # to the help text and exit 0 -- which this script would log as a successful
    # publish that never happened. Real ids look like w<n>:p<alnum>; the pattern
    # below also tolerates _ . - so a future id shape stays publishable, and
    # drops anything else as malformed input rather than passing it on.
    case "$1" in
    -* | *[!A-Za-z0-9:_.-]*)
        log_debug "rejected malformed pane id: $1"
        return 0
        ;;
    esac
    # The parsers above already drop kinds carrying non-printable characters;
    # this is an ASCII backstop at the last point before the value leaves the
    # plugin, so a future parser change cannot quietly reopen it. [[:cntrl:]]
    # is locale-dependent beyond ASCII, which is why the parsers do the real
    # check.
    case "$2" in
    *[[:cntrl:]]*)
        log_debug "rejected kind with control characters for pane=$1"
        return 0
        ;;
    esac
    if "$herdr_binary" pane report-metadata "$1" \
        --source "$metadata_source" --token "agent_kind=$2" >/dev/null 2>&1; then
        log_debug "published pane=$1 kind=$2"
    else
        # Never fail the hook for this: a publish can fail for reasons the user
        # cannot act on mid-session.
        log_debug "FAILED pane=$1 kind=$2"
    fi
}

# Every pane currently hosting a detected agent, as "pane_id kind" lines.
all_detected_agents() {
    "$herdr_binary" agent list 2>/dev/null | python3 -c '
import json, sys
try:
    agents = json.load(sys.stdin)["result"]["agents"]
except Exception:
    sys.exit(0)
# Both values must be non-empty strings, exactly as in the event path: a kind
# arriving as an object would otherwise be published as its Python repr. A pane
# id containing whitespace is rejected because this protocol is line-based and
# whitespace-separated, so the read loop below would truncate the id at its
# first space and swallow the rest into the kind. A kind may contain spaces; it
# is the last field, so it survives intact. A kind carrying any non-printable
# character is rejected: a newline would split it across two lines here, and a
# carriage return, escape sequence or Unicode control would reach the sidebar
# verbatim. str.isprintable covers all of those, ASCII and beyond, and still
# allows a plain space. The canonical ids Herdr generates never contain one.
def has_control_character(value):
    return not value.isprintable()

for agent in agents:
    pane_id, kind = agent.get("pane_id"), agent.get("agent")
    if not isinstance(pane_id, str) or not isinstance(kind, str):
        continue
    if not pane_id or not kind:
        continue
    if any(character.isspace() for character in pane_id) or has_control_character(kind):
        continue
    print(pane_id, kind)
'
}

# The pane carried by this event, as a single "pane_id kind" line.
event_pane() {
    printf '%s' "${HERDR_PLUGIN_EVENT_JSON:-}" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    payload = json.loads(raw)
except Exception:
    sys.exit(0)

# Locate any nested object carrying both a pane id and an agent kind, so this
# survives the payload being wrapped in an envelope. Requiring BOTH keys is what
# keeps it off sibling objects such as agent_session, which carries "agent" alone.
# The value guards mirror the sweep path: no whitespace in the pane id, no
# non-printable characters in the kind.
def has_control_character(value):
    return not value.isprintable()

def find_pane(node):
    if isinstance(node, dict):
        pane_id, kind = node.get("pane_id"), node.get("agent")
        if (
            isinstance(pane_id, str)
            and isinstance(kind, str)
            and pane_id
            and kind
            and not any(character.isspace() for character in pane_id)
            and not has_control_character(kind)
        ):
            return pane_id, kind
        for value in node.values():
            found = find_pane(value)
            if found:
                return found
    elif isinstance(node, list):
        for value in node:
            found = find_pane(value)
            if found:
                return found
    return None

found = find_pane(payload)
if found:
    print(found[0], found[1])
'
}

publish_all_detected() {
    all_detected_agents | while read -r pane_id agent_kind; do
        publish_kind "$pane_id" "$agent_kind"
    done
}

log_debug "event=${HERDR_PLUGIN_EVENT:-?} json=${HERDR_PLUGIN_EVENT_JSON:-}"

# Startup and the `refresh` action both mean "reconcile everything": neither
# carries a single pane to act on.
if [ "${HERDR_PLUGIN_EVENT:-}" = "startup" ] || [ -n "${HERDR_PLUGIN_ACTION_ID:-}" ]; then
    publish_all_detected
    exit 0
fi

# Split "pane_id kind" with parameter expansion rather than word splitting: zsh
# does not word-split unquoted expansions, so `set -- $event_output` would pass
# the whole line as the pane id there and silently publish nothing. With no
# space to split on, pane_id comes back equal to the whole line.
event_output="$(event_pane || true)"
event_pane_id="${event_output%% *}"
event_agent_kind="${event_output#* }"

if [ -n "$event_output" ] && [ "$event_pane_id" != "$event_output" ]; then
    publish_kind "$event_pane_id" "$event_agent_kind"
else
    # Fall back to a full sweep if the event payload was not shaped as expected.
    log_debug "no pane in event payload; sweeping all detected agents"
    publish_all_detected
fi
