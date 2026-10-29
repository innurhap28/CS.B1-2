# [Bug] Deadlock - 두 Worker의 순환 자원 대기에 의한 무응답

## 1. Description (현상 설명)

`MULTI_THREAD_ENABLE=true`에서 프로세스는 살아 있지만 두 Worker가 각각 상대가 보유한 자원을 기다리는 상태가 재현됐다. 같은 `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=10` 조건에서 `MULTI_THREAD_ENABLE=false`로 실행한 After에서는 Worker의 `WAITING/BLOCKED`가 없고 Scheduler 완료 로그와 다른 작업 로그가 진행했다.

## 2. Evidence & Logs (증거 자료)

실험기는 PGID 기준으로 `./bin/monitor.sh --pgroup <PGID> 1`을 실행해 부모·자식 PID별 CPU/RSS를 수집했다. `ps -eo ... | awk ...`는 프로세스 계보, process group의 각 PID에 실행한 `ps -L -p <PID> -o pid,tid,ppid,%cpu,%mem,stat,wchan:32`는 TID와 대기 채널을 기록한다. `top -H -b -d 1`은 CPU/스레드 상태를 연속 저장하고, `grep`/로그 발췌는 앱의 자원 보유·대기 관계를 확인한다. 도구 선택 근거와 대안 비교는 [명령어 비교 문서](command_reference.md#deadlock)에 있다.

### Before: `MULTI_THREAD_ENABLE=true`

[`evidence/exp_deadlock_before.meta`](../evidence/exp_deadlock_before.meta)은 PID/PGID `7303`, 설정값, 20초 관측 후 하네스가 종료한 사실을 기록한다. 앱 로그에서 다음 순서를 확인했다.

```text
2026-10-29 22:16:33,914 [INFO] [AgentWorker][Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]. (Holding...)
2026-10-29 22:16:33,915 [INFO] [AgentWorker][Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]. (Holding...)
2026-10-29 22:16:35,927 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
2026-10-29 22:16:35,927 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
```

[`evidence/exp_deadlock_before_ps.log`](../evidence/exp_deadlock_before_ps.log)에서 부모 PID `7303`과 자식 PID `7321`이 관측됐다. [`evidence/exp_deadlock_before_threads.log`](../evidence/exp_deadlock_before_threads.log)의 자식 TID `7412`, `7413`은 모두 `futex_wait` 상태다. [`evidence/exp_deadlock_before_monitor.csv`](../evidence/exp_deadlock_before_monitor.csv)에서 해당 자식 RSS는 약 `18,640→18,720KB`, CPU 구간 값은 대체로 0%로 정체했다. [`top` 스냅샷](../evidence/exp_deadlock_before_top.log)도 프로세스가 살아 있는 동안 시스템 CPU가 거의 idle임을 보여준다.

### After: `MULTI_THREAD_ENABLE=false`

나머지 설정은 동일하다. [`evidence/exp_deadlock_after.log`](../evidence/exp_deadlock_after.log)에는 두 Worker의 `WAITING/BLOCKED`가 없고 Scheduler 완료 뒤 MemoryWorker/CpuWorker 로그가 이어진다. [`evidence/exp_deadlock_after.meta`](../evidence/exp_deadlock_after.meta)는 PID/PGID `7593`이 20초 관측 동안 살아 있어 하네스가 정리했다고 기록한다. [`evidence/exp_deadlock_after_threads.log`](../evidence/exp_deadlock_after_threads.log)에는 `do_select` 등 정상 대기 지점이 보이고, [`top` 스냅샷](../evidence/exp_deadlock_after_top.log)과 함께 Deadlock Before의 두 Worker가 서로 락을 기다리는 상태가 After에는 없음을 확인했다.

## 3. Root Cause Analysis (원인 분석)

Thread-1은 `Shared_Memory_A`를 보유한 채 `Socket_Pool_B`를 기다리고, Thread-2는 `Socket_Pool_B`를 보유한 채 `Shared_Memory_A`를 기다린다. 이 로그와 두 TID의 `futex_wait`, 프로세스 PID 유지, CPU 정체를 결합하면 순환 대기 상태로 판단할 수 있다. 상호 배제, 점유 대기, 비선점, 순환 대기 조건이 성립한다.

After에서는 멀티스레드 모드를 끄자 해당 두 Worker의 락 경쟁이 재현되지 않고 다른 로그 진행이 확인됐다. 이는 우회 조치이며, 근본 해결에는 락 획득 순서 통일이나 timeout 등 코드 수정이 필요하다.

## 4. Workaround & Verification (조치 및 검증)

| 항목 | Before | After |
|---|---|---|
| `MULTI_THREAD_ENABLE` | `true` | `false` |
| PID/생존 | PID 7303/자식 7321, 20초 관측 | PID 7593 및 자식 실행, 20초 관측 |
| Worker 로그 | 서로의 자원을 기다리는 `BLOCKED` | 해당 `WAITING/BLOCKED` 없음, Scheduler 완료 |
| 스레드 상태 | Worker TID 7412/7413 모두 `futex_wait` | 대기 중인 일반 작업 스레드, 순환 락 로그 없음 |
| 종료 처리 | 20초 뒤 하네스 정리 | 20초 뒤 하네스 정리 |

Before/After 모두 같은 관측 시간으로 비교했고, 관측 구간 종료 신호는 앱 장애 종료가 아니라 하네스 정리다. 따라서 Before는 교착을 입증하고 After는 설정 변경에 따른 회피를 관측 구간 안에서 확인한다.
