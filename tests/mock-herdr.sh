#!/bin/sh
# Stand-in for the real `herdr` binary, wired in through HERDR_BIN_PATH.
#
# It records every invocation so a test can assert on exactly what the plugin
# asked Herdr to do, and it serves canned `agent list` JSON so the parsing can
# be exercised against payload shapes we cannot produce on demand from a live
# server -- which is the whole point, since those shapes come from a Herdr
# version we do not control.
#
# Behaviour is driven entirely by environment variables set by tests/run.sh:
#   MOCK_HERDR_CALLS       file to append one line per invocation to
#   MOCK_AGENT_LIST_JSON   file whose contents `agent list` prints
#   MOCK_AGENT_LIST_EXIT   exit status for `agent list`            (default 0)
#   MOCK_REPORT_EXIT       exit status for `pane report-metadata`  (default 0)
set -eu

if [ -n "${MOCK_HERDR_CALLS:-}" ]; then
    printf '%s\n' "$*" >>"$MOCK_HERDR_CALLS"
fi

case "${1:-}${2:+ $2}" in
"agent list")
    # A failing herdr writes a diagnostic to stderr and nothing parseable to
    # stdout, so serve the canned payload only on success.
    if [ "${MOCK_AGENT_LIST_EXIT:-0}" != "0" ]; then
        echo "mock-herdr: agent list failed" >&2
        exit "${MOCK_AGENT_LIST_EXIT}"
    fi
    if [ -n "${MOCK_AGENT_LIST_JSON:-}" ] && [ -f "${MOCK_AGENT_LIST_JSON}" ]; then
        cat "$MOCK_AGENT_LIST_JSON"
    fi
    ;;
"pane report-metadata")
    exit "${MOCK_REPORT_EXIT:-0}"
    ;;
esac

exit 0
