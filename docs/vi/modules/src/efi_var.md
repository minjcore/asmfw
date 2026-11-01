# efi_var.asm
[`src/efi_var.asm`](../../../../src/efi_var.asm) — 515 dòng, 8 entry point.

UEFI variables, kept in RAM.

GetVariable, SetVariable, GetNextVariableName and QueryVariableInfo over a fixed array of records. Nothing here is persistent: the flash this firmware runs from is read-only to it, so a variable lives until the machine resets.

## Entry point

| Tên | Dòng | Hợp đồng |
| --- | --- | --- |
| `var_init` | [53](../../../../src/efi_var.asm#L53) | allocate the store and empty it. Returns EAX = 1 if there is one. |
| `var_name_size` | [83](../../../../src/efi_var.asm#L83) | RSI = a CHAR16 name. Returns RAX = its size in bytes with the NUL, or 0 if it does not fit a record. |
| `var_find` | [105](../../../../src/efi_var.asm#L105) | RSI = a CHAR16 name, RDI = a GUID. Returns RAX = the record holding that variable, or 0. Finds hidden variables too; var_visible is the separate question. |
| `var_visible` | [153](../../../../src/efi_var.asm#L153) | RAX = a record. ZF clear if the caller may see it: always before ExitBootServices, and afterwards only with runtime access. |
| `rt_get_variable` | [166](../../../../src/efi_var.asm#L166) | GetVariable(Name, Guid, Attributes OPTIONAL, DataSize, Data OPTIONAL). |
| `rt_set_variable` | [228](../../../../src/efi_var.asm#L228) | SetVariable(Name, Guid, Attributes, DataSize, Data). Attributes of zero, or a DataSize of zero without APPEND_WRITE, deletes. An existing variable can only be rewritten with the attributes it has; the one exception is APPEND_WRITE, which is a request rather than an attribute. |
| `rt_get_next_variable_name` | [386](../../../../src/efi_var.asm#L386) | GetNextVariableName(NameSize, Name, Guid). An empty Name starts the walk; otherwise Name and Guid say where it got to, and are overwritten with the variable after that one. |
| `rt_query_variable_info` | [474](../../../../src/efi_var.asm#L474) | QueryVariableInfo(Attributes, MaximumVariableStorageSize, RemainingVariableStorageSize, MaximumVariableSize). Counted in whole records, since that is how the store is spent: a one-byte variable costs a slot exactly as a full one does. |

## Định nghĩa

Hằng số: 20.

## Phụ thuộc

Gọi vào:

- [mem.asm](mem.md) — `mem_alloc_pages`

Bị gọi bởi:

- [init64.asm](init64.md) — `var_init`

---

Sinh bởi `docs/generate.py`. Kiểm bởi `docs/verify.py`.
