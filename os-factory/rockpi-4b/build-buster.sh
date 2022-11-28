#!/bin/bash

set -e

export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin

boards=("rockpi-4b")
mount_image="/tmp/sbc-factory/image"
mount_target="/tmp/sbc-factory/target"

dropbear_pub_key="ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBN19s2s2hiWF6gxZkfgNuxarSUE1n4cfj9xJqc8JlterzCqtyuDI99ivCKKTwzVPEiDgjHIRe0pukVzrKgtoLxY= darrenchin@failxps.dchin.dev"
ssh_pub_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVugR+fcz9NY1mXzL/V4O24Vt+HKeE+HJMAq9kapk1H darrenchin@ryzenfail.dchin.dev"

# DEBUG
#loop_new_image=/dev/loop0
#loop=/dev/loop1

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
    rm -f ${mount_target}/etc/systemd/system/display-manager.service

    # Use our own resizer
    rm -f ${mount_target}/etc/systemd/system/basic.target.wants/resize-assistant.service
    tee ${mount_target}/etc/systemd/system/digaxfr-resizer.service << EOF
[Unit]
Description=Resize root filesystem to fit available disk space
After=systemd-remount-fs.service

[Service]
Type=oneshot
ExecStart=-/root/digaxfr-resizer.sh
ExecStartPost=/bin/systemctl disable digaxfr-resizer.service

[Install]
WantedBy=basic.target
EOF

    tee ${mount_target}/root/digaxfr-resizer.sh << EOF
#!/bin/bash

# Cheap work around, first boot reboots, so we do a sleep so the script doesn't get interrupted by the reboot.
# On second boot, it will sleep again, but at least the script wiill finish this time around.
sleep 120

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
echo '${BUILD_CRYPT_PASSWORD}' | cryptsetup resize /dev/mapper/sbc-root

# Kernel refresh again for good measure
partprobe

# Resize filesytem
resize2fs /dev/mapper/sbc-root

# Remove ourself
rm /root/digaxfr-resizer.sh
EOF
    chmod +x ${mount_target}/root/digaxfr-resizer.sh

    # Workaround for eth issue
    tee ${mount_target}/etc/systemd/system/digaxfr-net-mod.service << EOF
[Unit]
Description=Reload networking module for workaround
Before=network-pre.target

[Service]
Type=oneshot
ExecStart=-/usr/sbin/rmmod dwmac_rk
ExecStartPost=/usr/sbin/modprobe dwmac_rk

[Install]
WantedBy=basic.target
EOF

    # Set up the chroot
    mount -t proc proc ${mount_target}/proc
    mount -t sysfs sysfs ${mount_target}/sys
    mount -t devtmpfs devtmpfs ${mount_target}/dev
    mount -t tmpfs tmpfs ${mount_target}/dev/shm
    mount -t devpts devpts ${mount_target}/dev/pts
    mount --bind /etc/resolv.conf ${mount_target}/etc/resolv.conf
    chroot ${mount_target} usermod -d /home/digaxfr -m -l digaxfr rock
    chroot ${mount_target} usermod -a -G sudo digaxfr
    chroot ${mount_target} apt-get -y purge xfce* xserver* firefox* chromium* desktop-base desktop-file-utils *-icon-theme lightdm x11-* xfdesktop4
    chroot ${mount_target} apt autoremove -y
    chroot ${mount_target} apt-get update
    DEBIAN_FRONTEND=noninteractive chroot ${mount_target} apt-get -q -y upgrade
    DEBIAN_FRONTEND=noninteractive chroot ${mount_target} apt-get -q -y install \
        busybox \
        cryptsetup \
        cryptsetup-initramfs \
        dropbear \
        dropbear-initramfs \
        locales-all \
        openssh-server \
        vim
    chroot ${mount_target} apt-get clean
    echo "en_US.UTF-8 UTF-8" >> ${mount_target}/etc/locale.gen
