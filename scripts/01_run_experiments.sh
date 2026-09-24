#!/bin/bash

# 프로젝트 및 VM 설정
VM_NAME="ubuntu-2404-dev"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# evidence 폴더 생성 (맥 호스트)
mkdir -p "$PROJECT_DIR/evidence"

# VM 내부에서 실행할 통합 준비 및 실험 스크립트 작성
cat << 'EOF' > /tmp/run_exp_inside_vm.sh
#!/bin/bash

# Boot Sequence 6단계를 한 번에 모두 통과시키기 위한 전체 환경 세팅
export AGENT_HOME=$HOME/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
export AGENT_LOG_DIR=$HOME/agent-app/logs

# 포트 자연 해제를 기다리는 함수 (프로세스 종료 + TCP TIME_WAIT 소켓 정리 대기)
cleanup_agent() {
    pkill -f agent-leak-app-x86 2>/dev/null || true
    # TCP 소켓이 커널에서 완전히 릴리즈되도록 10초간 대기
    sleep 10
}

# 1. 필수 디렉터리 일괄 생성
mkdir -p "$AGENT_HOME" "$AGENT_LOG_DIR" "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH"

# 2. 필수 파일 생성
echo "agent_api_key_test" > "$AGENT_KEY_PATH/secret.key"
touch "$AGENT_LOG_DIR/agent.log"

# 3. 초기 포트 정리
cleanup_agent

# 4. 바이너리 존재 확인 및 복사
if [ ! -f "$AGENT_HOME/agent-leak-app-x86" ]; then
    cp /mnt/mac/Users/innuendo3712/CS.B1-2/bin/agent-leak-app-x86 "$AGENT_HOME/"
    chmod +x "$AGENT_HOME/agent-leak-app-x86"
fi

# monitor.sh 생성
cat << 'MONITOR_EOF' > "$AGENT_HOME/monitor.sh"
#!/bin/bash

PID="$1"
INTERVAL="${2:-1}"

if [ -z "$PID" ]; then
    echo "Usage: $0 <PID> [interval]"
    exit 1
fi

echo "timestamp,pid,cpu_percent,rss_kb,vsz_kb"

while kill -0 "$PID" 2>/dev/null; do
    if ps -p "$PID" -o pid= > /dev/null 2>&1; then
        ps -p "$PID" -o pid=,pcpu=,rss=,vsz= | \
        awk -v pid="$PID" '{
            printf "%s,%s,%s,%s,%s\n",
                   strftime("%Y-%m-%d %H:%M:%S"),
                   pid,
                   $2,
                   $3,
                   $4
        }'
    fi

    sleep "$INTERVAL"
done

echo "PROCESS_EXITED,pid=$PID"
MONITOR_EOF

chmod +x "$AGENT_HOME/monitor.sh"

MAC_PROJECT_DIR="/mnt/mac/Users/innuendo3712/CS.B1-2"

# ----------------------------------------------------
# [실험 1] OOM Crash
# ----------------------------------------------------
echo "=== [1/3] OOM Crash 실험 진행 중... ==="
cleanup_agent

export MEMORY_LIMIT=50
export CPU_MAX_OCCUPY=100
export MULTI_THREAD_ENABLE=true

"$AGENT_HOME/agent-leak-app-x86" \
    > "$MAC_PROJECT_DIR/evidence/exp_oom_before.log" 2>&1 &
OOM_PID=$!
echo "OOM Before 실행 중..."
echo "PID: $OOM_PID"
"$AGENT_HOME/monitor.sh" "$OOM_PID" 1 \
    > "$MAC_PROJECT_DIR/evidence/exp_oom_before_monitor.csv" 2>&1 &
OOM_MONITOR_PID=$!
sleep 30
kill "$OOM_MONITOR_PID" 2>/dev/null || true
cleanup_agent

export MEMORY_LIMIT=512
"$AGENT_HOME/agent-leak-app-x86" \
    > "$MAC_PROJECT_DIR/evidence/exp_oom_after.log" 2>&1 &
OOM_AFTER_PID=$!
echo "OOM After 실행 중..."
echo "PID: $OOM_AFTER_PID"
"$AGENT_HOME/monitor.sh" "$OOM_AFTER_PID" 1 \
    > "$MAC_PROJECT_DIR/evidence/exp_oom_after_monitor.csv" 2>&1 &
