#!/bin/sh
# ============================================================================
# getlinux.sh -- fetch the Linux kernel and initramfs that make check-linux
# boots, and refuse them unless they are exactly the files it was written for
#
# Alpine's netboot pair: a kernel with the EFI stub built in, and an initramfs
# whose init has nothing to boot into and so drops to a shell -- which is the
# landmark. Pinned to one release by URL and by hash, so a newer release
# cannot quietly change what the check is checking.
#
# Usage: tools/getlinux.sh <dir>
# ============================================================================
set -eu

DIR=${1:-build/linux}
BASE=https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/netboot-3.24.3
KERNEL_SHA=17fbd3efd16f2e7cb1b945f06423b37399ba7d5ac8cdd3665e7f13f363500e85
INITRD_SHA=41d55a3fd650c99f5fa2a9dfed1eff3b441186831fd4f8d2223f717d8a28217d

mkdir -p "$DIR"

fetch() {                                   # fetch <name> <sha256>
    if [ -f "$DIR/$1" ] && echo "$2  $DIR/$1" | shasum -a 256 -c - >/dev/null 2>&1; then
        echo "getlinux: $1 already here"
        return
    fi
    echo "getlinux: fetching $1"
    curl -sSfL -o "$DIR/$1.part" "$BASE/$1"
    if ! echo "$2  $DIR/$1.part" | shasum -a 256 -c - >/dev/null 2>&1; then
        rm -f "$DIR/$1.part"
        echo "getlinux: $1 does not match its pinned hash; refusing it"
        exit 1
    fi
    mv "$DIR/$1.part" "$DIR/$1"
}

fetch vmlinuz-virt "$KERNEL_SHA"
fetch initramfs-virt "$INITRD_SHA"
