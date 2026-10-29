#!/usr/bin/env bash
# Run in the Ubuntu VM. Each case keeps its own logs and process monitor output.
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

mkdir -p "$EVIDENCE_DIR" "$AGENT_HOME/upload_files" "$AGENT_HOME/api_keys" "$AGENT_HOME/logs"
printf '%s\n' 'agent_api_key_test' > "$AGENT_HOME/api_keys/secret.key"
export AGENT_HOME AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
export AGENT_LOG_DIR="$AGENT_HOME/logs"

stop_case() {
    local pid="${1:-}"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        for _ in {1..10}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
}

run_case() {
    local name="$1" memory="$2" cpu="$3" threads="$4" seconds="$5"
    local pid monitor_pid
    echo "=== $name: MEMORY_LIMIT=$memory CPU_MAX_OCCUPY=$cpu MULTI_THREAD_ENABLE=$threads (${seconds}s observation) ==="
    MEMORY_LIMIT="$memory" CPU_MAX_OCCUPY="$cpu" MULTI_THREAD_ENABLE="$threads" \
        "$APP" > "$EVIDENCE_DIR/${name}.log" 2>&1 &
    pid=$!
    echo "PID=$pid" > "$EVIDENCE_DIR/${name}.meta"
    "$MONITOR" "$pid" 1 > "$EVIDENCE_DIR/${name}_monitor.csv" 2>&1 &
    monitor_pid=$!
    sleep "$seconds"
    if kill -0 "$pid" 2>/dev/null; then
        ps -p "$pid" -o pid,ppid,%cpu,%mem,rss,vsz,stat,etime,args \
            > "$EVIDENCE_DIR/${name}_ps.log" 2>&1 || true
        if [[ "$name" == exp_deadlock_* ]]; then
            ps -L -p "$pid" -o pid,tid,%cpu,%mem,stat,wchan:32 \
                > "$EVIDENCE_DIR/${name}_threads.log" 2>&1 || true
        fi
        echo "HARNESS_STOPPED_AFTER=${seconds}s" >> "$EVIDENCE_DIR/${name}.meta"
    else
        echo "PROCESS_EXITED_WITHIN=${seconds}s" >> "$EVIDENCE_DIR/${name}.meta"
    fi
    stop_case "$pid"
    wait "$monitor_pid" 2>/dev/null || true
}

# MemoryGuard should end the low-limit run by itself. The higher-limit run is
# deliberately bounded; metadata records whether the harness stopped it.
run_case exp_oom_before 50 100 false 40
run_case exp_oom_after 512 100 false 40

# Disable concurrency here so the lock demonstration cannot preempt CPU work.
run_case exp_cpu_before 512 10 false 60
run_case exp_cpu_after 512 90 false 60

run_case exp_deadlock_before 512 100 true 20
run_case exp_deadlock_after 512 100 false 20

echo "Experiment run complete. Evidence directory: $EVIDENCE_DIR"
