#!/bin/bash

set -e

function help() {
    echo "  Usage: $0"
    echo "    Must be run as root."
    exit 0
}

if [ ${UID} -ne 0 ]; then
    echo "Error, must be executed as root"
    help
fi

function debian() {
    export DEBIAN_FRONTEND=noninterative
    apt-get update
    apt-get install -y qemu-user-static qemu-efi-arm qemu-system-arm qemu-efi-aarch64
}

function fedora() {
    dnf -y install qemu qemu-kvm qemu-user-static
}

function main() {
    # Get the distribution
    DISTRO=$(lsb_release -i -s)
    if [ "${DISTRO}" == "Debian" ]; then
        debian
    elif [ "${DISTRO}" == "Fedora" ]; then
        fedora
    else
        echo "No supported host OS found!"
        exit 1
    fi
}

main
