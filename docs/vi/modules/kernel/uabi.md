# uabi.inc
[`kernel/uabi.inc`](../../../../kernel/uabi.inc) — 30 dòng, 0 entry point.

The contract between the kernel and a program.

Included by both sides. It is the only thing they are allowed to agree on: a program is a flat binary loaded at the base of its window with nothing resolved for it, so everything else it knows it has to be told at entry.

## Định nghĩa

Hằng số: 10.

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.
