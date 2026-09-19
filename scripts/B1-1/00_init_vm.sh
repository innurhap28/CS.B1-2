#!/bin/bash

# 명령어 실패 시 스크립트를 즉시 중단(exit)
set -e

source ../library.sh

# 인스턴스 이름 설정
VM_NAME="ubuntu-2404-dev"

echo "🚀 OrbStack을 사용하여 Ubuntu 24.04 인스턴스 생성을 시작합니다..."

# 1. OrbStack CLI 존재 여부 확인
if ! command -v orb &> /dev/null; then
    echo "❌ 에러: 'orb' 명령어를 찾을 수 없습니다. OrbStack이 설치되어 있는지, PATH가 설정되어 있는지 확인하세요."
    exit 1
fi

# 2. OrbStack 인스턴스 생성 (실패 시 즉시 exit)
if ! orb create ubuntu:noble $VM_NAME; then
    echo "❌ 에러: OrbStack 인스턴스 생성에 실패했습니다."
    exit 1
fi

orb start $VM_NAME

# 3. 내부 환경 설정 (업데이트 및 필수 도구 설치)
echo "📦 내부 패키지 업데이트 및 기본 도구 설치 중..."
run_vm sudo apt-get update

# 과제 수행에 필요한 도구 설치
run_vm sudo apt-get install -y openssh-server ufw acl curl

# 4. 완료 메시지
echo "---"
echo "✅ OrbStack Ubuntu 24.04 빌드 완료!"
echo "접속하려면 다음 명령어를 입력하세요:"
echo "👉 orb -m $VM_NAME"
echo "---"