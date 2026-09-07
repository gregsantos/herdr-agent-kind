#!/usr/bin/env bash
# Publishes each pane's detected agent kind as the $kind sidebar token.
#
# Herdr's built-in `agent` token renders the Herdr agent name whenever one is
# set and falls back to the kind only when none is, so a named agent hides
# whether it is claude or codex. This publishes the kind as a separate token
# that never competes with the name.
set -euo pipefail

herdr_binary="${HERDR_BIN_PATH:-herdr}"
metadata_source="agent-kind"
debug_log="${HERDR_PLUGIN_STATE_DIR:-/tmp}/events.log"

log_event() {
    mkdir -p "$(dirname "$debug_log")" 2>/dev/null || return 0
    printf '%s event=%s json=%s\n' "$(date -u +%FT%TZ)" \
        "${HERDR_PLUGIN_EVENT:-?}" "${HERDR_PLUGIN_EVENT_JSON:-}" >>"$debug_log" 2>/dev/null || true
    if [ -f "$debug_log" ]; then
        tail -n 50 "$debug_log" >"$debug_log.trimmed" 2>/dev/null && mv "$debug_log.trimmed" "$debug_log" || true
    fi
}

publish_kind() {
    local pane_id="$1" agent_kind="$2"
    [ -n "$pane_id" ] && [ -n "$agent_kind" ] || return 0
    "$herdr_binary" pane report-metadata "$pane_id" \
        --source "$metadata_source" --token "kind=$agent_kind" >/dev/null 2>&1 || true
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
# survives the payload being wrapped in an envelope.
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

log_event

if [ "${HERDR_PLUGIN_EVENT:-}" = "startup" ]; then
    while read -r pane_id agent_kind; do
        publish_kind "$pane_id" "$agent_kind"
    done < <(all_detected_agents)
    exit 0
fi

read -r pane_id agent_kind < <(event_pane) || true
if [ -n "${pane_id:-}" ]; then
    publish_kind "$pane_id" "$agent_kind"
else
    # Fall back to a full sweep if the event payload was not shaped as expected.
    while read -r pane_id agent_kind; do
        publish_kind "$pane_id" "$agent_kind"
    done < <(all_detected_agents)
fi
