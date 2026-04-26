# EigenScript Language Gaps Found During DMG Emulator

---

## GAP-DMG-001: No jump table / dictionary dispatch for opcode decoding
- Found during: CPU core implementation
- Severity: **Critical** — project-blocking
- Description: The SM83 CPU has 256 opcodes + 256 CB-prefixed opcodes. The only way to dispatch in EigenScript is a linear if/elif chain or match/case. The tree-walking interpreter evaluates every condition sequentially — for opcode 0x06 (LD B, d8), it checks ~20 conditions before finding a match. For opcodes in the 0xF0+ range, it checks all ~200 conditions. A single opcode dispatch takes longer than the entire instruction should.
- Workaround: None viable. A 256-element array of functions would work if EigenScript supported callable values in arrays, but `get_at` + function call hasn't been tested. Even then, building the dispatch table is expensive.
- Proper fix: Either (a) add a native `dispatch of [table, key]` builtin that does O(1) lookup into a dict/array of functions, (b) compile match/case to a jump table when cases are integer constants, or (c) add a bytecode VM that can represent switch dispatch natively.
- Impact: Without this, no interpreter-class project (emulators, VMs, parsers with large token sets) is viable in EigenScript.

## GAP-DMG-002: Operator precedence with `of` keyword
- Found during: ALU implementation
- Severity: Medium
- Description: `bit_and of [a, 0x0F] + bit_and of [b, 0x0F]` parses as `bit_and of [a, 0x0F + bit_and of [b, 0x0F]]` because `of` binds to the entire right-hand expression. Every arithmetic expression combining builtin results needs explicit parentheses: `(bit_and of [a, 0x0F]) + (bit_and of [b, 0x0F])`.
- Workaround: Add parentheses around every `builtin of [...]` in arithmetic expressions.
- Proper fix: Tighten `of` binding precedence so `f of x + g of y` parses as `(f of x) + (g of y)`.
