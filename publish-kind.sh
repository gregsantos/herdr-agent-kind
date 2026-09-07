#!/usr/bin/env bash
# Publishes each pane's detected agent kind as the $agent_kind sidebar token.
#
# Herdr's built-in `agent` token renders the Herdr agent name whenever one is
# set and falls back to the kind only when none is, so a named agent hides
# whether it is claude or codex. This publishes the kind as a separate token
# that never competes with the name.
#
# Pane metadata is runtime-only and is not written to session.json, so the
# [[startup]] hook is what restores tokens after a Herdr server restart.
set -euo pipefail

herdr_binary="${HERDR_BIN_PATH:-herdr}"
metadata_source="agent-kind"

# Diagnostics are opt-in: this runs on every agent detection, and an always-on
# log would mean constant file churn (and a read-rewrite race between
# concurrent detections) to serve a case that only matters when debugging.
#   touch "$HERDR_PLUGIN_CONFIG_DIR/debug"   # or export HERDR_AGENT_KIND_DEBUG=1
debug_log="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}/agent-kind.log"
debug_enabled=false
if [ "${HERDR_AGENT_KIND_DEBUG:-}" = "1" ] ||
    { [ -n "${HERDR_PLUGIN_CONFIG_DIR:-}" ] && [ -e "${HERDR_PLUGIN_CONFIG_DIR}/debug" ]; }; then
    debug_enabled=true
fi

log_debug() {
    [ "$debug_enabled" = true ] || return 0
    mkdir -p "$(dirname "$debug_log")" 2>/dev/null || return 0
    printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$debug_log" 2>/dev/null || true
}

publish_kind() {
    local pane_id="$1" agent_kind="$2"
    [ -n "$pane_id" ] && [ -n "$agent_kind" ] || return 0
    if "$herdr_binary" pane report-metadata "$pane_id" \
        --source "$metadata_source" --token "agent_kind=$agent_kind" >/dev/null 2>&1; then
        log_debug "published pane=$pane_id kind=$agent_kind"
    else
        # Never fail the hook: a plugin that exits non-zero is noise in Herdr's
        # log for something the user cannot act on mid-session.
        log_debug "FAILED pane=$pane_id kind=$agent_kind"
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
for agent in agents:
    pane_id, kind = agent.get("pane_id"), agent.get("agent")
    if pane_id and kind:
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
def find_pane(node):
    if isinstance(node, dict):
        pane_id, kind = node.get("pane_id"), node.get("agent")
        if pane_id and isinstance(kind, str):
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
    local pane_id agent_kind
    while read -r pane_id agent_kind; do
        publish_kind "$pane_id" "$agent_kind"
    done < <(all_detected_agents)
}

log_debug "event=${HERDR_PLUGIN_EVENT:-?} json=${HERDR_PLUGIN_EVENT_JSON:-}"

# Startup and the `refresh` action both mean "reconcile everything": neither
# carries a single pane to act on.
if [ "${HERDR_PLUGIN_EVENT:-}" = "startup" ] || [ -n "${HERDR_PLUGIN_ACTION_ID:-}" ]; then
    publish_all_detected
    exit 0
fi

event_pane_id=""
event_agent_kind=""
read -r event_pane_id event_agent_kind < <(event_pane) || true

if [ -n "$event_pane_id" ]; then
    publish_kind "$event_pane_id" "$event_agent_kind"
else
    # Fall back to a full sweep if the event payload was not shaped as expected.
    log_debug "no pane in event payload; sweeping all detected agents"
    publish_all_detected
fi
