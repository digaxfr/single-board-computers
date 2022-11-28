# rock-5b

For Radxa's rock-5b, I have decided to not do full disk encryption with LUKS. These boards are purely for homelab usage
that contain no sensitive data. Credentials, whether stored hashed or in plaintext, are all "lab" passwords anyways.

With that said, there will not be a `build.sh` version of rock-5b.

## Bootstrap

* Install latest u-boot spi image via maskrom mode.
* Image OS of choice onto nvme drive via USB enclosure.
* Boot up board and login over serial.
* Rename the default user account: `usermod -d /home/<user> -m -l <new-user> <old-user>`
  * Decided on `cloud-user`
* Rename the default user group: `groupmod -n <new-group> <old-group>`
  * Decided on `cloud-user`
* Modify `/etc/shadow` for default user's password to be `*`.
* Create `/home/<user>/.ssh` and dump the appropriate public key (and set proper file permissions).
* If using wireless only, if on Intel, download
https://packages.debian.org/buster/all/firmware-iwlwifi/download and remove `intel-wifibt-firmware`
  * Copy over via USB
* Update boot kernel commands at `/etc/default/extlinux` and update with `update_extlinux.sh`. <-- Doesn't work; maybe spi boot requires u-boot binary config
* Set up hostname with `hostnamectl` and modify `/etc/hosts` as needed.
