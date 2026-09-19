#!/bin/bash
# Apply video tuning to an existing installation, preserving other KVMD settings.
set -euo pipefail
export PATH=/usr/sbin:/sbin:$PATH
[[ $EUID == 0 ]] || { echo 'Run with sudo'; exit 1; }
repo=$(cd "$(dirname "$0")/.." && pwd)
backup=$(mktemp -d /var/backups/pikvm-video.XXXXXX)
for file in /etc/kvmd/override.yaml /etc/kvmd/tc358743-edid.hex /usr/local/bin/kvmd-setup.sh /etc/NetworkManager/conf.d/99-pikvm-wifi-powersave.conf; do
    if [[ -e $file ]]; then cp --parents -a "$file" "$backup"; else echo "$file" >> "$backup/created-files"; fi
done
if command -v iw >/dev/null && iw dev wlan0 get power_save > "$backup/wifi-before" 2>/dev/null; then :; fi
cat > "$backup/restore.sh" <<'RESTORE'
#!/bin/bash
set -euo pipefail
export PATH=/usr/sbin:/sbin:$PATH
base=$(cd "$(dirname "$0")" && pwd)
systemctl stop kvmd
trap 'systemctl start kvmd' EXIT
if [[ -f $base/created-files ]]; then while IFS= read -r file; do rm -f -- "$file"; done < "$base/created-files"; fi
for dir in etc usr; do [[ ! -d $base/$dir ]] || cp -a "$base/$dir/." "/$dir/"; done
bash /usr/local/bin/kvmd-setup.sh
if command -v nmcli >/dev/null; then nmcli general reload conf; fi
if grep -q 'Power save: on' "$base/wifi-before" 2>/dev/null; then iw dev wlan0 set power_save on; fi
RESTORE
chmod 700 "$backup/restore.sh"
trap 'code=$?; echo "Apply failed; restoring $backup"; bash "$backup/restore.sh"; exit "$code"' ERR
/usr/sbin/python - "$repo" <<'PY'
from pathlib import Path
import sys, yaml
repo = Path(sys.argv[1])
path = Path('/etc/kvmd/override.yaml')
config = yaml.safe_load(path.read_text()) or {}
streamer = yaml.safe_load((repo / 'configs/override.yaml').read_text())['kvmd']['streamer']
config.setdefault('kvmd', {}).setdefault('streamer', {}).update(streamer)
path.write_text(yaml.safe_dump(config, sort_keys=False))
data = bytes.fromhex((repo / 'edid/tc358743-edid.hex').read_text())
assert len(data) == 256 and all(sum(data[i:i+128]) % 256 == 0 for i in (0, 128))
PY
kvmd --dump-config >/dev/null
install -m644 "$repo/edid/tc358743-edid.hex" /etc/kvmd/tc358743-edid.hex
install -m755 "$repo/scripts/kvmd-setup.sh" /usr/local/bin/kvmd-setup.sh
if command -v nmcli >/dev/null; then
    install -d /etc/NetworkManager/conf.d
    install -m644 "$repo/configs/99-pikvm-wifi-powersave.conf" /etc/NetworkManager/conf.d/
    nmcli general reload conf
fi
if command -v iw >/dev/null && iw dev wlan0 info >/dev/null 2>&1; then iw dev wlan0 set power_save off; fi
systemctl stop kvmd
bash /usr/local/bin/kvmd-setup.sh
systemctl start kvmd
sleep 4
systemctl is-active --quiet kvmd
trap - ERR
echo "Applied. Rollback: sudo bash $backup/restore.sh"
echo 'Log in again. Select 1920x1080 at 50Hz on the controlled computer if desired.'
