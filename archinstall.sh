#!/usr/bin/env bash
# =============================================================================
# Arch Linux 2025 • УЛЬТРА-БЕЗОПАСНАЯ установка
# → Выбор диска сокращённо (sda / nvme0n1 / vda)
# → Пауза 30 сек на каждом этапе
# → Двойное подтверждение + полный вывод lsblk
# =============================================================================

set -euo pipefail

G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; B='\033[1;34m'; N='\033[0m'
log()   { echo -e "${G}[+] $1${N}"; }
warn()  { echo -e "${Y}[!] $1${N}"; }
error() { echo -e "${R}[X] $1${N}"; exit 1; }

pause() {
    echo -e "${B}════════════════════════════════════════════════════════════════${N}"
    echo -e "${B}   $1${N}"
    echo -e "${B}   Enter — продолжить сразу • ждите 30 сек — автопродолжение${N}"
    echo -e "${B}════════════════════════════════════════════════════════════════${N}"
    read -t 30 -p " → Нажмите Enter или ждите... " || echo
    echo
}

# Проверки
[[ $EUID -eq 0 ]] || error "Запускайте от root!"
[[ -d /sys/firmware/efi ]] || error "Включите UEFI в BIOS/VirtualBox!"
ping -c 1 8.8.8.8 &>/dev/null || { warn "Нет интернета!"; exit 1; }
timedatectl set-ntp true

# =============================================================================
# 1. ВЫБОР ДИСКА — СОКРАЩЁННЫЙ ВВОД
# =============================================================================
clear
echo -e "${Y}╔══════════════════════════════════════════╗${N}"
echo -e "${Y}║        ВЫБОР ДИСКА ДЛЯ УСТАНОВКИ         ║${N}"
echo -e "${Y}╚══════════════════════════════════════════╝${N}"
echo
log "Доступные диски:"
echo
lsblk -dpo NAME,SIZE,MODEL | grep -v loop
echo
echo -e "${R}ВНИМАНИЕ: ВЫБРАННЫЙ ДИСК БУДЕТ ПОЛНОСТЬЮ СТЁРТ!${N}"
echo

while true; do
    read -p "$(echo -e "${Y}Введите имя диска (например sda, nvme0n1, vda): ${N}")" SHORTDISK
    SHORTDISK=$(echo "$SHORTDISK" | xargs)

    # Автоматически подставляем /dev/
    DISK="/dev/$SHORTDISK"

    if [[ -b "$DISK" ]]; then
        echo
        warn "Вы выбрали: $DISK"
        lsblk -f "$DISK"
        echo
        read -p "$(echo -e "${R}ПОДТВЕРДИТЕ УДАЛЕНИЕ ВСЕГО НА $DISK — введите \"YES\": ${N}")" confirm
        [[ "$confirm" == "YES" ]] && break
    else
        error "Диск /dev/$SHORTDISK не найден! Попробуйте снова."
    fi
done

# =============================================================================
# ДАЛЬШЕ — ВСЁ ПО ПРЕЖНЕМУ (паузы, безопасность, VirtualBox-fallback и т.д.)
# =============================================================================

pause "Запрос паролей"
read -s -p "$(echo -e "${Y}Пароль для пользователя user: ${N}")" USERPASS; echo
read -s -p "$(echo -e "${Y}Пароль для root: ${N}")" ROOTPASS; echo
[[ ${#USERPASS} -lt 4 || ${#ROOTPASS} -lt 4 ]] && error "Пароли короткие!"

pause "ОЧИСТКА И РАЗМЕТКА ДИСКА $DISK"
wipefs -af "$DISK" &>/dev/null
sgdisk -Z "$DISK"
sgdisk -n 1:0:+1G   -t 1:ef00 -c 1:"EFI"  "$DISK"
sgdisk -n 2:0:+100G -t 2:8300 -c 2:"Root" "$DISK"
sgdisk -n 3:0:0     -t 3:8300 -c 3:"Home" "$DISK"
partprobe "$DISK"; udevadm settle; sleep 3

SUFFIX=""; [[ "$DISK" =~ ^/dev/(nvme|mmc) ]] && SUFFIX="p"
EFI_PART="${DISK}${SUFFIX}1"
ROOT_PART="${DISK}${SUFFIX}2"
HOME_PART="${DISK}${SUFFIX}3"

pause "ФОРМАТИРОВАНИЕ"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
mkfs.ext4 -F "$HOME_PART"

pause "МОНТИРОВАНИЕ"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,home}
mount "$EFI_PART" /mnt/boot
mount "$HOME_PART" /mnt/home

pause "PACSTRAP — установка базы (~5 мин)"
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || true
pacstrap -K /mnt base linux linux-firmware base-devel grub efibootmgr networkmanager \
    amd-ucode intel-ucode git vim sudo zram-generator reflector os-prober ntfs-3g

genfstab -U /mnt >> /mnt/etc/fstab

pause "ФИНАЛЬНАЯ НАСТРОЙКА (GRUB, zram, пользователи)"
cat > /mnt/root/chroot-setup.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail
HOSTNAME="arch"; USERNAME="user"; USERPASS='$USERPASS'; ROOTPASS='$ROOTPASS'; TIMEZONE='Europe/Moscow'

ln -sf /usr/share/zoneinfo/\$TIMEZONE /etc/localtime; hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen; echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen; locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
localectl set-x11-keymap us,ru pc105 ,,grp:win_space_toggle

echo "\$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   \$HOSTNAME.localdomain \$HOSTNAME
HOSTS

useradd -m -G wheel "\$USERNAME"; echo "\$USERNAME:\$USERPASS" | chpasswd; echo "root:\$ROOTPASS" | chpasswd
sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^#//' /etc/sudoers

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck
mkdir -p /boot/EFI/BOOT; cp /boot/grub/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true

git clone --depth=1 https://github.com/vinceliuice/grub2-themes.git /tmp/t 2>/dev/null && cp -r /tmp/t/themes/Vimix /boot/grub/themes/ 2>/dev/null || true

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

chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh
rm -f /mnt/root/chroot-setup.sh

pause "УСТАНОВКА ЗАВЕРШЕНА!"
log "Перезагрузка через 30 секунд..."
warn "VirtualBox: отключите ISO!"
sleep 30
umount -R /mnt
sync
reboot now
