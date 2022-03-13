#!/bin/bash

set -e

export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin

boards=("odroidn2" "rock64")
mount_image="/tmp/sbc-factory/image"
mount_target="/tmp/sbc-factory/target"
ssh_pub_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVugR+fcz9NY1mXzL/V4O24Vt+HKeE+HJMAq9kapk1H darrenchin@ryzenfail.dchin.dev"

function check_options() {
    if [ ${UID} -ne 0 ]; then
        echo "Error, must be executed as root"
        exit 1
    fi

    if [[ -z ${BUILD_CRYPT_PASSWORD} ]]; then
        echo "Set environment variable BUILD_CRYPT_PASSWORD"
        exit 1
    fi

    if [[ -z ${board} ]]; then
        echo "-b <board-name> needs to be supplied"
        exit 1
    fi

    if [[ ! "${boards[*]}" =~ "${board}" ]]; then
        echo "${board} is not a valid board"
        exit 1
    fi

    if [[ -z ${disk} ]]; then
        echo "-d <disk> needs to be supplied"
        exit 1
    fi

    if [[ ! $(lsblk ${disk} 2>/dev/null) ]]; then
        echo "Invalid disk supplied: ${disk}"
        exit 1
    fi

    if [[ -z ${image} ]]; then
        echo "-i <image> needs to be supplied"
        exit 1
    fi

    if [[ ! -f ${image} ]]; then
        echo "Invalid image provided: ${image}"
        exit 1
    fi

    read -p "Are you sure you want to delete disk ${disk} (YES): " disk_prompt
    if [[ "${disk_prompt}" != "YES" ]]; then
        echo "Answer was not 'YES', exiting."
        exit 1
    fi
}

function chroot_config() {
    sed -i 's/console=.*/console=serial/g' ${mount_target}/boot/armbianEnv.txt
    sed -i 's/rootdev=.*/rootdev=\/dev\/mapper\/sbc-root/g' ${mount_target}/boot/armbianEnv.txt
    rm -f ${mount_target}/root/.not_logged_in_yet
    rm -f ${mount_target}/etc/systemd/system/sysinit.target.wants/armbian-zram-config.service
    rm -f ${mount_target}/etc/systemd/system/sysinit.target.wants/armbian-ramlog.service
    rm -f ${mount_target}/etc/systemd/system/basic.target.wants/armbian-resize-filesystem.service
    rm -f ${mount_target}/etc/systemd/system/multi-user.target.wants/armbian-firstrun-config.service

    if [[ ${board} == "odroidn2" ]]; then
        sed -i 's/MAX_SPEED=.*/MAX_SPEED=1800000/' ${mount_target}/etc/default/cpufrequtils
    fi

    # Set up the chroot
    mount -t proc proc ${mount_target}/proc
    mount -t sysfs sysfs ${mount_target}/sys
    mount -t devtmpfs devtmpfs ${mount_target}/dev
    mount -t tmpfs tmpfs ${mount_target}/dev/shm
    mount -t devpts devpts ${mount_target}/dev/pts
    mount --bind /etc/resolv.conf ${mount_target}/etc/resolv.conf
    chroot ${mount_target} useradd -c "digaxfr" -m -s /bin/bash digaxfr
    chroot ${mount_target} usermod -a -G sudo digaxfr
    chroot ${mount_target} apt-get update
    chroot ${mount_target} apt-get -y upgrade
    chroot ${mount_target} apt-get -y install \
        busybox \
        cryptsetup \
        cryptsetup-initramfs \
        dropbear \
        dropbear-initramfs \
        openssh-server \
        vim
    chroot ${mount_target} apt-get clean
    echo "en_US.UTF-8 UTF-8" >> ${mount_target}/etc/locale.gen
    chroot ${mount_target} locale-gen
    chroot ${mount_target} update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en
    chroot ${mount_target} ln -fs /usr/share/zoneinfo/America/New_York /etc/localtime
    chroot ${mount_target} systemctl enable ssh
    chroot ${mount_target} mkdir -p /home/digaxfr/.ssh
    chroot ${mount_target} chmod 0700 /home/digaxfr/.ssh
    chroot ${mount_target} tee /home/digaxfr/.ssh/authorized_keys << EOF
${ssh_pub_key}
EOF
    chroot ${mount_target} chmod 600 /home/digaxfr/.ssh/authorized_keys
    chroot ${mount_target} chown digaxfr: /home/digaxfr/.ssh/
    chroot ${mount_target} chown digaxfr: /home/digaxfr/.ssh/authorized_keys
    chroot ${mount_target} passwd -l digaxfr
    chroot ${mount_target} sed -i 's/\%sudo[ \t]ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/g' /etc/sudoers
    if [ -f "../wpa_supplicant.conf" ]; then
        cp ../wpa_supplicant.conf ${mount_target}/boot/wpa_supplicant.conf
        chmod 600 ${mount_target}/boot/wpa_supplicant.conf
    fi
    chroot ${mount_target} update-alternatives --set editor /usr/bin/vim.basic
    # Encryption setup
    tee ${mount_target}/etc/fstab << EOF
/dev/mmcblk0p1          /boot   ext4    defaults,noatime,nodiratime,commit=60,errors=remount-ro 0 2
/dev/mapper/sbc-root    /       ext4    defaults,noatime,nodiratime,commit=60,errors=remount-ro 0 1
EOF
    tee ${mount_target}/etc/crypttab << EOF
sbc-root /dev/mmcblk0p2 none luks
EOF
    echo "CRYPTSETUP=y" >> ${mount_target}/etc/cryptsetup-initramfs/conf-hook
    echo "${ssh_pub_key}" >> ${mount_target}/etc/dropbear-initramfs/authorized_keys
    kernel_version=$(ls -tr ${mount_target}/lib/modules | head -n1)
    chroot ${mount_target} /usr/sbin/mkinitramfs -o /boot/initrd.img-${kernel_version} ${kernel_version}
    chroot ${mount_target} /etc/initramfs/post-update.d/99-uboot ${kernel_version} /boot/initrd.img-${kernel_version}
    chroot ${mount_target} sync
    sync
}

