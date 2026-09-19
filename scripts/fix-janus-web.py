#!/usr/bin/env python3
"""Bridge KVMD 3.198's legacy stream callback to Janus 1.1.2 tracks."""
import datetime
import hashlib
from pathlib import Path
import shutil

stream_path = Path('/usr/share/kvmd/web/share/js/kvm/stream_janus.js')
janus_path = Path('/usr/share/janus/javascript/janus.js')
stream = stream_path.read_text()
janus = janus_path.read_text()
updates = {}
if '"onremotetrack": function(track, mid, added)' not in stream:
    assert hashlib.sha256(stream.encode()).hexdigest() == '6b8dc49bbb8ef528b40e52acf66eb371a9badc3d0da16b6f2ef94b5c9e703080', 'Unknown stream_janus.js'
    anchor = '\t\t\t"onremotestream": function(stream) {'
    assert stream.count(anchor) == 1
    callback = '''            // Janus 1.x delivers individual tracks instead of onremotestream.
            "onremotetrack": function(track, mid, added) {
                let stream = $("stream-video").srcObject || new MediaStream();
                if (added && !stream.getTracks().includes(track)) stream.addTrack(track);
                if (!added) stream.removeTrack(track);
                _Janus.attachMediaStream($("stream-video"), stream);
                if (added) {
                    __sendKeyRequired();
                    __startInfoInterval();
                }
            },

'''
    updates[stream_path] = stream.replace(anchor, callback + anchor)
old = '\t\t\tif(oldOBF && typeof oldOBF == "function") {\n\t\t\t\toldOBF();\n\t\t\t}\n'
if old in janus:
    assert janus.count(old) == 1
    updates[janus_path] = janus.replace(old, '\t\t\t// The browser invokes the existing property handler with its Event.\n')
if updates:
    backup = Path('/var/backups') / ('pikvm-janus-web-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir(mode=0o700)
    restore = ['#!/bin/sh', 'set -eu', 'base=$(cd "$(dirname "$0")" && pwd)']
    for path in updates:
        shutil.copy2(path, backup / path.name)
        restore.append(f'cp -p "$base/{path.name}" "{path}"')
    for path, content in updates.items():
        temporary = path.with_suffix('.js.cm0-new')
        temporary.write_text(content)
        temporary.chmod(path.stat().st_mode & 0o777)
        temporary.replace(path)
    (backup / 'restore.sh').write_text('\n'.join(restore) + '\n')
    (backup / 'restore.sh').chmod(0o700)
    print('Janus browser compatibility patched. Rollback:', backup / 'restore.sh')
else:
    print('Janus browser compatibility already patched')
