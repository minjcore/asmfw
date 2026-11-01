# lisp.asm
[`kernel/progs/lisp.asm`](../../../../../kernel/progs/lisp.asm) — 2053 dòng, 53 entry point.

A Lisp, in ring 3, with a garbage collector.

A small Scheme-flavoured Lisp: integers, symbols, conses, closures, and the special forms quote, if, define, lambda, let, begin, set!, cond, and, or. It runs a demo script embedded below, prints what each expression evaluates to, and then reads expressions from the keyboard until nobody types. Values are 64-bit words.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `_start` | [106](../../../../../kernel/progs/lisp.asm#L106) | RDI = task id, RSI = this window. Lays the window out, interns the special forms and primitives, and runs the demo and then the REPL. |
| `demo_next` | [186](../../../../../kernel/progs/lisp.asm#L186) | evaluate the next demo expression; where an error in one resumes. |
| `repl` | [231](../../../../../kernel/progs/lisp.asm#L231) | prompt, read a balanced line, evaluate it; where an error resumes. |
| `fatal` | [354](../../../../../kernel/progs/lisp.asm#L354) | where an error goes before there is a REPL to return to. |
| `show_result` | [361](../../../../../kernel/progs/lisp.asm#L361) | RAX = a value. Prints it as "task 4   = value". |
| `lisp_error` | [376](../../../../../kernel/progs/lisp.asm#L376) | RSI = message, RDI = the offending value or 0. Does not return: it prints, throws the stack away, and resumes the top level. |
| `eval` | [405](../../../../../kernel/progs/lisp.asm#L405) | RDI = an expression, RSI = an environment. Returns RAX. An environment is an association list of (symbol . value) pairs, searched before the symbol's global value. Every form whose last step is to evaluate something else — if, begin, a lambda body, let, cond, and, or — does it by replacing the expression and jumping back to the top rather than calling, so a loop written as tail recursion runs in constant stack. |
| `evlis` | [752](../../../../../kernel/progs/lisp.asm#L752) | RDI = a list of expressions, RSI = an environment. Returns RAX = a fresh list of their values, in order. |
| `bind` | [793](../../../../../kernel/progs/lisp.asm#L793) | RDI = parameters, RSI = arguments, RDX = the closure's environment. Returns RAX = that environment extended with one pair per parameter. A parameter list ending in a symbol rather than nil — (a b . rest), or a lone symbol as the whole list — binds that symbol to whatever arguments are left. |
| `lookup_pair` | [848](../../../../../kernel/progs/lisp.asm#L848) | RDI = a symbol, RSI = an environment. Returns RAX = its (symbol . value) pair, or 0 if only the global applies. |
| `make_lambda` | [866](../../../../../kernel/progs/lisp.asm#L866) | RDI = parameters, RSI = body, RDX = environment. |
| `cons` | [877](../../../../../kernel/progs/lisp.asm#L877) | RDI = car, RSI = cdr. Returns RAX. Preserves everything else. |
| `scar` | [888](../../../../../kernel/progs/lisp.asm#L888) | RDI = anything. Its car if it is a cons, nil if it is anything else, so that a malformed form reads as one with nils in it. |
| `scdr` | [897](../../../../../kernel/progs/lisp.asm#L897) | RDI = anything. Its cdr if it is a cons, nil otherwise. |
| `alloc` | [915](../../../../../kernel/progs/lisp.asm#L915) | AL = a tag. Returns RAX = an object with that tag and its fields zeroed. Preserves every other register, which is what makes it safe to collect from inside: whatever the caller is holding is still in a register, and gc pushes them all before it scans the stack. |
| `gc` | [950](../../../../../kernel/progs/lisp.asm#L950) | mark from the roots and the stack, then sweep the heap into a free list. |
| `mark` | [1036](../../../../../kernel/progs/lisp.asm#L1036) | RDI = any word. If it is the address of an object in the heap, mark it and everything it reaches. Anything else — an integer, a return address, a stale value — is ignored, which is all conservatism means. Clobbers RAX and RDI. Recurses on cars and loops on cdrs, so a long list costs no stack. |
| `intern` | [1086](../../../../../kernel/progs/lisp.asm#L1086) | RSI = a name, RCX = its length. Returns RAX = the one symbol with that name, made if there was none. |
| `intern_cstr` | [1146](../../../../../kernel/progs/lisp.asm#L1146) | RSI = a NUL-terminated name. Returns RAX = its symbol. |
| `skip_ws` | [1167](../../../../../kernel/progs/lisp.asm#L1167) | step over blanks and ; comments. Returns AL = the next character, not consumed, or 0 at the end. |
| `is_delim` | [1197](../../../../../kernel/progs/lisp.asm#L1197) | AL = a character. ZF set if it ends a token. |
| `read_expr` | [1216](../../../../../kernel/progs/lisp.asm#L1216) | read one expression. Returns RAX. |
| `read_list` | [1283](../../../../../kernel/progs/lisp.asm#L1283) | after the "(". Returns RAX = the list, having eaten the ")". |
| `parse_int` | [1348](../../../../../kernel/progs/lisp.asm#L1348) | RSI = a token, RCX = its length. CF clear and RAX = the integer as a value if the token is one; CF set if it is not. |
| `print` | [1401](../../../../../kernel/progs/lisp.asm#L1401) | RDI = a value, appended to the output line. |
| `out_reset` | [1478](../../../../../kernel/progs/lisp.asm#L1478) | start a new, empty line. |
| `out_char` | [1483](../../../../../kernel/progs/lisp.asm#L1483) | AL = a character, appended. |
| `out_str` | [1498](../../../../../kernel/progs/lisp.asm#L1498) | RSI = a NUL-terminated string, appended. |
| `out_src` | [1513](../../../../../kernel/progs/lisp.asm#L1513) | RSI = source text, RCX = its length; line breaks become spaces. |
| `out_dec` | [1535](../../../../../kernel/progs/lisp.asm#L1535) | RAX = a signed integer, appended in decimal. |
| `out_flush` | [1576](../../../../../kernel/progs/lisp.asm#L1576) | write the line as it stands, without ending it, and empty it. |
| `out_line` | [1588](../../../../../kernel/progs/lisp.asm#L1588) | end the line and write it. |
| `write_bytes` | [1601](../../../../../kernel/progs/lisp.asm#L1601) | RSI = bytes, RCX = how many. Preserves every register; the system call takes RCX, R11 and R10, so they are saved here instead of at every caller. |
| `next_int` | [1628](../../../../../kernel/progs/lisp.asm#L1628) | RBX = an argument list. Returns RAX = its first element as a plain integer, and advances RBX past it. |
| `truth_if_zf` | [1642](../../../../../kernel/progs/lisp.asm#L1642) | ZF set means true. Returns RAX = t or nil. |
| `p_add` | [1650](../../../../../kernel/progs/lisp.asm#L1650) | (+ n...): the sum, 0 for none. |
| `p_mul` | [1667](../../../../../kernel/progs/lisp.asm#L1667) | (* n...): the product, 1 for none. |
| `p_sub` | [1684](../../../../../kernel/progs/lisp.asm#L1684) | (- n) negates; (- n m...) subtracts the rest from the first. |
| `p_quotient` | [1705](../../../../../kernel/progs/lisp.asm#L1705) | (quotient n m): truncated toward zero. |
| `p_remainder` | [1725](../../../../../kernel/progs/lisp.asm#L1725) | (remainder n m): with the sign of n, as idiv leaves it. |
| `divide_by_zero` | [1745](../../../../../kernel/progs/lisp.asm#L1745) | the error both divisions share. Does not return. |
| `p_eq` | [1777](../../../../../kernel/progs/lisp.asm#L1777) | (eq? a b): the same object, or the same integer. |
| `p_cons` | [1792](../../../../../kernel/progs/lisp.asm#L1792) | (cons a b): a fresh pair. |
| `p_car` | [1809](../../../../../kernel/progs/lisp.asm#L1809) | (car l): the first element; (car nil) is nil. |
| `p_cdr` | [1819](../../../../../kernel/progs/lisp.asm#L1819) | (cdr l): the rest; (cdr nil) is nil. |
| `not_a_list` | [1829](../../../../../kernel/progs/lisp.asm#L1829) | RAX = the offender. Does not return. |
| `p_list` | [1833](../../../../../kernel/progs/lisp.asm#L1833) | (list x...): the argument list itself, which evlis made fresh. |
| `p_null` | [1838](../../../../../kernel/progs/lisp.asm#L1838) | (null? x) and (not x): t for nil, nil for anything else. |
| `p_pair` | [1844](../../../../../kernel/progs/lisp.asm#L1844) | (pair? x): t for a cons. |
| `p_number` | [1854](../../../../../kernel/progs/lisp.asm#L1854) | (number? x): t for an integer. |
| `p_symbol` | [1865](../../../../../kernel/progs/lisp.asm#L1865) | (symbol? x): t for a symbol. |
| `p_display` | [1876](../../../../../kernel/progs/lisp.asm#L1876) | (display x...): print the arguments on a line of their own. Returns nil. |
| `p_gc` | [1899](../../../../../kernel/progs/lisp.asm#L1899) | (gc): collect now. Returns how many cells are free. |

## Định nghĩa

Macro: `JNCONS`, `OUTS`, `ERROR`, `COMPARE`

Hằng số: 31.

Dữ liệu và state: `n_nil`, `n_t`, `n_quote`, `n_if`, `n_define`, `n_lambda`, `n_let`, `n_begin`, `n_set`, `n_cond`, `n_and`, `n_or`, `n_else`, `n_add`, `n_sub`, `n_mul`, `n_quotient`, `n_remainder`, và 58 nữa

## Phụ thuộc

Gọi vào:

- [ulib.inc](ulib.md) — `u_exit`, `u_read`, `u_write`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.
