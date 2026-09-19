// SPDX-License-Identifier: GPL-3.0-or-later
// Touch input adapter for KVMD 3.198. Uses its existing HID WebSocket messages.
export function createTouchGestures({move, click, wheel, flush, now = () => Date.now()}) {
    let mode = "idle", start = null, last = null, started = 0, moved = false;
    let remainder = {x: 0, y: 0};
    const point = (touches) => ({
        x: touches.reduce((sum, t) => sum + t.clientX, 0) / touches.length,
        y: touches.reduce((sum, t) => sum + t.clientY, 0) / touches.length,
    });
    const reset = () => { mode = "idle"; start = last = null; remainder = {x: 0, y: 0}; };
    return {
        start(touches) {
            if (touches.length === 1 && mode === "idle") {
                mode = "single"; start = last = point(touches); started = now(); moved = false;
                move(last, {x: 0, y: 0}, true);
            } else if (touches.length === 2) {
                mode = "scroll"; last = point(touches); remainder = {x: 0, y: 0};
            } else { mode = "blocked"; }
        },
        move(touches) {
            if (mode === "single" && touches.length === 1) {
                const pos = point(touches);
                moved ||= Math.hypot(pos.x - start.x, pos.y - start.y) > 10;
                move(pos, {x: pos.x - last.x, y: pos.y - last.y}, false);
                last = pos;
            } else if (mode === "scroll" && touches.length === 2) {
                const pos = point(touches), delta = {x: 0, y: 0};
                for (const axis of ["x", "y"]) {
                    remainder[axis] += pos[axis] - last[axis];
                    const steps = Math.trunc(remainder[axis] / 20);
                    remainder[axis] -= steps * 20;
                    delta[axis] = Math.max(-20, Math.min(20, steps * 2));
                }
                if (delta.x || delta.y) wheel(delta);
                last = pos;
            }
        },
        end(touches) {
            flush();
            if (!touches.length) {
                if (mode === "single" && !moved && now() - started < 350) click();
                reset();
            } else { mode = "blocked"; }
        },
        cancel: reset,
    };
}

export function installTouchControls({box, container, move, flush, button, wheel, enabled}) {
    const doc = box.ownerDocument;
    const link = doc.createElement("link");
    link.rel = "stylesheet"; link.href = "/share/css/kvm/cm0-touch.css?v=1";
    doc.head.appendChild(link);
    const toolbar = doc.createElement("div");
    toolbar.id = "cm0-touch-controls";
    toolbar.setAttribute("role", "toolbar");
    toolbar.setAttribute("aria-label", "触控鼠标");
    let dragging = false, dragButton;
    const setDragging = (state) => {
        if (dragging === state) return;
        dragging = state;
        button("left", state);
        dragButton.setAttribute("aria-pressed", String(state));
        dragButton.textContent = state ? "松开" : "拖拽";
    };
    const release = () => { gestures.cancel(); setDragging(false); };
    const click = (name) => {
        if (!enabled()) return;
        if (dragging) { setDragging(false); return; }
        flush(); button(name, true); button(name, false);
    };
    const addButton = (text, action) => {
        const el = doc.createElement("button");
        el.type = "button"; el.textContent = text;
        el.addEventListener("click", (event) => { event.stopPropagation(); action(); });
        toolbar.appendChild(el);
        return el;
    };
    addButton("左键", () => click("left"));
    addButton("右键", () => click("right"));
    dragButton = addButton("拖拽", () => { if (enabled()) { flush(); setDragging(!dragging); } });
    dragButton.setAttribute("aria-pressed", "false");
    addButton("滚动↑", () => { if (enabled()) wheel({x: 0, y: 3}); });
    addButton("滚动↓", () => { if (enabled()) wheel({x: 0, y: -3}); });
    const hint = doc.createElement("span");
    hint.textContent = "单指定位 · 轻点单击 · 双指滚动";
    toolbar.appendChild(hint);
    container.appendChild(toolbar);
    const toggle = doc.createElement("button");
    toggle.className = "window-button-cm0-touch";
    toggle.type = "button"; toggle.textContent = "触控"; toggle.title = "显示或隐藏触控鼠标按钮";
    toggle.setAttribute("aria-label", "显示或隐藏触控鼠标按钮");
    toggle.addEventListener("click", () => {
        const showing = doc.defaultView.getComputedStyle(toolbar).display !== "none";
        container.classList.toggle("cm0-touch-show", !showing);
        container.classList.toggle("cm0-touch-hide", showing);
        if (showing) release();
    });
    container.querySelector(".window-header").appendChild(toggle);
    const gestures = createTouchGestures({
        move: (pos, delta, first) => {
            const rect = box.getBoundingClientRect();
            move({x: Math.max(0, Math.min(rect.width, pos.x - rect.left)),
                  y: Math.max(0, Math.min(rect.height, pos.y - rect.top))}, delta, first);
        },
        flush, wheel, click: () => click("left"),
    });
    const handle = (name) => (event) => {
        event.preventDefault();
        if (!enabled()) { release(); return; }
        if (name === "start" && event.touches.length > 1) setDragging(false);
        gestures[name](Array.from(event.touches));
    };
    // Replace the legacy property handlers; prevent synthesized duplicate mouse clicks.
    box.ontouchstart = handle("start");
    box.ontouchmove = handle("move");
    box.ontouchend = handle("end");
    box.ontouchcancel = (event) => { event.preventDefault(); release(); };
    doc.defaultView.addEventListener("blur", release);
    doc.addEventListener("visibilitychange", () => { if (doc.hidden) release(); });
    return {release};
}
