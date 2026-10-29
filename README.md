# 리눅스 프로세스 및 시스템 리소스 트러블슈팅

`agent-leak-app-x86`를 Linux VM에서 실행해 OOM, CPU 과점유, Deadlock 증거를 수집하고 결과를 이슈 형식의 보고서로 정리하는 과제 저장소입니다.

## 저장소 구성

- `bin/agent-leak-app-x86`: 제공된 Linux x86-64 실행 파일
- `bin/monitor.sh`: process group의 CPU 구간값, RSS, VSZ, 상태를 초 단위 CSV로 관측
- `scripts/01_run_experiments.sh`: macOS 호스트에서 OrbStack 실험 실행
- `scripts/01_run_experiments_vm.sh`: Ubuntu VM에서 실행 및 증거 저장
- `evidence/`: 실행 로그, 프로세스 관측 CSV, PID/스레드 스냅샷
- `reports/`: OOM, CPU, Deadlock 분석 보고서
- `reports/command_reference.md`: 리소스 수집 명령과 대안 도구 비교
- `study.md`: 관련 OS 개념 정리

## 실험 실행

OrbStack에 `ubuntu-2404-dev` VM이 준비되어 있고 프로젝트가 VM에서 `/mnt/mac` 아래로 마운트되어 있어야 합니다. 저장소 루트에서 실행합니다.

```bash
./scripts/01_run_experiments.sh
```

VM 안의 사용자는 root가 아니어야 합니다. 스크립트가 필요한 `AGENT_*` 디렉터리와 `secret.key`를 준비하고 케이스별 출력을 `evidence/`에 기록합니다. 실험 실행 시 기존 증거 파일을 덮어씁니다.

실행은 제한된 시간 동안 관측합니다. 시간이 끝날 때까지 살아 있는 프로세스는 `.meta`에 하네스가 정지시켰다고 기록되므로, 이를 애플리케이션 또는 Watchdog의 종료와 구분해야 합니다. 애플리케이션 로그, monitor CSV, `ps` 상태, Deadlock 스레드 상태를 함께 검토하세요.

## 최신 실험 결과 요약

- OOM: `MEMORY_LIMIT=50`에서 MemoryGuard 종료와 자식 RSS 약 18MB→44MB 상승을 관측했습니다. `512`에서는 40초 동안 Heap 325MB/RSS 약 326MB까지 증가했고, 하네스가 관측을 끝냈습니다.
- CPU: `CPU_MAX_OCCUPY=10`은 내부 CpuWorker Load를 10%에서 제한해 60초 생존했습니다. `90`은 내부 Load 51.1%에서 앱 threshold 로그를 남기고 약 40초 후 SIGTERM 상태로 종료됐습니다. 단, OS가 측정한 process CPU는 최대 약 5%이고 시스템 CPU는 거의 idle이라 실제 CPU 과점유 증거는 부분 충족입니다.
- Deadlock: `MULTI_THREAD_ENABLE=true`에서 두 Worker의 순환 `WAITING/BLOCKED`와 TID의 `futex_wait`를 확인했습니다. `false`에서는 같은 로그가 없고 작업 진행이 관측됐습니다.

실험을 다시 실행하면 `evidence/` 파일을 덮어씁니다. `.meta`의 `HARNESS_STOPPED_AFTER`는 수집기가 정리한 종료이고, `APP_EXITED_AFTER`는 앱 종료입니다. 각 보고서의 해석과 남은 CPU 측정 한계를 제출 전에 함께 검토하세요.

`exp_deadlock_ps.log`, `exp_deadlock_threads.log`, `exp_deadlock_monitor.csv`처럼 `_before` 접미사가 없는 Deadlock 파일은 이전 실험 산출물입니다. 현재 보고서는 새 실행에서 생성한 `exp_deadlock_before_*` 파일을 인용합니다.
