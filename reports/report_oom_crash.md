[Bug] OOM Crash - MemoryGuard 메모리 임계치 초과에 의한 프로세스 강제 종료

## 1. Description (현상 설명)
- `agent-leak-app` 애플리케이션 실행 후 시간 경과에 따라 물리 메모리 사용량이 선형적으로 계속 상승하는 현상이 관측됨.
- 메모리 사용량이 설정된 임계치에 도달하면 내부 메모리 보호 정책(MemoryGuard)이 작동하여 프로세스가 `SELF-TERMINATED` 메시지와 함께 강제 종료됨.

## 2. Evidence & Logs (증거 자료)
- **monitor.sh 관제 데이터 (수치):**
  - 초기: `MEM: 5.1%` (정상 범위)
  - 2분 경과: `MEM: 45.2%` (상승 추세)
  - 4분 경과: `MEM: 96.8%` (임계치 도달)
- **프로그램 실행 로그:**
```
```

## 3. Root Cause Analysis (원인 분석)
- 애플리케이션 로직 내부에서 할당한 메모리 객체를 해제하지 않아 힙(Heap) 영역에 지속적으로 쌓이는 메모리 누수 (Memory Leak) 결함이 존재함. 
- 물리 메모리 점유율이 `MEMORY_LIMIT` 환경변수로 지정한 50MB에 도달하자, MemoryGuard가 시스템 전체 장애(OOM Killer 발동)을 막기 위해 스스로 프로세스를 종료시킴. 

## 4. Workaround & Verification (조치 및 검증)
- **환경변수 조정** : `MEMORY_LIMIT`을 `50`(Before)에서 `512`(After)로 상향 변경함.
- **Before & After 비교** :
  - **Before (50MB)** : 실행 후 약 3-4분 내에 MemoryGuard에 의해 강제 종료됨.
  - **After (512MB)** : 가용 메모리 확장으로 강제 종료 없이 프로세스가 오랜 시간 안정적으로 생존함을 확인함.
- **추가 제안** : 코드 레벨에서 불필요한 참조 객체를 주기적으로 삭제(GC/Free)하는 메모리 관리 리팩토링이 필요함.

