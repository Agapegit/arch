#!/usr/bin/env bash
set -euo pipefail

echo "=== Установка Arch Linux ==="
read -rp "Введите диск для установки (пример: sda или nvme0n1): " DISK

# Определяем путь
if [[ "$DISK" == nvme* ]]; then
    DISK_PATH="/dev/${DISK}"
    P1="${DISK_PATH}p1"
    P2="${DISK_PATH}p2"
else
    DISK_PATH="/dev/${DISK}"
    P1="${DISK_PATH}1"
    P2="${DISK_PATH}2"
fi

echo "Выбран диск: $DISK_PATH"
read -rp "!!! ВНИМАНИЕ: ДИСК БУДЕТ ПОЛНОСТЬЮ ОЧИЩЕН. Продолжить? (yes/no): " OK
[[ "$OK" == "yes" ]] || exit 1


echo "=== Разметка диска ==="
sgdisk -Z "$DISK_PATH"
sgdisk -o "$DISK_PATH"

sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK_PATH"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK_PATH"


echo "=== Форматирование ==="
mkfs.fat -F32 "$P1"
mkfs.btrfs "$P2"


echo "=== Создание btrfs subvolumes ==="
mount "$P2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt


echo "=== Монтирование subvolumes ==="
mount -o compress=zstd,subvol=@ "$P2" /mnt

mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg,.snapshots}
mount -o compress=zstd,subvol=@home       "$P2" /mnt/home
mount -o compress=zstd,subvol=@log        "$P2" /mnt/var/log
mount -o compress=zstd,subvol=@pkg        "$P2" /mnt/var/cache/pacman/pkg
mount -o compress=zstd,subvol=@snapshots  "$P2" /mnt/.snapshots

mount "$P1" /mnt/boot


echo "=== Установка базовой системы ==="
pacstrap /mnt base linux linux-firmware btrfs-progs networkmanager grub efibootmgr


echo "=== Генерация fstab ==="
genfstab -U /mnt >> /mnt/etc/fstab


echo "=== Создание post-config.sh ==="

cat << 'EOF' > /mnt/root/post-config.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=== Пост-настройка Arch Linux в chroot ==="

### --- ЛОКАЛЬ --- ###
echo "Настройка локали..."
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

### --- TIMEZONE --- ###
echo "Настройка часового пояса..."
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

### --- HOSTNAME --- ###
read -rp "Введите hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname

cat <<EOT > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOT

### --- NETWORKMANAGER --- ###
echo "Включение NetworkManager..."
systemctl enable NetworkManager

### --- ROOT PASSWORD --- ###
echo "Установка пароля root"
passwd

### --- USER CREATION --- ###
read -rp "Введите имя пользователя: " USERNAME
useradd -m -G wheel -s /bin/bash "$USERNAME"

echo "Установка пароля пользователя $USERNAME"
passwd "$USERNAME"

# Разрешаем sudo для wheel
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

### --- GRUB --- ###
echo "Установка GRUB EFI..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Пост-настройка завершена ==="
EOF

chmod +x /mnt/root/post-config.sh


echo "=== Вход в chroot и запуск post-config.sh ==="
arch-chroot /mnt /root/post-config.sh


echo "=== Очистка и размонтирование ==="
sync

umount -R /mnt || true

echo "=== Перезагрузка ==="
reboot
