#!/usr/bin/env python3
"""Install a guarded front-end-only patch; no backend restart or account changes."""
import datetime
import hashlib
from pathlib import Path
import shutil
import sys

ROOT = Path('/usr/share/kvmd/web')
REPO = Path(__file__).resolve().parent.parent
MOUSE = ROOT / 'share/js/kvm/mouse.js'
EXPECTED = '22ac8cfc0d4760e943a09645524ae6828eee29874e61e063293661861c2f4503'

def patched(source):
    if 'installTouchControls' in source:
        raise SystemExit('Touch update is already installed; restore the backup before replacing it.')
    if hashlib.sha256(source.encode()).hexdigest() != EXPECTED:
        raise SystemExit('Unknown mouse.js version; refusing to patch. No files changed.')
    edits = [
        ('import {Keypad} from "../keypad.js";', 'import {Keypad} from "../keypad.js";\nimport {installTouchControls} from "./cm0-touch.js?v=1";'),
        ('var __keypad = null;', 'var __keypad = null;\n\tvar __touch = null;'),
        ('\t\t$("stream-box").ontouchend = (event) => __streamTouchEndHandler(event);', '''\t\t$("stream-box").ontouchend = (event) => __streamTouchEndHandler(event);
        __touch = installTouchControls({
            box: $("stream-box"), container: $("stream-window"),
            enabled: () => !!(__ws && __ws.readyState === 1 && __online && !$("hid-mute-switch").checked),
            move: (pos, delta, first) => {
                if (__absolute) { __planned_pos = pos; if (first) __sendPlannedMove(); }
                else if (!first) __sendOrPlanRelativeMove(delta);
            },
            flush: __sendPlannedMove,
            button: (name, state) => __keypad.emitByCode(name, state),
            wheel: __sendWheel,
        });'''),
        ('self.setSocket = function(ws) {', 'self.setSocket = function(ws) {\n\t\tif (!ws && __touch) __touch.release();'),
        ('self.releaseAll = function() {', 'self.releaseAll = function() {\n\t\tif (__touch) __touch.release();'),
        ('if (__ws && !$("hid-mute-switch").checked) {', 'if (__ws && __ws.readyState === 1 && !$("hid-mute-switch").checked) {'),
    ]
    for old, new in edits:
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    return source

def main():
    text = patched(MOUSE.read_text())
    if '--check' in sys.argv:
        print('Compatible KVMD mouse.js; patch anchors validated')
        return
    backup = Path('/var/backups') / ('pikvm-web-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
    backup.mkdir(mode=0o700)
    shutil.copy2(MOUSE, backup / 'mouse.js')
    targets = [(REPO / 'web/cm0-touch.js', ROOT / 'share/js/kvm/cm0-touch.js'),
               (REPO / 'web/cm0-touch.css', ROOT / 'share/css/kvm/cm0-touch.css')]
    for src, dst in targets:
        if dst.exists():
            raise SystemExit(f'Unexpected existing asset: {dst}; no installed files changed')
    try:
        for src, dst in targets:
            shutil.copyfile(src, dst)
            dst.chmod(0o644)
        temporary = MOUSE.with_suffix('.js.cm0-new')
        temporary.write_text(text)
        temporary.chmod(MOUSE.stat().st_mode & 0o777)
        temporary.replace(MOUSE)
    except Exception:
        shutil.copy2(backup / 'mouse.js', MOUSE)
        for _, dst in targets:
            dst.unlink(missing_ok=True)
        MOUSE.with_suffix('.js.cm0-new').unlink(missing_ok=True)
        raise
    restore = backup / 'restore.sh'
    restore.write_text('#!/bin/sh\nset -eu\ncp -p "$(dirname "$0")/mouse.js" /usr/share/kvmd/web/share/js/kvm/mouse.js\n'
                       'rm -f /usr/share/kvmd/web/share/js/kvm/cm0-touch.js /usr/share/kvmd/web/share/css/kvm/cm0-touch.css\n')
    restore.chmod(0o700)
    print('Installed. Refresh browser. Rollback: sudo sh ' + str(restore))

if __name__ == '__main__':
    main()