#    chroot ${mount_target} locale-gen
#    chroot ${mount_target} update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en
#    chroot ${mount_target} localectl set-locale en_US.utf8
    chroot ${mount_target} ln -fs /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
    chroot ${mount_target} ln -fs /etc/systemd/system/digaxfr-net-mode.service /etc/systemd/system/basic.target.wants/digaxfr-net-mod.service
    chroot ${mount_target} ln -fs /etc/systemd/system/digaxfr-resizer.service /etc/systemd/system/basic.target.wants/digaxfr-resizer.service
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
/dev/mmcblk2p4          /boot   ext4    defaults,noatime,nodiratime,commit=60,errors=remount-ro 0 2
/dev/mapper/sbc-root    /       ext4    defaults,noatime,nodiratime,commit=60,errors=remount-ro 0 1
EOF
    tee ${mount_target}/etc/crypttab << EOF
sbc-root /dev/mmcblk2p5 none luks
EOF
    echo "CRYPTSETUP=y" >> ${mount_target}/etc/cryptsetup-initramfs/conf-hook
    echo "${dropbear_pub_key}" >> ${mount_target}/etc/dropbear-initramfs/authorized_keys
    kernel_version=$(ls -tr ${mount_target}/lib/modules | head -n1)
    chroot ${mount_target} /usr/sbin/mkinitramfs -o /boot/initrd.img-${kernel_version} ${kernel_version}
    chroot ${mount_target} sync
    sync
}

function cleanup() {
    umount -R ${mount_image}
    umount -R ${mount_target}
    rmdir ${mount_image} ${mount_target}
    losetup -d ${loop}
    cryptsetup close sbc-root
    losetup -d ${loop_new_image}
}

function copy_data() {
    # Create the loopback dev
    loop=$(losetup -f)
    losetup -P ${loop} ${image}

    # Mount it
    mkdir -p ${mount_image}
    mount ${loop}p5 ${mount_image}
    mount ${loop}p4 ${mount_image}/boot

    # Now mount our target
    mkdir -p ${mount_target}
    mount /dev/mapper/sbc-root ${mount_target}
    mkdir ${mount_target}/boot
    mount ${loop_new_image}p4 ${mount_target}/boot

    # Copy boot and os data
    rsync -avh ${mount_image}/ ${mount_target}/

    # Write the boot partitions
    dd if=${loop}p1 of=${loop_new_image}p1
    dd if=${loop}p2 of=${loop_new_image}p2
    dd if=${loop}p3 of=${loop_new_image}p3
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
    # Create our dummy image file
    dd if=/dev/zero of=rockpi-4b.img bs=1M count=4096
    (
        echo x      # Expert menu
        echo l      # Change alignment
        echo 64     # Start on sector 64
        echo m      # Go back to main menu
        echo n      # New partition
        echo 1      # Partition 1
        echo 64
        echo 8063
        echo 0700
        echo n
        echo 2
        echo 16384
        echo 24575
        echo 0700
        echo n
        echo 3
        echo 24576
        echo 32767
        echo 0700
        echo n
        echo 4
        echo 32768
        echo 1081343
        echo EF00
        echo n
        echo 5
        echo 1081344
        echo ""
        echo 8309
        echo w
        echo Y
    ) | gdisk ./rockpi-4b.img

    # Mount the image as a loopback
    loop_new_image=$(losetup -f)
    losetup -P ${loop_new_image} ./rockpi-4b.img

    echo -n ${BUILD_CRYPT_PASSWORD} | cryptsetup luksFormat -c aes-xts-plain64 -s 512 -h sha512 --pbkdf-memory 512000 ${loop_new_image}p5 '-'
    echo -n ${BUILD_CRYPT_PASSWORD} | cryptsetup open ${loop_new_image}p5 sbc-root

    # Too lazy to make it dynamic. The UUID will need to be changed if a newer image is used.
    mkfs.ext4 -L root -U 1c1fc7a2-aa70-4951-a076-96f709819b01 /dev/mapper/sbc-root
    mkfs.ext4 -L boot ${loop_new_image}p4
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
