#!/usr/bin/env bash
# Sample one PID or every process in an isolated process group on Linux.
set -u

MODE=pid
TARGET=""
INTERVAL=1
if [[ "${1:-}" == "--pgroup" || "${1:-}" == "-g" ]]; then
    MODE=pgroup
    TARGET="${2:-}"
    INTERVAL="${3:-1}"
else
    TARGET="${1:-}"
    INTERVAL="${2:-1}"
fi

usage() {
    echo "Usage: $0 <pid> [interval-seconds] | $0 --pgroup <pgid> [interval-seconds]" >&2
    exit 2
}

[[ "$TARGET" =~ ^[0-9]+$ ]] || usage
[[ "$INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
[[ "$INTERVAL" != "0" && "$INTERVAL" != "0.0" ]] || usage
[[ -r /proc/stat ]] || { echo "ERROR: this monitor requires Linux /proc" >&2; exit 1; }

CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)"
declare -A PREV_TICKS=()
PREV_TIME=""
echo "timestamp,pgid,pid,ppid,cpu_percent_interval,rss_kb,vsz_kb,state"

while :; do
    if [[ "$MODE" == pgroup ]]; then
        rows="$(ps -eo pid=,ppid=,pgid=,rss=,vsz=,stat= 2>/dev/null | awk -v target="$TARGET" '$3 == target')"
    else
        rows="$(ps -p "$TARGET" -o pid=,ppid=,pgid=,rss=,vsz=,stat= 2>/dev/null || true)"
    fi
    [[ -n "$rows" ]] || break

    now="$(date +%s.%N)"
    live_count=0
    while read -r pid ppid pgid rss vsz state; do
        [[ -n "${pid:-}" ]] || continue
        if [[ "$MODE" == pgroup && "$pgid" != "$TARGET" ]]; then
            continue
        fi
        if [[ "$state" != Z* ]]; then
            ((live_count += 1))
        fi

        cpu="0.0"
        stat_file="/proc/$pid/stat"
        if [[ -r "$stat_file" ]]; then
            IFS= read -r stat_line < "$stat_file" || true
            stat_fields="${stat_line##*) }"
            read -r -a fields <<< "$stat_fields"
            if ((${#fields[@]} > 12)); then
                ticks=$((fields[11] + fields[12]))
                if [[ -n "${PREV_TICKS[$pid]:-}" && -n "$PREV_TIME" ]]; then
                    cpu="$(awk -v cur="$ticks" -v prev="${PREV_TICKS[$pid]}" -v hz="$CLK_TCK" -v start="$PREV_TIME" -v end="$now" 'BEGIN { elapsed=end-start; if (elapsed > 0) printf "%.1f", ((cur-prev)/hz/elapsed)*100; else printf "0.0" }')"
                fi
                PREV_TICKS[$pid]="$ticks"
            fi
        fi
        printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$pgid" "$pid" "$ppid" "$cpu" "$rss" "$vsz" "$state"
    done <<< "$rows"

    ((live_count > 0)) || break
    PREV_TIME="$now"
    sleep "$INTERVAL"
done

if [[ "$MODE" == pgroup ]]; then
    echo "PROCESS_GROUP_EXITED,pgid=$TARGET"
else
    echo "PROCESS_EXITED,pid=$TARGET"
fi
