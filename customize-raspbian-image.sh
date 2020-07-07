#!/bin/bash

set -ex

# Note that the BOARD variable isn't actually used yet. This is in anticipation
# for when Raspbian will offer a arm64 release for the rpi4b.
BOARD=$1
LOSETUP=$(which losetup)

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
if [ ! -f "raspbian_lite_latest" ]; then
    curl -O -L https://downloads.raspberrypi.org/raspbian_lite_latest
fi

unzip -o raspbian_lite_latest
dd if=/dev/zero bs=1M count=2048 >> *.img

# https://superuser.com/questions/332252/how-to-create-and-format-a-partition-using-a-bash-script

(
    echo d      # Delete partition
    echo 2      # Delete partition 2 (rootfs)
    echo n      # Create new partition
    echo p      # Primary
    echo 2      # Partitoin 1
    if [ "${BOARD}" == "rpi4b" ]; then
        echo 532480   # Start at sector 532480 - As of 2019-01-10
    fi
    echo ""     # End sector is 100%
    echo w      # Write changes
) | fdisk *.img

# Ceate the loopback device, fsck, resize, mount it, and set up the chroot
LOOP=$(${LOSETUP} -f)
${LOSETUP} -P ${LOOP} *.img
fsck -f ${LOOP}p2
resize2fs ${LOOP}p2
mkdir -p mnt
mount ${LOOP}p2 mnt
mount ${LOOP}p1 mnt/boot
mount -t proc proc mnt/proc
mount -t sysfs sysfs mnt/sys
mount -t devtmpfs devtmpfs mnt/dev
mount -t tmpfs tmpfs mnt/dev/shm
mount -t devpts devpts mnt/dev/pts
mount --bind /etc/resolv.conf mnt/etc/resolv.conf

# Make the customizations required
chroot mnt usermod -l digaxfr pi
chroot mnt usermod -m -d /home/digaxfr digaxfr
# Set the password via Ansible as part of deployments... if I really care that much
chroot mnt passwd --delete digaxfr
chroot mnt groupmod -n digaxfr pi
chroot mnt apt-get -y upgrade
chroot mnt apt-get -y install openssh-server vim
chroot mnt apt-get clean
echo "en_US.UTF-8 UTF-8" >> mnt/etc/locale.gen
chroot mnt locale-gen
chroot mnt update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en
chroot mnt ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
chroot mnt systemctl enable ssh
chroot mnt mkdir -p /home/digaxfr/.ssh
chroot mnt chmod 0700 /home/digaxfr/.ssh
chroot mnt tee /home/digaxfr/.ssh/authorized_keys << "EOF"
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0OqzFm/vPZQoMr8kzWHH4wuBf24GXCQNwbO0w9GHJVdmEdhVecUNoVsPPzwj/aHpuY4daxnAxvOVPJdGLszUNSkRvPYnLgl77Zw0WXEVSIk8ReOaFMcLkwOX8FjaRzPoxTMG+BpfJZMHLWvBnIjywvvg5rr8eF2V1PScWCELvkWoZ3haXjVTb0G+0Wb3AhS+PEEGi0jxmkPQwktW31EdbMqQgZtiV3A+iPsHx/q1kB9kOQrGCLfk9ZKxP64w+RMimsw+J42F07wrX9LQ76g8bW5lZpvoZtcRgBweuGPjwNEn/QFdZ6T8pOjdAbbJyvTn680J/2EjRPd2zbKCP43yr darrenchin@MacFailPro.local
EOF
chroot mnt chmod 600 /home/digaxfr/.ssh/authorized_keys
chroot mnt chown digaxfr: /home/digaxfr/.ssh/
chroot mnt chown digaxfr: /home/digaxfr/.ssh/authorized_keys
chroot mnt passwd -l digaxfr
chroot mnt sed -i 's/\%sudo[ \t]ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
if [ -f "../wpa_supplicant.conf" ]; then
    cp ../wpa_supplicant.conf mnt/boot/wpa_supplicant.conf
    chmod 600 mnt/boot/wpa_supplicant.conf
fi
echo "enable_uart=1" >> mnt/boot/config.txt
chroot mnt update-alternatives --set editor /usr/bin/vim.basic
chroot mnt ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
chroot mnt sync
sync

sleep 5

# Unmount the chroot, image, and remove the loopback
umount -R mnt
${LOSETUP} -d ${LOOP}

popd
