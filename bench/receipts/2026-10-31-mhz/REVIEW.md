# Independent collection review

The `build-loop` required a fresh-context read-only critic. Agent
`/root/receipt_critic` read the task brief and collection files, without building,
testing or benchmarking. Review took place before the manifest seal or any
correctness/performance workload.

Round 1 found missing source content checks, sample validation/exclusion
classification, independent tier parity, and interrupted-attempt retention.
Those were added before collection. It also found that unchanged
`k_oracle.sh` removes its raw per-point files. The AOT arm was already blocked
by an actual perf permission refusal, so no substitute AOT number is collected.

Round 2 cleared VM collection after seal, passing correctness gates/parity,
warmups and quiet check. It identified an AOT-only capability-state race. The
refusal-only oracle attempt now has a deliberately nonexistent `K_BIN` interlock;
even if perf access changes, it cannot execute points without raw retention.

Parser/classifier calibration is retained in `calibrate.py` and
`calibration.json`: known-good control and planted PC/cycle/exit/stderr/thermal/
contamination defects, a source-hash mutant, and interrupted-attempt overwrite
refusal. This is a one-time calibration, not a new CI gate.
