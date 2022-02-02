# single-board-computers
Collection of scripts for my single board computers

## Notes

192.168.188.97 dc:a6:32:0e:da:ca

Must use exact crypt names while creating initramfs

/usr/sbin/mkinitramfs -o /boot/initramfs.gz 5.10.92-v8+

https://www.kali.org/blog/secure-kali-pi-2018/
https://andreashug.medium.com/raspberry-pi-4-with-encrypted-root-partition-lvm-and-remote-unlock-457e680fc8d5

https://rr-developer.github.io/LUKS-on-Raspberry-Pi/

```
IP-Config: eth0 complete (dhcp from 192.168.188.1):
 address: 192.168.188.97   broadcast: 192.168.188.255  netmask: 255.255.255.0
 gateway: 192.168.188.1    dns0     : 192.168.188.88   dns1   : 1.1.1.1
 domain : dchin.dev
 rootserver: 192.168.188.1 rootpath:
 filename  :
Begin: Starting dropbear ...
Nothing to read on input.
cryptsetup: ERROR: crypt: cryptsetup failed, bad password or options?
Please unlock disk crypt:
cryptsetup: crypt: set up successfully
done.
Begin: Running /scripts/local-premount ... done.
Begin: Will now check root file system ... fsck from util-linux 2.36.1
[/sbin/fsck.ext4 (1) -- /dev/mapper/crypt] fsck.ext4 -y -C0 /dev/mapper/crypt
e2fsck 1.46.2 (28-Feb-2021)
/dev/mapper/crypt: clean, 40812/244800 files, 361621/977920 blocks
done.
[   73.373134] EXT4-fs (dm-0): mounted filesystem with ordered data mode. Opts: (null)
done.
Begin: Running /scripts/local-bottom ... done.
Begin: Running /scripts/init-bottom ... Begin: Stopping dropbear ... done.
Begin: Bringing down eth0 ... [   73.524505] bcmgenet fd580000.ethernet eth0: Link is Down
done.
Begin: Bringing down lo ... done.
done.
mount: /sys: sys already mounted or mount point busy.
[   73.982199] EXT4-fs (dm-0): re-mounted. Opts: (null)
cat: '/sys/block/*/mapper/partition': No such file or directory
fdisk: cannot open /dev/*: No such file or directory
cat: '/sys/block/*/size': No such file or directory
Error: Could not stat device /dev/* - No such file or directory.
```

Need to take out init=...resize from /boot/cmdline.txt

Need to use specific algo for crypt on raspberrypi for hwaccel

cryptsetup --type luks2 --cipher xchacha20,aes-adiantum-plain64 --hash sha256 --iter-time 5000 –keysize 256 --pbkdf argon2i luksFormat /dev/mmcblk0p2

Can extend luks volume with cryptsetup resize, but it might be safest to build tooling on preparing the sdcard appropriately, then rsync the data.

```
Device     Boot  Start     End Sectors  Size Id Type
/dev/sdb1         8192  532479  524288  256M  c W95 FAT32 (LBA)
/dev/sdb2       532480 8388607 7856128  3.7G 83 Linux
```
