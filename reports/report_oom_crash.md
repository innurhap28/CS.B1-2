# [Bug] OOM Crash - MemoryGuard 제한 초과에 따른 프로세스 종료

## 1. Description (현상 설명)

`MEMORY_LIMIT=50MB`로 실행하자 MemoryWorker Heap이 25MB에서 50MB로 증가했고, MemoryGuard가 초과를 기록한 뒤 앱 자식 프로세스가 종료됐다. 제한을 512MB로 높인 실행에서는 40초 관측 동안 Heap이 325MB까지 증가했지만 MemoryGuard 종료는 발생하지 않았다.

## 2. Evidence & Logs (증거 자료)

### 수집 방법과 명령

실험기는 `./bin/monitor.sh --pgroup <PGID> 1`로 앱의 process group 전체를 매초 수집했다. 이 CSV에는 부모/자식 PID별 RSS·VSZ와 `/proc` tick 차이로 계산한 구간 CPU가 있다. 앱 로그의 Heap/MemoryGuard 줄과 `ps -eo ... | awk ...` 프로세스 계보도 함께 대조했다. `free -h`는 시스템 전체 메모리만 보여줘 앱 RSS의 주 증거로 쓰지 않았다. 대안 명령의 장단점은 [명령어 비교 문서](command_reference.md#oom-crash)에 정리했다.

### Before: `MEMORY_LIMIT=50`, 공통 `CPU_MAX_OCCUPY=10`, `MULTI_THREAD_ENABLE=false`

[`evidence/exp_oom_before.meta`](../evidence/exp_oom_before.meta)는 PID/PGID `5344`와 앱 종료까지 6초, leader 종료 상태 `137`을 기록한다. 앱 로그에는 종료 원인이 남았다.

```text
2026-10-29 22:14:00,533 [INFO] [MemoryWorker] Current Heap: 25MB
2026-10-29 22:14:03,580 [INFO] [MemoryWorker] Current Heap: 50MB
2026-10-29 22:14:03,580 [CRITICAL] [MemoryGuard] Memory limit exceeded (50MB >= 50MB)
2026-10-29 22:14:03,581 [CRITICAL] [MemoryGuard] Self-terminating process 5362 to prevent system instability.
```

[`evidence/exp_oom_before_monitor.csv`](../evidence/exp_oom_before_monitor.csv)에서 앱 자식 PID `5362`의 RSS는 처음 기록된 `18,588KB`에서 종료 전 `44,192KB`까지 증가했다. 따라서 Heap 증가와 OS가 측정한 resident memory 증가, 자체 종료 로그가 같은 실험에 기록되어 있다.

### After: `MEMORY_LIMIT=512`, 나머지 설정 동일

[`evidence/exp_oom_after.log`](../evidence/exp_oom_after.log)에서 Heap은 `25MB → 325MB`까지 증가했고 MemoryGuard 초과 로그는 없었다. [`evidence/exp_oom_after_monitor.csv`](../evidence/exp_oom_after_monitor.csv)에서 자식 PID `5454`의 RSS는 `18,548KB → 326,092KB`로 증가했다. [`evidence/exp_oom_after.meta`](../evidence/exp_oom_after.meta)는 process group이 40초 관측 시간 동안 살아 있어 하네스가 정리했음을 기록한다(`HARNESS_STOPPED_AFTER=40s`, leader status `143`). 이는 앱 자체 종료가 아니다.

## 3. Root Cause Analysis (원인 분석)

Before 실행에서는 `Memory limit exceeded`와 `Self-terminating process`가 연속 기록되고 종료 상태가 137(SIGKILL 관례 값)이다. 로그와 관측을 종합하면 Linux OOM Killer가 아닌 앱 내부 MemoryGuard가 제한을 적용한 종료로 판단한다.

제한을 높인 After에서도 Heap과 RSS가 계속 증가했다. 그러므로 512MB 설정은 종료 시점을 늦춘 임시 조치이며 메모리 증가 원인을 해결하지 않는다. 확보된 앱 로그만으로 누수 객체나 코드 위치까지 특정할 수는 없다.

## 4. Workaround & Verification (조치 및 검증)

| 항목 | Before | After |
|---|---:|---:|
| `MEMORY_LIMIT` | 50MB | 512MB |
| Heap | 25→50MB, 약 3초 내 제한 초과 | 25→325MB, 40초 관측 |
| 앱 자식 RSS | 18,588→44,192KB | 18,548→326,092KB |
| 종료 | MemoryGuard 로그, leader status 137, 약 6초 이내 | 관측 중 생존; 40초 후 하네스가 SIGTERM으로 종료 |

동일한 `CPU_MAX_OCCUPY=10`과 멀티스레드 비활성 설정에서 메모리 제한만 변경했다. 512MB 실행에서 Heap/RSS가 더 높은 값까지 증가하고 40초 관측을 버틴 결과, 제한 상향이 앱 제한 종료를 늦춘다는 점을 확인했다. RSS 상승은 50MB와 512MB 두 실행에서 각각 monitor CSV로 확인할 수 있다.
