#!/usr/bin/env bash
set -Eeuo pipefail

# setup-arch-43pr.sh
# Prepara um Arch Linux recém-instalado para o ambiente 43PR/dotfiles.
# NÃO particiona discos e NÃO reinstala o sistema.
# Execute como usuário normal (não como root):
#   chmod +x setup-arch-43pr.sh
#   ./setup-arch-43pr.sh

REPO_URL="https://github.com/43PR/dotfiles.git"
REPO_DIR="${HOME}/Projects/43pr-dotfiles"
LOG_FILE="${HOME}/setup-43pr-$(date +%Y%m%d-%H%M%S).log"

exec > >(tee -a "$LOG_FILE") 2>&1

info() { printf '\n\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\n\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[AVISO]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'printf "\n[ERRO] Falha na linha %s. Consulte: %s\n" "$LINENO" "$LOG_FILE" >&2' ERR

[[ $EUID -ne 0 ]] || fail "Execute como usuário normal, não com sudo/root."
command -v sudo >/dev/null 2>&1 || fail "sudo não foi encontrado."
command -v pacman >/dev/null 2>&1 || fail "pacman não foi encontrado; este script é para Arch Linux."

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" == *arch* ]] || fail "Distribuição não parece ser Arch/Arch-based: ${PRETTY_NAME:-desconhecida}"
fi

info "Solicitando sudo uma vez para as etapas administrativas..."
sudo -v

info "Ativando NetworkManager..."
sudo systemctl enable --now NetworkManager

if ! getent ahosts archlinux.org >/dev/null 2>&1; then
  cat <<'MSG'

A rede/DNS ainda não está funcionando.
Se estiver no Wi-Fi, conecte manualmente e rode o script de novo:

  nmcli radio wifi on
  nmcli device wifi list
  nmcli device wifi connect "NOME_DO_WIFI" password "SENHA"

MSG
  fail "Sem resolução DNS para archlinux.org."
fi
ok "Rede/DNS funcionando."

info "Configurando locale pt_BR.UTF-8, teclado ABNT2 e fuso horário..."
if grep -qE '^#?pt_BR\.UTF-8 UTF-8' /etc/locale.gen; then
  sudo sed -i 's/^#\s*pt_BR\.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
else
  echo 'pt_BR.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
fi
sudo locale-gen
sudo localectl set-locale LANG=pt_BR.UTF-8
sudo localectl set-keymap br-abnt2
sudo timedatectl set-timezone America/Sao_Paulo
sudo timedatectl set-ntp true

info "Atualizando o sistema e instalando base de hardware Intel/Wayland..."
sudo pacman -Syu --needed --noconfirm \
  git base-devel curl wget openssh \
  intel-ucode mesa vulkan-intel intel-media-driver \
  libva-utils mesa-utils vulkan-tools sof-firmware \
  polkit-kde-agent

# O notebook deste setup usa Intel Core i7-1165G7 / Iris Xe.
# Não falha se lspci não estiver disponível; é apenas informativo.
if command -v lspci >/dev/null 2>&1; then
  info "GPU detectada:"
  lspci -k | grep -A3 -E 'VGA|3D|Display' || true
fi

info "Regenerando GRUB para incluir o microcode Intel, se o GRUB estiver presente..."
if [[ -f /boot/grub/grub.cfg ]] && command -v grub-mkconfig >/dev/null 2>&1; then
  sudo grub-mkconfig -o /boot/grub/grub.cfg
else
  warn "GRUB não detectado em /boot/grub; etapa ignorada."
fi

info "Preparando diretório permanente do 43PR..."
mkdir -p "${HOME}/Projects"

if [[ -d "${REPO_DIR}/.git" ]]; then
  info "Repositório já existe em ${REPO_DIR}. Atualizando por fast-forward..."
  if ! git -C "$REPO_DIR" pull --ff-only; then
    fail "Não foi possível atualizar o repositório sem sobrescrever mudanças locais. Resolva o Git manualmente e rode novamente."
  fi
elif [[ -e "$REPO_DIR" ]]; then
  fail "${REPO_DIR} já existe, mas não é um clone Git válido. Renomeie/remova esse diretório e rode novamente."
else
  git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

info "Ajustando teclado do Hyprland para layout brasileiro (br)..."
HYPR_FILE="${REPO_DIR}/.config/hypr/hyprland.lua"
if [[ -f "$HYPR_FILE" ]]; then
  if grep -q 'kb_layout = "us"' "$HYPR_FILE"; then
    sed -i 's/kb_layout = "us"/kb_layout = "br"/' "$HYPR_FILE"
  elif grep -q 'kb_layout = "br"' "$HYPR_FILE"; then
    ok "Hyprland já está com kb_layout = br."
  else
    warn "Não encontrei a linha kb_layout esperada em $HYPR_FILE; revise o arquivo após a instalação."
  fi
else
  fail "Arquivo Hyprland não encontrado: $HYPR_FILE"
fi

info "Executando o instalador oficial do 43PR/dotfiles..."
chmod +x install.sh update.sh
./install.sh

info "Ativando Bluetooth (pacote bluez é instalado pelo 43PR)..."
if systemctl list-unit-files bluetooth.service >/dev/null 2>&1; then
  sudo systemctl enable --now bluetooth.service
else
  warn "bluetooth.service não encontrado; ignore se não usar Bluetooth."
fi

info "Garantindo NetworkManager ativo após a instalação..."
sudo systemctl enable --now NetworkManager

info "Validações rápidas..."
printf 'Locale:      '; localectl status | sed -n 's/^ *System Locale: //p' || true
printf 'VC Keymap:   '; localectl status | sed -n 's/^ *VC Keymap: //p' || true
printf 'Hyprland:    '; command -v Hyprland || true
printf 'Quickshell:  '; command -v qs || command -v quickshell || true
printf 'Kitty:       '; command -v kitty || true
printf 'Zsh:         '; command -v zsh || true
printf 'Config link: '; readlink -f "$HOME/.config/hypr/hyprland.lua" || true

cat <<EOF2

==============================================
  Preparação do 43PR concluída
==============================================

Log completo:
  $LOG_FILE

Repositório permanente:
  $REPO_DIR

Próximos passos:
  1. Faça logout e login novamente para aplicar o Zsh.
  2. No TTY, execute:
       Hyprland
  3. NÃO instale display manager ainda; valide primeiro o desktop manualmente.

Observação:
  O atalho Super+B do 43PR aponta para Brave, mas o repositório não instala
  Brave automaticamente. Podemos configurar Brave/Chrome depois.

EOF2
