#!/bin/sh
# ============================================================================
# smoke.sh -- boot both disks and assert the log says what it said before
#
# This project has no test framework and cannot have one in the usual sense:
# the unit under test is a machine at reset. What it has instead is a serial
# transcript, and the landmarks below are the assertions.
#
# Nothing here exits QEMU. The firmware halts, the kernel halts -- both by
# design -- so every boot runs under a timeout, and a boot that has to be
# killed before its last landmark arrives is a failure.
#
# Usage:  make check          both disks, plus the OVMF control if present
#         make check-fw       the firmware and its payload only
#         make check-kernel   the kernel only
# ============================================================================
set -eu

BUILD=${BUILD:-build}
LOGS=$BUILD/logs
QEMU=${QEMU:-qemu-system-x86_64}
FW=$BUILD/FIRMWARE.fd
FW_SECONDS=${FW_SECONDS:-25}
OVMF_CODE=${OVMF_CODE:-/opt/homebrew/share/qemu/edk2-x86_64-code.fd}
OVMF_VARS=${OVMF_VARS:-/opt/homebrew/share/qemu/edk2-i386-vars.fd}
K_SECONDS=${K_SECONDS:-40}

# GNU timeout: coreutils installs it as gtimeout on macOS.
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT=gtimeout
elif timeout --version >/dev/null 2>&1;  then TIMEOUT=timeout
else echo "smoke: need GNU timeout (brew install coreutils)"; exit 1; fi

mkdir -p "$LOGS"
fails=0
checks=0

boot() {                                    # boot <disk> <seconds> <log>
    ( $TIMEOUT -s TERM "$2" $QEMU -machine pc -m 256 -bios "$FW" \
        -drive file="$1",format=raw,if=ide -no-reboot \
        -display none -serial stdio > "$3" 2>&1 || true ) 2>/dev/null
}

boot_ovmf() {                               # boot_ovmf <disk> <machine> <seconds> <log>
    cp "$OVMF_VARS" "$BUILD/smoke-vars.fd"
    ( $TIMEOUT -s TERM "$3" $QEMU -machine "$2" -m 256 -no-reboot \
        -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,unit=1,file="$BUILD/smoke-vars.fd" \
        -drive file="$1",format=raw,if=ide \
        -display none -serial stdio > "$4" 2>&1 || true ) 2>/dev/null
}

want() {                                    # want <log> <fixed string>
    checks=$((checks + 1))
    if grep -qF "$2" "$1"; then return; fi
    echo "  MISSING  $2"
    fails=$((fails + 1))
}

deny() {                                    # deny <log> <fixed string>
    checks=$((checks + 1))
    if ! grep -qF "$2" "$1"; then return; fi
    echo "  PRESENT  $2   <- must not be"
    fails=$((fails + 1))
}

# ---------------------------------------------------------------------------
# The firmware, and the payload it boots.
#
# Read as a sequence: the last landmark present names the phase that did not
# finish. The payload's own lines are the part that proves the protocols
# answer rather than merely existing -- ACPI checksums because tables that
# point at nothing still look plausible, and ConIn because a wrong letter is
# indistinguishable from a right one until somebody asks for a particular key.
# ---------------------------------------------------------------------------
check_fw() {
    log=$LOGS/fw.log
    echo "== firmware + payload   ($log)"
    boot "$BUILD/esp.img" "$FW_SECONDS" "$log"

    want "$log" "[SEC] long mode entered"
    want "$log" "[PEI] page allocator armed"
    want "$log" "[DXE] PCI: BARs assigned"
    want "$log" "[DXE] GOP: 1024x768x32"
    want "$log" "[DXE] ATA:"
    want "$log" "kbd   i8042 translation on, set 1 codes"
    want "$log" "[DXE] EFI tables built, protocols published"
    want "$log" "[DXE] ACPI: 4 tables"
    want "$log" "[DXE] SMBIOS 2.8, 8 structures"
    want "$log" "[DXE] variables: 32 slots"
    want "$log" "[DXE] done"
    want "$log" "[BDS] EFI system partition at LBA"
    want "$log" "[BDS] FAT32 volume mounted"
    want "$log" "\\EFI\\BOOT\\BOOTX64.EFI"
    want "$log" "[BDS] starting image"

    want "$log" "hello from a hand-assembled UEFI application"
    want "$log" "read myself back off the file system; still a PE image"
    want "$log" "every one of them checksums to zero"
    want "$log" "structures walked to the end marker; entry point checksums to zero"
    want "$log" "system: QEMU Standard PC (i440FX + PIIX, 1996)"
    want "$log" "appended to, found among 1 by enumeration, deleted"
    want "$log" "graphics output protocol located; drawing"
    want "$log" "ConIn"
    want "$log" "[BDS] image returned, status 0000000000000000"
    want "$log" "[BDS] no further boot options; system halted"
}

