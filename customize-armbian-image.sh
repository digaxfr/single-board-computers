#!/bin/bash

BOARD=$1

function help() {
    echo "  Usage: $0 <board>"
    echo "    Must be run as root."
    exit 0
}

if [ ${#} -ne 1 ]; then
    echo "Error, missing <board> argument"
    help
fi

if [ ${UID} -ne 0 ]; then
    echo "Error, must be executed as root"
    help
fi

# Create our workspace, grab the image, and then unpack it
mkdir -p ${BOARD}
pushd ${BOARD}
if [ ! -f "Debian_stretch_default.7z" ]; then
    curl -O -L https://dl.armbian.com/${BOARD}/Debian_stretch_default.7z
    #curl -O -L https://dl.armbian.com/${BOARD}/Ubuntu_bionic_default.7z
fi
7z -y x *.7z
dd if=/dev/zero bs=1M count=2048 >> *.img

# https://superuser.com/questions/332252/how-to-create-and-format-a-partition-using-a-bash-script

(
    echo d      # Delete partition
    echo n      # Create new partition
    echo p      # Primary
    echo 1      # Partitoin 1
    if [ "${BOARD}" == "odroidn2" ]; then
        echo 8192   # Start at sector 8192
    elif [ "${BOARD}" == "rock64" ]; then
        echo 32768  # Start at sector 32768
    fi
    echo ""     # End sector is 100%
    echo w      # Write changes
) | fdisk *.img

# Ceate the loopback device, fsck, resize, mount it, and set up the chroot
LOOP=$(/usr/sbin/losetup -f)
/usr/sbin/losetup -P ${LOOP} *.img
fsck -f ${LOOP}p1
resize2fs ${LOOP}p1
mkdir -p mnt
mount ${LOOP}p1 mnt
mount -t proc proc mnt/proc
mount -t sysfs sysfs mnt/sys
mount -t devtmpfs devtmpfs mnt/dev
mount -t tmpfs tmpfs mnt/dev/shm
mount -t devpts devpts mnt/dev/pts
mount --bind /etc/resolv.conf mnt/etc/resolv.conf

# Check to see if we have any customizations
# odroidn2 has one for now until a new release of Armbian with https://github.com/armbian/build/pull/1398
if [ -f "../debs/linux-image-${BOARD}_5.88_arm64.deb" ]; then
    cp ../debs/linux-image-${BOARD}_5.88_arm64.deb mnt/tmp
fi

# Make the customizations required -- keep in mind, we want to do as little
# possible here. Extra packages and such should be done in a post-install.
chroot mnt cat /etc/sudoers
chroot mnt apt-get -y update
chroot mnt apt-get -y upgrade
chroot mnt apt-get clean
chroot mnt sed -i 's/^root:.*/root:!:0:0:99999:7:::/g' /etc/shadow
chroot mnt useradd -c "Default Armbian User" -G sudo -m -s /bin/bash armbian
chroot mnt mkdir -p /home/armbian/.ssh
chroot mnt chmod 0700 /home/armbian/.ssh
chroot mnt tee /home/armbian/.ssh/authorized_keys << "EOF"
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHYU5ohkrcI9PZHZZTFWkhlKfCfp5rsEslWDyzz3w3hYzec/fOiP92M29Ck/JS35N1BZ+vZZ7JOqjxmXhADt6V8= dchin@failxps.localdomain
EOF
chroot mnt chmod 600 /home/armbian/.ssh/authorized_keys
chroot mnt chown armbian: /home/armbian/.ssh/
chroot mnt chown armbian: /home/armbian/.ssh/authorized_keys
chroot mnt sed -i 's/\%sudo[ \t]ALL=(ALL:ALL)[ \t]ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
chroot mnt rm /root/.not_logged_in_yet
if [ -f "../debs/linux-image-${BOARD}_5.88_arm64.deb" ]; then
    chroot mnt dpkg -i /tmp/linux-image-odroidn2_5.88_arm64.deb
    chroot mnt rm /tmp/linux-image-odroidn2_5.88_arm64.deb
fi
chroot mnt sync

# Unmount the chroot, image, and remove the loopback
umount -R mnt
/usr/sbin/losetup -d ${LOOP}

popd
