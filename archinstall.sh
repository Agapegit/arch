#!/usr/bin/env bash
# =============================================================================
# Arch Linux 2025 • БЕЗОПАСНАЯ автоматическая установка (с паузами 30 сек)
# VirtualBox + реальная машина • UEFI • Без swap • GRUB + Vimix
# Автор: Grok (xAI) • Версия от 21 ноября 2025
# =============================================================================

set -euo pipefail  # Выход при ошибке, обработка undefined vars, pipefail

# =========================== НАСТРОЙКИ (измените перед запуском!) ==============
DISK="/dev/sda"                    # ← УЖЕ С /dev/ (в VirtualBox обычно /dev/sda, проверьте lsblk)
HOSTNAME="arch"                    # Имя хоста
USERNAME="user"                    # Логин пользователя
TIMEZONE="Europe/Moscow"           # Часовой пояс (список: timedatectl list-timezones)
# =============================================================================

# Цвета для вывода
G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; B='\033[1;34m'; N='\033[0m'

log()   { echo -e "${G}[+] $1${N}"; }  # Зелёный лог
warn()  { echo -e "${Y}[!] $1${N}"; } # Жёлтое предупреждение
error() { echo -e "${R}[X] $1${N}"; exit 1; }  # Красная ошибка

# Функция: пауза 30 сек с возможностью пропуска (Enter = сразу продолжить)
pause() {
    echo -e "${B}"
    echo "════════════════════════════════════════════════════════════════"
    echo "   Следующий шаг: $1"
    echo "   Диск: $DISK будет полностью стёрт на некоторых этапах!"
    echo "   Нажмите Enter — продолжить СРАЗУ"
    echo "   Или подождите 30 секунд — продолжится автоматически"
    echo "════════════════════════════════════════════════════════════════${N}"
    read -t 30 -p " → Нажмите Enter для продолжения или ждите... " || echo
    echo
}

# =============================================================================
# 0. Проверки окружения — убеждаемся, что всё готово
# =============================================================================
log "Старт безопасной установки Arch Linux 2025 (UEFI, VB-совместимо)"
[[ $EUID -eq 0 ]] || error "Запускайте от root! (sudo bash arch-install.sh)"
[[ -d /sys/firmware/efi ]] || error "Включите UEFI в настройках VM/BIOS! (в VB: System > Enable EFI)"
[[ -b "$DISK" ]] || error "Диск $DISK не найден! (проверьте: lsblk)"

# Проверка интернета
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    warn "Нет интернета! Подключитесь (wifi-menu или ip link) и перезапустите."
    exit 1
fi

log "Все проверки пройдены. Начинаем установку через 10 секунд..."
sleep 10

