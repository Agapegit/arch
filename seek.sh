#!/bin/bash
set -e
loadkeys us
timedatectl set-ntp true
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary fat32 1MiB 513MiB
parted -s /dev/sda set 1 esp on
parted -s /dev/sda mkpart primary ext4 513MiB 100%
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2
mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
pacstrap /mnt base base-devel linux linux-firmware
genfstab -U /mnt >> /mnt/fstab
arch-chroot /mnt /bin/bash <<EOF >/dev/null 2>&1
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "arch" > /etc/hostname

### --- ROOT PASSWORD --- ###
echo "Установка пароля root"
passwd

### --- USER CREATION --- ###
read -rp "Введите имя пользователя: " USERNAME
useradd -m -G wheel -s /bin/bash "$USERNAME"

echo "Установка пароля пользователя $USERNAME"
passwd "$USERNAME"

pacman -S --noconfirm networkmanager grub efibootmgr
systemctl enable NetworkManager
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF
umount -R /mnt
reboot
