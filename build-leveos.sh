#!/usr/bin/env bash
# =====================================================================
#  LeveOS - gerador de ISO (Arch Linux + LXQt + Catppuccin + Wine)
#  Rode em um Arch Linux (ou VM/container Arch):  sudo ./build-leveos.sh
#  Precisa de ~15 GB livres e internet. A ISO sai em ./leveos/out/
# =====================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo ./build-leveos.sh"; exit 1; }

BASE="$PWD/leveos"
PROFILE="$BASE/profile"
AIROOT="$PROFILE/airootfs"

echo "==> [1/8] Instalando ferramentas de build"
pacman -Sy --needed --noconfirm archiso git

echo "==> [2/8] Habilitando Chaotic-AUR no host (fornece o Calamares pronto)"
if ! pacman-key --list-keys 3056513887B78AEB &>/dev/null; then
  pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
  pacman-key --lsign-key 3056513887B78AEB
fi
pacman -U --noconfirm --needed \
  'https://geo-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
  'https://geo-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo "==> [3/8] Copiando perfil base (releng)"
rm -rf "$BASE"
mkdir -p "$BASE"
cp -r /usr/share/archiso/configs/releng "$PROFILE"

# --- pacman.conf do perfil: multilib (Wine 32 bits) + Chaotic-AUR
cat >> "$PROFILE/pacman.conf" <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
# mesma configuracao dentro do sistema instalado
cp "$PROFILE/pacman.conf" "$AIROOT/etc/pacman.conf"

# --- nome da ISO
sed -i 's/^iso_name=.*/iso_name="leveos"/' "$PROFILE/profiledef.sh"
sed -i 's/^iso_label=.*/iso_label="LEVEOS_$(date +%Y%m)"/' "$PROFILE/profiledef.sh"
sed -i 's/^iso_publisher=.*/iso_publisher="LeveOS"/' "$PROFILE/profiledef.sh"
sed -i 's/^iso_application=.*/iso_application="LeveOS Live\/Install"/' "$PROFILE/profiledef.sh"

echo "==> [4/8] Lista de pacotes"
cat >> "$PROFILE/packages.x86_64" <<'EOF'
# --- base / sistema
sudo
git
networkmanager
network-manager-applet
polkit
gvfs
ntfs-3g
dosfstools
btrfs-progs
mtools
os-prober
grub
efibootmgr
xdg-user-dirs
unzip
p7zip
cabextract
# --- video / audio
xorg-server
xorg-xinit
mesa
lib32-mesa
vulkan-icd-loader
lib32-vulkan-icd-loader
vulkan-radeon
lib32-vulkan-radeon
vulkan-intel
lib32-vulkan-intel
pipewire
pipewire-pulse
pipewire-alsa
wireplumber
# --- interface LXQt
sddm
openbox
lxqt-session
lxqt-panel
lxqt-runner
lxqt-config
lxqt-policykit
lxqt-themes
lxqt-qtplugin
lxqt-notificationd
lxqt-powermanagement
lxqt-globalkeys
lxqt-admin
lxqt-sudo
lxqt-archiver
pcmanfm-qt
qterminal
featherpad
lximage-qt
screengrab
pavucontrol-qt
obconf-qt
# --- tema
kvantum
papirus-icon-theme
noto-fonts
ttf-liberation
ttf-jetbrains-mono
# --- programas
firefox
# --- compatibilidade Windows
wine
wine-mono
wine-gecko
winetricks
flatpak
# --- instalador (Chaotic-AUR)
chaotic-keyring
chaotic-mirrorlist
calamares
EOF

echo "==> [5/8] Usuario live, servicos e hostname"
echo "leveos" > "$AIROOT/etc/hostname"

# usuario live sem senha
echo 'live:x:1000:1000::/home/live:/bin/bash' >> "$AIROOT/etc/passwd"
echo 'live:x:1000:' >> "$AIROOT/etc/group"
echo 'live::14871::::::' >> "$AIROOT/etc/shadow"
mkdir -p "$AIROOT/etc/sudoers.d"
echo 'live ALL=(ALL) NOPASSWD: ALL' > "$AIROOT/etc/sudoers.d/g_live"

# permissoes (profiledef.sh)
sed -i '/^file_permissions=(/a\  ["/etc/sudoers.d/g_live"]="0:0:440"\n  ["/home/live"]="1000:1000:750"' "$PROFILE/profiledef.sh"

# NetworkManager no lugar do systemd-networkd/iwd do releng
find "$AIROOT/etc/systemd/system" \( -name 'systemd-networkd*' -o -name 'iwd.service' \) -delete 2>/dev/null || true
mkdir -p "$AIROOT/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager.service \
  "$AIROOT/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
ln -sf /usr/lib/systemd/system/sddm.service \
  "$AIROOT/etc/systemd/system/display-manager.service"

# login automatico no Live
mkdir -p "$AIROOT/etc/sddm.conf.d"
cat > "$AIROOT/etc/sddm.conf.d/autologin.conf" <<'EOF'
[Autologin]
User=live
Session=lxqt.desktop
EOF

echo "==> [6/8] Visual: LXQt + Catppuccin Mocha + Papirus"
SKEL="$AIROOT/etc/skel"
mkdir -p "$SKEL/.config/lxqt" "$SKEL/.config/pcmanfm-qt/lxqt" "$SKEL/.config/Kvantum" "$SKEL/Desktop"

cat > "$SKEL/.config/lxqt/lxqt.conf" <<'EOF'
[General]
icon_theme=Papirus-Dark
theme=dark
single_click_activate=false

