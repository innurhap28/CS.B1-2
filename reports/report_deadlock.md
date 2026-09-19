[Bug] Deadlock - 멀티스레드 교착상태 발생으로 인한 프로세스 무응답

## 1. Description (현상 설명)
- 애플리케이션 실행 후 프로세스는 종료되지 않고 PID가 상주해 있으나, CPU 및 메모리 점유율 변화가 전혀 없고 로그 출력도 완전 멈추는 무응답(Hang) 상태가 발생함.

## 2. Evidence & Logs (증거 자료)
- **PID 존재 확인 (`ps -ef` 결과):**
  - `agent-admin  12345  ... /home/agent-admin/agent-app/agent-leak-app-x86` (프로세스 정상 등록 상태)
- **자원 변화 정체 (`top -H` / 관제 수치):**
  - CPU: 0.0%, MEM: 변화 없음 (동결 상태)
- **마지막 프로그램 실행 로그 (`/tmp/exp_deadlock_before.log` 발췌):**
  ```text
  [INFO] [Thread-1] Acquiring Lock A... Success.
  [INFO] [Thread-2] Acquiring Lock B... Success.
  [WARNING] [Thread-1] Waiting for Lock B... (BLOCKED)
  [WARNING] [Thread-2] Waiting for Lock A... (BLOCKED)

## 3. Root Cause Analysis (원인 분석)
- `MULTI_THREAD_ENABLE=true` 설정 시 멀티스레드 환경에서 Thread-1은 Lock A를 쥔 채 Lock B를 기다리고, Thread-2는 Lock B를 쥔 채 Lock A를 기다리는 순환 대기(Circular Wait) 조건이 성립함.
- 교착상태 4대 조건 (상호 배제, 점유 대기, 비선점, 순환 대기)이 충족되어 두 스레드가 영구적인 대기 상태에 빠짐.

## 4. Workaround & Verification (조치 및 검증)
- **환경변수 조정** : `MULTI_THREAD_ENABLE`를 `true`(Before)에서 `false`(After)로 변경하여 단일 스레드 모드로 전환함.
- **Before & After 비교** : 
  - **Before (true)** : 락 획득 경쟁으로 인해 `BLOCKED` 발생 후 무응답 상태에 빠짐.
  - **After (false)** : 자원 경합이 차단되어 Deadlock 없이 로직이 순차적으로 끝까지 정상 실행됨.
- **추가 제안** : 락 획득 순서를 일치시키거나(Lock Ordering) 타임아웃 기법(Lock Timeout)을 적용하는 코드로 수정 필요.