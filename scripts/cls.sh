#!/bin/bash

# 생성했던 인스턴스 이름 (init.sh에서 설정한 이름과 동일해야 합니다)
VM_NAME="ubuntu-2404-dev"

echo "🧹 OrbStack 인스턴스 '$VM_NAME' 삭제를 시작합니다..."

# 1. 인스턴스 존재 여부 확인 후 삭제
if orb list | grep -q "$VM_NAME"; then
    # 인스턴스 중지 (실행 중일 경우를 대비)
    echo "🛑 인스턴스 중지 중..."
    orb stop $VM_NAME 2>/dev/null

    # 인스턴스 삭제 (-f 옵션으로 확인 절차 없이 즉시 삭제 가능)
    echo "🗑️ 인스턴스 영구 삭제 중..."
    orb delete -f $VM_NAME

    echo "✨ 삭제가 완료되었습니다. 깔끔하네요!"
else
    echo "⚠️ 삭제할 인스턴스 '$VM_NAME'을(를) 찾을 수 없습니다."
fi