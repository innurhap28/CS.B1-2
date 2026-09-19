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
    # TCP 소켓이 커널에서 완전히 릴리즈되도록 5초간 대기
    sleep 5
}

# 1. 필수 디렉터리 일괄 생성
mkdir -p "$AGENT_HOME" "$AGENT_LOG_DIR" "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH"

# 2. 필수 파일 생성
echo "dummy-secret-key-1234" > "$AGENT_KEY_PATH/secret.key"
touch "$AGENT_LOG_DIR/agent.log"

# 3. 초기 포트 정리
cleanup_agent

# 4. 바이너리 존재 확인 및 복사
if [ ! -f "$AGENT_HOME/agent-leak-app-x86" ]; then
    cp /mnt/mac/Users/innuendo3712/CS.B1-2/bin/agent-leak-app-x86 "$AGENT_HOME/"
    chmod +x "$AGENT_HOME/agent-leak-app-x86"
fi

MAC_PROJECT_DIR="/mnt/mac/Users/innuendo3712/CS.B1-2"

# ----------------------------------------------------
# [실험 1] OOM Crash
# ----------------------------------------------------
echo "=== [1/3] OOM Crash 실험 진행 중... ==="
cleanup_agent

export MEMORY_LIMIT=50
export CPU_MAX_OCCUPY=100
export MULTI_THREAD_ENABLE=true

"$AGENT_HOME/agent-leak-app-x86" > "$MAC_PROJECT_DIR/evidence/exp_oom_before.log" 2>&1 &
OOM_PID=$!
echo "OOM Before 실행 중 (약 30초 대기)..."
sleep 30
cleanup_agent

export MEMORY_LIMIT=512
"$AGENT_HOME/agent-leak-app-x86" > "$MAC_PROJECT_DIR/evidence/exp_oom_after.log" 2>&1 &
OOM_AFTER_PID=$!
echo "OOM After 실행 중 (약 15초 대기)..."
sleep 15
cleanup_agent

# ----------------------------------------------------
# [실험 2] CPU Latency
# ----------------------------------------------------
echo "=== [2/3] CPU 과점유 실험 진행 중... ==="
cleanup_agent

export MEMORY_LIMIT=512
export CPU_MAX_OCCUPY=10
export MULTI_THREAD_ENABLE=true

"$AGENT_HOME/agent-leak-app-x86" > "$MAC_PROJECT_DIR/evidence/exp_cpu_before.log" 2>&1 &
CPU_PID=$!
echo "CPU Before 실행 중 (약 20초 대기)..."
sleep 20
cleanup_agent

export CPU_MAX_OCCUPY=90
"$AGENT_HOME/agent-leak-app-x86" > "$MAC_PROJECT_DIR/evidence/exp_cpu_after.log" 2>&1 &
CPU_AFTER_PID=$!
echo "CPU After 실행 중 (약 15초 대기)..."
sleep 15
cleanup_agent

# ----------------------------------------------------
# [실험 3] Deadlock
# ----------------------------------------------------
echo "=== [3/3] Deadlock 실험 진행 중... ==="
cleanup_agent

export MEMORY_LIMIT=512
export CPU_MAX_OCCUPY=100
export MULTI_THREAD_ENABLE=true

"$AGENT_HOME/agent-leak-app-x86" > "$MAC_PROJECT_DIR/evidence/exp_deadlock_before.log" 2>&1 &
DL_PID=$!
echo "Deadlock Before 실행 중 (약 15초 대기)..."
sleep 15
ps -ef | grep agent-leak-app-x86 | grep -v grep > "$MAC_PROJECT_DIR/evidence/exp_deadlock_ps.log"
cleanup_agent

export MULTI_THREAD_ENABLE=false
"$AGENT_HOME/agent-leak-app-x86" > "$MAC_PROJECT_DIR/evidence/exp_deadlock_after.log" 2>&1 &
DL_AFTER_PID=$!
echo "Deadlock After 실행 중 (약 15초 대기)..."
sleep 15
cleanup_agent

EOF

chmod +x /tmp/run_exp_inside_vm.sh

# VM 내부에서 실행
orb -m $VM_NAME /bin/bash /mnt/mac/tmp/run_exp_inside_vm.sh

echo "=== ✅ 모든 실험 완료! evidence/ 에 로그 파일들이 정상적으로 생성되었습니다. ==="