# ---------------------------------------------------------------------------
# The kernel: bring-up, four tasks that end four different ways, and a Lisp.
#
# The assertion is not that the tasks run. It is that none of them takes the
# machine with it -- task 1 dies of #GP, task 2 of #PF, and the log still
# reaches "every task has ended". A ring 0 trap means the kernel itself went
# wrong and there was nothing left to hand off to, so it is denied outright.
# ---------------------------------------------------------------------------
check_kernel() {
    log=$LOGS/kernel.log
    echo "== kernel               ($log)"
    boot "$BUILD/kernel.img" "$K_SECONDS" "$log"

    want "$log" "paging   4 GiB identity mapped"
    want "$log" "gdt      kernel and user descriptors loaded, tss rsp0 armed"
    want "$log" "idt      256 vectors"
    want "$log" "timer    8254 at 100 Hz on vector 32, ticking"
    want "$log" "kbd      i8042 on vector 33, irq1 open"
    want "$log" "syscall  lstar armed; sysret will enter cs 002b"
    want "$log" "task     0  window"
    want "$log" "task     3  window"

    want "$log" "solved:"                       # task 0: preempted, never yields
    want "$log" "kernel   task 0 exited, status 0"
    want "$log" "task 1   line 0001"
    want "$log" "task 1   done counting; now executing cli"
    want "$log" "trap 13 (#GP )"
    want "$log" "kernel   task 1 killed; the others keep running"
    want "$log" "a write to address zero was refused"   # the boundary check
    want "$log" "reading my neighbour's window"
    want "$log" "kernel   task 2 killed; the others keep running"
    want "$log" "task 3   loaded from \\PROGS\\TYPE.BIN"
    want "$log" "kernel   task 3 exited, status 0"
    want "$log" "task 4   = 2432902008176640000"    # (fact 20)
    want "$log" "task 4   = (1 4 9 16 25)"          # map, lambda, quote
    want "$log" "task 4   = 6765"                   # (fib 20)
    want "$log" "task 4   = 2"                      # a closure's second call
    want "$log" "task 4   = 5000050000"             # 100000 tail calls
    want "$log" "task 4   error: unbound symbol no-such-function"
    want "$log" "task 4   demo done; the collector ran"
    deny "$log" "the collector ran 0 times"
    want "$log" "kernel   task 4 exited, status 0"
    want "$log" "kernel   every task has ended after"
    want "$log" "kernel   nothing left to run; halted"

    deny "$log" "cs 0008"                       # a trap taken in ring 0
}

# ---------------------------------------------------------------------------
# The control. A single implementation can only be compared against your
# beliefs about it; two can be compared against each other. If the payload
# runs under OVMF and not here, the firmware is at fault; if it runs under
# neither, the payload is.
# ---------------------------------------------------------------------------
check_ovmf() {
    if [ ! -f "$OVMF_CODE" ] || [ ! -f "$OVMF_VARS" ]; then
        echo "== control              skipped: no OVMF at $OVMF_CODE"
        return
    fi
    log=$LOGS/ovmf.log
    echo "== control: payload under OVMF   ($log)"
    boot_ovmf "$BUILD/esp.img" q35 "$FW_SECONDS" "$log"
    want "$log" "hello from a hand-assembled UEFI application"
    want "$log" "every one of them checksums to zero"
    # No structure count here: OVMF adds a type 0 of its own when QEMU
    # supplies none, so it walks one more than asmfw does, correctly.
    want "$log" "structures walked to the end marker; entry point checksums to zero"
    want "$log" "refused a change of attributes, appended to, found among"
    want "$log" "graphics output protocol located; drawing"

    log=$LOGS/ovmfk.log
    echo "== control: kernel under OVMF    ($log)"
    boot_ovmf "$BUILD/kernel.img" pc "$K_SECONDS" "$log"
    want "$log" "kernel   every task has ended after"
    want "$log" "kernel   nothing left to run; halted"
}

case "${1:-all}" in
    fw)     check_fw ;;
    kernel) check_kernel ;;
    all)    check_fw; check_kernel; check_ovmf ;;
    *)      echo "usage: smoke.sh [all|fw|kernel]"; exit 1 ;;
esac

echo
if [ "$fails" -eq 0 ]; then
    echo "PASS  $checks checks"
else
    echo "FAIL  $fails of $checks checks; logs in $LOGS"
    exit 1
fi
