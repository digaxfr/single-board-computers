#!/bin/bash

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
chroot mnt systemctl enable ssh
chroot mnt mkdir -p /home/digaxfr/.ssh
chroot mnt chmod 0700 /home/digaxfr/.ssh
chroot mnt tee /home/digaxfr/.ssh/authorized_keys << "EOF"
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHYU5ohkrcI9PZHZZTFWkhlKfCfp5rsEslWDyzz3w3hYzec/fOiP92M29Ck/JS35N1BZ+vZZ7JOqjxmXhADt6V8= dchin@failxps.localdomain
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDDp0gFvIt68xd9n9N7GKeu/ubNkJgCVq41yHPOTVv7u3c9H5tPM8dHK2VdpzinqYk2WkSVqp8zUqXvqawi+Tmdma2PA/Xzo4WWe1hm/y9V6hwsOOQxrE/cYzp6ZjthkeGAI4xwknIF7N81hw6KUlEVDAtvs78ZvNDM1M3+lGp5MuEumXmnoDe9beUd8Eg3MXZPQd/gt1zMUdspr5m+GtUwi0pgKu3Dfsp8RKaTH5+4Y+zCUW43gpl0eiuxtkALNOmb1psRB5YDmF2t9PiJ/0C2Z2WQWhn4Gz5m1bi9KUTKUNlwesN589frIjYTy7NohsPvum1bsKD4bUjLCiM9Y//f dchin@failxps
EOF
chroot mnt chmod 600 /home/digaxfr/.ssh/authorized_keys
chroot mnt chown digaxfr: /home/digaxfr/.ssh/
chroot mnt chown digaxfr: /home/digaxfr/.ssh/authorized_keys
chroot mnt sed -i 's/\%sudo[ \t]ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
if [ -f "../wpa_supplicant.conf" ]; then
    cp ../wpa_supplicant.conf mnt/etc/wpa_supplicant/wpa_supplicant.conf
    chmod 600 mnt/etc/wpa_supplicant/wpa_supplicant.conf
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
