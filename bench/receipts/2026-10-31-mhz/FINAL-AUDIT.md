# Independent final audit — PASS

A fresh-context, read-only reviewer (`/root/final_receipt_audit`) read the task
brief, receipt, BASELINE and raw evidence. It ran only small arithmetic/file
checks: no builds, runtime/native binaries, suites, benchmarks or retries.
No material findings; no files modified by the reviewer.

The reviewer independently verified:

- All 21 started/completed samples: status 0, 500,004 actual cycles, exact
  normalized stdout and stderr parity, no timeout/exclusion or orphaned start.
  The CSV agrees with raw JSON/stdout/stderr. Seven samples per VM/control arm.
- Wall medians: interpreter 0.542594246 s, JIT 0.564605968 s, identical-JIT
  repeat 0.566053894 s. MHz medians: 0.921506270, 0.885580437, 0.883315185.
  All published ranges, exclusive median-of-halves quartiles/IQRs and paired
  statistics agree with independent calculation.
- Interpreter→JIT paired wall median +4.0567555%. A/A median −0.7250474%,
  IQR 5.1608515 percentage points, median/max absolute delta
  2.0256603% / 6.1971322%. A/A binary, argv, cwd and environment are identical;
  counterbalanced order and no sample overlap are confirmed.
- Manifest checksum and frozen files match. Source changes after seal are
  confined to the requested BASELINE.md documentation update. Chronology:
  seal 16:08:22 UTC → final correctness 17:08:39 → final warmup 17:09:02 →
  quiet check 17:09:13 → first sample 17:09:14.
- Both VM arms have unit passes, all 12 CPU ROM child passes and all four
  timing ROM child passes. Each CPU gate reports 456,000,068 total cycles.
  JIT diagnostic proves the selected modes.
- Native CPU-test compilation refusal, two gate timeouts, and two 2M parity
  timeouts are retained and described accurately. AOT remains unchecked with
  zero valid speed samples, no native MHz/K claim and explicit #335/#89 links.
- `k_budget.txt` exactly matches its frozen hash and ouroboros Git HEAD:
  K_TOTAL 182.1, tolerance 8%, BASELINE 0 / WINDOW 2M. #333 remains separate.
- Important local links resolve. Historical/cross-tier scope, timing
  resolution, observed residual activity and A/A noise caveats are explicit.

The builder subsequently persisted this audit and generated/verified
`SHA256SUMS`; no measurement was rerun.
