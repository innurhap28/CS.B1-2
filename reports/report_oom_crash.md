# [Bug] OOM Crash - MemoryGuard 메모리 임계치 초과에 의한 프로세스 강제 종료

## 1. Description (현상 설명)

* `agent-leak-app` 실행 후 `MEMORY_LIMIT=50MB` 환경에서 MemoryWorker가 측정한 Heap 사용량이 `25MB`에서 `50MB`까지 증가했다.
* Heap 사용량이 설정된 메모리 제한인 `50MB`에 도달하자 `MemoryGuard`가 메모리 제한 초과를 감지했다.
* 이후 MemoryGuard가 `Self-terminating process`를 수행하여 프로세스가 종료되었다.
* 동일한 프로그램을 `MEMORY_LIMIT=512MB`로 변경하여 재실행한 결과, 제공된 관측 구간에서는 메모리 제한 초과 및 프로세스 자체 종료가 발생하지 않았다.
* 따라서 `MEMORY_LIMIT`을 증가시키면 동일한 메모리 사용 증가가 발생하더라도 MemoryGuard의 종료 조건에 도달하는 시점을 늦출 수 있음을 확인했다.

## 2. Evidence & Logs (증거 자료)

### 2.1 Before - MEMORY_LIMIT=50MB

프로그램 실행 시 `MEMORY_LIMIT=50MB`가 적용되어 있었다.

```text
MEMORY_LIMIT=50MB, CPU_MAX_OCCUPY=100%, MULTI_THREAD_ENABLE=True
```

부트 이후 MemoryWorker의 Heap 사용량이 다음과 같이 증가했다.

```text
2026-09-25 00:10:24,532 [INFO] [MemoryWorker] Current Heap: 25MB
2026-09-25 00:10:27,587 [INFO] [MemoryWorker] Current Heap: 50MB
```

Heap이 설정된 제한값에 도달한 직후 MemoryGuard의 제한 초과 및 프로세스 종료 로그가 발생했다.

```text
2026-09-25 00:10:27,587 [CRITICAL] [MemoryGuard] Memory limit exceeded (50MB >= 50MB) / (Recommend Over 256MB)
2026-09-25 00:10:27,587 [CRITICAL] [MemoryGuard] Self-terminating process 4423 to prevent system instability.
```

따라서 Before 실행에서는 **Heap 25MB → 50MB 증가 → MemoryGuard 제한 초과 감지 → 프로세스 자체 종료**의 순서를 확인할 수 있다.

### 2.2 Before - monitor.sh 관제 결과

Before 실행의 프로세스 관제 결과는 다음과 같다.

```text
timestamp,pid,cpu_percent,rss_kb,vsz_kb
2026-09-25 00:10:22,4416,0.0,2068,2904
2026-09-25 00:10:23,4416,8.7,2200,2908
2026-09-25 00:10:24,4416,4.4,2200,2908
2026-09-25 00:10:25,4416,2.9,2200,2908
2026-09-25 00:10:26,4416,2.2,2200,2908
2026-09-25 00:10:27,4416,1.7,2200,2908
PROCESS_EXITED,pid=4416
```

RSS는 `2068KB → 2200KB`로 증가한 이후 관측 구간 동안 `2200KB`로 유지되었다. 이후 `PROCESS_EXITED`가 기록되었다.

이 관제 결과만으로는 메모리 누수나 종료 원인을 직접 판단할 수 없으며, 위의 프로그램 실행 로그와 함께 분석해야 한다. 프로그램 로그에서는 Heap이 `50MB`에 도달한 시점에 MemoryGuard의 제한 초과 및 자체 종료가 명시적으로 기록되어 있다.

### 2.3 After - MEMORY_LIMIT=512MB

환경변수를 `50MB`에서 `512MB`로 변경하여 동일한 프로그램을 다시 실행했다.

```text
MEMORY_LIMIT=512MB, CPU_MAX_OCCUPY=100%, MULTI_THREAD_ENABLE=True
```

부트 과정에서 변경된 메모리 제한이 정상적으로 적용되었으며 다음과 같이 확인되었다.

