# ============================================================================
# asmfw -- UEFI firmware in assembly
# ============================================================================

NASM   ?= nasm
QEMU   ?= qemu-system-x86_64
PYTHON ?= python3

BUILD := build
FW    := $(BUILD)/FIRMWARE.fd
LST   := $(BUILD)/fw.lst
ESP   := $(BUILD)/esp.img
STAGE := $(BUILD)/payload

# The kernel is a second, separate bootable disk: it takes the machine over,
# so it cannot share one with the payload that only borrows it.
KESP   := $(BUILD)/kernel.img
KLST   := $(BUILD)/kernel.lst
KSTAGE := $(BUILD)/kernel
KSRCS  := $(wildcard kernel/*.asm) $(wildcard kernel/*.inc) src/font.inc
PROGS  := MAZE.BIN COUNT.BIN ROGUE.BIN TYPE.BIN LISP.BIN
PROGBIN := $(addprefix $(KSTAGE)/,$(PROGS))

FW_SRCS := $(wildcard src/*.asm) $(wildcard src/*.inc)

# Linux, booted as \EFI\BOOT\BOOTX64.EFI from a disk of its own. The kernel
# and initramfs are fetched, not committed: tools/getlinux.sh pins them.
LDIR    := $(BUILD)/linux
LSTAGE  := $(LDIR)/stage
LESP    := $(BUILD)/linux.img
LKERNEL := $(LDIR)/vmlinuz-virt
LINITRD := $(LDIR)/initramfs-virt
LCMDLINE := console=ttyS0 initrd=\INITRD

# Warnings are on, minus the three that fire on every absolute reference in a
# flat binary assembled at its final address -- which is to say, on everything.
NASMFLAGS := -f bin -I src/ -w+all \
             -w-reloc-abs-dword -w-reloc-abs-word -w-reloc-abs-qword

# The i440fx machine, whose PIIX3 IDE function answers on the legacy ATA ports
# the firmware's block driver drives directly.
QEMUFLAGS := -machine pc \
             -m 256 \
             -bios $(FW) \
             -drive file=$(ESP),format=raw,if=ide \
             -no-reboot

.PHONY: all run serial screenshot ovmf esp kernel runk serialk ovmfk \
        check check-fw check-kernel check-docs lstk clean \
        linux-fetch linux runl seriall ovmfl check-linux

all: $(FW) $(ESP)

# ---------------------------------------------------------------------------
# The flash volume
# ---------------------------------------------------------------------------
$(FW): $(FW_SRCS) | $(BUILD)
	$(NASM) $(NASMFLAGS) -o $@ -l $(LST) src/fw.asm
	@sz=$$(wc -c < $@); \
	 if [ "$$sz" -ne 1048576 ]; then \
	   echo "error: $@ is $$sz bytes, expected 1048576"; exit 1; fi
	@echo "built $@ ($$(wc -c < $@) bytes)"

# ---------------------------------------------------------------------------
# The test payload: a UEFI application whose PE headers are written by hand
# ---------------------------------------------------------------------------
$(STAGE)/BOOTX64.EFI: payload/hello.asm | $(STAGE)
	$(NASM) -f bin -o $@ $<

# ---------------------------------------------------------------------------
# A GPT disk carrying a FAT32 EFI system partition
# ---------------------------------------------------------------------------
esp: $(ESP)

$(ESP): $(STAGE)/BOOTX64.EFI tools/mkesp.py | $(BUILD)
	$(PYTHON) tools/mkesp.py $@ $(STAGE) 64

# ---------------------------------------------------------------------------
# The kernel, and its own disk
# ---------------------------------------------------------------------------
kernel: $(KESP)

$(KSTAGE)/BOOTX64.EFI: $(KSRCS) | $(KSTAGE)
	$(NASM) -f bin -I kernel/ -I src/ -o $@ -l $(KLST) kernel/kernel.asm

# The programs are flat binaries, not images: no headers, no relocations, and
# an entry point at offset zero, because the kernel has no loader beyond a read.
# Written out one rule each rather than as a pattern, because the names on the
# disk are the 8.3 ones FAT stores and make's patterns are case sensitive.
PROGDEPS  := kernel/uabi.inc kernel/progs/ulib.inc
PROGFLAGS := -f bin -I kernel/ -I kernel/progs/

$(KSTAGE)/MAZE.BIN: kernel/progs/maze.asm $(PROGDEPS) | $(KSTAGE)
	$(NASM) $(PROGFLAGS) -o $@ -l $(BUILD)/maze.lst $<

$(KSTAGE)/COUNT.BIN: kernel/progs/count.asm $(PROGDEPS) | $(KSTAGE)
	$(NASM) $(PROGFLAGS) -o $@ -l $(BUILD)/count.lst $<

$(KSTAGE)/ROGUE.BIN: kernel/progs/rogue.asm $(PROGDEPS) | $(KSTAGE)
	$(NASM) $(PROGFLAGS) -o $@ -l $(BUILD)/rogue.lst $<

$(KSTAGE)/TYPE.BIN: kernel/progs/type.asm $(PROGDEPS) | $(KSTAGE)
	$(NASM) $(PROGFLAGS) -o $@ -l $(BUILD)/type.lst $<

$(KSTAGE)/LISP.BIN: kernel/progs/lisp.asm $(PROGDEPS) | $(KSTAGE)
	$(NASM) $(PROGFLAGS) -o $@ -l $(BUILD)/lisp.lst $<

# Listings, the symbol map for turning a faulting RIP back into a line. They
# are written by every kernel build, as fw.lst is by every firmware build;
# this target exists so asking for one by name works too. The kernel is
# assembled at org 0: subtract the image base the firmware printed. A
# program's offset is rip minus the window the kernel printed for that task.
PLSTS := $(addprefix $(BUILD)/,maze.lst count.lst rogue.lst type.lst lisp.lst)

lstk: $(KLST) $(PLSTS)
	@ls -1 $^

# The builds above leave these behind; these rules only run when one is
# missing or stale, and assemble for the listing alone.
$(KLST): $(KSRCS) | $(BUILD)
	$(NASM) -f bin -I kernel/ -I src/ -o /dev/null -l $@ kernel/kernel.asm

$(BUILD)/%.lst: kernel/progs/%.asm $(PROGDEPS) | $(BUILD)
	$(NASM) $(PROGFLAGS) -o /dev/null -l $@ $<

$(KESP): $(KSTAGE)/BOOTX64.EFI $(PROGBIN) tools/mkesp.py | $(BUILD)
	$(PYTHON) tools/mkesp.py $@ $(KSTAGE) 64

$(BUILD) $(STAGE) $(KSTAGE):
	@mkdir -p $@

# ---------------------------------------------------------------------------
# Linux
# ---------------------------------------------------------------------------
linux-fetch:
	@tools/getlinux.sh $(LDIR)

linux: $(LESP)

# The command line goes in a file beside the image: with no persistent
# variables there is no Boot#### entry to carry load options, so BDS reads
# \EFI\BOOT\CMDLINE instead.
$(LESP): $(LKERNEL) $(LINITRD) tools/mkesp.py | $(BUILD)
	@mkdir -p $(LSTAGE)
	cp $(LKERNEL) $(LSTAGE)/BOOTX64.EFI
	cp $(LINITRD) $(LSTAGE)/INITRD
	printf '%s\n' '$(LCMDLINE)' > $(LSTAGE)/CMDLINE
	$(PYTHON) tools/mkesp.py $@ $(LSTAGE) 128

$(LKERNEL) $(LINITRD):
	@echo "no Linux to boot: run 'make linux-fetch' first"; exit 1

runl: $(FW) $(LESP)
	$(QEMU) -machine pc -m 512 -bios $(FW) \
	  -drive file=$(LESP),format=raw,if=ide -no-reboot -serial mon:stdio

seriall: $(FW) $(LESP)
	$(QEMU) -machine pc -m 512 -bios $(FW) \
	  -drive file=$(LESP),format=raw,if=ide -no-reboot -display none -serial stdio

# The same kernel, initrd and command line under OVMF, which takes them from
# QEMU directly and starts the kernel through the same EFI stub.
ovmfl: $(LKERNEL) $(LINITRD)
	@cp $(OVMF_VARS) $(BUILD)/lvars.fd
	$(QEMU) -machine pc -m 512 -no-reboot \
	  -drive if=pflash,format=raw,unit=0,readonly=on,file=$(OVMF_CODE) \
	  -drive if=pflash,format=raw,unit=1,file=$(BUILD)/lvars.fd \
	  -kernel $(LKERNEL) -initrd $(LINITRD) -append 'console=ttyS0' \
	  -display none -serial stdio

# ---------------------------------------------------------------------------
# Running it
# ---------------------------------------------------------------------------

# A graphical window, with the serial log multiplexed into the terminal.
run: $(FW) $(ESP)
	$(QEMU) $(QEMUFLAGS) -serial mon:stdio

# Serial only. The firmware says everything twice, once to each console.
serial: $(FW) $(ESP)
	$(QEMU) $(QEMUFLAGS) -display none -serial stdio

# The same two, booting the kernel instead of the payload.
runk: $(FW) $(KESP)
	$(QEMU) -machine pc -m 256 -bios $(FW) \
	  -drive file=$(KESP),format=raw,if=ide -no-reboot -serial mon:stdio

serialk: $(FW) $(KESP)
	$(QEMU) -machine pc -m 256 -bios $(FW) \
	  -drive file=$(KESP),format=raw,if=ide -no-reboot -display none -serial stdio

# Boot, wait, and write the framebuffer out as a PNG.
screenshot: $(FW) $(ESP)
	@(sleep 4; echo "screendump $(BUILD)/screen.ppm"; sleep 2; echo quit) | \
	   $(QEMU) $(QEMUFLAGS) -display none -monitor stdio -serial null >/dev/null 2>&1
	@sips -s format png $(BUILD)/screen.ppm --out $(BUILD)/screen.png >/dev/null
	@echo "wrote $(BUILD)/screen.png"

# The same disk under the reference firmware. If the payload runs here but not
# under asmfw, the firmware is at fault; if it runs under neither, the payload is.
OVMF_CODE ?= /opt/homebrew/share/qemu/edk2-x86_64-code.fd
OVMF_VARS ?= /opt/homebrew/share/qemu/edk2-i386-vars.fd

# The kernel under OVMF. It has to be the i440fx machine, not q35: the kernel
# drives the legacy ATA ports itself, and q35's disk is behind AHCI, which
# this kernel has no driver for and does not pretend to.
ovmfk: $(KESP)
	@cp $(OVMF_VARS) $(BUILD)/kvars.fd
	$(QEMU) -machine pc -m 256 -no-reboot \
	  -drive if=pflash,format=raw,unit=0,readonly=on,file=$(OVMF_CODE) \
	  -drive if=pflash,format=raw,unit=1,file=$(BUILD)/kvars.fd \
	  -drive file=$(KESP),format=raw,if=ide \
	  -display none -serial stdio

ovmf: $(ESP)
	@cp $(OVMF_VARS) $(BUILD)/vars.fd
	$(QEMU) -machine q35 -m 256 -no-reboot \
	  -drive if=pflash,format=raw,unit=0,readonly=on,file=$(OVMF_CODE) \
	  -drive if=pflash,format=raw,unit=1,file=$(BUILD)/vars.fd \
	  -drive file=$(ESP),format=raw,if=ide \
	  -display none -serial stdio

clean:
	rm -rf $(BUILD)

# ---------------------------------------------------------------------------
# Checking it
#
# There is no test framework here and cannot be one in the usual sense: the
# unit under test is a machine at reset. tools/smoke.sh boots both disks under
# a timeout -- nothing here exits QEMU on its own -- and asserts the serial
# transcript still contains the landmarks it contained before. `check` also
# runs the same disks under OVMF, which is the only comparison that can tell a
# firmware bug from a payload bug.
# ---------------------------------------------------------------------------
check: check-docs $(FW) $(ESP) $(KESP) $(if $(wildcard $(LKERNEL)),$(LESP))
	@OVMF_CODE="$(OVMF_CODE)" OVMF_VARS="$(OVMF_VARS)" BUILD="$(BUILD)" \
	 QEMU="$(QEMU)" tools/smoke.sh all

# Every line number in docs/modules/ and docs/vi/modules/ against the source.
# A check that only runs when someone remembers it does not get run.
check-docs:
	@$(PYTHON) docs/verify.py

check-fw: $(FW) $(ESP)
	@BUILD="$(BUILD)" QEMU="$(QEMU)" tools/smoke.sh fw

check-kernel: $(FW) $(KESP)
	@BUILD="$(BUILD)" QEMU="$(QEMU)" tools/smoke.sh kernel

check-linux: $(FW) $(LESP)
	@OVMF_CODE="$(OVMF_CODE)" OVMF_VARS="$(OVMF_VARS)" BUILD="$(BUILD)" \
	 QEMU="$(QEMU)" tools/smoke.sh linux
