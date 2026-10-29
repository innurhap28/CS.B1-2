# [Bug] CPU Latency - CPU 제한값 변경에 따른 과점유 보호 동작 분석

## 1. Description (현상 설명)

`CPU_MAX_OCCUPY=10`과 `90`으로 실행한 로그가 저장되어 있으나, 현재 체크인된 증거만으로는 Watchdog에 의한 종료나 CPU 과점유를 입증할 수 없다. 보고서 초안에 있던 `98.5%~100%`, `SIGTERM`, 생존 여부는 해당 로그에서 확인되지 않아 결과로 사용하지 않는다.

## 2. Evidence & Logs (증거 자료)

실험기는 `./bin/monitor.sh --pgroup <PGID> 1`로 프로세스 그룹 내 PID별 CPU/RSS 추이를 CSV로 수집하고, `ps --pgroup <PGID> ... --forest`로 부모·자식 관계를 남긴다. `top -H -b -n 2 -p <PIDLIST>`는 스레드 단위 부하 스냅샷, 앱 로그는 Watchdog/SIGTERM 원인 확인에 사용한다. 각 명령을 선택한 이유와 `htop`, `vmstat`, `pidstat` 등의 장단점은 [리소스 관측 명령과 선택 이유](command_reference.md#cpu-과점유--latency)에 정리했다.

### Before: `CPU_MAX_OCCUPY=10`

[`evidence/exp_cpu_before.log`](../evidence/exp_cpu_before.log)는 `CPU_MAX_OCCUPY=10%`로 부팅한 사실을 보여준다. 하지만 실제 로그는 다음과 같이 두 AgentWorker가 서로의 락을 기다리는 상태에서 끝난다.

```text
2026-09-25 00:11:46,545 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
2026-09-25 00:11:46,546 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
```

따라서 이 실행은 CPU 실험의 증거가 아니라 Deadlock 재현 로그가 잘못 저장된 것으로 보인다. [`evidence/exp_cpu_before_monitor.csv`](../evidence/exp_cpu_before_monitor.csv)의 기록도 프로세스 CPU가 대략 `0.3~6.8%`이며, 과점유 구간이나 `PROCESS_EXITED`가 없다.

### After: `CPU_MAX_OCCUPY=90`

[`evidence/exp_cpu_after.log`](../evidence/exp_cpu_after.log)는 `CpuWorker`가 시작했고 관측된 내부 Load가 약 `5.19%`에서 `23.27%`까지 증가한 기록을 담고 있다. [`evidence/exp_cpu_after_monitor.csv`](../evidence/exp_cpu_after_monitor.csv)의 프로세스 CPU는 약 `0.4~6.8%`로 나타난다. 종료 로그, Watchdog 메시지, SIGTERM 증거는 이 파일들에 없다.

## 3. Root Cause Analysis (원인 분석)

현재 자료는 과점유 또는 Watchdog 종료가 아니라 CPU Worker가 실행되었다는 점만 뒷받침한다. Before 로그의 Deadlock은 CPU 비교 실험에 `MULTI_THREAD_ENABLE=true`를 함께 사용한 실험 구성 문제로 판단된다. 이 때문에 CPU 설정값만의 효과를 비교할 수 없다.

프로세스 관제의 `%CPU`는 OS가 관측한 프로세스 사용률이고, `CpuWorker`의 `Current Load`는 애플리케이션 내부 로그 값이다. 서로 다른 지표이므로 같은 수치처럼 비교하지 않는다.

## 4. Workaround & Verification (조치 및 검증)

| 항목 | Before | After |
|---|---:|---:|
| `CPU_MAX_OCCUPY` | 10% | 90% |
| 멀티스레드 | 기존 로그의 부팅 설정은 `true` | 기존 로그의 부팅 설정은 `true` |
| 관측된 프로세스 CPU 범위 | 0.3~6.8% | 0.4~6.8% |
| Watchdog/SIGTERM | 증거 없음 | 증거 없음 |
| 결론 | CPU 실험으로 사용할 수 없음 (Deadlock 로그 혼입) | 과점유/종료 여부 확인 불가 |

재현 가능한 비교를 위해 [`scripts/01_run_experiments.sh`](../scripts/01_run_experiments.sh)는 두 CPU 케이스 모두 `MULTI_THREAD_ENABLE=false`로 실행한다. 실험기는 로그, process group별 CSV, 프로세스/스레드 상태, 종료 주체를 새로 수집하도록 보완했다. OrbStack CLI는 설치되어 있지만 현재 `orbctl status`가 `Stopped`이고 VM 시작 시 `VM exited unexpectedly`가 발생해 재측정하지 못했다. 따라서 본 보고서의 CPU 실험 결과는 미완료다.
