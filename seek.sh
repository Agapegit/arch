#!/bin/bash
set -e
loadkeys us >/dev/null 2>&1
timedatectl set-ntp true >/dev/null 2>&1
parted -s /dev/sda mklabel gpt >/dev/null 2>&1
parted -s /dev/sda mkpart primary fat32 1MiB 513MiB >/dev/null 2>&1
parted -s /dev/sda set 1 esp on >/dev/null 2>&1
parted -s /dev/sda mkpart primary ext4 513MiB 100% >/dev/null 2>&1
mkfs.fat -F32 /dev/sda1 >/dev/null 2>&1
mkfs.ext4 /dev/sda2 >/dev/null 2>&1
mount /dev/sda2 /mnt >/dev/null 2>&1
mkdir /mnt/boot >/dev/null 2>&1
mount /dev/sda1 /mnt/boot >/dev/null 2>&1
pacstrap /mnt base base-devel linux linux-firmware >/dev/null 2>&1
genfstab -U /mnt >> /mnt/fstab 2>/dev/null
arch-chroot /mnt /bin/bash <<EOF >/dev/null 2>&1
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "arch" > /etc/hostname
echo "root:123456" | chpasswd
pacman -S --noconfirm networkmanager grub efibootmgr >/dev/null 2>&1
systemctl enable NetworkManager >/dev/null 2>&1
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB >/dev/null 2>&1
grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
EOF
umount -R /mnt >/dev/null 2>&1
reboot
