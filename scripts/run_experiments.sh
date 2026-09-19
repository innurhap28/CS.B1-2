#!/bin/bash

# 환경변수 기본 설정
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
export AGENT_LOG_DIR=/var/log/agent-app

# ----------------------------------------------------
# [실험 1] OOM Crash
# ----------------------------------------------------
echo "=== [1/3] OOM Crash 실험 진행 중... ==="
pkill -f agent-leak-app-x86 2>/dev/null || true

# Before: MEMORY_LIMIT=50
export MEMORY_LIMIT=50
export CPU_MAX_OCCUPY=100
export MULTI_THREAD_ENABLE=true

$AGENT_HOME/agent-leak-app-x86 > /tmp/exp_oom_before.log 2>&1 &
OOM_PID=$!

echo "OOM Before 실행 중 (약 30초 대기)..."
sleep 30
kill -9 $OOM_PID 2>/dev/null || true

# After: MEMORY_LIMIT=512
export MEMORY_LIMIT=512
$AGENT_HOME/agent-leak-app-x86 > /tmp/exp_oom_after.log 2>&1 &
OOM_AFTER_PID=$!

echo "OOM After 실행 중 (약 15초 대기)..."
sleep 15
kill -9 $OOM_AFTER_PID 2>/dev/null || true


# ----------------------------------------------------
# [실험 2] CPU Latency (Watchdog)
# ----------------------------------------------------
echo "=== [2/3] CPU 과점유 실험 진행 중... ==="
pkill -f agent-leak-app-x86 2>/dev/null || true

# Before: CPU_MAX_OCCUPY=10
export MEMORY_LIMIT=512
export CPU_MAX_OCCUPY=10
export MULTI_THREAD_ENABLE=true

$AGENT_HOME/agent-leak-app-x86 > /tmp/exp_cpu_before.log 2>&1 &
CPU_PID=$!

echo "CPU Before 실행 중 (약 20초 대기)..."
sleep 20
kill -9 $CPU_PID 2>/dev/null || true

# After: CPU_MAX_OCCUPY=90
export CPU_MAX_OCCUPY=90
$AGENT_HOME/agent-leak-app-x86 > /tmp/exp_cpu_after.log 2>&1 &
CPU_AFTER_PID=$!

echo "CPU After 실행 중 (약 15초 대기)..."
sleep 15
kill -9 $CPU_AFTER_PID 2>/dev/null || true


# ----------------------------------------------------
# [실험 3] Deadlock
# ----------------------------------------------------
echo "=== [3/3] Deadlock 실험 진행 중... ==="
pkill -f agent-leak-app-x86 2>/dev/null || true

# Before: MULTI_THREAD_ENABLE=true
export MEMORY_LIMIT=512
export CPU_MAX_OCCUPY=100
export MULTI_THREAD_ENABLE=true

$AGENT_HOME/agent-leak-app-x86 > /tmp/exp_deadlock_before.log 2>&1 &
DL_PID=$!

echo "Deadlock Before 실행 중 (약 15초 대기)..."
sleep 15
ps -ef | grep agent-leak-app-x86 | grep -v grep > /tmp/exp_deadlock_ps.log
kill -9 $DL_PID 2>/dev/null || true

# After: MULTI_THREAD_ENABLE=false
export MULTI_THREAD_ENABLE=false
$AGENT_HOME/agent-leak-app-x86 > /tmp/exp_deadlock_after.log 2>&1 &
DL_AFTER_PID=$!

echo "Deadlock After 실행 중 (약 15초 대기)..."
sleep 15
kill -9 $DL_AFTER_PID 2>/dev/null || true

echo "=== ✅ 모든 실험 완료! /tmp 에 로그가 생성되었습니다. ==="
