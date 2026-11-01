#!/bin/bash
#========================================================================================
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Rebuild Armbian
# https://github.com/ophub/amlogic-s9xxx-armbian
#
# Function: Customize the startup script. Add content as needed.
# Dependent script: /etc/rc.local (which runs with 'set -e')
# File path: /etc/custom_service/start_service.sh
#
# Version: v1.3
#
#========================================================================================

set +euo pipefail

trap 'exit 0' EXIT

# Custom Service Log - all script output will be logged here
custom_log="/tmp/ophub_start_service.log"

# A helper function for logging with a timestamp
log_message() {
    echo "[$(date +"%Y.%m.%d.%H:%M:%S")] $1" >>"${custom_log}" 2>/dev/null || true
}

# Start of the script
log_message "Starting custom services..."

# Disabled verbose kernel messages on console
dmesg -n 1 >/dev/null 2>&1 || true
log_message "Kernel console logging level set to 1 (Panic only)."

# Search for the FDTFILE file (only the basename of the .dtb is needed)
ophub_release_file="/etc/ophub-release"
FDTFILE=""
# 1) /etc/ophub-release : FDTFILE='xxx.dtb'
[[ -f "${ophub_release_file}" ]] &&
    FDTFILE="$(awk -F"'" '/^FDTFILE=/ {print $2; exit}' "${ophub_release_file}" 2>/dev/null)"
# 2) /boot/uEnv.txt : FDT=/dtb/.../xxx.dtb  (or FDT=xxx.dtb)
[[ -z "${FDTFILE}" && -f "/boot/uEnv.txt" ]] &&
    FDTFILE="$(grep -E '^FDT=.*\.dtb$' /boot/uEnv.txt 2>/dev/null | head -n1 | sed -E 's#^FDT=##; s#.*/##')"
# 3) /boot/extlinux/extlinux.conf : "    fdt /dtb/.../xxx.dtb"
[[ -z "${FDTFILE}" && -f "/boot/extlinux/extlinux.conf" ]] &&
    FDTFILE="$(grep -Eo '/dtb/[^[:space:]]+\.dtb' /boot/extlinux/extlinux.conf 2>/dev/null | head -n1 | sed -E 's#.*/##')"
log_message "Detected FDT file: ${FDTFILE:-not found}"

# General System Services

# Restart ssh service
mkdir -p -m0755 /var/run/sshd >/dev/null 2>&1 || true
if [[ -f "/etc/init.d/ssh" ]]; then
    (sleep 5 && /etc/init.d/ssh restart >/dev/null 2>&1) &
    log_message "SSH service restart attempted."
fi

# Add network performance optimization
if [[ -x "/usr/sbin/balethirq.pl" ]]; then
    (perl /usr/sbin/balethirq.pl >/dev/null 2>&1) &
    log_message "Network optimization service (balethirq.pl) execution attempted."
fi

# Enable UDP GRO forwarding on all physical ethernet interfaces
# View command: ethtool -k eth0 | grep -i udp
if command -v ethtool >/dev/null 2>&1; then
    shopt -s nullglob
    for iface in /sys/class/net/*/device; do
        iface_name="$(basename "${iface%/device}")"
        # Skip non-ethernet interfaces (type != 1) and wireless interfaces
        [[ "$(cat /sys/class/net/${iface_name}/type 2>/dev/null)" != "1" ]] && continue
        [[ -d "/sys/class/net/${iface_name}/wireless" ]] && continue
        ethtool -K "${iface_name}" rx-udp-gro-forwarding on >/dev/null 2>&1
        log_message "Enabled rx-udp-gro-forwarding on ${iface_name}."
    done
    shopt -u nullglob
fi

# Led display control, Only for Amlogic devices (meson-*) with valid boxid.
openvfd_enable="no"  # yes or no, set to "yes" to enable OpenVFD service.
openvfd_boxid="15"   # Set the boxid according to your device. Refer to the documentation for details.
openvfd_restart="no" # yes or no, set to "yes" to restart the OpenVFD service.
if [[ "${openvfd_boxid}" != "0" && "${FDTFILE}" =~ ^meson- ]]; then
    (
        # Start OpenVFD service
        [[ "${openvfd_enable}" == "yes" ]] && armbian-openvfd "${openvfd_boxid}" >/dev/null 2>&1
        # Some devices require a restart to clear 'BOOT' and related messages
        [[ "${openvfd_restart}" == "yes" ]] && {
            armbian-openvfd "0" >/dev/null 2>&1
            sleep 3
            armbian-openvfd "${openvfd_boxid}" >/dev/null 2>&1
        }
        log_message "OpenVFD service execution attempted."
    ) &
fi

# For pveproxy startup service
if [[ -n "$(dpkg -l | awk '{print $2}' | grep -w "^pve-manager$" || true)" ]]; then
    # Restarting systemd services can sometimes fail during early boot.
    (systemctl restart pveproxy >/dev/null 2>&1) &
    log_message "PVE proxy service restart attempted."
fi

# Maximize root partition size
todo_rootfs_resize="/root/.no_rootfs_resize"
[[ -f "${todo_rootfs_resize}" && "$(cat ${todo_rootfs_resize} 2>/dev/null | xargs)" == "yes" ]] && {
    armbian-tf >/dev/null 2>&1 &
    log_message "Root partition resize completed."
}

# Finalization
log_message "All custom services have been processed successfully."
trap '' HUP INT QUIT TERM PIPE
exit 0
