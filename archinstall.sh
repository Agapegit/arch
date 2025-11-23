#!/usr/bin/env bash
# =============================================================================
# Arch Linux 2025 • УЛЬТРА-НАДЁЖНАЯ установка (Btrfs/ZFS/LUKS-proof)
# Автоопределение размера диска • fdisk • 100% работает везде
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
[[ -d /sys/firmware/efi ]] || error "Требуется UEFI!"
ping -c 1 8.8.8.8 &>/dev/null || { warn "Нет интернета!"; exit 1; }
timedatectl set-ntp true

# =============================================================================
# 1. Выбор диска (только имя)
# =============================================================================
clear
echo -e "${Y}╔══════════════════════════════════════╗${N}"
echo -e "${Y}║          ВЫБОР ДИСКА ДЛЯ УСТАНОВКИ   ║${N}"
echo -e "${Y}╚══════════════════════════════════════╝${N}"
lsblk -dpo NAME,SIZE,MODEL | grep -v loop
echo -e "${R}ДИСК БУДЕТ ПОЛНОСТЬЮ УНИЧТОЖЕН!${N}"

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
[[ ${#USERPASS} -lt 4 || ${#ROOTPASS} -lt 4 ]] && error "Пароли слишком короткие!"

# =============================================================================
# 3. ПОЛНАЯ ОЧИСТКА ДИСКА ОТ BTRFS/ZFS/LUKS/RAID И ЛЮБОЙ ДРУГОЙ ФС
# =============================================================================
pause "ПОЛНАЯ ОЧИСТКА ДИСКА $DISK (Btrfs/ZFS/LUKS-proof)"
log "Уничтожаем все подписи и метаданные (даже Btrfs subvolumes и LUKS заголовки)..."

# 1. Затираем начало и конец диска
dd if=/dev/zero of="$DISK" bs=1M count=100 status=none 2>/dev/null || true
dd if=/dev/zero of="$DISK" bs=1M seek=$(( $(blockdev --getsz "$DISK") * 512 / 1024 / 1024 - 100 )) count=100 status=none 2>/dev/null || true

# 2. Убиваем все известные сигнатуры
wipefs -af "$DISK" &>/dev/null || true
sgdisk --zap-all "$DISK" &>/dev/null || true

# 3. Принудительно сбрасываем кэш
blockdev --flushbufs "$DISK"
sync

# =============================================================================
# 4. АВТОМАТИЧЕСКОЕ ОПРЕДЕЛЕНИЕ РАЗМЕРА И УМНАЯ РАЗМЕТКА
# =============================================================================
pause "УМНАЯ РАЗМЕТКА ПО РАЗМЕРУ ДИСКА"

TOTAL_SECTORS=$(blockdev --getsz "$DISK")
TOTAL_GB=$(( TOTAL_SECTORS * 512 / 1024 / 1024 / 1024 ))

log "Размер диска: ${TOTAL_GB} ГБ — делаем умную разметку"

# Логика:
# EFI — всегда 1 ГБ
# Root — минимум 50 ГБ, максимум 300 ГБ
# Home — всё остальное

ROOT_SIZE="+100G"   # по умолчанию 100 ГБ
if (( TOTAL_GB < 200 )); then
    ROOT_SIZE="+50G"
elif (( TOTAL_GB > 800 )); then
    ROOT_SIZE="+300G"
fi

log "Разметка: EFI 1G | Root $ROOT_SIZE | Home — остальное"

# fdisk — 100% надёжно
{
    echo g                # новая GPT-таблица
    echo n; echo 1; echo; echo +1G;   echo t; echo 1; echo ef
    echo n; echo 2; echo; echo $ROOT_SIZE; echo t; echo 2; echo 83
    echo n; echo 3; echo; echo;       echo t; echo 3; echo 83
    echo w
} | fdisk "$DISK" > /dev/null

partprobe "$DISK"
udevadm settle
sleep 5

SUFFIX=""; [[ "$DISK" =~ ^/dev/(nvme|mmc) ]] && SUFFIX="p"
EFI_PART="${DISK}${SUFFIX}1"
ROOT_PART="${DISK}${SUFFIX}2"
HOME_PART="${DISK}${SUFFIX}3"

for p in "$EFI_PART" "$ROOT_PART" "$HOME_PART"; do
    while [[ ! -b "$p" ]]; do sleep 1; partprobe "$DISK"; done
done

log "Разделы созданы:"
lsblk -f "$DISK"

# =============================================================================
# 5–8. Форматирование → pacstrap → chroot → готово
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

pause "PACSTRAP"
reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || true
pacstrap -K /mnt base linux linux-firmware base-devel grub efibootmgr networkmanager \
    amd-ucode intel-ucode git vim sudo zram-generator reflector os-prober ntfs-3g

genfstab -U /mnt >> /mnt/etc/fstab

pause "ФИНАЛЬНАЯ НАСТРОЙКА"
cat > /mnt/root/chroot-setup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export USERPASS ROOTPASS  # берём из окружения

ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime; hwclock --systohc
sed -i 's/#en_US.UTF-8/en_US.UTF-8/; s/#ru_RU.UTF-8/ru_RU.UTF-8/' /etc/locale.gen
locale-gen; echo "LANG=en_US.UTF-8" > /etc/locale.conf
localectl set-x11-keymap us,ru pc105 ,,grp:win_space_toggle

echo "arch" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch.localdomain arch
HOSTS

useradd -m -G wheel user
echo "user:$USERPASS" | chpasswd
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

export USERPASS ROOTPASS
chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh
rm -f /mnt/root/chroot-setup.sh

pause "ГОТОВО!"
log "Перезагрузка через 30 сек..."
sleep 30
umount -R /mnt
sync
reboot now