```text
[ MEMORY ] Limit: 512MB        [ OK ]
```

After 실행에서는 제공된 로그 관측 구간 동안 MemoryGuard의 메모리 제한 초과 로그가 발생하지 않았다.

대신 CPU Worker가 정상적으로 실행되고 있는 것이 확인되었다.

```text
2026-09-25 00:11:04,477 [INFO] [CpuWorker] Current Load: 5.00%
2026-09-25 00:11:07,597 [INFO] [CpuWorker] Current Load: 5.94%
2026-09-25 00:11:10,718 [INFO] [CpuWorker] Current Load: 7.43%
2026-09-25 00:11:13,838 [INFO] [CpuWorker] Current Load: 11.17%
2026-09-25 00:11:16,959 [INFO] [CpuWorker] Current Load: 11.88%
```

### 2.4 After - monitor.sh 관제 결과

After 실행의 관제 결과는 다음과 같다.

```text
timestamp,pid,cpu_percent,rss_kb,vsz_kb
2026-09-25 00:11:02,4450,0.0,2060,2904
2026-09-25 00:11:03,4450,5.8,2192,2908
2026-09-25 00:11:04,4450,2.9,2192,2908
2026-09-25 00:11:05,4450,1.9,2192,2908
2026-09-25 00:11:06,4450,1.4,2192,2908
2026-09-25 00:11:07,4450,1.1,2192,2908
2026-09-25 00:11:08,4450,0.9,2192,2908
2026-09-25 00:11:09,4450,0.8,2192,2908
2026-09-25 00:11:10,4450,0.7,2192,2908
2026-09-25 00:11:11,4450,0.6,2192,2908
2026-09-25 00:11:12,4450,0.5,2192,2908
2026-09-25 00:11:13,4450,0.5,2192,2908
2026-09-25 00:11:14,4450,0.4,2192,2908
2026-09-25 00:11:15,4450,0.4,2192,2908
2026-09-25 00:11:16,4450,0.4,2192,2908
```

After 실행에서는 관측이 종료된 시점까지 `PROCESS_EXITED`가 기록되지 않았으며, RSS 역시 `2060KB → 2192KB`로 증가한 후 `2192KB`로 유지되었다.

따라서 제공된 관측 구간에서는 `MEMORY_LIMIT=512MB` 환경에서 프로세스가 종료되지 않고 계속 실행되는 것을 확인할 수 있다.

## 3. Root Cause Analysis (원인 분석)

### 3.1 직접적인 종료 원인

Before 실행의 직접적인 종료 원인은 **MemoryGuard의 메모리 제한 초과 감지**이다.

실행 로그에서 다음과 같은 순서가 명확하게 확인된다.

```text
Current Heap: 25MB
        ↓
Current Heap: 50MB
        ↓
Memory limit exceeded (50MB >= 50MB)
        ↓
Self-terminating process
```

즉, `MEMORY_LIMIT=50MB` 환경에서 MemoryWorker가 측정한 Heap 사용량이 `50MB`에 도달했고, MemoryGuard가 이를 제한 초과로 판단하여 프로세스를 자체 종료했다.

이번 로그에서는 Linux의 OOM Killer가 프로세스를 종료했다는 증거는 확인되지 않는다. 오히려 프로그램 자체 로그에서 `MemoryGuard`가 `Self-terminating process`를 명시하고 있으므로, **이번 장애의 종료 메커니즘은 운영체제의 OOM Killer가 아니라 애플리케이션 내부 MemoryGuard의 보호 동작**으로 판단한다.

### 3.2 메모리 사용량 증가에 대한 분석

MemoryWorker 로그에서는 짧은 시간 동안 Heap 사용량이 다음과 같이 증가했다.

```text
25MB → 50MB
```

따라서 애플리케이션 실행 중 메모리 사용량을 증가시키는 동작이 존재한다고 볼 수 있다.

