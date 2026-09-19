#!/bin/bash
# Tested with Debian 13 arm64, uStreamer 5.37 and Janus 1.1.2.
set -euo pipefail
export PATH=/usr/sbin:/sbin:$PATH
[[ $EUID == 0 ]] || { echo 'Run with sudo'; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo 'Requires arm64'; exit 1; }
[[ $(ustreamer --version) == 5.37 ]] || { echo 'Requires uStreamer 5.37'; exit 1; }
[[ $(dpkg-query -W -f='${Version}' janus) == 1.1.2-* ]] || { echo 'Requires Janus 1.1.2'; exit 1; }
for tool in gcc make apt-get dpkg-deb; do command -v "$tool" >/dev/null; done
repo=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d /var/tmp/pikvm-webrtc-build.XXXXXX)
echo "Build directory: $build"
cd "$build"
/usr/bin/python3 - <<'PY'
import hashlib, io, tarfile, urllib.request
from pathlib import Path
sources = [
 ('https://codeload.github.com/pikvm/ustreamer/tar.gz/refs/tags/v5.37', 'b3112c3095ef89e9c683b57a08fe1219f6770aa54f4f19646465fa4670465359'),
 ('https://codeload.github.com/meetecho/janus-gateway/tar.gz/refs/tags/v1.1.2', 'f721d62a22b38ba3a341a5502f06b8b3a5a4f7bd0e9cc6c53de257fe99695e17'),
 ('https://registry.npmjs.org/webrtc-adapter/-/webrtc-adapter-8.2.3.tgz', '031e73d276e2cd9e0a2cf17ae95415164971b66e6053f6f16471a5b118555f09'),
]
for url, expected in sources:
    data = urllib.request.urlopen(url, timeout=60).read()
    assert hashlib.sha256(data).hexdigest() == expected, url
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        archive.extractall('.', filter='data')
js = Path('janus-gateway-1.1.2/html/janus.js').read_text()
Path('janus.js').write_text('import "./adapter.js";\n' + js + '\nexport { Janus };\n')
PY
mkdir deps sysroot
cd deps
# Extract development files; do not upgrade system runtime libraries.
apt-get download libjansson-dev libglib2.0-dev libgio-2.0-dev libopus-dev libspeexdsp-dev libasound2-dev
for deb in *.deb; do dpkg-deb -x "$deb" ../sysroot; done
cd ..
mkdir -p sysroot/usr/include/janus
cp janus-gateway-1.1.2/src/*.h sysroot/usr/include/janus/
cp -a janus-gateway-1.1.2/src/plugins sysroot/usr/include/janus/
root=$build/sysroot
make -C ustreamer-5.37/janus -j2 \
  "_CFLAGS=-fPIC -MD -c -std=c17 -Wall -Wextra -D_GNU_SOURCE -DWITH_PTHREAD_NP -O2 -I$root/usr/include -I$root/usr/include/janus -I$root/usr/include/glib-2.0 -I$root/usr/lib/aarch64-linux-gnu/glib-2.0/include" \
  '_LDFLAGS=-shared -lm -pthread -lrt -l:libjansson.so.4 -l:libopus.so.0 -l:libasound.so.2 -l:libspeexdsp.so.1 -l:libglib-2.0.so.0'
if ldd ustreamer-5.37/janus/libjanus_ustreamer.so | grep -q 'not found'; then
    echo 'Missing runtime library; no installation performed'; exit 1
fi
if [[ ${1:-} == --build-only ]]; then echo "Build passed: $build"; exit 0; fi
backup=$(mktemp -d /var/backups/pikvm-webrtc.XXXXXX)
files=(/usr/lib/ustreamer/janus/libjanus_ustreamer.so /usr/share/janus/javascript/janus.js /usr/share/janus/javascript/adapter.js /usr/share/kvmd/web/share/js/kvm/stream_janus.js)
for name in janus.jcfg janus.plugin.ustreamer.jcfg janus.transport.websockets.jcfg; do files+=("/etc/kvmd/janus/$name"); done
for file in "${files[@]}"; do
    if [[ -e $file ]]; then cp --parents -a "$file" "$backup"; else echo "$file" >> "$backup/created-files"; fi
done
systemctl is-enabled kvmd-janus-static > "$backup/enabled-before" || true
systemctl is-active kvmd-janus-static > "$backup/active-before" || true
install -d /usr/lib/ustreamer/janus /usr/share/janus/javascript
install -m755 ustreamer-5.37/janus/libjanus_ustreamer.so /usr/lib/ustreamer/janus/
install -m644 janus.js package/out/adapter.js /usr/share/janus/javascript/
install -m644 "$repo"/configs/janus/*.jcfg /etc/kvmd/janus/
cat > "$backup/restore.sh" <<'RESTORE'
#!/bin/bash
set -euo pipefail
base=$(cd "$(dirname "$0")" && pwd)
systemctl stop kvmd-janus-static
if [[ -f $base/created-files ]]; then while IFS= read -r file; do rm -f -- "$file"; done < "$base/created-files"; fi
for dir in etc usr; do [[ ! -d $base/$dir ]] || cp -a "$base/$dir/." "/$dir/"; done
if grep -qx enabled "$base/enabled-before"; then systemctl enable kvmd-janus-static; else systemctl disable kvmd-janus-static; fi
if grep -qx active "$base/active-before"; then systemctl start kvmd-janus-static; fi
RESTORE
chmod 700 "$backup/restore.sh"
if ! /usr/bin/python3 "$repo/scripts/fix-janus-web.py"; then bash "$backup/restore.sh"; exit 1; fi
if ! systemctl restart kvmd-janus-static; then bash "$backup/restore.sh"; exit 1; fi
sleep 3
if ! systemctl is-active --quiet kvmd-janus-static || [[ ! -S /run/kvmd/janus-ws.sock ]]; then
    bash "$backup/restore.sh"; exit 1
fi
systemctl enable kvmd-janus-static
echo "Installed. Rollback: sudo bash $backup/restore.sh"
echo 'Now apply video configuration: sudo bash scripts/apply-optimizations.sh'
