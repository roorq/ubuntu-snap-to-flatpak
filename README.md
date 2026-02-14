# 🔄 Ubuntu Snap to Flatpak Migration Script

A one-liner bash script that completely removes Snap from Ubuntu and replaces it with Flatpak + Flathub.

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/roorq/ubuntu-snap-to-flatpak/main/migrate.sh)"

📋 What does it do?
Step	Action
1	Removes all installed snap packages (in correct dependency order)
2	Stops and removes the snapd service
3	Cleans up leftover snap directories (/snap, /var/snap, /var/lib/snapd, ~/snap)
4	Blocks snapd from being reinstalled via apt pinning
5	Installs Flatpak, GNOME Software plugin, and adds Flathub repository
⚙️ Requirements
OS: Ubuntu 20.04 / 22.04 / 24.04 (or derivatives)
Privileges: Root (sudo)
Internet connection required
🛡️ Safety Features
✅ Requires explicit user confirmation before proceeding
✅ Removes snaps in correct order (apps → themes → core → snapd)
✅ Gracefully handles missing packages and services
✅ Non-destructive — does not affect non-snap applications
📦 After Installation

Install apps from Flathub:

# Browse available apps
flatpak search <app_name>

# Install examples
flatpak install flathub org.mozilla.firefox
flatpak install flathub com.spotify.Client
flatpak install flathub com.visualstudio.code

# Run an app
flatpak run org.mozilla.firefox

# Update all apps
flatpak update

🔓 Reverting Changes

To re-enable snap if needed:

# Remove the apt pin
sudo rm /etc/apt/preferences.d/nosnap.pref

# Reinstall snapd
sudo apt update && sudo apt install snapd

⚠️ Disclaimer

This script modifies system packages and services. Use at your own risk. A system reboot is recommended after running the script.

📄 License

MIT