function cleanup() {
    umount -R ${mount_image}
    umount -R ${mount_target}
    rmdir ${mount_image} ${mount_target}
    losetup -d ${loop}
}

function copy_data() {
    # Create the loopback dev
    loop=$(losetup -f)
    losetup -P ${loop} ${image}

    # Mount it
    mkdir -p ${mount_image}
    mount ${loop}p1 ${mount_image}

    # Now mount our target
    mkdir -p ${mount_target}
    mount /dev/mapper/sbc-root ${mount_target}
    mkdir ${mount_target}/boot
    mount ${disk}1 ${mount_target}/boot

    # Copy boot and os data
    rsync -avh ${mount_image}/ ${mount_target}/
}

function get_options() {
    local OPTIND OPTARG
    while getopts ":hb:d:i:" arg; do
        case ${arg} in
            b)
                board=${OPTARG}
                ;;
            d)
                disk=${OPTARG}
                ;;
            i)
                image=${OPTARG}
                ;;
            h|*)
                print_help
                exit 0
                ;;
        esac
    done
}

function prepare_disk() {
# First write the bootloader
case ${board} in
    odroidn2)
        dd if=${image} of=${disk} bs=512 count=8191
        sleep 1
        partprobe
        (
            echo o      # Fresh DOS partition table
            echo n      # Create new partition
            echo p      # Primary
            echo 1      # Partitoin 1
            echo 8192   # Start at sector 8192
            echo 532479 # End at sector 532479
            echo n      # New partition
            echo p      # Primary
            echo 2      # Partition 2
            echo 532480 # Start after the first partition
            echo ""     # End sector is 100%
            echo w      # Write changes
        ) | fdisk -w always -W always ${disk}
        ;;

    rock64)
        dd if=${image} of=${disk} bs=512 count=32767
        sleep 1
        partprobe
        (
            echo o      # Fresh DOS partition table
            echo n      # Create new partition
            echo p      # Primary
            echo 1      # Partitoin 1
            echo 32768  # Start at sector 32768
            echo 557055 # End at sector 557055
            echo n      # New partition
            echo p      # Primary
            echo 2      # Partition 2
            echo 557056 # Start after the first partition
            echo ""     # End sector is 100%
            echo w      # Write changes
        ) | fdisk -w always -W always ${disk}
        ;;
esac

    if [[ ${board} == "rock64" || ${board} == "odroidn2" ]]; then
        echo -n ${BUILD_CRYPT_PASSWORD} | cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 --pbkdf-memory 512000 ${disk}2 '-'
    else
        echo -n ${BUILD_CRYPT_PASSWORD} | cryptsetup luksFormat ${disk}2 '-'
    fi

    echo -n ${BUILD_CRYPT_PASSWORD} | cryptsetup open ${disk}2 sbc-root
    mkfs.ext4 -L SBC_ROOT /dev/mapper/sbc-root
    mkfs.ext4 -L SBC_BOOT ${disk}1
}

function print_help() {
    echo "  Usage: $0 <fill me in later>"
    echo "    Must be run as root."
    exit 0
}

function main() {
    get_options ${@}
    check_options
    prepare_disk
    copy_data
    chroot_config
    cleanup
}

main ${@}
