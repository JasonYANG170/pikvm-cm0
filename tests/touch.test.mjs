import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
const source = await readFile(new URL('../web/cm0-touch.js', import.meta.url), 'utf8');
const {createTouchGestures, installTouchControls} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
function setup() {
    const events = [];
    let time = 0;
    const touch = createTouchGestures({
        move: (...args) => events.push(['move', ...args]),
        click: () => events.push(['click']), wheel: (d) => events.push(['wheel', d]),
        flush: () => events.push(['flush']), now: () => time,
    });
    return {touch, events, setTime: (t) => {time = t;}};
}
const p = (x, y) => ({clientX: x, clientY: y});
test('short tap moves then flushes before one click', () => {
    const {touch, events, setTime} = setup();
    touch.start([p(10, 20)]); setTime(100); touch.end([]);
    assert.deepEqual(events.map(e => e[0]), ['move', 'flush', 'click']);
});
test('movement and long presses do not synthesize clicks', () => {
    for (const moving of [true, false]) {
        const {touch, events, setTime} = setup();
        touch.start([p(10, 20)]);
        if (moving) touch.move([p(40, 20)]); else setTime(500);
        touch.end([]); assert.equal(events.filter(e => e[0] === 'click').length, 0);
    }
});
test('two-finger scroll accumulates small moves and never clicks on lift', () => {
    const {touch, events} = setup();
    touch.start([p(10, 10)]); touch.start([p(10, 10), p(30, 10)]);
    touch.move([p(10, 19), p(30, 19)]); touch.move([p(10, 31), p(30, 31)]);
    touch.end([p(10, 31)]); touch.move([p(50, 90)]); touch.end([]);
    assert.deepEqual(events.filter(e => e[0] === 'wheel'), [['wheel', {x: 0, y: 2}]]);
    assert.equal(events.filter(e => e[0] === 'move').length, 1);
    assert.equal(events.filter(e => e[0] === 'click').length, 0);
});
test('cancel resets gesture and permits a subsequent tap', () => {
    const {touch, events} = setup();
    touch.start([p(0, 0)]); touch.cancel(); touch.end([]);
    touch.start([p(1, 1)]); touch.end([]);
    assert.equal(events.filter(e => e[0] === 'click').length, 1);
});
test('large scrolling remains inside HID wheel bounds', () => {
    const {touch, events} = setup();
    touch.start([p(0, 0), p(10, 0)]);
    touch.move([p(10000, -10000), p(10010, -10000)]);
    assert.deepEqual(events.find(e => e[0] === 'wheel')[1], {x: 20, y: -20});
});
test('drag is released on cancel, blur and explicit release; mute blocks new presses', () => {
    class Element {
        children = []; events = {}; attributes = {};
        appendChild(el) { this.children.push(el); }
        addEventListener(name, fn) { this.events[name] = fn; }
        setAttribute(name, value) { this.attributes[name] = value; }
        getBoundingClientRect() { return {left: 0, top: 0, width: 100, height: 100}; }
    }
    const doc = new Element();
    doc.head = new Element(); doc.defaultView = new Element(); doc.createElement = () => new Element();
    const box = new Element(); box.ownerDocument = doc;
    const container = new Element(), header = new Element();
    container.querySelector = () => header;
    const buttons = []; let enabled = true;
    const controls = installTouchControls({box, container, move() {}, flush() {}, wheel() {},
        button: (name, state) => buttons.push([name, state]), enabled: () => enabled});
    const drag = container.children[0].children[2];
    const click = () => drag.events.click({stopPropagation() {}});
    for (const cancel of [() => box.ontouchcancel({preventDefault() {}}),
        () => doc.defaultView.events.blur(), () => controls.release()]) {
        click(); assert.equal(drag.attributes['aria-pressed'], 'true');
        cancel(); assert.equal(drag.attributes['aria-pressed'], 'false');
        assert.deepEqual(buttons.slice(-2), [['left', true], ['left', false]]);
    }
    enabled = false; const before = buttons.length; click();
    assert.equal(buttons.length, before);
});
