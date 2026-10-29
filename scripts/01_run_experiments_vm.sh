#!/usr/bin/env bash
# Run in the Ubuntu VM. Each case is isolated in its own process group.
set -uo pipefail

PROJECT_DIR="${1:-}"
if [[ -z "$PROJECT_DIR" || ! -d "$PROJECT_DIR" ]]; then
    echo "Usage: $0 <mounted-project-directory>" >&2
    exit 2
fi

EVIDENCE_DIR="$PROJECT_DIR/evidence"
APP="$PROJECT_DIR/bin/agent-leak-app-x86"
MONITOR="$PROJECT_DIR/bin/monitor.sh"
AGENT_HOME="$HOME/agent-app"

if [[ "$(id -u)" -eq 0 ]]; then
    echo "ERROR: run as a regular user; the application rejects root." >&2
    exit 1
fi
for required in "$APP" "$MONITOR"; do
    [[ -x "$required" ]] || { echo "ERROR: executable not found: $required" >&2; exit 1; }
done
for command in setsid ps top awk; do
    command -v "$command" >/dev/null 2>&1 || { echo "ERROR: required command not found: $command" >&2; exit 1; }
done

mkdir -p "$EVIDENCE_DIR" "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" "$AGENT_HOME/logs"
printf '%s\n' 'agent_api_key_test' > "$AGENT_HOME/api_keys/secret.key"
export AGENT_HOME AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
export AGENT_LOG_DIR="$AGENT_HOME/logs"

group_alive() {
    local pgid="$1"
    ps -eo pgid=,stat= 2>/dev/null | awk -v target="$pgid" '$1 == target && $2 !~ /^Z/ { live=1 } END { exit !live }'
}

group_pids() {
    local pgid="$1"
    ps -eo pid=,pgid= 2>/dev/null | awk -v target="$pgid" '$2 == target { printf "%s%s", sep, $1; sep="," }'
}

group_snapshot() {
    local pgid="$1"
    ps -eo pid=,ppid=,pgid=,%cpu=,%mem=,rss=,vsz=,stat=,etime=,args= 2>/dev/null \
        | awk -v target="$pgid" '$3 == target'
}

capture_processes() {
    local name="$1" pgid="$2" pids pid
    {
        echo "PID PPID PGID %CPU %MEM RSS_KB VSZ_KB STAT ELAPSED COMMAND"
        group_snapshot "$pgid"
    } > "$EVIDENCE_DIR/${name}_ps.log" 2>&1 || true
    if [[ "$name" == exp_deadlock_* ]]; then
        {
            for pid in $(group_pids "$pgid" | tr ',' ' '); do
                ps -L -p "$pid" -o pid,tid,ppid,%cpu,%mem,stat,wchan:32 2>&1
            done
        } > "$EVIDENCE_DIR/${name}_threads.log"
    fi
}

run_case() {
    local name="$1" memory="$2" cpu="$3" threads="$4" seconds="$5" interval="${6:-1}"
    local pid pgid monitor_pid top_pid started elapsed leader_status
    echo "=== $name: MEMORY_LIMIT=$memory CPU_MAX_OCCUPY=$cpu MULTI_THREAD_ENABLE=$threads (${seconds}s observation) ==="
    MEMORY_LIMIT="$memory" CPU_MAX_OCCUPY="$cpu" MULTI_THREAD_ENABLE="$threads" \
        setsid "$APP" > "$EVIDENCE_DIR/${name}.log" 2>&1 &
    pid=$!
    for _ in {1..5}; do
        pgid="$(ps -p "$pid" -o pgid= 2>/dev/null | tr -d ' ')"
        [[ -n "$pgid" ]] && break
        sleep 1
    done
    if [[ -z "${pgid:-}" ]]; then
        echo "ERROR: could not determine process group for PID $pid" >&2
        wait "$pid" 2>/dev/null || true
        return 1
    fi

    {
        echo "PID=$pid"
        echo "PGID=$pgid"
        echo "MEMORY_LIMIT=$memory"
        echo "CPU_MAX_OCCUPY=$cpu"
        echo "MULTI_THREAD_ENABLE=$threads"
    } > "$EVIDENCE_DIR/${name}.meta"
    "$MONITOR" --pgroup "$pgid" "$interval" > "$EVIDENCE_DIR/${name}_monitor.csv" 2>&1 &
    monitor_pid=$!
    top -H -b -d "$interval" > "$EVIDENCE_DIR/${name}_top.log" 2>&1 &
    top_pid=$!
    started="$(date +%s)"
    elapsed=0
    while ((elapsed < seconds)) && group_alive "$pgid"; do
        sleep 1
        elapsed="$(( $(date +%s) - started ))"
    done

    if group_alive "$pgid"; then
        capture_processes "$name" "$pgid"
        echo "HARNESS_STOPPED_AFTER=${seconds}s" >> "$EVIDENCE_DIR/${name}.meta"
        kill -TERM -- "-$pgid" 2>/dev/null || true
        for _ in {1..10}; do
            group_alive "$pgid" || break
            sleep 1
        done
        if group_alive "$pgid"; then
            kill -KILL -- "-$pgid" 2>/dev/null || true
        fi
    else
        echo "APP_EXITED_AFTER=${elapsed}s" >> "$EVIDENCE_DIR/${name}.meta"
    fi
    wait "$pid" 2>/dev/null
    leader_status="$?"
    if [[ -f "$EVIDENCE_DIR/${name}.meta" ]] && grep -q '^HARNESS_STOPPED_AFTER=' "$EVIDENCE_DIR/${name}.meta"; then
        echo "HARNESS_LEADER_EXIT_STATUS=$leader_status" >> "$EVIDENCE_DIR/${name}.meta"
    else
        echo "APP_LEADER_EXIT_STATUS=$leader_status" >> "$EVIDENCE_DIR/${name}.meta"
    fi
    kill "$top_pid" 2>/dev/null || true
    wait "$top_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
}

# Each case uses one changed control variable; the collector records every
# process in the case's isolated process group, including children.
run_case exp_oom_before 50 10 false 40
run_case exp_oom_after 512 10 false 40
run_case exp_cpu_before 512 10 false 60 0.2
run_case exp_cpu_after 512 90 false 60 0.2
run_case exp_deadlock_before 512 10 true 20
run_case exp_deadlock_after 512 10 false 20

echo "Experiment run complete. Evidence directory: $EVIDENCE_DIR"
