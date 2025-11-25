#!/bin/bash
set -e
DISK=/dev/sda
BOOT_PART=${DISK}1
ROOT_PART=${DISK}2
TIMEZONE=UTC
LOCALE="en_US.UTF-8"
HOSTNAME=archlinux
ROOT_PASS="change_me"
timedatectl set-ntp true
sgdisk --zap-all $DISK
sgdisk --new=1:0:+512M --type=1:EF00 $DISK
sgdisk --new=2:0:0 --type=2:8300 $DISK
mkfs.fat -F32 $BOOT_PART
mkfs.ext4 $ROOT_PART
mount $ROOT_PART /mnt
mkdir -p /mnt/boot
mount $BOOT_PART /mnt/boot
pacstrap -K /mnt base linux linux-firmware
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
arch-chroot /mnt hwclock --systohc
echo "$LOCALE UTF-8" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
echo $HOSTNAME > /mnt/etc/hostname
echo "127.0.0.1 localhost" > /mnt/etc/hosts
echo "::1 localhost" >> /mnt/etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /mnt/etc/hosts
arch-chroot /mnt mkinitcpio -P
echo "root:$ROOT_PASS" | arch-chroot /mnt chpasswd
arch-chroot /mnt bootctl --path=/boot install
umount -R /mnt
reboot
