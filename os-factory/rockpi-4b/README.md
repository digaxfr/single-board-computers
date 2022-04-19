# rockpi-4b

## eMMC

Write to eMMC: https://wiki.radxa.com/Rockpi4/dev/usb-install

```
Disk /dev/loop0: 2.79 GiB, 3000000000 bytes, 5859375 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: EC0538D3-AF08-49DD-BD00-077AE4B534E4

Device         Start     End Sectors  Size Type
/dev/loop0p1      64    8063    8000  3.9M Microsoft basic data
/dev/loop0p2   16384   24575    8192    4M Microsoft basic data
/dev/loop0p3   24576   32767    8192    4M Microsoft basic data
/dev/loop0p4   32768 1081343 1048576  512M EFI System
/dev/loop0p5 1081344 5859341 4777998  2.3G Linux filesystem
```

```
Disk /dev/loop0: 5859375 sectors, 2.8 GiB
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): EC0538D3-AF08-49DD-BD00-077AE4B534E4
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 5859341
Partitions will be aligned on 64-sector boundaries
Total free space is 8350 sectors (4.1 MiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1              64            8063   3.9 MiB     0700  loader1
   2           16384           24575   4.0 MiB     0700  loader2
   3           24576           32767   4.0 MiB     0700  trust
   4           32768         1081343   512.0 MiB   EF00  boot
   5         1081344         5859341   2.3 GiB     8300  rootfs
```

```
root@rockpi-4b:~# lsblk
NAME         MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
mmcblk2      179:0    0 57.6G  0 disk
├─mmcblk2p1  179:1    0  3.9M  0 part
├─mmcblk2p2  179:2    0    4M  0 part
├─mmcblk2p3  179:3    0    4M  0 part
├─mmcblk2p4  179:4    0  512M  0 part
└─mmcblk2p5  179:5    0 57.1G  0 part /
mmcblk2boot0 179:32   0    4M  1 disk
mmcblk2boot1 179:64   0    4M  1 disk
```

## Notes

### Ethernet not coming up

https://forum.pine64.org/showthread.php?tid=9351&page=4

It seems that adding the ethernet modules to initramfs may cause an issue when booting up. After initramfs, sometimes
ethernet is not working.

```
[Sun Apr 17 23:23:55 2022] rk_gmac-dwmac fe300000.ethernet: Failed to reset the dma
[Sun Apr 17 23:23:55 2022] rk_gmac-dwmac fe300000.ethernet eth0: stmmac_hw_setup: DMA engine initialization failed
[Sun Apr 17 23:23:55 2022] rk_gmac-dwmac fe300000.ethernet eth0: stmmac_open: Hw setup failed
```

The workaround is to reload the moudle `dwmac_rk`.

Can do a simple workaround with a systemd unit before networking.

### WIfi

https://github.com/LibreELEC/brcmfmac_sdio-firmware

### Dropbear on Debian Buster (2018.76.x)

This version is old and only supports unencrypted Dropbear keys. It means we must use the Dropbear client (dbclient).

### Resizing

The resize-assistant that comes with the OS does not work in this case. High level steps are:

```
# Extend GPT information
sgdisk -e /dev/mmcblk2

# Recreate partition to max space
gdisk /dev/mmcblk2 ...
d
5
n
""
""
""
""
w
y

partprobe

# Resize crypt
cryptsetup resize /dev/mapper/sbc-root

partprobe

resize2fs /dev/mapper/sbc-root
```


```
#!/bin/bash

# Fix GPT partition
sgdisk -e /dev/mmcblk2

# Resize the root partition
(
    echo d
    echo 5
    echo n
    echo ""
    echo ""
    echo ""
    echo ""
    echo w
    echo y
) | gdisk /dev/mmcblk2

# Kernel refresh
partprobe

# Resize LUKS
echo 'passwd' | cryptsetup resize /dev/mapper/sbc-root

# Kernel refresh again for good measure
partprobe

# Resize filesytem
resize2fs /dev/mapper/sbc-root
```
