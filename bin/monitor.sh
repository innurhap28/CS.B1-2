#!/usr/bin/env bash

# Sample one Linux process until it exits. Output is CSV so it can be retained
# as experiment evidence or plotted later.
set -u

PID="${1:-}"
INTERVAL="${2:-1}"

usage() {
    echo "Usage: $0 <pid> [interval-seconds]" >&2
    exit 2
}

[[ "$PID" =~ ^[0-9]+$ ]] || usage
[[ "$INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
[[ "$INTERVAL" != "0" && "$INTERVAL" != "0.0" ]] || usage

if ! command -v ps >/dev/null 2>&1; then
    echo "ERROR: ps is required" >&2
    exit 1
fi

echo "timestamp,pid,cpu_percent,rss_kb,vsz_kb,state"
while :; do
    row="$(ps -p "$PID" -o %cpu=,rss=,vsz=,stat= 2>/dev/null || true)"
    [[ -n "$row" ]] || break

    read -r cpu rss vsz state <<< "$row"
    # A zombie has exited even though its parent has not reaped it yet.
    [[ "$state" == Z* ]] && break
    printf '%s,%s,%s,%s,%s,%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$PID" "$cpu" "$rss" "$vsz" "$state"
    sleep "$INTERVAL"
done

echo "PROCESS_EXITED,pid=$PID"
