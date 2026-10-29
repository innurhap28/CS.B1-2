# [Bug] Deadlock - 멀티스레드 자원 순환 대기에 의한 무응답

## 1. Description (현상 설명)

명세상 재현 대상은 `MULTI_THREAD_ENABLE=true`일 때 프로세스가 살아 있으면서 두 Worker가 서로 다른 자원을 기다려 진행을 멈추는 현상이다. 현재 저장소의 증거 파일에는 이 상황을 보여주는 로그가 있으나 `exp_cpu_before.log`라는 CPU 실험 파일에 잘못 들어가 있다. 이름이 맞는 Deadlock 증거 세트는 일관성이 없어 결과를 확정할 수 없다.

## 2. Evidence & Logs (증거 자료)

프로세스 계보는 `ps --pgroup <PGID> ... --forest`, 스레드별 상태와 대기 채널은 `ps --pgroup <PGID> -L ... wchan`, 부하 정체는 `top -H`와 process group monitor CSV로 확인한다. 마지막 `WAITING/BLOCKED` 앱 로그와 함께 대조한다. `strace` 등 대안의 장단점 및 명령 선택 근거는 [리소스 관측 명령과 선택 이유](command_reference.md#deadlock)에 정리했다.

### 체크인된 Deadlock 증거의 불일치

- [`evidence/exp_cpu_before.log`](../evidence/exp_cpu_before.log)에 `MULTI_THREAD_ENABLE=True` 설정과 다음 두 대기 로그가 있다.

```text
2026-09-25 00:11:46,545 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
2026-09-25 00:11:46,546 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
```

- [`evidence/exp_deadlock_before.log`](../evidence/exp_deadlock_before.log)은 `MULTI_THREAD_ENABLE=True`지만 로그에서 CpuWorker가 시작해 진행한다. 위 `WAITING/BLOCKED` 줄은 포함되어 있지 않다.
- [`evidence/exp_deadlock_threads.log`](../evidence/exp_deadlock_threads.log)은 헤더만 반복되어 Thread별 상태 증거가 아니다.
- [`evidence/exp_deadlock_ps.log`](../evidence/exp_deadlock_ps.log)에는 프로세스 경로가 두 번 나타나지만, 같은 실행의 PID와 `WAITING` 로그를 연계할 자료가 부족하다.

따라서 로그의 순환 대기 관계 자체는 관찰되지만, 현재 파일 구성만으로 PID 생존 및 스레드 대기 상태까지 한 실행에 연결해 완전한 재현 증거라고 할 수는 없다.

## 3. Root Cause Analysis (원인 분석)

잘못 저장된 `exp_cpu_before.log`의 기록에서는 Worker-Thread-1이 `Shared_Memory_A`를 획득한 뒤 `Socket_Pool_B`를 기다리고, Worker-Thread-2가 `Socket_Pool_B`를 획득한 뒤 `Shared_Memory_A`를 기다린다. 각 스레드가 상대가 가진 자원을 기다리는 순환 대기가 형성되어 있다.

이 상태에서는 자원 상호 배제, 자원 보유 중 추가 자원 대기, 선점 불가, 순환 대기가 함께 성립할 수 있다. 다만 이는 해당 로그만을 바탕으로 한 원인 추론이며, 파일명과 관제 상태가 일치하지 않아 재실행으로 검증해야 한다.

## 4. Workaround & Verification (조치 및 검증)

명세의 비교 방법은 `MULTI_THREAD_ENABLE=true`와 `false`를 각각 실행해 로그 및 스레드 상태를 대조하는 것이다. 현재 `exp_deadlock_after.log`는 `false` 설정에서 CpuWorker 진행 로그가 있는 반면 `exp_deadlock_after_threads.log`도 헤더만 있어, After 실행이 Deadlock을 회피했다는 결론을 프로세스/스레드 관측으로 확인하지 못했다.

실험 실행기를 수정하여 Before/After 각각에 독립적인 로그, PID/PGID metadata, process group 상태, 20초 시점의 모든 그룹 멤버에 대한 `ps -L` 및 `top -H` 결과를 저장하도록 했다. OrbStack CLI는 설치되어 있지만 현재 `orbctl status`가 `Stopped`이고 VM 시작 시 `VM exited unexpectedly`가 발생해 재측정하지 못했다. VM이 정상 실행되면 `scripts/01_run_experiments.sh`를 실행해 증거 세트를 갱신해야 최종 검증을 완료할 수 있다.
