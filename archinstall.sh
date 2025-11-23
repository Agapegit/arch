#!/usr/bin/env bash
# =============================================================================
# Arch Linux 2025 • 100% ИНТЕРАКТИВНАЯ установка с выбором размеров
# → Вводите размер Root или Enter → авто (50–300 ГБ)
# → Полностью безопасно, Btrfs/LUKS-proof, fdisk, VirtualBox-совместимо
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
# 1. Выбор диска
# =============================================================================
clear
echo -e "${Y}╔══════════════════════════════════════╗${N}"
echo -e "${Y}║          ВЫБОР ДИСКА ДЛЯ УСТАНОВКИ   ║${N}"
echo -e "${Y}╚══════════════════════════════════════╝${N}"
lsblk -dpo NAME,SIZE,MODEL | grep -v loop
echo -e "${R}ДИСК БУДЕТ ПОЛНОСТЬЮ УНИЧТОЖЕН!${N}"

while true; do
    read -p "$(echo -e "${Y}Имя диска (sda / nvme0n1 / vda): ${N}")" SHORT
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
# 3. Определяем размер диска и предлагаем Root
# =============================================================================
pause "ВЫБОР РАЗМЕРА РАЗДЕЛА ROOT"
TOTAL_GB=$(( $(blockdev --getsz "$DISK") * 512 / 1024 / 1024 / 1024 ))

echo -e "${Y}Размер диска: ${TOTAL_GB} ГБ${N}"
echo "Рекомендуется:"
if (( TOTAL_GB < 150 )); then
    DEFAULT_ROOT="+50G"
    echo " → Root: 50 ГБ (для маленьких дисков)"
elif (( TOTAL_GB < 600 )); then
    DEFAULT_ROOT="+100G"
    echo " → Root: 100 ГБ (оптимально)"
elif (( TOTAL_GB < 1500 )); then
    DEFAULT_ROOT="+200G"
    echo " → Root: 200 ГБ (для больших дисков)"
else
    DEFAULT_ROOT="+300G"
    echo " → Root: 300 ГБ (для очень больших дисков)"
fi

echo
read -p "$(echo -e "${Y}Введите размер Root (например 150G) или Enter → $DEFAULT_ROOT: ${N}")" INPUT_ROOT
ROOT_SIZE="${INPUT_ROOT:-$DEFAULT_ROOT}"

# Проверка корректности ввода
if [[ -n "$INPUT_ROOT" ]]; then
    if ! [[ "$ROOT_SIZE" =~ ^\+[0-9]+[GMK]$ ]]; then
        error "Неверный формат! Пример: 120G или +150G"
    fi
fi

log "Будет создано: EFI 1G | Root $ROOT_SIZE | Home — остальное"

# =============================================================================
# 4. Полная очистка (Btrfs/LUKS/ZFS-proof)
# =============================================================================
pause "ПОЛНАЯ ОЧИСТКА ДИСКА $DISK"
dd if=/dev/zero of="$DISK" bs=1M count=100 status=none 2>/dev/null || true
dd if=/dev/zero of="$DISK" bs=1M seek=$(( $(blockdev --getsz "$DISK") * 512 / 1024 / 1024 - 100 )) count=100 status=none 2>/dev/null || true
wipefs -af "$DISK" &>/dev/null || true
sgdisk --zap-all "$DISK" &>/dev/null || true
sync

# =============================================================================
# 5. Разметка через fdisk с вашим размером Root
# =============================================================================
pause "РАЗМЕТКА ДИСКА"
{
    echo g                # новая GPT
    echo n; echo 1; echo; echo +1G;   echo t; echo 1; echo ef
    echo n; echo 2; echo; echo "$ROOT_SIZE"; echo t; echo 2; echo 83
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
# 6–9. Форматирование → pacstrap → chroot → готово
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
export USERPASS ROOTPASS

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
mkdir -p /boot/EFI/BOOT; cp /boot/grub/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true

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

pause "УСТАНОВКА ЗАВЕРШЕНА!"
log "Перезагрузка через 30 сек..."
sleep 30
umount -R /mnt
sync
reboot now
