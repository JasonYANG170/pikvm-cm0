#!/bin/bash
# PiKVM boot setup script
set -euo pipefail

# Wait for devices to be ready
sleep 3

# Create kvmd-video symlink
ln -sf /dev/video0 /dev/kvmd-video

# Apply the persistent PiKVM CSI EDID
v4l2-ctl --device=/dev/kvmd-video --set-edid=file=/etc/kvmd/tc358743-edid.hex || exit 1

# Video timings are queried and followed by uStreamer --dv-timings.
# Do not query once at boot: the HDMI source may still be off.

# Fix permissions
mkdir -p /run/kvmd
chown kvmd:kvmd /run/kvmd
chmod 775 /run/kvmd

# Add kvmd user to dialout group
usermod -aG dialout kvmd

exit 0
