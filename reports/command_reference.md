# 리소스 관측 명령과 선택 이유

실험기는 각 앱 실행을 별도의 process group으로 띄우며, 부모 PID뿐 아니라 같은 그룹의 자식 PID도 관측합니다. `<PGID>`는 케이스별 `.meta` 파일에서 확인합니다.

## 공통 시계열 수집

```bash
PGID=1234 # .meta의 PGID 값으로 바꿔 실행
./bin/monitor.sh --pgroup "$PGID" 1 > evidence/exp_case_monitor.csv
```

`monitor.sh`는 Linux `/proc/<PID>/stat`의 user/system tick 차이로 직전 1초 구간 CPU 사용률을 계산하고, process group 내 각 PID의 PPID, 상태, RSS, VSZ를 CSV로 기록합니다. `ps %CPU`가 프로세스 생애 평균인 것과 달리 시간별 증감을 볼 수 있습니다.

### 도구 비교

| 명령/도구 | 장점 | 단점 | 이 과제에서의 용도 |
|---|---|---|---|
| `monitor.sh` | PID별 시계열 CSV, RSS/VSZ, 구간별 CPU, 자식 PID 포함 | Linux `/proc`와 Bash가 필요하고 직접 유지해야 함 | 세 케이스의 추이와 Before/After 수집 |
| `ps` | 기본 설치, 가볍고 PID/PPID/상태/대기 채널 확인 가능 | 기본 호출은 한 시점 스냅샷, `%CPU`는 생애 평균 | 프로세스 계보와 Deadlock 상태 스냅샷 |
| `top` | 반복 갱신과 스레드별 부하를 바로 확인 | 기본 화면은 재현·공유하기 어렵고 샘플 설정에 영향 | `top -H -b -d 1`을 실행해 연속 스냅샷 파일 저장 |
| `htop` | 트리와 스레드를 대화형으로 보기 쉬움 | 별도 설치가 필요할 수 있고 자동 수치 비교에 부적합 | 사람의 보조 진단용 |
| `vmstat` | CPU 대기열, 메모리, swap 등 시스템 전체 상태 확인 | 앱별 수치가 아니어서 원인 프로세스를 특정하지 못함 | 시스템 전체 부하 여부 보조 확인 |
| `pidstat` | PID/스레드별 CPU·메모리를 일정 간격으로 출력 | `sysstat` 설치 여부에 좌우됨 | monitor 대체 또는 교차 확인 |
| `/proc/<PID>/status`, `smaps_rollup` | 커널이 제공하는 메모리 항목, smaps_rollup은 RSS 구성 상세 | 반복 수집·자식 합산은 별도 구현이 필요 | RSS 이상 징후 추가 조사 |

## OOM Crash

### 수집 명령

```bash
PGID=1234
./bin/monitor.sh --pgroup "$PGID" 1 > evidence/exp_oom_before_monitor.csv
grep -E 'MEMORY_LIMIT|Current Heap|Memory limit exceeded|Self-terminating|SELF-TERMINATED' evidence/exp_oom_before.log
ps -eo pid,ppid,pgid,%cpu,%mem,rss,vsz,stat,etime,args | awk -v pgid="$PGID" '$3 == pgid'
```

monitor CSV는 OS가 본 RSS 상승과 종료 시점을 제공하고, 앱 로그는 Heap/MemoryGuard가 제한을 감지한 직접 근거를 제공합니다. `ps`는 실행 시점의 PID 계보와 RSS를 교차 확인합니다. `free -h`는 시스템 전체 메모리만 보여주므로 앱의 증가를 증명하는 데 쓰지 않습니다. `/proc/<PID>/smaps_rollup`은 자세하지만 반복 측정에 번거로워 보조 도구로 둡니다.

Heap과 RSS는 서로 다른 지표입니다. Heap은 앱 자체 계측이고 RSS는 OS가 집계한 resident pages입니다. 두 값이 다르면 둘 다 있는 그대로 기록하며 Heap 상승만으로 RSS 상승 요건을 충족했다고 보지 않습니다.

## CPU 과점유 / Latency

### 수집 명령

```bash
PGID=1234
./bin/monitor.sh --pgroup "$PGID" 0.2 > evidence/exp_cpu_before_monitor.csv
ps -eo pid,ppid,pgid,%cpu,%mem,rss,vsz,stat,etime,args | awk -v pgid="$PGID" '$3 == pgid'
top -H -b -d 0.2 > evidence/exp_cpu_before_top.log
grep -E 'CPU_MAX_OCCUPY|CpuWorker|WATCHDOG|Watchdog|SIGTERM|Threshold Violated' evidence/exp_cpu_before.log
```

monitor의 구간별 CPU로 시간 변화와 그룹 내 PID를 기록합니다. `top -H`는 초당 프로세스/스레드 상태와 시스템 전체 CPU를 연속 수집합니다. 앱 로그는 설정 적용 및 Watchdog/threshold 종료 사유를 확인합니다. `ps %CPU`는 생애 평균이므로 순간 spike 확인에 단독 사용하지 않습니다. `vmstat 1`은 시스템 전체 부하를 보완하지만 앱 PID를 특정하지 못합니다.

## Deadlock

### 수집 명령

```bash
PGID=1234
ps -eo pid,ppid,pgid,%cpu,%mem,rss,vsz,stat,etime,args | awk -v pgid="$PGID" '$3 == pgid'
for pid in $(ps -eo pid=,pgid= | awk -v pgid="$PGID" '$2 == pgid {print $1}'); do
  ps -L -p "$pid" -o pid,tid,ppid,%cpu,%mem,stat,wchan:32
done
top -H -b -d 1 > evidence/exp_deadlock_before_top.log
./bin/monitor.sh --pgroup "$PGID" 1 > evidence/exp_deadlock_before_monitor.csv
tail -n 12 evidence/exp_deadlock_before.log
```

PID/PPID로 프로세스 계보를 찾고, process group 안의 각 PID에 `ps -L -p`를 실행해 PID와 TID, 상태, `wchan`(커널 대기 지점)을 기록합니다. 실험기도 이 방식을 사용했습니다. `top -H`와 monitor CSV는 CPU/MEM 변화 정체를 보완합니다. 앱 로그에서 서로 다른 스레드가 상대방이 보유한 자원을 기다리는 내용까지 연결해야 순환 대기를 주장할 수 있습니다.

`strace -f`는 시스템 호출 대기에는 유용하지만 사용자 공간 mutex 보유 관계를 직접 보여주지 않고 attach 권한과 추적 오버헤드가 필요할 수 있어 필수 수집에는 사용하지 않습니다. `wchan` 또한 커널 대기 지점만 보여주므로 앱 로그와 같이 해석합니다.
