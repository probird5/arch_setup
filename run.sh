#!/bin/bash

# Print the logo
print_logo() {
    cat << "EOF"
  ___           _       _____      _               
 / _ \         | |     /  ___|    | |              
/ /_\ \_ __ ___| |__   \ `--.  ___| |_ _   _ _ __  
|  _  | '__/ __| '_ \   `--. \/ _ \ __| | | | '_ \ 
| | | | | | (__| | | | /\__/ /  __/ |_| |_| | |_) |
\_| |_/_|  \___|_| |_| \____/ \___|\__|\__,_| .__/ 
                                            | |    
                                            |_|   
EOF
}

# Clear screen and show logo
clear
print_logo

# Exit on any error
set -e

# Source utility functions
source utils.sh

# Source the package list
if [ ! -f "packages.conf" ]; then
  echo "Error: packages.conf not found!"
  exit 1
fi

source packages.conf

echo "Starting system setup..."

# Update the system first
echo "Updating system..."
sudo pacman -Syu --noconfirm

# Install yay AUR helper if not present
if ! command -v yay &> /dev/null; then
  echo "Installing yay AUR helper..."
  sudo pacman -S --needed git base-devel --noconfirm
  git clone https://aur.archlinux.org/yay.git
  cd yay
  echo "building yay.... yaaaaayyyyy"
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
else
  echo "yay is already installed"
fi

# Install packages by category
echo "Installing system utilities..."
install_packages "${SYSTEM_UTILS[@]}"

echo "Installing development tools..."
install_packages "${DEV_TOOLS[@]}"

echo "Installing system maintenance tools..."
install_packages "${MAINTENANCE[@]}"

echo "Installing desktop environment..."
install_packages "${DESKTOP[@]}"

echo "Installing desktop environment..."
install_packages "${OFFICE[@]}"

echo "Installing media packages..."
install_packages "${MEDIA[@]}"

echo "Installing fonts..."
install_packages "${FONTS[@]}"

# Enable services
echo "Configuring services..."
for service in "${SERVICES[@]}"; do
  if ! systemctl is-enabled "$service" &> /dev/null; then
    echo "Enabling $service..."
    sudo systemctl enable "$service"
  else
    echo "$service is already enabled"
  fi
done

# Some programs just run better as flatpaks. Like discord/spotify
echo "Installing flatpaks (like discord and spotify)"
. install-flatpaks.sh

echo "Setting up default shell"
chsh -s /bin/zsh

echo "Installing Dotfiles"
. dotfiles-setup.sh

echo "Reloading config"
hyprctl reload

echo "Setup complete! You may want to reboot your system."