OOM_AFTER_MONITOR_PID=$!
sleep 15
kill "$OOM_AFTER_MONITOR_PID" 2>/dev/null || true
cleanup_agent

# ----------------------------------------------------
# [실험 2] CPU Latency
# ----------------------------------------------------
echo "=== [2/3] CPU 과점유 실험 진행 중... ==="
cleanup_agent

export MEMORY_LIMIT=512
export CPU_MAX_OCCUPY=10
export MULTI_THREAD_ENABLE=true

"$AGENT_HOME/agent-leak-app-x86" \
    > "$MAC_PROJECT_DIR/evidence/exp_cpu_before.log" 2>&1 &
CPU_PID=$!
echo "CPU Before 실행 중..."
echo "PID: $CPU_PID"
"$AGENT_HOME/monitor.sh" "$CPU_PID" 1 \
    > "$MAC_PROJECT_DIR/evidence/exp_cpu_before_monitor.csv" 2>&1 &
CPU_MONITOR_PID=$!
sleep 20
kill "$CPU_MONITOR_PID" 2>/dev/null || true
cleanup_agent

export CPU_MAX_OCCUPY=90
"$AGENT_HOME/agent-leak-app-x86" \
    > "$MAC_PROJECT_DIR/evidence/exp_cpu_after.log" 2>&1 &
CPU_AFTER_PID=$!
echo "CPU After 실행 중..."
echo "PID: $CPU_AFTER_PID"
"$AGENT_HOME/monitor.sh" "$CPU_AFTER_PID" 1 \
    > "$MAC_PROJECT_DIR/evidence/exp_cpu_after_monitor.csv" 2>&1 &
CPU_AFTER_MONITOR_PID=$!
sleep 15
kill "$CPU_AFTER_MONITOR_PID" 2>/dev/null || true
cleanup_agent

# ----------------------------------------------------
# [실험 3] Deadlock
# ----------------------------------------------------
echo "=== [3/3] Deadlock 실험 진행 중... ==="
cleanup_agent

export MEMORY_LIMIT=512
export CPU_MAX_OCCUPY=100
export MULTI_THREAD_ENABLE=true

"$AGENT_HOME/agent-leak-app-x86" \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_before.log" 2>&1 &

DL_PID=$!

echo "Deadlock Before 실행 중..."
echo "PID: $DL_PID"

"$AGENT_HOME/monitor.sh" "$DL_PID" 1 \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_monitor.csv" 2>&1 &

DL_MONITOR_PID=$!

sleep 15

# 프로세스 존재 증거
ps -ef | grep agent-leak-app-x86 | grep -v grep \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_ps.log"

# 스레드별 CPU/MEM 상태
ps -L -p "$DL_PID" -o pid,tid,pcpu,pmem,stat,wchan:30 \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_threads.log"

kill "$DL_MONITOR_PID" 2>/dev/null || true

cleanup_agent

export MULTI_THREAD_ENABLE=false

"$AGENT_HOME/agent-leak-app-x86" \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_after.log" 2>&1 &

DL_AFTER_PID=$!

echo "Deadlock After 실행 중..."
echo "PID: $DL_AFTER_PID"

"$AGENT_HOME/monitor.sh" "$DL_AFTER_PID" 1 \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_after_monitor.csv" 2>&1 &

DL_AFTER_MONITOR_PID=$!

sleep 15

ps -ef | grep agent-leak-app-x86 | grep -v grep \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_after_ps.log"

ps -L -p "$DL_AFTER_PID" -o pid,tid,pcpu,pmem,stat,wchan:30 \
    > "$MAC_PROJECT_DIR/evidence/exp_deadlock_after_threads.log"

kill "$DL_AFTER_MONITOR_PID" 2>/dev/null || true

cleanup_agent

EOF

chmod +x /tmp/run_exp_inside_vm.sh

# VM 내부에서 실행
orb -m $VM_NAME /bin/bash /mnt/mac/tmp/run_exp_inside_vm.sh

echo "=== ✅ 모든 실험 완료! evidence/ 에 로그 파일들이 정상적으로 생성되었습니다. ==="