#!/bin/bash

set -euo pipefail

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

# Determine real user's home (for ~/snap cleanup)
if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME=""
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

# --- STEP 1: Block snapd from being reinstalled FIRST (before apt autoremove) ---
echo ""
echo -e "${GREEN}[1/5] Blocking snapd from being reinstalled...${NC}"
cat > /etc/apt/preferences.d/nosnap.pref << 'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF
echo -e "    ${CYAN}Created /etc/apt/preferences.d/nosnap.pref${NC}"

# --- STEP 2: Remove installed snap packages ---
echo ""
echo -e "${GREEN}[2/5] Removing installed snap packages...${NC}"

if command -v snap >/dev/null 2>&1; then
    # First pass: remove user-installed snaps, skip core components
    for snap in $(snap list 2>/dev/null | awk 'NR>1 {print $1}'); do
        case "$snap" in
            snapd|bare|core*|gtk-common-themes|gnome-*) continue ;;
            *)
                echo -e "    ${YELLOW}→ Removing: ${snap}${NC}"
                snap remove --purge "$snap" 2>/dev/null || true
                ;;
        esac
    done

    # Second pass: remove remaining non-core snaps (themes, gnome runtimes, etc.)
    for snap in $(snap list 2>/dev/null | awk 'NR>1 {print $1}'); do
        case "$snap" in
            snapd|bare|core*) continue ;;
            *)
                echo -e "    ${YELLOW}→ Removing: ${snap}${NC}"
                snap remove --purge "$snap" 2>/dev/null || true
                ;;
        esac
    done

    # Final pass: retry loop for stubborn core snaps (snapd, core*, bare)
    attempts=0
    while [[ -n "$(snap list 2>/dev/null | awk 'NR>1 {print $1}')" ]] && [[ $attempts -lt 5 ]]; do
        for snap in $(snap list 2>/dev/null | awk 'NR>1 {print $1}' | tac); do
            echo -e "    ${YELLOW}→ Removing: ${snap}${NC}"
            snap remove --purge "$snap" 2>/dev/null || true
        done
        attempts=$((attempts + 1))
    done

    if [[ -n "$(snap list 2>/dev/null | awk 'NR>1 {print $1}')" ]]; then
        echo -e "    ${RED}[!] Some snaps could not be removed — continuing anyway.${NC}"
    fi
else
    echo -e "    ${CYAN}snap command not found — skipping.${NC}"
fi

# --- STEP 3: Remove snapd service and package ---
echo ""
echo -e "${GREEN}[3/5] Removing snapd...${NC}"

# Stop and disable all snapd-related services that exist
for svc in snapd.service snapd.socket snapd.apparmor.service snapd.seeded.service; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}"; then
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    fi
done

# Purge snapd (pinning from step 1 prevents reinstall via dependencies)
apt-get remove --purge -y snapd 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

# --- STEP 4: Clean up leftover snap directories ---
echo ""
echo -e "${GREEN}[4/5] Cleaning up snap leftovers...${NC}"
rm -rf /snap
rm -rf /var/snap
rm -rf /var/lib/snapd
rm -rf /var/cache/snapd
rm -rf /root/snap

# Remove the real user's ~/snap (not root's, since we're running under sudo)
if [[ -n "$USER_HOME" ]] && [[ -d "$USER_HOME/snap" ]]; then
    rm -rf "$USER_HOME/snap"
    echo -e "    ${CYAN}Removed ${USER_HOME}/snap${NC}"
fi

echo -e "    ${CYAN}Removed snap directories.${NC}"

# --- STEP 5: Install Flatpak and configure Flathub ---
echo ""
echo -e "${GREEN}[5/5] Installing Flatpak...${NC}"
apt-get update
apt-get install -y flatpak

# Install GNOME Software plugin for Flatpak integration (if GNOME Software is installed)
if dpkg-query -W -f='${Status}' gnome-software 2>/dev/null | grep -q "install ok installed"; then
    apt-get install -y gnome-software-plugin-flatpak || true
    echo -e "    ${CYAN}Installed Flatpak plugin for GNOME Software.${NC}"
fi

# Add the Flathub repository as a Flatpak remote
echo ""
echo -e "${GREEN}[+] Adding Flathub repository...${NC}"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
echo -e "    ${CYAN}Flathub added.${NC}"

# Verify pinning works
if apt-cache policy snapd 2>/dev/null | grep -q "Candidate: (none)"; then
    echo -e "    ${CYAN}Verified: snapd is pinned and blocked.${NC}"
fi

# --- SUMMARY ---
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}             ✓ Done!                    ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "    ${GREEN}✓${NC} Snap has been removed and blocked"
echo -e "    ${GREEN}✓${NC} Flatpak installed"
echo -e "    ${GREEN}✓${NC} Flathub configured"
echo ""
echo -e "${YELLOW}[!] A system reboot is recommended:${NC}"
echo -e "    sudo reboot"
echo ""
echo -e "${CYAN}Example Flatpak app installation:${NC}"
echo -e "    flatpak install flathub org.mozilla.firefox"
echo -e "    flatpak install flathub com.spotify.Client"
echo ""
