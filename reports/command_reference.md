# 리소스 관측 명령과 선택 이유

실험 실행기는 각 애플리케이션 실행을 별도 process group으로 띄웁니다. 따라서 부모 PID만이 아니라 같은 그룹에 속한 자식 프로세스까지 관측합니다. 모든 측정은 Ubuntu VM 안에서 수행하며, 아래 `<PGID>`와 `<PIDLIST>`는 실행마다 생성된 값입니다.

## 공통 수집기

```bash
./bin/monitor.sh --pgroup <PGID> 1 > evidence/<case>_monitor.csv
```

`monitor.sh`는 1초 간격으로 process group의 각 PID, PPID, 상태, RSS, VSZ를 기록합니다. CPU는 Linux `/proc/<pid>/stat`의 user/system tick 차이를 이용해 **직전 표본 구간의 CPU 사용률**로 계산합니다. `ps %CPU`의 프로세스 생애 평균과 달리 짧은 부하 구간을 시간 순서대로 비교할 수 있습니다.

### 도구 선택 비교

| 명령/도구 | 장점 | 단점 | 이 과제에서의 용도 |
|---|---|---|---|
| `monitor.sh` | PID별 시계열 CSV, RSS/VSZ, 초당 CPU 변화, process group 내 자식 포함 | Linux `/proc`와 Bash가 필요하며 구현을 유지해야 함 | 세 케이스의 추이와 Before/After 수집 |
| `ps` | 가볍고 설치가 기본이며 PID/PPID/상태/대기 채널을 한 번에 확인 | 기본 호출은 한 시점의 스냅샷이고 `%CPU`는 생애 평균이라 순간 spike 판단에 부적절 | 프로세스 계보 및 Deadlock 상태 스냅샷 |
| `top` | 반복 갱신과 스레드별 사용률을 현장에서 바로 확인 가능 | 대화형 화면은 재현·공유하기 어렵고, 샘플 간격/실행 시간이 결과에 영향 | `top -H -b`로 스레드 부하 스냅샷을 파일 저장 |
| `htop` | 트리/스레드를 대화형으로 보기 쉬움 | VM에 별도 설치가 필요할 수 있고, 화면 중심이라 자동 비교 자료로 남기기 번거로움 | 사람의 보조 진단용, 필수 증거 수집에는 미사용 |
| `vmstat` | CPU 대기열, 메모리, swap 등 시스템 전체 부하를 함께 확인 | 프로세스별 수치가 아니므로 특정 앱 원인을 단독 입증할 수 없음 | 시스템 전체 문제와 앱 문제를 구분할 때 보조 사용 |
| `pidstat` | PID/스레드별 CPU·메모리 등을 일정 간격으로 출력 | `sysstat` 설치 여부에 좌우되며 기본 VM에 없을 수 있음 | `monitor.sh` 대체/교차 확인용 |
| `/proc/<PID>/status`, `smaps_rollup` | Linux가 제공하는 메모리 항목을 직접 확인, `smaps_rollup`은 RSS 구성 상세 | 한 번에 한 PID를 읽어야 하고 시계열·자식 합산은 별도로 구현해야 함 | RSS 이상 징후 상세 조사 |

## OOM Crash

### 사용 명령

```bash
./bin/monitor.sh --pgroup <PGID> 1 > evidence/exp_oom_before_monitor.csv
grep -E 'MEMORY_LIMIT|Current Heap|Memory limit exceeded|Self-terminating|SELF-TERMINATED' \
  evidence/exp_oom_before.log
ps --pgroup <PGID> -o pid,ppid,pgid,%cpu,%mem,rss,vsz,stat,etime,args --forest
```

`monitor.sh`에서 시간에 따른 RSS를 보고, 애플리케이션 로그의 Heap/MemoryGuard 메시지로 앱 내부 제한 초과와 종료 원인을 확인합니다. `ps`는 실행 시점의 PID 계보와 RSS를 교차 확인합니다. `free -h`는 시스템 전체 메모리만 보여주므로 프로세스 메모리 증가를 증명하는 주 증거로 사용하지 않습니다. `/proc/<PID>/smaps_rollup`은 상세하지만 반복 수집과 process group 합산이 번거로워 이 실험에서는 보조 조사 도구입니다.

### 지표 해석

애플리케이션의 `Current Heap`과 Linux 프로세스 RSS는 서로 다른 값입니다. Heap은 앱 로그의 자체 계측이고 RSS는 OS가 실제 상주 중이라고 집계한 물리 페이지입니다. 따라서 Heap 증가만으로 명세의 관제 RSS 상승 요건을 충족했다고 단정하지 않으며, 양쪽 값을 나란히 기록합니다.

## CPU 과점유 / Latency

### 사용 명령

```bash
./bin/monitor.sh --pgroup <PGID> 1 > evidence/exp_cpu_before_monitor.csv
ps --pgroup <PGID> -o pid,ppid,pgid,%cpu,%mem,rss,vsz,stat,etime,args --forest
top -H -b -n 2 -p <PIDLIST> > evidence/exp_cpu_before_top.log
grep -E 'CPU_MAX_OCCUPY|CpuWorker|WATCHDOG|SIGTERM|EMERGENCY ABORT' \
  evidence/exp_cpu_before.log
```

`monitor.sh`의 구간별 CPU 수치로 시간 변화와 process group의 각 프로세스를 확인합니다. `top -H`는 스레드별 순간 부하를 보완하고, 앱 로그는 `CPU_MAX_OCCUPY`와 Watchdog 종료 사유를 확인합니다. `ps %CPU`는 누적 평균이라 순간 spike를 놓칠 수 있어 단독 판단에 쓰지 않습니다. `vmstat 1`은 전체 CPU가 바쁜지 보조 확인하지만 앱 PID를 특정하지 못합니다.

## Deadlock

### 사용 명령

```bash
ps --pgroup <PGID> -o pid,ppid,pgid,%cpu,%mem,rss,vsz,stat,etime,args --forest
ps --pgroup <PGID> -L -o pid,tid,ppid,%cpu,%mem,stat,wchan:32
top -H -b -n 2 -p <PIDLIST>
./bin/monitor.sh --pgroup <PGID> 1 > evidence/exp_deadlock_before_monitor.csv
tail -n 12 evidence/exp_deadlock_before.log
```

`ps`의 부모/자식 트리로 올바른 프로세스를 찾고, `-L`로 PID와 TID를 나눠 스레드 상태 및 `wchan`(커널 대기 지점)을 확인합니다. `top -H`는 같은 실행에서 스레드별 CPU가 멈춰 있는지 보완합니다. 마지막 애플리케이션 로그의 `WAITING/BLOCKED` 자원 이름을 두 스레드의 보유/대기 관계와 연결해야 순환 대기를 주장할 수 있습니다.

`strace -f`는 시스템 호출 대기에는 유용하지만 사용자 공간 mutex/lock 보유 관계를 직접 보여주지 않으며, attach 권한과 추적 오버헤드가 필요할 수 있어 필수 수집에는 사용하지 않습니다. `wchan` 또한 커널 대기 지점만 보여주므로 앱 로그와 함께 해석합니다.
