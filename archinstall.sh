#!/usr/bin/env bash
# =============================================================================
# Arch Linux 2025 • 100% рабочая установка с fdisk (без sgdisk!)
# → Выбор диска сокращённо (sda / nvda / nvme0n1)
# → Пауза 30 сек на каждом этапе
# → Полностью безопасно + VirtualBox-совместимо
# =============================================================================

set -euo pipefail

G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; B='\033[1;34m'; N='\033[0m'
log()   { echo -e "${G}[+] $1${N}"; }
warn()  { echo -e "${Y}[!] $1${N}"; }
error() { echo -e "${R}[X] $1${N}"; exit 1; }

pause() {
    echo -e "${B}════════════════════════════════════════════════════════════════${N}"
    echo -e "${B}   $1${N}"
    echo -e "${B}   Enter — сразу • ждите 30 сек — автопродолжение${N}"
    echo -e "${B}════════════════════════════════════════════════════════════════${N}"
    read -t 30 -p " → Нажмите Enter или ждите... " || echo
    echo
}

# Проверки
[[ $EUID -eq 0 ]] || error "Запускайте от root!"
[[ -d /sys/firmware/efi ]] || error "Требуется UEFI-режим!"
ping -c 1 8.8.8.8 &>/dev/null || { warn "Нет интернета!"; exit 1; }
timedatectl set-ntp true

# =============================================================================
# 1. Выбор диска (вводим только имя)
# =============================================================================
clear
echo -e "${Y}╔══════════════════════════════════════╗${N}"
echo -e "${Y}║          ВЫБОР ДИСКА ДЛЯ УСТАНОВКИ   ║${N}"
echo -e "${Y}╚══════════════════════════════════════╝${N}"
lsblk -dpo NAME,SIZE,MODEL | grep -v loop
echo -e "${R}ДИСК БУДЕТ ПОЛНОСТЬЮ СТЁРТ!${N}"

while true; do
    read -p "$(echo -e "${Y}Введите имя диска (sda / nvme0n1 / vda): ${N}")" SHORT
    SHORT=$(echo "$SHORT" | xargs)
    DISK="/dev/$SHORT"
    [[ -b "$DISK" ]] || { error "Диск $DISK не найден!"; continue; }
    lsblk -f "$DISK"
    read -p "$(echo -e "${R}Подтвердите удаление $DISK — введите YES: ${N}")" ok
    [[ "$ok" == "YES" ]] && break
done

# =============================================================================
# 2. Пароли
# =============================================================================
pause "Запрос паролей"
read -s -p "Пароль пользователя user: " USERPASS; echo
read -s -p "Пароль root: " ROOTPASS; echo
[[ ${#USERPASS} -lt 4 || ${#ROOTPASS} -lt 4 ]] && error "Слишком короткие пароли!"

# =============================================================================
# 3. РАЗМЕТКА ЧЕРЕЗ fdisk — 100% работает везде!
# =============================================================================
pause "РАЗМЕТКА ДИСКА $DISK ЧЕРЕЗ fdisk (надёжно и просто)"

log "Очистка и создание GPT-таблицы..."
printf "g\nw\n" | fdisk "$DISK" > /dev/null

log "Создание разделов..."
{
    echo n; echo 1; echo; echo +1G;   echo t; echo 1; echo ef
    echo n; echo 2; echo; echo +100G; echo t; echo 2; echo 83
    echo n; echo 3; echo; echo;       echo t; echo 3; echo 83
    echo w
} | fdisk "$DISK" > /dev/null

# Ждём появления разделов
partprobe "$DISK"
udevadm settle
sleep 5

# Определяем имена
SUFFIX=""; [[ "$DISK" =~ ^/dev/(nvme|mmc) ]] && SUFFIX="p"
EFI_PART="${DISK}${SUFFIX}1"
ROOT_PART="${DISK}${SUFFIX}2"
HOME_PART="${DISK}${SUFFIX}3"

for p in "$EFI_PART" "$ROOT_PART" "$HOME_PART"; do
    while [[ ! -b "$p" ]]; do sleep 1; partprobe "$DISK"; done
done

log "Разделы созданы успешно:"
lsblk -f "$DISK"

# =============================================================================
# 4–7. Остальное без изменений (форматирование → pacstrap → chroot)
# =============================================================================
pause "ФОРМАТИРОВАНИЕ"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
mkfs.ext4 -F "$HOME_PART"

pause "МОНТИРОВАНИЕ"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,home}
mount "$EFI_PART" /mnt/boot
mount "$HOME_PART" /mnt/home

pause "PACSTRAP — установка базы"
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || true
pacstrap -K /mnt base linux linux-firmware base-devel grub efibootmgr networkmanager \
    amd-ucode intel-ucode git vim sudo zram-generator reflector os-prober ntfs-3g

genfstab -U /mnt >> /mnt/etc/fstab

pause "ФИНАЛЬНАЯ НАСТРОЙКА"
cat > /mnt/root/chroot-setup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HOSTNAME="arch"; USERNAME="user"; TIMEZONE='Europe/Moscow'

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime; hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen; echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen; locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
localectl set-x11-keymap us,ru pc105 ,,grp:win_space_toggle

echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$USERPASS" | chpasswd
echo "root:$ROOTPASS" | chpasswd
sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^#//' /etc/sudoers

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
mkdir -p /boot/EFI/BOOT
cp /boot/grub/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true

git clone --depth=1 https://github.com/vinceliuice/grub2-themes.git /tmp/t 2>/dev/null && \
    cp -r /tmp/t/themes/Vimix /boot/grub/themes/ 2>/dev/null || true

cat > /etc/default/grub <<'GRUB'
GRUB_TIMEOUT=4
GRUB_TIMEOUT_STYLE=menu
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 nowatchdog"
GRUB_THEME="/boot/grub/themes/Vimix/theme.txt"
GRUB_DISABLE_OS_PROBER=false
GRUB
grub-mkconfig -o /boot/grub/grub.cfg

cat > /etc/systemd/zram-generator.conf <<Z
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
Z
systemctl enable systemd-zram-setup@zram0.service reflector.timer NetworkManager
EOF

# Передаём пароли в chroot
export USERPASS ROOTPASS
chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh
rm -f /mnt/root/chroot-setup.sh

pause "УСТАНОВКА ЗАВЕРШЕНА!"
log "Перезагрузка через 30 сек..."
warn "VirtualBox: отключите ISO!"
sleep 30
umount -R /mnt
sync
reboot now
