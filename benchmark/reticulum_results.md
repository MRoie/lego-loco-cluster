# Reticulum Benchmark Results

Generated: 2026-02-22T20:58:43Z

## Summary

- ✅ Baseline RTT: 0.040 ms (target < 50 ms)
- 🔒 Encrypted RTT: 0.040 ms
-    Encryption overhead: +0.0%
- 📊 Throughput: 24486.6 pps / 50148.5 kbps
- 📉 Jitter: 0.002 ms

## Detailed Results

| Test | Payload | Peers | Msgs | Lost | RTT mean | RTT p95 | RTT p99 | Jitter | Throughput |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| rtt_payload | 64 B | 1 | 200 | 0 | 0.040 ms | 0.051 ms | 0.098 ms | — | — |
| rtt_payload | 256 B | 1 | 200 | 0 | 0.040 ms | 0.049 ms | 0.067 ms | — | — |
| rtt_payload | 512 B | 1 | 200 | 0 | 0.041 ms | 0.055 ms | 0.059 ms | — | — |
| rtt_payload | 1024 B | 1 | 200 | 0 | 0.035 ms | 0.049 ms | 0.056 ms | — | — |
| rtt_payload | 4096 B | 1 | 200 | 0 | 0.043 ms | 0.057 ms | 0.068 ms | — | — |
| encrypted_rtt | 256 B | 1 | 200 | 0 | 0.040 ms | 0.053 ms | 0.069 ms | — | — |
| encrypted_rtt | 1024 B | 1 | 200 | 0 | 0.041 ms | 0.046 ms | 0.067 ms | — | — |
| throughput | 256 B | 1 | 122433 | 0 | — | — | — | — | 24486.6 pps |
| throughput | 1024 B | 1 | 218927 | 1 | — | — | — | — | 43785.0 pps |
| throughput | 4096 B | 1 | 155688 | 4 | — | — | — | — | 31136.7 pps |
| concurrent | 256 B | 1 | 66 | 0 | 0.037 ms | 0.052 ms | 0.083 ms | — | — |
| concurrent | 256 B | 3 | 198 | 0 | 0.098 ms | 0.195 ms | 0.317 ms | — | — |
| concurrent | 256 B | 9 | 594 | 0 | 0.305 ms | 0.455 ms | 0.831 ms | — | — |
| jitter | 256 B | 1 | 200 | 0 | 0.042 ms | 0.045 ms | 0.074 ms | 0.002 ms | — |

## Feasibility Verdict

| Criterion | Target | Result | Status |
| --- | --- | --- | --- |
| Mean RTT | < 50 ms | 0.040 ms | ✅ PASS |
| Packet loss | < 1% | 0.0% | ✅ PASS |
| Throughput | > 1000 pps | 24486.6 pps | ✅ PASS |

