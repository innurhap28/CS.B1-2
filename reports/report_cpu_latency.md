[Bug] CPU Latency - Watchdog 보호 조치에 의한 프로세스 강제 종료

## 1. Description (현상 설명)
- `agent-leak-app` 실행 후 무한 루프 또는 과도한 연산 로직으로 인해 CPU 사용률이 급격히 100%에 가깝게 치솟는 현상이 발생함.
- 과점유 상태가 지속되면 Watchdog 시스템 보호 모듈에 의해 `SIGTERM` 신호를 받고 프로세스가 종료됨.

## 2. Evidence & Logs (증거 자료)
- **top / ps 출력 및 CPU 점유율 수치:**
  - `agent-leak-app-x86` 프로세스의 CPU 사용률이 98.5%~100% 유지 확인.
- **프로그램 실행 로그 (`/tmp/exp_cpu_before.log` 발췌):**
  ```text
  [WARNING] [Watchdog] CPU occupancy threshold exceeded (99% > 10%)
  [CRITICAL] [Watchdog] Emergency abort initiated to prevent system freeze.
  >>> [SYSTEM] WATCHDOG: INITIATING EMERGENCY ABORT (SIGTERM) <<<

## 3. Root Cause Analysis (원인 분석)
- 스레드가 CPU 자원을 독점하는 Busy Waiting 연산이 존재하여 단일 프로세스가 전체 CPU 성능을 과점유함.
- 시스템 부하 및 타 프로세스 기아 상태를 방지하기 위해 Watchdog 모듈이 `CPU_MAX_OCCUPY` 제한(10%) 초과 감지 즉시 SIGTERM을 전송함.

## 4. Workaround & Verification (조치 및 검증)
- **환경변수 조정** : `CPU_MAX_OCCUPY`를 `10`(Before)에서 `90`(After)로 상향 변경함.
- **Before & After 비교** : 
  - **Before (10%)** : CPU 부하 발생 직후 Watchdog에 걸려 곧바로 SIGTERM 강제 종료됨.
  - **After (90%)** : CPU 허용 임계치가 증가함에 따라 비정상 종료 없이 프로세스가 계속 유지됨.
- **추가 제안** : 무한 루프 내 `sleep` 타임 슬롯을 추가하거나 로직 비동기화를 통해 CPU 점유 시간을 완화해야 함.