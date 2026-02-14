#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Remove Snap + Install Flatpak         ${NC}"
echo -e "${CYAN}  Ubuntu Snap → Flatpak Migration       ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] This script requires root privileges. Run with sudo.${NC}"
    exit 1
fi

# User confirmation before proceeding
echo -e "${YELLOW}[!] This script will:${NC}"
echo "    1. Remove all snap packages"
echo "    2. Remove snapd from the system"
echo "    3. Block snapd from being reinstalled"
echo "    4. Install Flatpak + Flathub repository"
echo ""
read -rp "Do you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 0
fi

# --- STEP 1: Remove installed snap packages ---
echo ""
echo -e "${GREEN}[1/5] Removing installed snap packages...${NC}"

snap_list=$(snap list 2>/dev/null | awk 'NR>1 {print $1}' || true)

if [[ -n "$snap_list" ]]; then
    # First pass: remove user-installed snaps, skip core components
    for snap in $snap_list; do
        case "$snap" in
            snapd|bare|core*|gtk-common-themes|gnome-*) continue ;;
            *)
                echo -e "  ${YELLOW}→ Removing: ${snap}${NC}"
                snap remove --purge "$snap" 2>/dev/null || true
                ;;
        esac
    done

    # Second pass: remove remaining non-core snaps (gtk-common-themes, gnome-*, etc.)
    for snap in $(snap list 2>/dev/null | awk 'NR>1 {print $1}' || true); do
        case "$snap" in
            snapd|bare|core*) continue ;;
            *)
                echo -e "  ${YELLOW}→ Removing: ${snap}${NC}"
                snap remove --purge "$snap" 2>/dev/null || true
                ;;
        esac
    done

    # Final pass: remove core*, bare, and snapd itself (in reverse order)
    for snap in $(snap list 2>/dev/null | awk 'NR>1 {print $1}' | tac || true); do
        echo -e "  ${YELLOW}→ Removing: ${snap}${NC}"
        snap remove --purge "$snap" 2>/dev/null || true
    done
else
    echo -e "  ${CYAN}No snap packages found.${NC}"
fi

# --- STEP 2: Remove snapd service and package ---
echo ""
echo -e "${GREEN}[2/5] Removing snapd...${NC}"
systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
systemctl disable snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
apt remove --purge -y snapd 2>/dev/null || true
apt autoremove -y 2>/dev/null || true

# --- STEP 3: Clean up leftover snap directories ---
echo ""
echo -e "${GREEN}[3/5] Cleaning up snap leftovers...${NC}"
rm -rf /snap
rm -rf /var/snap
rm -rf /var/lib/snapd
rm -rf /var/cache/snapd
rm -rf ~/snap
echo -e "  ${CYAN}Removed snap directories.${NC}"

# --- STEP 4: Prevent snapd from being reinstalled via apt pinning ---
echo ""
echo -e "${GREEN}[4/5] Blocking snapd from being reinstalled...${NC}"

cat > /etc/apt/preferences.d/nosnap.pref << 'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

echo -e "  ${CYAN}Created /etc/apt/preferences.d/nosnap.pref${NC}"

# --- STEP 5: Install Flatpak and configure Flathub ---
echo ""
echo -e "${GREEN}[5/5] Installing Flatpak...${NC}"
apt update
apt install -y flatpak

# Install GNOME Software plugin for Flatpak integration (if GNOME Software is present)
if dpkg -l | grep -q gnome-software; then
    apt install -y gnome-software-plugin-flatpak 2>/dev/null || true
    echo -e "  ${CYAN}Installed Flatpak plugin for GNOME Software.${NC}"
fi

# Add the Flathub repository as a Flatpak remote
echo ""
echo -e "${GREEN}[+] Adding Flathub repository...${NC}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
echo -e "  ${CYAN}Flathub added.${NC}"

# --- SUMMARY ---
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}  ✓ Done!${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "  ${GREEN}✓${NC} Snap has been removed and blocked"
echo -e "  ${GREEN}✓${NC} Flatpak installed"
echo -e "  ${GREEN}✓${NC} Flathub configured"
echo ""
echo -e "${YELLOW}[!] A system reboot is recommended:${NC}"
echo -e "    sudo reboot"
echo ""
echo -e "${CYAN}Example Flatpak app installation:${NC}"
echo -e "    flatpak install flathub org.mozilla.firefox"
echo -e "    flatpak install flathub com.spotify.Client"
echo ""