다만 현재 확보된 로그만으로는 해당 메모리 증가가 정확히 어떤 객체나 코드에 의해 발생했는지 확인할 수 없다. 따라서 특정 객체의 메모리 누수라고 단정하기보다는, **지속적인 메모리 할당 또는 메모리 누수 가능성으로 인해 Heap 사용량이 증가하는 현상**으로 기술하는 것이 적절하다.

또한 `monitor.sh`의 RSS 값은 Before에서 `2068KB → 2200KB`, After에서 `2060KB → 2192KB`로 증가한 뒤 일정하게 유지된다. 따라서 이번 관제 CSV만으로는 프로세스의 RSS가 시간에 따라 선형적으로 계속 증가하는 현상을 확인할 수 없다.

따라서 이번 장애의 근거는 `monitor.sh`의 RSS 상승 자체보다는 **MemoryWorker의 Heap 증가와 MemoryGuard의 명시적인 제한 초과 로그**에 둔다.

### 3.3 OS 및 메모리 보호 관점

프로세스의 메모리 사용량이 계속 증가하면 시스템에서 사용할 수 있는 메모리가 감소하고 다른 프로세스의 실행에도 영향을 줄 수 있다.

이 프로그램은 이러한 상황을 방지하기 위해 `MemoryGuard`를 사용하며, 설정된 `MEMORY_LIMIT`에 도달했을 때 프로세스를 자체 종료하는 보호 정책을 수행한다.

따라서 이번 장애는 다음과 같은 흐름으로 정리할 수 있다.

```text
애플리케이션의 메모리 사용 증가
        ↓
Heap 사용량 증가
        ↓
MEMORY_LIMIT=50MB 도달
        ↓
MemoryGuard가 제한 초과 감지
        ↓
프로세스 자체 종료
```

## 4. Workaround & Verification (조치 및 검증)

### 4.1 조치 내용

`MEMORY_LIMIT` 환경변수를 다음과 같이 변경했다.

```text
Before: 50MB
After:  512MB
```

`MEMORY_LIMIT=512MB`로 변경한 뒤 프로그램을 다시 실행하여 동작을 확인했다.

### 4.2 Before & After 비교

| 항목                       |          Before |            After |
| ------------------------ | --------------: | ---------------: |
| `MEMORY_LIMIT`           |            50MB |            512MB |
| MemoryGuard 상태           |         Warning |               OK |
| MemoryWorker Heap        |     25MB → 50MB |         해당 로그 없음 |
| Memory limit exceeded    |              발생 |     제공된 구간에서 미발생 |
| Self-terminating process |              발생 |     제공된 구간에서 미발생 |
| monitor RSS              | 2068KB → 2200KB |  2060KB → 2192KB |
| `PROCESS_EXITED`         |              발생 |     제공된 구간에서 미발생 |
| 관측 결과                    |  메모리 제한 도달 후 종료 | 관측 종료 시점까지 실행 유지 |

### 4.3 검증 결과

`MEMORY_LIMIT`을 `50MB`에서 `512MB`로 증가시킨 결과, Before 실행에서는 Heap이 `50MB`에 도달하자 MemoryGuard가 프로세스를 종료했지만, After 실행에서는 제공된 관측 구간 동안 메모리 제한 초과 및 자체 종료가 발생하지 않았다.

따라서 `MEMORY_LIMIT` 증가가 MemoryGuard의 종료 조건을 완화하여 **프로세스의 생존 시간을 증가시키는 효과가 있음**을 확인했다.

다만 이것은 메모리 사용량 증가의 근본 원인을 해결한 것이 아니라 **메모리 제한을 높인 임시 조치(Workaround)**이다. 실제 메모리 사용 증가가 계속된다면 더 높은 제한에서도 동일한 문제가 재발할 가능성이 있으므로, 근본적으로는 메모리 할당 및 객체 생명주기를 분석하여 불필요한 메모리 사용이 지속되는 원인을 해결해야 한다.

또한 이번 After 관측은 `00:11:02~00:11:16`의 제한된 구간이므로, 이를 근거로 장시간 안정성을 확정하기보다는 **"제공된 관측 구간 동안 프로세스가 종료되지 않았다"**고 판단하는 것이 적절하다.
