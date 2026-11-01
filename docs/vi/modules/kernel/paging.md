# paging.asm
[`kernel/paging.asm`](../../../../kernel/paging.asm) — 84 dòng, 1 entry point.

Address spaces.

Every task gets its own. They agree on everything except one entry: the low 4 GiB is identity mapped as supervisor in all of them, so the kernel is reachable no matter which one is loaded, and exactly one 2 MiB page carries U/S — the window belonging to whichever task the space was built for.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `paging_build` | [22](../../../../kernel/paging.asm#L22) | RDI = a PT_PAGE_COUNT-page region to build in, RSI = the user window to expose, or 0 for none. Returns RAX = the PML4 to load into CR3. Does not load it. |

## Phụ thuộc

Bị gọi bởi:

- [kernel.asm](kernel.md) — `paging_build`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.