[Qt]
style=kvantum
font="Noto Sans,10,-1,5,50,0,0,0,0,0"
fixedFont="JetBrains Mono,10,-1,5,50,0,0,0,0,0"
EOF

cat > "$SKEL/.config/pcmanfm-qt/lxqt/settings.conf" <<'EOF'
[Desktop]
WallpaperMode=color
BgColor=#1e1e2e
FgColor=#cdd6f4
ShadowColor=#11111b
EOF

# Tema Catppuccin para o Kvantum (baixado do GitHub)
TMP="$(mktemp -d)"
if git clone --depth 1 https://github.com/catppuccin/Kvantum.git "$TMP/kv" 2>/dev/null || \
   git clone --depth 1 https://github.com/catppuccin/kvantum.git "$TMP/kv" 2>/dev/null; then
  THEME_DIR="$(find "$TMP/kv" -type d -iname 'catppuccin-mocha-mauve' | head -n1 || true)"
  if [[ -n "${THEME_DIR:-}" ]]; then
    cp -r "$THEME_DIR" "$SKEL/.config/Kvantum/"
    printf '[General]\ntheme=%s\n' "$(basename "$THEME_DIR")" > "$SKEL/.config/Kvantum/kvantum.kvconfig"
  else
    echo "AVISO: tema Catppuccin do Kvantum nao encontrado; usando tema escuro padrao."
  fi
else
  echo "AVISO: nao foi possivel baixar o tema Catppuccin; usando tema escuro padrao."
fi
rm -rf "$TMP"

# Atalhos na area de trabalho e no menu
mkdir -p "$AIROOT/usr/share/applications" "$AIROOT/usr/local/bin"

cat > "$AIROOT/usr/share/applications/leveos-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Instalar LeveOS
Comment=Instalar o LeveOS no disco
Exec=sudo -E calamares
Icon=system-software-install
Terminal=false
Categories=System;
EOF

cat > "$AIROOT/usr/local/bin/leveos-install-bottles" <<'EOF'
#!/usr/bin/env bash
# Instala o Bottles (gerenciador grafico de programas Windows) via Flatpak
set -e
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.usebottles.bottles
echo; echo "Bottles instalado! Abra pelo menu."; read -rp "Enter para fechar..."
EOF
chmod +x "$AIROOT/usr/local/bin/leveos-install-bottles"

cat > "$AIROOT/usr/share/applications/leveos-bottles.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Instalar Bottles (programas Windows)
Comment=Baixa e instala o Bottles via Flatpak (requer internet)
Exec=qterminal -e /usr/local/bin/leveos-install-bottles
Icon=wine
Terminal=false
Categories=System;
EOF

cp "$AIROOT/usr/share/applications/leveos-install.desktop" "$SKEL/Desktop/"
cp "$AIROOT/usr/share/applications/leveos-bottles.desktop" "$SKEL/Desktop/"
chmod +x "$SKEL/Desktop/"*.desktop

# home do usuario live = copia do skel
mkdir -p "$AIROOT/home/live"
cp -a "$SKEL/." "$AIROOT/home/live/"

echo "==> [7/8] Configuracao do Calamares"
CAL="$AIROOT/etc/calamares"
mkdir -p "$CAL/modules"

cat > "$CAL/settings.conf" <<'EOF'
---
modules-search: [ local ]

instances:
  - id: kernel
    module: shellprocess
    config: shellprocess-kernel.conf
  - id: cleanup
    module: shellprocess
    config: shellprocess-cleanup.conf

sequence:
  - show:
      - welcome
      - locale
      - keyboard
      - partition
      - users
      - summary
  - exec:
      - partition
      - mount
      - unpackfs
      - machineid
      - fstab
      - locale
      - keyboard
      - localecfg
      - users
      - networkcfg
      - hwclock
      - shellprocess@kernel
      - shellprocess@cleanup
      - initcpio
      - grubcfg
      - bootloader
      - umount
  - show:
      - finished

branding: default
prompt-install: false
dont-chroot: false
EOF

cat > "$CAL/modules/unpackfs.conf" <<'EOF'
---
unpack:
    - source: "/run/archiso/bootmnt/arch/x86_64/airootfs.sfs"
      sourcefs: "squashfs"
      destination: ""
EOF

cat > "$CAL/modules/shellprocess-kernel.conf" <<'EOF'
---
dontChroot: true
timeout: 120
script:
    - "cp /run/archiso/bootmnt/arch/boot/x86_64/vmlinuz-linux ${ROOT}/boot/vmlinuz-linux"
EOF

cat > "$CAL/modules/shellprocess-cleanup.conf" <<'EOF'
---
dontChroot: false
timeout: 120
script:
    - "rm -f /etc/sddm.conf.d/autologin.conf"
    - "rm -f /etc/mkinitcpio.conf.d/archiso.conf"
    - "rm -f /etc/sudoers.d/g_live"
    - "userdel -r live || true"
    - "rm -f /usr/share/applications/leveos-install.desktop"
    - "rm -f /etc/skel/Desktop/leveos-install.desktop"
EOF

cat > "$CAL/modules/initcpio.conf" <<'EOF'
---
kernel: linux
EOF

echo "==> [8/8] Gerando a ISO (pode demorar bastante)"
mkarchiso -v -w "$BASE/work" -o "$BASE/out" "$PROFILE"

echo
echo "PRONTO! ISO em: $BASE/out/"
ls -lh "$BASE/out/"
echo "Teste com:  qemu-system-x86_64 -enable-kvm -m 4G -cdrom $BASE/out/leveos-*.iso -boot d"
