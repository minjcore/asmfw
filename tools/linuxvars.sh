#!/bin/sh
# linuxvars.sh <log> -- typed into Linux's recovery shell once it appears:
# load efivarfs from the modloop on /dev/vda, then list the firmware's own
# variable, write one from Linux, read it back, delete it. Every step is a
# runtime services call made after SetVirtualAddressMap.
L=$1
G=6a5f1d2e-3b4c-4d5e-8f90-a1b2c3d4e5f6
V=/sys/firmware/efi/efivars
for i in $(seq 1 400); do grep -qa "emergency recovery shell" "$L" 2>/dev/null && break; sleep 0.2; done
sleep 1
printf 'modprobe virtio_pci; modprobe virtio_blk; sleep 1; mkdir -p /mnt/m; mount -t squashfs -o ro /dev/vda /mnt/m; insmod /mnt/m/modules/*/kernel/fs/efivarfs/efivarfs.ko; mount -t efivarfs none %s && echo VARS-MOUNTED\n' $V; sleep 3
printf 'echo "fw says: $(tail -c +5 %s/AsmfwVersion-%s)"\n' $V $G; sleep 1
printf "printf '\\\\007\\\\000\\\\000\\\\000linux was here' > %s/LinuxTest-%s && echo VAR-WRITTEN\n" $V $G; sleep 1
printf 'echo "read back: $(tail -c +5 %s/LinuxTest-%s)"\n' $V $G; sleep 1
printf 'chattr -i %s/LinuxTest-%s 2>/dev/null; rm %s/LinuxTest-%s && ls %s | grep -c LinuxTest\n' $V $G $V $G $V; sleep 2
