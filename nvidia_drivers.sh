#!/usr/bin/env bash
# install-nvidia.sh – standalone NVIDIA driver helper for Arch Linux

###############################################################################
# 0.  Strict mode & always-defined vendor flags (prevents "unbound variable")
###############################################################################
AMD=false          # AuthenticAMD?
INTEL=false        # GenuineIntel?

set -euo pipefail  # enable "fail-fast" *after* we created the flags

###############################################################################
# 1.  General helpers & colouring
###############################################################################
RED=$(printf '\033[0;31m');   GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[0;33m'); CYAN=$(printf '\033[0;36m')
RC=$(printf '\033[0m')        # Reset colour

command_exists() { command -v "$1" >/dev/null 2>&1; }

PACKAGER=pacman          # Arch only
ESCALATION_TOOL=sudo     # script should be run as normal user

###############################################################################
# 2.  CPU-vendor detection  (runs once, sets $AMD and $INTEL)
###############################################################################
detectCpuVendor() {
    local vendor
    vendor=$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $3}')
    case "$vendor" in
        AuthenticAMD) AMD=true ;;
        GenuineIntel) INTEL=true ;;
    esac
}
detectCpuVendor

###############################################################################
# 3.  Sanity-check the environment
###############################################################################
checkEnv() {
  if ! command_exists "$PACKAGER"; then
    printf "%b\n" "${RED}Pacman not found – this script is meant for Arch Linux.${RC}"
    exit 1
  fi
}
checkEscalationTool() {
  if ! command_exists "$ESCALATION_TOOL"; then
    printf "%b\n" "${RED}sudo is required.  Please install sudo and try again.${RC}"
    exit 1
  fi
}

###############################################################################
# 4.  Dependency installation
###############################################################################
installDeps() {
  "${ESCALATION_TOOL}" "$PACKAGER" -S --needed --noconfirm \
      base-devel dkms ninja meson git

  installed_kernels=$("$PACKAGER" -Q | \
    grep -E '^(linux(-zen|-lts|-rt|-rt-lts|-hardened)?)[[:space:]]' | awk '{print $1}')

  for kernel in $installed_kernels; do
    header="${kernel}-headers"
    printf "%b\n" "${CYAN}Installing headers for ${kernel} …${RC}"
    if ! "${ESCALATION_TOOL}" "$PACKAGER" -S --needed --noconfirm "$header"; then
      printf "%b\n" "${RED}Failed to install headers for ${kernel}.${RC}"
      printf "%b"  "${YELLOW}Continue anyway? [y/N]: ${RC}"; read -r ans
      case "$ans" in y|Y) printf "%b\n" "${YELLOW}Continuing …${RC}" ;; *) exit 1 ;;
      esac
    fi
  done
}

###############################################################################
# 5.  Hardware checks & prompts
###############################################################################
checkNvidiaHardware() {
  # Returns 0 for Ada/Lovelace, 1 for older (Maxwell / Pascal / Volta)
  local code
  code=$(lspci -k | grep -A2 -E "(VGA|3D)" | \
         grep NVIDIA | sed 's/.*Corporation //;s/ .*//' | cut -c1-2)
  case "$code" in
      TU|GA|AD) return 0 ;;  # Turing / Ampere / Ada → open driver ok
      GM|GP|GV) return 1 ;;  # Maxwell / Pascal / Volta → proprietary
      *) printf "%b\n" "${RED}Unsupported NVIDIA GPU.${RC}" ; exit 1 ;;
  esac
}

checkIntelHardware() {
  $INTEL || return 1                 # skip entirely on non-Intel CPUs
  local gen
  gen=$(grep -m1 "model name" /proc/cpuinfo \
        | sed -n 's/.*Gen \([0-9]\+\).*/\1/p')
  [[ ${gen:-0} -ge 11 ]]            # Gen-11+ needs ibt=off
}

promptUser() {
  printf "%b" "$1 [y/N]: "; read -r reply
  [[ $reply == [yY] ]]
}

