# EigenScript Language Gaps Found During DMG Emulator

---

## GAP-DMG-001: No jump table / dictionary dispatch for opcode decoding
- Found during: CPU core implementation
- Severity: **Critical** — project-blocking
- Status: **RESOLVED** — `dispatch of [table, key, arg]` builtin added
- Description: SM83 has 256+256 opcodes. Linear if/elif chains made dispatch O(N). The `dispatch` builtin provides O(1) lookup into a list of functions.

## GAP-DMG-002: Operator precedence with `of` keyword
- Found during: ALU implementation
- Severity: Medium
- Status: **RESOLVED** — native bitwise operators added
- Description: `bit_and of [a, 0x0F] + bit_and of [b, 0x0F]` needed explicit parens. Now use `(a & 0x0F) + (b & 0x0F)` with proper C-style precedence.

## GAP-DMG-003: Memory growth from temporary Value allocation in tight loops
- Found during: Running Blargg test ROMs (5M+ cycles)
- Severity: **High** — causes OOM on constrained hardware
- Status: **Partially resolved**
- Description: Every `f of [a, b]` call allocates a heap list for the arguments. In a tight emulator loop (~30K instructions/sec, ~10 calls/instruction), this creates ~300K temporary lists/sec that are never freed (refcount stays at 1, no owner to decref). On 4GB RAM, OOM in ~2 minutes.
- Partial fix: (1) Native bitwise operators eliminate 151 list-creating builtin calls. (2) Scratch list stack in AST_RELATION reuses a static list for `of [...]` args, eliminating heap allocation for the dominant call pattern.
- Remaining issue: Individual `make_num()` values for intermediate expression results still leak (~48 bytes each). At ~100K intermediates/sec this adds ~4.6MB/sec. Survives 5M cycles but would OOM on longer runs.
- Proper fix: Either (a) add a generational GC for short-lived Values, (b) extend eval_num_fast to cover all expression positions (not just assignments), or (c) add arena mark/reset per loop iteration for temporary values.

## GAP-DMG-004: No native bitwise operators (RESOLVED)
- Found during: ALU implementation, performance profiling
- Severity: **High** — performance and memory
- Status: **RESOLVED** — &, |, ^, <<, >>, ~ operators added with C-style precedence
- Description: All bitwise operations required `bit_and of [a, b]` builtin calls, each allocating a temporary list. Native operators compile to inline integer ops with zero allocation via the eval_num_fast path.
