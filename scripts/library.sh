#!/bin/bash

# OrbStack 업데이트 문구 삭제
run_vm() {
    orb -m ubuntu-2404-dev "$@" 2>&1 \
    | tr -d '\r' \
    | sed '/╭────────────────/,+8d'
}

# 출력 문구 함수
prompt_step() {
    local message="$1"

    echo "=============================="
    echo "$message"
    read -p "다음 단계로 진행하려면 Enter를 누르세요..."
    echo "=============================="
}


# 다음 스크립트로 진행
run_step() {
    local script="$1"
    local message="$2"

    bash "$script" || {
        echo "[ERROR] $script 실행 실패"
        exit 1 
    }

    echo "=============================="
    echo "$message"
    read -p "다음 단계로 진행하려면 Enter를 누르세요..."
    echo "=============================="
}

step_log() {
    local message="$1"

    clear
    echo "=============================="
    echo "$message"
    read -p "다음 단계로 진행하려면 Enter를 누르세요..."
    echo "=============================="
}