###############################################################################
# 6.  GRUB helpers
###############################################################################
setKernelParam() {
  local param=$1
  if grep -q "$param" /etc/default/grub; then
    printf "%b\n" "${YELLOW}${param} already present in GRUB cmdline.${RC}"
  else
    "${ESCALATION_TOOL}" sed -i \
      "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ ${param}\"/" /etc/default/grub
    printf "%b\n" "${CYAN}Added ${param} to GRUB config.${RC}"
    "${ESCALATION_TOOL}" grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

###############################################################################
# 7.  VA-API / NVDEC helper
###############################################################################
setupHardwareAcceleration() {
  if ! command_exists grub-mkconfig; then
    printf "%b\n" "${RED}Hardware acceleration helper currently supports GRUB only.${RC}"
    return
  fi

  "${ESCALATION_TOOL}" "$PACKAGER" -S --needed --noconfirm libva-nvidia-driver

  LIBVA_DIR="$HOME/.local/share/linutil/libva"
  printf "%b\n" "${CYAN}Building patched libva in ${LIBVA_DIR} …${RC}"
  mkdir -p "$LIBVA_DIR"
  rm -rf   "$LIBVA_DIR"/*
  git clone --branch=v2.22-branch --depth=1 \
      https://github.com/intel/libva "$LIBVA_DIR/src"

  mkdir -p "$LIBVA_DIR/build"
  cd "$LIBVA_DIR/build"
  arch-meson ../src -Dwith_legacy=nvctrl
  ninja
  "${ESCALATION_TOOL}" ninja install
  cd - >/dev/null

  # Firefox / Electron env vars
  "${ESCALATION_TOOL}" sed -i \
      '/^\(MOZ_DISABLE_RDD_SANDBOX\|LIBVA_DRIVER_NAME\)=/d' /etc/environment
  printf "LIBVA_DRIVER_NAME=nvidia\nMOZ_DISABLE_RDD_SANDBOX=1\n" | \
      "${ESCALATION_TOOL}" tee -a /etc/environment >/dev/null

  printf "%b\n" "${GREEN}VA-API / NVDEC acceleration enabled.${RC}"

  if promptUser "Enable HW-decoding in MPV"; then
    mkdir -p "$HOME/.config/mpv"
    sed -i '/^hwdec=/d' "$HOME/.config/mpv/mpv.conf" 2>/dev/null || true
    echo "hwdec=auto" >> "$HOME/.config/mpv/mpv.conf"
    printf "%b\n" "${GREEN}MPV configured for hardware decoding.${RC}"
  fi
}

###############################################################################
# 8.  Main installer
###############################################################################
installDriver() {
  installDeps

  if checkNvidiaHardware && promptUser "Use NVIDIA *open* driver (beta)"; then
    printf "%b\n" "${CYAN}Installing open-source driver …${RC}"
    "${ESCALATION_TOOL}" "$PACKAGER" -S --needed --noconfirm \
        nvidia-open-dkms nvidia-utils
  else
    printf "%b\n" "${CYAN}Installing proprietary driver …${RC}"
    "${ESCALATION_TOOL}" "$PACKAGER" -S --needed --noconfirm \
        nvidia-dkms nvidia-utils
  fi

  # Extra kernel parameters
  checkIntelHardware && setKernelParam "ibt=off"
  setKernelParam "nvidia.NVreg_PreserveVideoMemoryAllocations=1"

  # Systemd suspend/resume helpers
  "${ESCALATION_TOOL}" systemctl enable nvidia-suspend.service \
                                         nvidia-hibernate.service \
                                         nvidia-resume.service

  printf "%b\n" "${GREEN}Driver installed successfully.${RC}"

  if promptUser "Set up VA-API / hardware acceleration"; then
    setupHardwareAcceleration
  fi

  printf "%b\n" "${GREEN}All done – reboot to start using the new driver.${RC}"
}

###############################################################################
# 9.  Kick things off
###############################################################################
checkEnv
checkEscalationTool
installDriver

