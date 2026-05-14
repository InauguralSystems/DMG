# EigenScript Language Gaps Found During DMG Emulator

Each GAP-DMG-NNN is a language primitive that landed upstream because the
emulator demanded it. This is the whole point of DMG.

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
- Status: **RESOLVED**
- Description: Every `f of [a, b]` call allocates a heap list for the arguments. In a tight emulator loop (~30K instructions/sec, ~10 calls/instruction), this creates ~300K temporary lists/sec that are never freed (refcount stays at 1, no owner to decref). On 4GB RAM, OOM in ~2 minutes.
- Fix: (1) Native bitwise operators eliminate 151 list-creating builtin calls. (2) Scratch list stack in AST_RELATION reuses a static list for `of [...]` args. (3) eval_num_fast extended with comparison operators (<, >, <=, >=, ==, !=), enabling zero-allocation loop conditions. (4) Safe val_decref on fresh allocations from AST_BINOP/UNARY/RELATION in loop conditions, list comprehension filters, and match patterns.

## GAP-DMG-004: No native bitwise operators
- Found during: ALU implementation, performance profiling
- Severity: **High** — performance and memory
- Status: **RESOLVED** — &, |, ^, <<, >>, ~ operators added with C-style precedence
- Description: All bitwise operations required `bit_and of [a, b]` builtin calls, each allocating a temporary list. Native operators compile to inline integer ops with zero allocation via the eval_num_fast path.

## GAP-DMG-005: No compound assignment operators
- Found during: CPU flag manipulation, cycle accumulation
- Severity: **Medium** — code verbosity
- Status: **RESOLVED** — +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>= added
- Description: `cpu.f is cpu.f | FLAG_Z` and `total_cycles is total_cycles + cycles` repeated everywhere. Compound operators desugar in the parser to existing AST nodes, getting the eval_num_fast path for free. Works on simple variables, dot-access, and index-access.

## GAP-DMG-006: No sign extension builtin
- Found during: Opcode decoder (relative jumps, SP offset)
- Severity: **Medium** — boilerplate in hot path
- Status: **RESOLVED** — `sign_extend of [val, bits]` builtin added
- Description: `sign8(val)` helper was defined in EigenScript and called 7+ times. Sign extension is a fundamental numeric operation that belongs in the runtime.

## GAP-DMG-007: No sort builtin
- Found during: PPU sprite X-priority sorting
- Severity: **Low** — 10-element sort per frame
- Status: **RESOLVED** — `sort of list` C builtin using qsort
- Description: Manual 8-line insertion sort replaced with in-place C qsort. Pure EigenScript sort in lib/sort.eigs still available for custom comparators.

## GAP-DMG-008: VAL_BUFFER not iterable
- Found during: PPU implementation, ROM loading
- Severity: **High** — forced PPU rewrite in C
- Status: **RESOLVED** — `for x in buffer:` and comprehensions now work
- Description: VAL_BUFFER (compact double* array) only supported indexing. `for x in buf:`, list comprehensions, and what/who interrogation rejected buffers. This forced ppu_render_frame to be written in C instead of pure EigenScript. Buffer is now a first-class iterable type.