# =============================================================================
# 1. Запрос паролей (безопасно, без эха)
# =============================================================================
pause "Запрос паролей для пользователя и root"
read -s -p "$(echo -e "${Y}Введите пароль для пользователя $USERNAME (минимум 4 символа): ${N}")" USERPASS; echo
read -s -p "$(echo -e "${Y}Введите пароль для root (минимум 4 символа): ${N}")" ROOTPASS; echo
[[ ${#USERPASS} -lt 4 || ${#ROOTPASS} -lt 4 ]] && error "Пароли слишком короткие (минимум 4 символа)!"

# Синхронизация времени + зеркала для скорости
timedatectl set-ntp true
log "Обновление зеркал (reflector) для быстрой установки"
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist &>/dev/null || warn "reflector не сработал, используем дефолт"
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf  # Параллельные загрузки

# =============================================================================
# 2. Очистка и разметка диска (GPT: EFI 1G + root 100G + home остальное)
# =============================================================================
pause "ПОЛНОЕ СТИРАНИЕ И РАЗМЕТКА ДИСКА $DISK (все данные потеряются!)"
log "Текущие разделы диска (проверьте lsblk -f):"
lsblk -f "$DISK"
log "Очистка и разметка..."
wipefs -af "$DISK" &>/dev/null  # Удаляем старые подписи ФС
sgdisk -Z "$DISK"              # Затираем GPT/MBR таблицы
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK"    # EFI: 1G, FAT32, тип EF00
sgdisk -n 2:0:+100G -t 2:8300 -c 2:"Root" "$DISK" # Root: 100G, ext4
sgdisk -n 3:0:0 -t 3:8300 -c 3:"Home" "$DISK"     # Home: остальное, ext4

# Обновление udev (важно в VB)
partprobe "$DISK"
udevadm settle
sleep 3

# Определение имён разделов (VB/sda: без 'p'; NVMe: с 'p')
SUFFIX=""; [[ "$DISK" =~ ^/dev/(nvme|mmc) ]] && SUFFIX="p"
EFI_PART="${DISK}${SUFFIX}1"
ROOT_PART="${DISK}${SUFFIX}2"
HOME_PART="${DISK}${SUFFIX}3"

# Проверка создания разделов
[[ -b "$EFI_PART" ]] || error "Ошибка: EFI-раздел $EFI_PART не создан! (lsblk)"
[[ -b "$ROOT_PART" ]] || error "Ошибка: Root-раздел $ROOT_PART не создан!"
log "Разделы готовы: EFI=$EFI_PART, Root=$ROOT_PART, Home=$HOME_PART"

# =============================================================================
# 3. Форматирование разделов
# =============================================================================
pause "ФОРМАТИРОВАНИЕ разделов (irreversible — все данные стираются!)"
log "Форматирование..."
mkfs.fat -F32 "$EFI_PART"      # EFI: FAT32
mkfs.ext4 -F "$ROOT_PART"      # Root: ext4 (быстрое, -F = force)
mkfs.ext4 -F "$HOME_PART"      # Home: ext4

# =============================================================================
# 4. Монтирование файловых систем
# =============================================================================
pause "Монтирование (root в /mnt, EFI в /boot, home в /mnt/home)"
mount "$ROOT_PART" /mnt || error "Ошибка монтирования root!"
mkdir -p /mnt/{boot,home}
mount "$EFI_PART" /mnt/boot || error "Ошибка монтирования EFI в /boot!"
mount "$HOME_PART" /mnt/home || error "Ошибка монтирования home!"

# Генерация fstab с UUID (persistent в VB)
genfstab -U /mnt >> /mnt/etc/fstab
log "fstab сгенерирован с UUID. Проверьте: cat /mnt/etc/fstab"

# =============================================================================
# 5. Установка базовой системы (pacstrap)
# =============================================================================
pause "Установка базовой системы (pacstrap) — ~3-5 минут (зависит от интернета)"
pacstrap -K /mnt \
    base linux linux-firmware base-devel grub efibootmgr \
    networkmanager amd-ucode intel-ucode git vim sudo zram-generator reflector \
    os-prober ntfs-3g neofetch htop curl wget unzip p7zip bash-completion

# =============================================================================
# 6. Chroot: Финальная настройка (локаль, GRUB, zram, пользователи)
# =============================================================================
pause "Финальная настройка в chroot (GRUB с VB-fallback, zram, пароли)"
cat > /mnt/root/chroot-setup.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Переменные из основного скрипта
HOSTNAME='$HOSTNAME'
USERNAME='$USERNAME'
USERPASS='$USERPASS'
ROOTPASS='$ROOTPASS'
TIMEZONE='$TIMEZONE'

# ─── Локаль, время и раскладки ───
ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf  # Консоль: us (ru по Alt+Shift)
localectl set-x11-keymap us,ru pc105 "" grp:win_space_toggle  # X11/Wayland: Win+Space

# ─── Хостнейм и сеть ───
echo "\$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   \$HOSTNAME.localdomain \$HOSTNAME
HOSTS

# ─── Пользователь и sudo ───
useradd -m -G wheel "\$USERNAME" -s /bin/bash
echo "\$USERNAME:\$USERPASS" | chpasswd
echo "root:\$ROOTPASS" | chpasswd
sed -i '/%wheel ALL=(ALL:ALL) ALL/s/^# //' /etc/sudoers  # Включаем sudo для wheel

# ─── GRUB: Установка + тема Vimix (опционально) + VB-fallback ───
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck || warn "grub-install warning (VB quirk)"
pacman -Syy --noconfirm os-prober ntfs-3g  # Для dual-boot

# Тема Vimix (git clone, игнор ошибок если нет сети)
if command -v git &>/dev/null && git clone --depth=1 https://github.com/vinceliuice/grub2-themes.git /tmp/grub-themes 2>/dev/null; then
    cp -r /tmp/grub-themes/themes/Vimix /boot/grub/themes/ 2>/dev/null || true
    rm -rf /tmp/grub-themes
fi

cat > /etc/default/grub << 'GRUB'
GRUB_TIMEOUT=4
GRUB_TIMEOUT_STYLE=menu
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=y
GRUB_DISABLE_RECOVERY=true
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 nowatchdog"
GRUB_GFXMODE=auto
GRUB_THEME="/boot/grub/themes/Vimix/theme.txt"
GRUB_DISABLE_OS_PROBER=false
GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# VB EFI-fallback: Копируем grubx64.efi в BOOT/BOOTX64.EFI (VB "забывает" NVRAM)
mkdir -p /boot/EFI/BOOT
cp /boot/grub/grubx64.efi /boot/EFI/BOOT/BOOTX64.EFI 2>/dev/null || true

# ─── zram (вместо swap), reflector.timer, NetworkManager ───
cat > /etc/systemd/zram-generator.conf << ZRAM
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
ZRAM
systemctl enable systemd-zram-setup@zram0.service

# Авто-обновление зеркал (reflector.timer)
cat > /etc/systemd/system/reflector.service << REF_SVC
[Unit]
Description=Update mirrorlist

[Service]
Type=oneshot
ExecStart=/usr/bin/reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
REF_SVC

cat > /etc/systemd/system/reflector.timer << REF_TIMER
[Unit]
Description=Run reflector every 6h

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
REF_TIMER
systemctl daemon-reload
systemctl enable reflector.timer

systemctl enable NetworkManager

echo "Chroot-настройка завершена! Готово к загрузке."
EOF

# Запуск chroot-скрипта
chmod +x /mnt/root/chroot-setup.sh
arch-chroot /mnt /root/chroot-setup.sh
rm -f /mnt/root/chroot-setup.sh  # Очистка временных файлов

# =============================================================================
# 7. Завершение: Размонтирование + авто-reboot
# =============================================================================
pause "УСТАНОВКА ЗАВЕРШЕНА! Перезагрузка через 30 секунд"
log "Система установлена успешно! Проверьте: lsblk, mount | grep /mnt"
warn "В VirtualBox: отключите ISO в Storage перед перезагрузкой!"
warn "Если EFI-shell — F12 > Boot Manager > EFI Hard Drive"
sleep 30
umount -R /mnt  # Размонтировать всё
sync  # Синхронизация дисков
log "Перезагрузка в новую систему..."
reboot now
