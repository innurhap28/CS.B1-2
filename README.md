# 리눅스 프로세스 및 시스템 리소스 트러블슈팅

`agent-leak-app-x86`를 Linux VM에서 실행해 OOM, CPU 과점유, Deadlock 증거를 수집하고 결과를 이슈 형식의 보고서로 정리하는 과제 저장소입니다.

## 저장소 구성

- `bin/agent-leak-app-x86`: 제공된 Linux x86-64 실행 파일
- `bin/monitor.sh`: PID의 CPU, RSS, VSZ, 상태를 초 단위 CSV로 관측
- `scripts/01_run_experiments.sh`: macOS 호스트에서 OrbStack 실험 실행
- `scripts/01_run_experiments_vm.sh`: Ubuntu VM에서 실행 및 증거 저장
- `evidence/`: 실행 로그, 프로세스 관측 CSV, PID/스레드 스냅샷
- `reports/`: OOM, CPU, Deadlock 분석 보고서
- `study.md`: 관련 OS 개념 정리

## 실험 실행

OrbStack에 `ubuntu-2404-dev` VM이 준비되어 있고 프로젝트가 VM에서 `/mnt/mac` 아래로 마운트되어 있어야 합니다. 저장소 루트에서 실행합니다.

```bash
./scripts/01_run_experiments.sh
```

VM 안의 사용자는 root가 아니어야 합니다. 스크립트가 필요한 `AGENT_*` 디렉터리와 `secret.key`를 준비하고 케이스별 출력을 `evidence/`에 기록합니다. 실험 실행 시 기존 증거 파일을 덮어씁니다.

실행은 제한된 시간 동안 관측합니다. 시간이 끝날 때까지 살아 있는 프로세스는 `.meta`에 하네스가 정지시켰다고 기록되므로, 이를 애플리케이션 또는 Watchdog의 종료와 구분해야 합니다. 애플리케이션 로그, monitor CSV, `ps` 상태, Deadlock 스레드 상태를 함께 검토하세요.

## 현재 증거 상태

기존 OOM 자료에는 `MEMORY_LIMIT=50`에서 MemoryGuard가 종료한 로그가 있습니다. 기존 CPU 및 Deadlock 자료는 일부 로그가 잘못된 케이스 파일에 저장됐고, 몇몇 스레드 스냅샷은 헤더뿐입니다. 보고서에 이 한계를 표시했습니다. 정확한 CPU 및 Deadlock Before/After 결론을 내려면 Linux VM에서 실험을 다시 실행해야 합니다.
