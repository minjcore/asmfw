#!/usr/bin/env python3
"""Build a GPT disk image with one FAT32 EFI system partition.

Usage: mkesp.py <image> <payload-dir> [size-mib]

The partition table is written here; the filesystem inside it is left to
mtools, which is pointed at the partition with its @@offset syntax.
"""

import os
import subprocess
import sys
import uuid
import zlib

SECTOR = 512
ENTRY_SIZE = 128
ENTRY_COUNT = 128
ENTRY_SECTORS = ENTRY_SIZE * ENTRY_COUNT // SECTOR       # 32
PART_START = 2048                                        # 1 MiB in

ESP_TYPE = uuid.UUID('C12A7328-F81F-11D2-BA4B-00A0C93EC93B')


def gpt_header(my_lba, alt_lba, first_usable, last_usable, disk_guid,
               entries_lba, entries_crc):
    h = bytearray(92)
    h[0:8] = b'EFI PART'
    h[8:12] = (0x00010000).to_bytes(4, 'little')         # revision 1.0
    h[12:16] = (92).to_bytes(4, 'little')                # header size
    # h[16:20] is the header CRC, computed over the header with it zeroed
    h[24:32] = my_lba.to_bytes(8, 'little')
    h[32:40] = alt_lba.to_bytes(8, 'little')
    h[40:48] = first_usable.to_bytes(8, 'little')
    h[48:56] = last_usable.to_bytes(8, 'little')
    h[56:72] = disk_guid.bytes_le
    h[72:80] = entries_lba.to_bytes(8, 'little')
    h[80:84] = ENTRY_COUNT.to_bytes(4, 'little')
    h[84:88] = ENTRY_SIZE.to_bytes(4, 'little')
    h[88:92] = entries_crc.to_bytes(4, 'little')
    h[16:20] = (zlib.crc32(bytes(h)) & 0xFFFFFFFF).to_bytes(4, 'little')
    return bytes(h)


def protective_mbr(total_sectors):
    mbr = bytearray(SECTOR)
    e = mbr[446:462]
    e = bytearray(16)
    e[0] = 0x00                                          # not bootable
    e[1:4] = b'\x00\x02\x00'                             # CHS start, cosmetic
    e[4] = 0xEE                                          # GPT protective
    e[5:8] = b'\xFF\xFF\xFF'                             # CHS end, cosmetic
    e[8:12] = (1).to_bytes(4, 'little')
    e[12:16] = min(total_sectors - 1, 0xFFFFFFFF).to_bytes(4, 'little')
    mbr[446:462] = e
    mbr[510:512] = b'\x55\xAA'
    return bytes(mbr)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    image = sys.argv[1]
    payload_dir = sys.argv[2]
    size_mib = int(sys.argv[3]) if len(sys.argv) > 3 else 64

    total = size_mib * 1024 * 1024 // SECTOR
    first_usable = 2 + ENTRY_SECTORS
    last_usable = total - 1 - ENTRY_SECTORS - 1
    part_end = last_usable
    part_sectors = part_end - PART_START + 1

    # Fixed GUIDs keep rebuilds byte-identical, which makes diffing images
    # while debugging the reader actually useful.
    disk_guid = uuid.UUID('11111111-2222-3333-4444-555555555555')
    part_guid = uuid.UUID('66666666-7777-8888-9999-AAAAAAAAAAAA')

    entries = bytearray(ENTRY_SIZE * ENTRY_COUNT)
    e = bytearray(ENTRY_SIZE)
    e[0:16] = ESP_TYPE.bytes_le
    e[16:32] = part_guid.bytes_le
    e[32:40] = PART_START.to_bytes(8, 'little')
    e[40:48] = part_end.to_bytes(8, 'little')
    e[48:56] = (0).to_bytes(8, 'little')
    name = 'EFI System'.encode('utf-16-le')
    # Slice assignment on a bytearray resizes it when the lengths differ, so
    # the end index has to come from the data, not from the field width.
    e[56:56 + len(name)] = name
    entries[0:ENTRY_SIZE] = e
    entries_crc = zlib.crc32(bytes(entries)) & 0xFFFFFFFF

    primary = gpt_header(1, total - 1, first_usable, last_usable,
                         disk_guid, 2, entries_crc)
    backup = gpt_header(total - 1, 1, first_usable, last_usable,
                        disk_guid, total - 1 - ENTRY_SECTORS, entries_crc)

    with open(image, 'wb') as f:
        f.truncate(total * SECTOR)
        f.seek(0)
        f.write(protective_mbr(total))
        f.seek(1 * SECTOR)
        f.write(primary.ljust(SECTOR, b'\x00'))
        f.seek(2 * SECTOR)
        f.write(entries)
        f.seek((total - 1 - ENTRY_SECTORS) * SECTOR)
        f.write(entries)
        f.seek((total - 1) * SECTOR)
        f.write(backup.ljust(SECTOR, b'\x00'))

    at = '%s@@%d' % (image, PART_START * SECTOR)
    run(['mformat', '-i', at, '-F', '-v', 'ASMFW', '-T', str(part_sectors),
         '-h', '64', '-s', '32', '::'])
    run(['mmd', '-i', at, '::/EFI'])
    run(['mmd', '-i', at, '::/EFI/BOOT'])
    run(['mmd', '-i', at, '::/PROGS'])

    # .efi is what firmware looks for; .bin is what the kernel loads once it
    # has stopped asking the firmware for anything.
    # CMDLINE sits beside the image it is the command line for; anything else
    # without an extension -- an initrd, say -- goes in the root, where a path
    # like \INITRD on that command line finds it.
    dest = {'.efi': '::/EFI/BOOT/', '.bin': '::/PROGS/', '': '::/', '.txt': '::/'}
    copied = 0
    for name in sorted(os.listdir(payload_dir)):
        if name == 'CMDLINE':
            where = '::/EFI/BOOT/'
        else:
            where = dest.get(os.path.splitext(name)[1].lower())
        if where is None:
            continue
        run(['mcopy', '-i', at, os.path.join(payload_dir, name), where + name])
        copied += 1
    if copied == 0:
        print('warning: nothing to copy from %s' % payload_dir, file=sys.stderr)

    print('%s: %d MiB, ESP at LBA %d (%d sectors), %d payload file(s)'
          % (image, size_mib, PART_START, part_sectors, copied))


def run(cmd):
    subprocess.run(cmd, check=True,
                   env=dict(os.environ, MTOOLS_SKIP_CHECK='1'))


if __name__ == '__main__':
    main()
