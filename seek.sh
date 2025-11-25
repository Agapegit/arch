#!/bin/bash
set -e
loadkeys ru
timedatectl set-ntp true
echo "Разметка диска"
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary fat32 1MiB 513MiB
parted -s /dev/sda set 1 esp on
parted -s /dev/sda mkpart primary ext4 513MiB 100%
echo "Форматирование разделов"
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
echo "Монтирование разделов"
mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
echo "Установка базовой системы"
pacstrap /mnt base base-devel linux linux-firmware
echo "Генерация fstab"
genfstab -U /mnt >> /mnt/fstab
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "arch" > /etc/hostname
echo "root:123456" | chpasswd
pacman -S --noconfirm networkmanager grub efibootmgr
systemctl enable NetworkManager
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF
echo "Установка завершена"
umount -R /mnt
reboot
