#!/bin/bash

# ------------------------------------------------------
# Setup locale, font, internet start
# ------------------------------------------------------

systemctl start systemd-resolved
sed -i s/'#en_US.UTF-8'/'en_US.UTF-8'/g /etc/locale.gen
sed -i s/'#ru_RU.UTF-8'/'ru_RU.UTF-8'/g /etc/locale.gen
chmod 777 /etc/locale.conf
chmod 777 /etc/vconsole.conf
echo 'LANG=ru_RU.UTF-8' > /etc/locale.conf
echo 'KEYMAP=ru' > /etc/vconsole.conf
echo 'FONT=cyr-sun16' >> /etc/vconsole.conf
chmod 644 /etc/locale.conf
chmod 644 /etc/vconsole.conf
setfont cyr-sun16
locale-gen >/dev/null 2>&1; RETVAL=$?
systemctl restart dhcpcd
dhcpcd >/dev/null 2>&1; RETVAL=$?


# ------------------------------------------------------
# Enter partition names
# ------------------------------------------------------
lsblk
read -p "Enter the name of the EFI partition (eg. sda1): " sda1
read -p "Enter the name of the ROOT partition (eg. sda2): " sda2
# read -p "Enter the name of the Home partition (eg. sda3): " sda3

# ------------------------------------------------------
# Sync time
# ------------------------------------------------------
timedatectl set-ntp true

# ------------------------------------------------------
# Format partitions
# ------------------------------------------------------
mkfs.fat -F 32 /dev/$sda1;
mkfs.btrfs -f /dev/$sda2
# mkfs.btrfs -f /dev/$sda3

# ------------------------------------------------------
# Mount points for btrfs
# ------------------------------------------------------
mount /dev/$sda2 /mnt
# mount /dev/$sda3 /mnt/home
btrfs su cr /mnt/@
btrfs su cr /mnt/@cache
btrfs su cr /mnt/@home
btrfs su cr /mnt/@snapshots
btrfs su cr /mnt/@log
umount -R /mnt

mount -o compress=zstd:1,noatime,subvol=@ /dev/$sda2 /mnt
mkdir -p /mnt/{boot/efi,home,.snapshots,var/{cache,log}}
mount -o compress=zstd:1,noatime,subvol=@cache /dev/$sda2 /mnt/var/cache
mount -o compress=zstd:1,noatime,subvol=@home /dev/$sda2 /mnt/home
mount -o compress=zstd:1,noatime,subvol=@log /dev/$sda2 /mnt/var/log
mount -o compress=zstd:1,noatime,subvol=@snapshots /dev/$sda2 /mnt/.snapshots
mount /dev/$sda1 /mnt/boot/efi
# ------------------------------------------------------
# Install base packages
# ------------------------------------------------------
pacstrap -K /mnt base base-devel git linux linux-firmware linux-headers intel-ucode

# ------------------------------------------------------
# Generate fstab
# ------------------------------------------------------
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab

# ------------------------------------------------------
# Install configuration scripts
# ------------------------------------------------------
mkdir /mnt/archinstall
#cp conf.sh /mnt/archinstall/
#cp 2-configuration.sh /mnt/archinstall/
#cp 3-yay.sh /mnt/archinstall/
#cp 4-zram.sh /mnt/archinstall/
#cp 5-timeshift.sh /mnt/archinstall/
#cp 6-preload.sh /mnt/archinstall/
#cp snapshot.sh /mnt/archinstall/

# ------------------------------------------------------
# Chroot to installed sytem
# ------------------------------------------------------
arch-chroot /mnt ./archinstall/2-configuration.sh
