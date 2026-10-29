# [Bug] CPU Latency - CPU Worker 제한 변경과 임계치 종료

## 1. Description (현상 설명)

`CPU_MAX_OCCUPY=10`에서는 앱 내부 CpuWorker Load가 10%에서 cooldown을 반복했고 실행이 60초 관측을 버텼다. `CPU_MAX_OCCUPY=90`에서는 내부 Load가 51.1%에 도달했을 때 `CPU Threshold Violated` 로그가 발생했고, process group이 약 40초 후 SIGTERM 종료 상태로 끝났다.

## 2. Evidence & Logs (증거 자료)

실험기는 `./bin/monitor.sh --pgroup <PGID> 1`로 process group의 PID별 RSS와 1초 CPU 구간값을 기록하고 `top -H -b -d 1`을 케이스 전체 구간 동안 저장했다. `ps -eo ... | awk ...`는 부모/자식 PID를 확인하는 데 사용했다. 로그 검색에는 `grep`을 써 설정값과 앱 종료 메시지를 확인했다. 도구의 이유와 `htop`, `vmstat`, `pidstat` 대안 비교는 [명령어 비교 문서](command_reference.md#cpu-과점유--latency)에 있다.

### Before: `CPU_MAX_OCCUPY=10`

[`evidence/exp_cpu_before.log`](../evidence/exp_cpu_before.log)에서 CpuWorker가 `Maximum CPU Limit: 10%`으로 시작하고 `Peak reached (10.00%). Starting cooldown...`을 반복했다. [`evidence/exp_cpu_before.meta`](../evidence/exp_cpu_before.meta)는 PID/PGID `5979`, `HARNESS_STOPPED_AFTER=60s`를 기록한다. 앱은 60초 동안 자체 종료하지 않았다.

[`evidence/exp_cpu_before_monitor.csv`](../evidence/exp_cpu_before_monitor.csv)의 OS 구간 CPU 최대는 약 5%였고, 연속 [`top` 스냅샷](../evidence/exp_cpu_before_top.log)에서도 앱 프로세스 값은 약 4% 이내였다. `top`의 시스템 CPU 요약은 대부분 99% 이상 idle이었다.

### After: `CPU_MAX_OCCUPY=90`

[`evidence/exp_cpu_after.log`](../evidence/exp_cpu_after.log)에는 내부 Load가 5%에서 51.1%까지 증가한 뒤 다음 로그가 있다.

```text
2026-10-29 22:16:22,713 [INFO] [CpuWorker] Current Load: 47.29%
2026-10-29 22:16:25,833 [INFO] [CpuWorker] Current Load: 51.10%
2026-10-29 22:16:25,935 [CRITICAL] [CpuWorker] CPU Threshold Violated! (51.1%).
```

[`evidence/exp_cpu_after.meta`](../evidence/exp_cpu_after.meta)는 PID/PGID `6769`, 앱 종료까지 약 40초, leader exit status `143`(SIGTERM 관례 값)을 기록한다. 명시적인 `WATCHDOG` 또는 `SIGTERM` 앱 로그는 없다. [`evidence/exp_cpu_after_monitor.csv`](../evidence/exp_cpu_after_monitor.csv)의 OS 구간 CPU 최대는 약 5%이고 [`top` 스냅샷](../evidence/exp_cpu_after_top.log)에서도 시스템 CPU는 대체로 idle이었다.

## 3. Root Cause Analysis (원인 분석)

이 비교는 `CPU_MAX_OCCUPY`에 따라 앱 내부 CpuWorker의 동작과 생존 시간이 달라짐을 보여준다. 10% 설정은 부하를 제한하고 cooldown하며, 90% 설정은 내부 Load가 51.1%에 도달한 시점에 `CPU Threshold Violated`를 기록한 뒤 process group이 SIGTERM 상태로 종료됐다. 관측 결과는 설정값과 별도로 앱 내부에 약 50% 부근의 보호 임계치가 있는 것처럼 보이지만, 바이너리 내부 구현을 확인할 수 없으므로 이는 로그에서 도출한 추론이다. 로그는 종료 주체를 `Watchdog`라고 명시하지 않으므로 보고서에서는 앱 로그 그대로 CpuWorker 임계치 종료라고 표현한다.

**지표 해석:** monitor와 `top`이 측정한 OS process CPU는 최대 약 5%였고 시스템 CPU도 포화되지 않았다. 앱 내부 `Current Load`와 `CPU Threshold Violated`는 앱이 출력한 별도 지표 및 임계치 로그다. 소문처럼 이 수치가 실제 CPU 사용률이 아니라 앱 내부에 하드코딩되었거나 자체 계산된 값일 가능성도 있지만, 바이너리를 열어 확인하지 않았으므로 사실로 단정하지 않는다. 따라서 두 종류의 값을 각각 출처와 의미가 확인된 범위에서 보고한다. OS 측정만으로 앱 내부 CPU 동작을 부정하지 않으며, 반대로 앱 로그만으로 OS CPU 포화나 시스템 지연을 주장하지 않는다.

## 4. Workaround & Verification (조치 및 검증)

| 항목 | Before | After |
|---|---:|---:|
| `CPU_MAX_OCCUPY` | 10% | 90% |
| 앱 내부 CpuWorker Load | 10%에서 cooldown 반복 | 51.1%에서 threshold 위반 로그 |
| OS process CPU | 최대 약 5% | 최대 약 5% |
| 관측 결과 | 60초 생존 후 하네스 정리 | 약 40초 후 종료, leader status 143 |
| Watchdog 텍스트 로그 | 없음 | 없음; 대신 CpuWorker threshold 로그 |

멀티스레드 상태와 다른 설정은 동일하게 두고 CPU 설정만 변경했다. 기존 실행 자료에서는 내부 Load, threshold 로그, 생존 시간의 차이가 확인된다. 2026-10-30 재실행은 OrbStack VM이 `VM exited unexpectedly`로 시작되지 않아 새 증거를 만들지 못했다. 따라서 이전 증거를 그대로 유지하며, 내부 지표가 하드코딩/자체 계산되었을 가능성은 미확인 가설로 남긴다. OS CPU 사용률은 별도 진단 자료로 제공하고 내부 Load와 혼합하지 않는다.
