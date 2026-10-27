const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'web', 'adspeed.js'), 'utf8');

function environment(configuration = {}, options = {}) {
    let now = 0;
    let wallOffset = 1700000000000;
    let nextHandle = 1;
    const tasks = new Map();
    const listeners = new Map();
    const windowListeners = new Map();
    const observers = [];
    const nativeCalls = [];
    const videos = [];
    const frameNodes = [];
    const document = {
        hidden: !!options.hidden,
        visibilityState: options.hidden ? 'hidden' : 'visible',
        // Default fixtures model unobstructed media under one container. Tests
        // for occlusion replace this with the actual frontmost fixture node.
        elementFromPoint() {
            return {contains(node) { return videos.includes(node) || frameNodes.includes(node); }};
        },
        querySelectorAll(selector) {
            assert.equal(selector, 'iframe,frame');
            return frameNodes;
        },
        getElementsByTagName(name) {
            assert.equal(name, 'video');
            return videos;
        },
        addEventListener(type, callback) {
            const handlers = listeners.get(type) || [];
            handlers.push(callback);
            listeners.set(type, handlers);
        }
    };
    const sandbox = {
        document,
        frames: [],
        addEventListener(type, callback) {
            const handlers = windowListeners.get(type) || [];
            handlers.push(callback);
            windowListeners.set(type, handlers);
        },
        innerWidth: 400,
        innerHeight: 800,
        getComputedStyle(node) {
            return Object.assign({display: 'block', visibility: 'visible', opacity: '1'}, node.style);
        },
        Date: {
            now() {
                return wallOffset + now;
            }
        },
        performance: {
            now() {
                return now;
            }
        },
        MutationObserver: class {
            constructor(callback) {
                this.callback = callback;
                observers.push(this);
            }
            observe(target, settings) {
                this.target = target;
                this.settings = settings;
            }
        }
    };
    sandbox.window = sandbox;
    sandbox.parent = sandbox;
    function timer(kind) {
        return function (callback, delay, ...args) {
            const handle = nextHandle++;
            const period = Math.max(1, Math.trunc(Number(delay) || 0));
            nativeCalls.push({kind, receiver: this, callback, delay, args, handle});
            tasks.set(handle, {callback, args, due: now + period, period, interval: kind === 'interval'});
            return handle;
        };
    }
    sandbox.setTimeout = timer('timeout');
    sandbox.setInterval = timer('interval');
    sandbox.clearTimeout = (handle) => tasks.delete(handle);
    sandbox.clearInterval = (handle) => tasks.delete(handle);
    if (options.noPerformance) {
        delete sandbox.performance;
    }
    vm.createContext(sandbox);
    const config = Object.assign({rate: 8, speedVideo: true}, configuration);
    const script = source.replace('__ADSPEED_CONFIG__', JSON.stringify(config));
    const api = {
        sandbox,
        document,
        videos,
        frameNodes,
        tasks,
        listeners,
        windowListeners,
        observers,
        nativeCalls,
        inject() {
            vm.runInContext(script, sandbox);
        },
        emit(type, target = document) {
            for (const callback of listeners.get(type) || []) {
                callback.call(document, {type, target});
            }
        },
        advance(milliseconds) {
            const target = now + milliseconds;
            let iterations = 0;
            for (;;) {
                let selected;
                for (const [handle, task] of tasks) {
                    if (task.due <= target && (!selected || task.due < selected[1].due)) {
                        selected = [handle, task];
                    }
                }
                if (!selected) {
                    break;
                }
                assert.ok(++iterations < 20000, 'scheduler must not loop without a bound');
                const [handle, task] = selected;
                now = task.due;
                if (task.interval) {
                    task.due += task.period;
                } else {
                    tasks.delete(handle);
                }
                if (typeof task.callback === 'function') {
                    task.callback.apply(sandbox, task.args);
                }
            }
            now = target;
        },
        time() {
            return now;
        },
        hide(value) {
            document.hidden = value;
            document.visibilityState = value ? 'hidden' : 'visible';
            this.emit('visibilitychange');
        },
        moveWallClock(delta) {
            wallOffset += delta;
        }
    };
    api.inject();
    return api;
}

function video(env, overrides = {}) {
    let position = 1;
    let playbackRate = 1;
    const attributes = new Set();
    const media = Object.assign({
        tagName: 'VIDEO',
        loop: false,
        currentSrc: 'https://example.invalid/creative.mp4',
        src: '',
        duration: 30,
        readyState: 4,
        paused: false,
        ended: false,
        seeking: false,
        hidden: false,
        isConnected: true,
        parentElement: null,
        style: {},
        seeks: [],
        rates: [],
        throwSeek: false,
        ignoreSeek: false,
        deferSeek: false,
        throwRate: false,
        ignoreRate: false,
        rectangle: {left: 0, top: 0, right: 320, bottom: 180, width: 320, height: 180},
        ranges: [[0, 30]],
        seekable: {
            get length() {
                return media.ranges.length;
            },
            start(index) {
                return media.ranges[index][0];
            },
            end(index) {
                return media.ranges[index][1];
            }
        },
        hasAttribute(name) {
            return attributes.has(name);
        },
        setAttribute(name) {
            attributes.add(name);
        },
        getBoundingClientRect() {
            return this.rectangle;
        }
    }, overrides);
    Object.defineProperties(media, {
        currentTime: {
            get() {
                return position;
            },
            set(value) {
                media.seeks.push(value);
                if (media.throwSeek) {
                    throw new Error('not seekable');
                }
                if (media.ignoreSeek) return;
                if (media.deferSeek) {
                    media.seeking = true;
                    return;
                }
                position = value;
            }
        },
        playbackRate: {
            get() {
                return playbackRate;
            },
            set(value) {
                media.rates.push(value);
                if (media.throwRate) {
                    throw new Error('unsupported playback rate');
                }
                if (!media.ignoreRate) {
                    playbackRate = value;
                }
                env.emit('ratechange', media);
            }
        }
    });
    env.videos.push(media);
    return media;
}

test('runs without browser globals and does not need to resolve configuration', () => {
    assert.doesNotThrow(() => vm.runInNewContext(source));
});

test('clamps finite rate and replaces malformed values with 8', () => {
    for (const [input, expected] of [[0, 1], [-4, 1], [100, 16], [4, 4], [null, 8], ['bad', 8]]) {
        const env = environment({rate: input});
        const media = video(env);
        env.emit('play', media);
        assert.equal(media.playbackRate, expected);
        assert.equal(env.sandbox.__adspeed.stats.rate, expected);
    }
});

test('idempotence preserves one API, poll, observer and timer wrapper', () => {
    const env = environment({compressTimers: true, accelerateClock: true});
    const api = env.sandbox.__adspeed;
    const timeout = env.sandbox.setTimeout;
    const listenerCount = Array.from(env.listeners.values()).reduce((sum, list) => sum + list.length, 0);
    env.inject();
    assert.equal(env.sandbox.__adspeed, api);
    assert.equal(env.sandbox.setTimeout, timeout);
    assert.equal(env.observers.length, 1);
    assert.equal(env.tasks.size, 1);
    assert.equal(Array.from(env.listeners.values()).reduce((sum, list) => sum + list.length, 0), listenerCount);
    assert.equal(Object.getOwnPropertyDescriptor(env.sandbox, '__adspeed').enumerable, false);
    let calls = 0;
    env.sandbox.setTimeout(() => calls++, 1000);
    env.advance(124);
    assert.equal(calls, 0);
    env.advance(1);
    assert.equal(calls, 1);
});

test('foreground polling stays at 4 Hz and suspends while hidden', () => {
    const env = environment();
    env.advance(1000);
    assert.equal(env.sandbox.__adspeed.stats.polls, 4);
    assert.equal(env.tasks.size, 1);
    env.hide(true);
    assert.equal(env.tasks.size, 0);
    env.advance(1000);
    assert.equal(env.sandbox.__adspeed.stats.polls, 4);
    env.hide(false);
    assert.equal(env.tasks.size, 1);
    env.advance(250);
    assert.equal(env.sandbox.__adspeed.stats.polls, 5);
});

test('manual-only mode does not poll', () => {
    const env = environment({speedVideo: false});
    assert.equal(env.tasks.size, 0);
    const media = video(env);
    assert.equal(env.sandbox.__adspeed.skip(), 1);
    assert.equal(media.seeks.length, 1);
});

test('explicit skip seeks to a short tail once and emits no fake media events', () => {
    const env = environment({speedVideo: false});
    const media = video(env);
    assert.equal(media.seeks.length, 0);
    assert.equal(env.sandbox.__adspeed.skip(), 1);
    assert.equal(media.currentTime, 29.75);
    assert.equal(media.ended, false);
    assert.equal(media.paused, false);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(media.seeks.length, 1);
    assert.equal(env.sandbox.__adspeed.stats.skipped, 1);
});

test('automatic skip stays disabled by default and is independent of speed', () => {
    const manual = environment();
    const first = video(manual);
    manual.emit('play', first);
    manual.advance(1000);
    assert.equal(first.seeks.length, 0);
    const automatic = environment({speedVideo: false, autoSkip: true});
    const second = video(automatic);
    automatic.emit('play', second);
    automatic.advance(1000);
    assert.equal(second.seeks.length, 1);
    assert.equal(second.playbackRate, 1);
});

test('paused, ended, seeking, hidden, disconnected, live and not-ready media are skipped safely', () => {
    const cases = [
        {paused: true},
        {ended: true},
        {seeking: true},
        {hidden: true},
        {isConnected: false},
        {duration: Infinity},
        {duration: NaN},
        {duration: 0},
        {duration: -1},
        {readyState: 1},
        {ranges: []},
        {ranges: [[0, 10]]},
        {style: {display: 'none'}},
        {style: {visibility: 'hidden'}},
        {style: {opacity: '0'}},
        {parentElement: {hidden: true}},
        {rectangle: {left: 401, right: 450, top: 0, bottom: 20, width: 49, height: 20}},
        {rectangle: {left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0}}
    ];
    for (const properties of cases) {
        const env = environment({speedVideo: false, autoSkip: true});
        const media = video(env, properties);
        env.emit('play', media);
        assert.equal(env.sandbox.__adspeed.skip(), 0, JSON.stringify(properties));
        assert.equal(media.seeks.length, 0);
    }
});

test('pausing is preserved and resuming makes a video eligible', () => {
    const env = environment({autoSkip: true});
    const media = video(env, {paused: true});
    env.emit('play', media);
    env.advance(250);
    assert.equal(media.seeks.length, 0);
    assert.equal(media.rates.length, 0);
    media.paused = false;
    env.emit('play', media);
    assert.equal(media.seeks.length, 1);
    assert.equal(media.playbackRate, 8);
    media.paused = true;
    env.emit('pause', media);
    env.advance(250);
    assert.equal(media.paused, true);
    assert.equal(media.seeks.length, 1);
});

test('source changes and same-source loadstart reset the bounded skip state', () => {
    const env = environment({autoSkip: true});
    const media = video(env);
    env.emit('play', media);
    media.currentSrc = 'https://example.invalid/second.mp4';
    media.currentTime = 1;
    media.seeks.length = 0;
    env.emit('loadedmetadata', media);
    assert.equal(media.seeks.length, 1);
    media.currentTime = 1;
    media.seeks.length = 0;
    env.emit('loadstart', media);
    assert.equal(media.seeks.length, 1);
    env.advance(1000);
    assert.equal(media.seeks.length, 1);
});

test('seek failure is bounded and leaves the independent speed fallback working', () => {
    const env = environment({autoSkip: true});
    const media = video(env, {throwSeek: true});
    env.emit('play', media);
    env.advance(2000);
    assert.equal(media.seeks.length, 1);
    assert.equal(env.sandbox.__adspeed.stats.seekFailures, 1);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(media.seeks.length, 2);
    assert.equal(media.playbackRate, 8);
    assert.equal(env.sandbox.__adspeed.stats.seekFailures, 2);
    assert.equal(env.sandbox.__adspeed.stats.skipped, 0);
});

test('throwing or ignored playbackRate setters stop retrying without stopping skip', () => {
    for (const properties of [{throwRate: true}, {ignoreRate: true}]) {
        const env = environment({autoSkip: true});
        const media = video(env, properties);
        env.emit('play', media);
        env.advance(2000);
        assert.equal(media.rates.length, 1);
        assert.equal(media.seeks.length, 1);
        assert.equal(env.sandbox.__adspeed.stats.rateFailures, 1);
    }
});

test('repeated SDK rate resets have a per-source correction limit', () => {
    const env = environment();
    const media = video(env);
    for (let index = 0; index < 20; index++) {
        media.playbackRate = 1;
    }
    assert.equal(env.sandbox.__adspeed.stats.rateChanges, 8);
    assert.equal(media.playbackRate, 1);
});

test('inline attributes are opt-in and do not resume media', () => {
    const env = environment({forceInline: true});
    const media = video(env);
    env.emit('play', media);
    assert.equal(media.hasAttribute('playsinline'), true);
    assert.equal(media.hasAttribute('webkit-playsinline'), true);
    assert.equal(media.playsInline, true);
    media.paused = true;
    env.emit('pause', media);
    assert.equal(media.paused, true);
});

test('dynamic timer gating resumes after video ends or is removed', () => {
    const env = environment({compressTimers: true});
    const calls = [];
    env.sandbox.setInterval(() => calls.push(env.time()), 1000);
    env.advance(125);
    assert.deepEqual(calls, [125]);
    const media = video(env);
    env.emit('play', media);
    env.advance(1000);
    assert.deepEqual(calls, [125, 1125]);
    media.ended = true;
    env.emit('ended', media);
    env.advance(125);
    assert.deepEqual(calls, [125, 1125, 1250]);
    media.ended = false;
    env.emit('play', media);
    env.videos.length = 0;
    env.observers[0].callback([]);
    env.advance(125);
    assert.deepEqual(calls, [125, 1125, 1250, 1375]);
});

test('a scheduled function timeout follows mode changes and fires only once', () => {
    const env = environment({compressTimers: true});
    const calls = [];
    env.sandbox.setTimeout(() => calls.push(env.time()), 1000);
    env.advance(50);
    const media = video(env);
    env.emit('play', media);
    env.advance(599);
    assert.equal(calls.length, 0);
    env.advance(101);
    assert.deepEqual(calls, [750]);
    env.advance(2000);
    assert.equal(calls.length, 1);
});

test('timer callbacks, extra arguments, receiver and cancellation are preserved', () => {
    const env = environment({compressTimers: true});
    const receiver = {owner: 'caller'};
    const seen = [];
    const handle = env.sandbox.setTimeout.call(receiver, function (...args) {
        seen.push({args, receiver: this});
    }, 1000, 'one', 2);
    const scheduled = env.nativeCalls.at(-1);
    assert.equal(scheduled.receiver, receiver);
    env.advance(125);
    assert.deepEqual(seen[0].args, ['one', 2]);
    assert.equal(seen[0].receiver, env.sandbox);
    assert.equal(env.tasks.has(handle), false);
    let canceled = false;
    const second = env.sandbox.setTimeout(() => canceled = true, 1000);
    env.sandbox.clearTimeout(second);
    env.advance(1000);
    assert.equal(canceled, false);
    let intervals = 0;
    const interval = env.sandbox.setInterval(() => intervals++, 1000);
    env.sandbox.clearInterval(interval);
    env.advance(1000);
    assert.equal(intervals, 0);
});

test('string timer callbacks stay on native timer paths without evaluation', () => {
    const env = environment({compressTimers: true});
    env.sandbox.setTimeout('nativeOnly()', 1000, 'extra');
    const timeout = env.nativeCalls.at(-1);
    assert.equal(timeout.kind, 'timeout');
    assert.equal(timeout.callback, 'nativeOnly()');
    assert.equal(timeout.delay, 125);
    assert.deepEqual(timeout.args, ['extra']);
    env.sandbox.setInterval('nativeOnly()', 1000);
    assert.equal(env.nativeCalls.at(-1).callback, 'nativeOnly()');
});

test('live media is left at its original rate and hidden media does not disable timer compression', () => {
    const env = environment({compressTimers: true, autoSkip: true});
    const live = video(env, {duration: Infinity});
    env.emit('play', live);
    assert.equal(live.playbackRate, 1);
    assert.equal(live.seeks.length, 0);
    live.hidden = true;
    env.emit('pause', live);
    let fired = false;
    env.sandbox.setTimeout(() => fired = true, 1000);
    env.advance(125);
    assert.equal(fired, true);
});

test('near-tail media does not repeatedly seek and metadata can make a pending item eligible', () => {
    const env = environment({speedVideo: false, autoSkip: true});
    const media = video(env, {readyState: 0});
    env.emit('play', media);
    assert.equal(media.seeks.length, 0);
    media.readyState = 4;
    media.currentTime = 29.9;
    media.seeks.length = 0;
    env.emit('loadedmetadata', media);
    env.advance(500);
    assert.equal(media.seeks.length, 0);
    media.currentSrc = 'https://example.invalid/new.mp4';
    media.currentTime = 1;
    media.seeks.length = 0;
    env.emit('loadedmetadata', media);
    assert.equal(media.seeks.length, 1);
});

test('clock transitions settle old speed even without intermediate clock reads', () => {
    const env = environment({accelerateClock: true});
    const initialDate = env.sandbox.Date.now();
    env.advance(100);
    const media = video(env);
    env.emit('play', media);
    env.advance(100);
    assert.equal(env.sandbox.Date.now() - initialDate, 900);
    assert.equal(env.sandbox.performance.now(), 900);
    media.ended = true;
    env.emit('ended', media);
    env.advance(100);
    assert.equal(env.sandbox.Date.now() - initialDate, 1700);
    assert.equal(env.sandbox.performance.now(), 1700);
    env.hide(true);
    env.advance(100);
    assert.equal(env.sandbox.Date.now() - initialDate, 1800);
    env.hide(false);
    env.advance(100);
    assert.equal(env.sandbox.Date.now() - initialDate, 2600);
});

test('virtual clocks never move backward when the system clock rolls back', () => {
    const env = environment({accelerateClock: true});
    env.advance(100);
    const before = env.sandbox.Date.now();
    env.moveWallClock(-10000);
    env.advance(100);
    assert.ok(env.sandbox.Date.now() >= before);
    assert.ok(env.sandbox.performance.now() >= 800);
});

test('clock acceleration remains optional and works without performance', () => {
    const normal = environment({compressTimers: true});
    normal.advance(100);
    assert.equal(normal.sandbox.performance.now(), 100);
    const fallback = environment({accelerateClock: true}, {noPerformance: true});
    const before = fallback.sandbox.Date.now();
    fallback.advance(100);
    assert.equal(fallback.sandbox.Date.now() - before, 800);
});

test('hidden-page startup does not scan or seek until foregrounded', () => {
    const env = environment({autoSkip: true}, {hidden: true});
    const media = video(env);
    env.emit('play', media);
    assert.equal(env.tasks.size, 0);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(env.sandbox.__adspeed.stats.scans, 0);
    env.hide(false);
    assert.equal(media.seeks.length, 1);
    assert.equal(env.tasks.size, 1);
});

test('automatic media scans have a fixed upper bound and manual ambiguity abstains', () => {
    const env = environment({speedVideo: false, autoSkip: true});
    for (let index = 0; index < 80; index++) {
        video(env);
    }
    env.emit('play', env.videos[0]);
    assert.equal(env.sandbox.__adspeed.stats.skipped, 64);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(env.videos[64].seeks.length, 0);
});

test('generated C++ header embeds the exact JavaScript and one config token', () => {
    const header = fs.readFileSync(path.join(root, 'AdSpeedWebScript.h'), 'utf8');
    const opening = 'static const char kAdSpeedWebScript[] = R"ADSPEEDJS(';
    const content = header.slice(header.indexOf(opening) + opening.length, header.lastIndexOf(')ADSPEEDJS";'));
    assert.equal(content, source.replace(/\r\n/g, '\n'));
    assert.equal(content.split('__ADSPEED_CONFIG__').length - 1, 1);
});

test('manual mode leaves video, native timers, and clocks unchanged until requested', () => {
    const env = environment({speedVideo: false, autoSkip: false, manualClose: true});
    const media = video(env);
    env.emit('play', media);
    env.advance(2000);
    assert.deepEqual(media.seeks, []);
    assert.deepEqual(media.rates, []);
    assert.equal(env.sandbox.__adspeed.stats.polls, 0);
    let fired = 0;
    env.sandbox.setTimeout(() => { fired += 1; }, 1000);
    env.advance(999);
    assert.equal(fired, 0);
    env.advance(1);
    assert.equal(fired, 1);
    assert.equal(env.sandbox.__adspeed.skip(), 1);
    assert.equal(media.seeks.length, 1);
    assert.deepEqual(media.rates, []);
    assert.equal(env.sandbox.performance.now(), 3000);
    assert.equal(env.sandbox.Date.now(), 1700000003000);
});

function frame(env, contentWindow, overrides = {}) {
    const node = Object.assign({
        contentWindow,
        hidden: false,
        isConnected: true,
        parentElement: null,
        style: {},
        rectangle: {left: 0, top: 0, right: 320, bottom: 180, width: 320, height: 180},
        getBoundingClientRect() {
            return this.rectangle;
        }
    }, overrides);
    env.frameNodes.push(node);
    env.sandbox.frames.push(contentWindow);
    return node;
}

function message(env, source, data) {
    for (const handler of env.windowListeners.get('message') || []) {
        handler({source, data});
    }
}

function connect(parent, child, overrides) {
    const parentProxy = {
        postMessage(data) {
            message(parent, childProxy, data);
        }
    };
    const childProxy = {
        postMessage(data) {
            message(child, parentProxy, data);
        }
    };
    child.sandbox.parent = parentProxy;
    frame(parent, childProxy, overrides);
    return {parentProxy, childProxy};
}

function installClose(env) {
    let closes = 0;
    env.sandbox.mraid = {
        getState: () => 'default',
        getPlacementType: () => 'interstitial',
        isViewable: () => true,
        close() {
            closes += 1;
        }
    };
    return () => closes;
}

const manualConfig = {speedVideo: false, manualClose: true, skipChannel: 'session-token'};

async function settle() {
    for (let index = 0; index < 20; index++) await Promise.resolve();
}

function inspectionReply(request, overrides = {}) {
    return Object.assign({adSpeedReply: 'session-token', phase: request.phase, id: request.id,
        count: 0, unresolved: 0, token: '123:456:9'}, overrides);
}

test('inspection and validation are side-effect free and tokens authorize one local seek', async () => {
    const env = environment(manualConfig);
    const media = video(env);
    const inspected = await env.sandbox.__adspeed.inspectAsync();
    assert.equal(inspected.count, 1);
    assert.equal(inspected.unresolved, 0);
    assert.equal(typeof inspected.token, 'string');
    assert.deepEqual(media.seeks, []);
    assert.deepEqual(media.rates, []);
    assert.equal(await env.sandbox.__adspeed.validateAsync(inspected.token), true);
    const result = await env.sandbox.__adspeed.skipAsync(inspected.token);
    assert.equal(result.handled, 1);
    assert.equal(media.currentTime, 29.75);
    assert.equal(media.ended, false);
    assert.equal((await env.sandbox.__adspeed.skipAsync(inspected.token)).handled, 0);
    assert.equal(media.seeks.length, 1);
});

test('empty snapshots are tokenized for native fallback and invalidate when media arrives', async () => {
    const env = environment(manualConfig);
    const inspected = await env.sandbox.__adspeed.inspectAsync();
    assert.equal(inspected.count, 0);
    assert.equal(typeof inspected.token, 'string');
    assert.equal(await env.sandbox.__adspeed.validateAsync(inspected.token), true);
    video(env);
    assert.equal(await env.sandbox.__adspeed.validateAsync(inspected.token), false);
    assert.equal((await env.sandbox.__adspeed.skipAsync(inspected.token)).handled, 0);
});

test('manual APIs never invoke generic MRAID close, including empty and finished documents', async () => {
    const env = environment(manualConfig);
    const closes = installClose(env);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    const media = video(env, {ended: true});
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(closes(), 0);
    assert.equal(media.seeks.length, 0);
    assert.equal(env.sandbox.__adspeed.stats.closeRequests, 0);
});

test('a second press never closes a video whose seek has not ended', async () => {
    const env = environment(manualConfig);
    const media = video(env);
    const closes = installClose(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    env.advance(1100);
    const second = await env.sandbox.__adspeed.skipAsync();
    assert.equal(second.handled, 0);
    assert.equal(second.unresolved, 1);
    assert.equal(media.ended, false);
    assert.equal(media.seeks.length, 1);
    assert.equal(closes(), 0);
});

test('two local videos are ambiguous and neither is sought', async () => {
    const env = environment(manualConfig);
    const first = video(env);
    const second = video(env, {currentSrc: 'https://example.invalid/other.mp4'});
    const inspected = await env.sandbox.__adspeed.inspectAsync();
    assert.equal(inspected.count, 2);
    assert.equal(inspected.token, null);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(first.seeks.length + second.seeks.length, 0);
});

test('local media cannot preempt a child-frame ad during discovery', async () => {
    const parent = environment(manualConfig);
    const child = environment(manualConfig);
    const game = video(parent);
    const ad = video(child);
    connect(parent, child);
    const inspected = await parent.sandbox.__adspeed.inspectAsync();
    assert.equal(inspected.count, 2);
    const result = await parent.sandbox.__adspeed.skipAsync();
    assert.equal(result.handled, 0);
    assert.equal(result.unresolved, 1);
    assert.equal(game.seeks.length + ad.seeks.length, 0);
    assert.ok(parent.sandbox.__adspeed.stats.frameRequests > 0);
});

test('frame discovery authorizes only one video and never closes a sibling frame', async () => {
    const parent = environment(manualConfig);
    const videoFrame = environment(manualConfig);
    const closeFrame = environment(manualConfig);
    const ad = video(videoFrame);
    const closes = installClose(closeFrame);
    connect(parent, videoFrame);
    connect(parent, closeFrame);
    const inspected = await parent.sandbox.__adspeed.inspectAsync();
    assert.equal(inspected.count, 1);
    assert.equal(ad.seeks.length, 0);
    assert.equal(closes(), 0);
    const result = await parent.sandbox.__adspeed.skipAsync(inspected.token);
    assert.equal(result.handled, 1);
    assert.equal(result.unresolved, 0);
    assert.equal(ad.seeks.length, 1);
    assert.equal(closes(), 0);
    assert.equal(parent.tasks.size + videoFrame.tasks.size + closeFrame.tasks.size, 0);
});

test('multiple child-frame videos abstain without performing any action', async () => {
    const parent = environment(manualConfig);
    const first = environment(manualConfig);
    const second = environment(manualConfig);
    const a = video(first);
    const b = video(second);
    connect(parent, first);
    connect(parent, second);
    assert.equal((await parent.sandbox.__adspeed.skipAsync()).unresolved, 1);
    assert.equal(a.seeks.length + b.seeks.length, 0);
});

test('new root media during empty child discovery invalidates the original request', async () => {
    const parent = environment(manualConfig);
    let request;
    const child = {postMessage(data) { request = data; }};
    frame(parent, child);
    const closes = installClose(parent);
    const pending = parent.sandbox.__adspeed.skipAsync();
    const media = video(parent);
    message(parent, child, inspectionReply(request));
    const result = await pending;
    assert.equal(result.handled, 0);
    assert.equal(result.unresolved, 1);
    assert.equal(media.seeks.length, 0);
    assert.equal(closes(), 0);
});

test('new sibling media after discovery invalidates action on a different child', async () => {
    const parent = environment(manualConfig);
    const first = environment(manualConfig);
    const second = environment(manualConfig);
    const original = video(first);
    connect(parent, first);
    connect(parent, second);
    const inspected = await parent.sandbox.__adspeed.inspectAsync();
    const replacement = video(second);
    assert.equal(await parent.sandbox.__adspeed.validateAsync(inspected.token), false);
    const result = await parent.sandbox.__adspeed.skipAsync(inspected.token);
    assert.equal(result.handled, 0);
    assert.equal(original.seeks.length + replacement.seeks.length, 0);
});

test('tokens reject source replacement, loadstart, hidden pages and expiration', async () => {
    for (const change of [
        (env, media) => { media.currentSrc = 'https://example.invalid/new.mp4'; },
        (env, media) => env.emit('loadstart', media),
        (env) => env.hide(true),
        (env) => env.advance(5001)
    ]) {
        const env = environment(manualConfig);
        const media = video(env);
        const inspected = await env.sandbox.__adspeed.inspectAsync();
        change(env, media);
        assert.equal(await env.sandbox.__adspeed.validateAsync(inspected.token), false);
        assert.equal((await env.sandbox.__adspeed.skipAsync(inspected.token)).handled, 0);
        assert.equal(media.seeks.length, 0);
    }
});

test('one token cannot perform two concurrent actions', async () => {
    const env = environment(manualConfig);
    const media = video(env);
    const inspected = await env.sandbox.__adspeed.inspectAsync();
    const results = await Promise.all([
        env.sandbox.__adspeed.skipAsync(inspected.token),
        env.sandbox.__adspeed.skipAsync(inspected.token)
    ]);
    assert.equal(results.reduce((sum, result) => sum + result.handled, 0), 1);
    assert.equal(media.seeks.length, 1);
});

test('failed seeks can be explicitly retried with a fixed per-source attempt bound', async () => {
    const env = environment(manualConfig);
    const media = video(env, {throwSeek: true});
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    media.throwSeek = false;
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    media.currentTime = 1;
    media.seeks.length = 0;
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    media.currentTime = 1;
    media.seeks.length = 0;
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(media.seeks.length, 0);
    assert.equal(env.sandbox.__adspeed.stats.skipAttempts, 3);
});

test('silently ignored seeks report failure and preserve looping playback', async () => {
    const env = environment(manualConfig);
    const media = video(env, {loop: true, ignoreSeek: true});
    const closes = installClose(env);
    const result = await env.sandbox.__adspeed.skipAsync();
    assert.equal(result.handled, 0);
    assert.equal(result.unresolved, 1);
    assert.equal(media.currentTime, 1);
    assert.equal(media.loop, true);
    assert.equal(media.paused, false);
    assert.equal(env.sandbox.__adspeed.stats.skipped, 0);
    assert.equal(env.sandbox.__adspeed.stats.seekFailures, 1);
    assert.equal(closes(), 0);
    media.ignoreSeek = false;
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    assert.equal(media.currentTime, 29.75);
    assert.equal(media.loop, false);
});

test('an asynchronous seek is accepted while the media element reports seeking', async () => {
    const env = environment(manualConfig);
    const media = video(env, {deferSeek: true});
    const result = await env.sandbox.__adspeed.skipAsync();
    assert.equal(result.handled, 1);
    assert.equal(media.seeking, true);
    assert.equal(media.seeks.length, 1);
    assert.equal(env.sandbox.__adspeed.stats.seekFailures, 0);
});

test('immutable loops and failed seeks cannot authorize close and restore loop state', async () => {
    const frozen = environment(manualConfig);
    const immutable = video(frozen);
    const frozenCloses = installClose(frozen);
    Object.defineProperty(immutable, 'loop', {get: () => true, set() {}});
    assert.equal((await frozen.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(immutable.loop, true);
    assert.equal(immutable.seeks.length, 0);
    assert.equal(frozenCloses(), 0);
    const failing = environment(manualConfig);
    const media = video(failing, {loop: true, throwSeek: true});
    assert.equal((await failing.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(media.loop, true);
    assert.equal(media.seeks.length, 1);
});

test('explicit looping video seeks only after the click and lets actual playback end', async () => {
    const env = environment(manualConfig);
    const media = video(env, {loop: true});
    env.emit('play', media);
    env.advance(2000);
    assert.equal(media.loop, true);
    assert.equal(media.seeks.length, 0);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    assert.equal(media.loop, false);
    assert.equal(media.currentTime, 29.75);
    assert.equal(media.ended, false);
    assert.equal(media.paused, false);
});

test('automatic scans leave looping media untouched', () => {
    const env = environment({speedVideo: false, autoSkip: true});
    const media = video(env, {loop: true});
    env.emit('play', media);
    env.advance(2000);
    assert.equal(media.loop, true);
    assert.equal(media.seeks.length, 0);
});

test('hidden frames receive no discovery or action and cannot cause a close', async () => {
    const parent = environment(manualConfig);
    const child = environment(manualConfig);
    const media = video(child);
    connect(parent, child, {parentElement: {hidden: true}});
    const closes = installClose(parent);
    const result = await parent.sandbox.__adspeed.skipAsync();
    assert.equal(result.handled, 0);
    assert.equal(result.unresolved, 0);
    assert.equal(media.seeks.length, 0);
    assert.equal(parent.sandbox.__adspeed.stats.frameRequests, 0);
    assert.equal(closes(), 0);
});

test('unresponsive visible frames time out unresolved without fallback actions', async () => {
    const env = environment(manualConfig);
    let posts = 0;
    frame(env, {postMessage() { posts += 1; }});
    const closes = installClose(env);
    const pending = env.sandbox.__adspeed.skipAsync();
    assert.equal(posts, 1);
    env.advance(800);
    assert.equal((await pending).unresolved, 1);
    assert.equal(closes(), 0);
    assert.equal(env.tasks.size, 0);
});

test('discovery replies require source, channel, phase, request ID and bounded counts', async () => {
    const env = environment(manualConfig);
    let request;
    const child = {postMessage(data) { request = data; }};
    frame(env, child);
    const pending = env.sandbox.__adspeed.inspectAsync();
    const valid = inspectionReply(request);
    message(env, {}, valid);
    message(env, child, {...valid, adSpeedReply: 'wrong'});
    message(env, child, {...valid, id: 'stale'});
    message(env, child, {...valid, phase: 'act'});
    message(env, child, {...valid, count: NaN});
    message(env, child, {...valid, count: -1});
    message(env, child, {...valid, token: null});
    assert.equal(env.tasks.size, 1);
    message(env, child, valid);
    const result = await pending;
    assert.equal(result.count, 0);
    assert.equal(result.unresolved, 0);
    assert.equal(env.tasks.size, 0);
    message(env, child, valid);
    assert.equal(env.tasks.size, 0);
});

test('wrong parents and old action broadcasts cannot trigger media actions', async () => {
    const env = environment(manualConfig);
    const media = video(env);
    const parent = {postMessage() {}};
    env.sandbox.parent = parent;
    message(env, parent, {adSpeedSkip: 'session-token'});
    message(env, parent, {adSpeedRequest: 'session-token', id: '123:456:1', depth: 1});
    message(env, {}, {adSpeedProtocol: 'session-token', phase: 'act', token: '123:456:1', id: '123:456:2', depth: 1});
    message(env, parent, {adSpeedProtocol: 'wrong', phase: 'act', token: '123:456:1', id: '123:456:2', depth: 1});
    await settle();
    assert.equal(media.seeks.length, 0);
});

test('duplicate parent action messages consume one snapshot only', async () => {
    const env = environment(manualConfig);
    const media = video(env);
    const replies = [];
    const parent = {postMessage(data) { replies.push(data); }};
    env.sandbox.parent = parent;
    message(env, parent, {adSpeedProtocol: 'session-token', phase: 'inspect', id: '123:456:1', depth: 1});
    await settle();
    const token = replies[0].token;
    const request = {adSpeedProtocol: 'session-token', phase: 'act', token, id: '123:456:2', depth: 1};
    message(env, parent, request);
    message(env, parent, request);
    await settle();
    message(env, parent, request);
    await settle();
    assert.equal(media.seeks.length, 1);
    assert.ok(replies.filter((reply) => reply.phase === 'act').length >= 1);
});

test('concurrent convenience requests share discovery and hiding cancels action', async () => {
    const env = environment(manualConfig);
    let request;
    const child = {postMessage(data) { request = data; }};
    frame(env, child);
    const first = env.sandbox.__adspeed.skipAsync();
    const second = env.sandbox.__adspeed.skipAsync();
    assert.equal(first, second);
    assert.equal(env.sandbox.__adspeed.stats.frameRequests, 1);
    env.hide(true);
    message(env, child, inspectionReply(request));
    assert.equal((await first).unresolved, 1);
});

test('late replies cannot resolve a newer discovery', async () => {
    const env = environment(manualConfig);
    const requests = [];
    const child = {postMessage(data) { requests.push(data); }};
    frame(env, child);
    const first = env.sandbox.__adspeed.inspectAsync();
    env.advance(800);
    assert.equal((await first).unresolved, 1);
    const second = env.sandbox.__adspeed.inspectAsync();
    message(env, child, inspectionReply(requests[0]));
    assert.equal(env.tasks.size, 1);
    message(env, child, inspectionReply(requests[1]));
    assert.equal((await second).unresolved, 0);
});

test('frame enumeration and tokens are bounded; missing channels remain unresolved', async () => {
    const env = environment(manualConfig);
    let posts = 0;
    for (let index = 0; index < 100; index++) frame(env, {postMessage() { posts += 1; }});
    const pending = env.sandbox.__adspeed.skipAsync();
    assert.equal((await pending).unresolved, 1);
    assert.equal(posts, 0);
    const missing = environment({speedVideo: false});
    frame(missing, {postMessage() { throw new Error('must not relay without channel'); }});
    assert.equal((await missing.sandbox.__adspeed.skipAsync()).unresolved, 1);
    const local = environment(manualConfig);
    video(local);
    const first = await local.sandbox.__adspeed.inspectAsync();
    for (let index = 0; index < 9; index++) await local.sandbox.__adspeed.inspectAsync();
    assert.equal(await local.sandbox.__adspeed.validateAsync(first.token), false);
});

test('nested requests stop discovery at depth limit', async () => {
    const env = environment(manualConfig);
    const replies = [];
    let posts = 0;
    frame(env, {postMessage() { posts += 1; }});
    const parent = {postMessage(data) { replies.push(data); }};
    env.sandbox.parent = parent;
    message(env, parent, {adSpeedProtocol: 'session-token', phase: 'inspect', id: '123:456:1', depth: 8});
    await settle();
    assert.equal(posts, 0);
    assert.equal(replies.length, 1);
    assert.equal(replies[0].unresolved, 1);
});

test('exposed action API cannot be overwritten by another page script', () => {
    const env = environment(manualConfig);
    const api = env.sandbox.__adspeed;
    assert.equal(Object.isFrozen(api), true);
    assert.throws(() => vm.runInContext("'use strict'; window.__adspeed.skipAsync = function(){}", env.sandbox));
    assert.equal(env.sandbox.__adspeed, api);
});

test('covered media and frames abstain instead of acting behind foreground content', async () => {
    const env = environment(manualConfig);
    const media = video(env);
    env.document.elementFromPoint = () => ({tagName: 'DIV'});
    const covered = await env.sandbox.__adspeed.inspectAsync();
    assert.equal(covered.unresolved, 1);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(media.seeks.length, 0);
    const parent = environment(manualConfig);
    frame(parent, {postMessage() { throw new Error('covered frame must not be queried'); }});
    parent.document.elementFromPoint = () => ({tagName: 'DIV'});
    assert.equal((await parent.sandbox.__adspeed.inspectAsync()).unresolved, 1);
});

test('a covering iframe blocks a local video even when the child has no video', async () => {
    const parent = environment(manualConfig);
    const child = environment(manualConfig);
    const media = video(parent);
    connect(parent, child);
    const node = parent.frameNodes[0];
    parent.document.elementFromPoint = () => node;
    assert.equal((await parent.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(media.seeks.length, 0);
});

test('new occlusion invalidates a previously discovered video snapshot', async () => {
    const env = environment(manualConfig);
    const media = video(env);
    env.document.elementFromPoint = () => media;
    const snapshot = await env.sandbox.__adspeed.inspectAsync();
    assert.equal(snapshot.count, 1);
    env.document.elementFromPoint = () => ({tagName: 'DIV'});
    assert.equal(await env.sandbox.__adspeed.validateAsync(snapshot.token), false);
    assert.equal((await env.sandbox.__adspeed.skipAsync(snapshot.token)).handled, 0);
    assert.equal(media.seeks.length, 0);
});

const playbackConfig = Object.assign({}, manualConfig, {manualPlayback: true});

test('production manual playback preserves time and clocks and requests only 2x after pressing', async () => {
    const env = environment(playbackConfig);
    const media = video(env, {ranges: []});
    env.emit('play', media);
    env.advance(2000);
    assert.equal(media.playbackRate, 1);
    assert.equal(media.currentTime, 1);
    assert.equal(env.tasks.size, 0);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    assert.equal(media.playbackRate, 2);
    assert.equal(media.currentTime, 1);
    assert.deepEqual(media.seeks, []);
    assert.equal(env.sandbox.Date.now(), 1700000002000);
    assert.equal(env.sandbox.performance.now(), 2000);
});

test('production playback rejects ignored rates with bounded retries and no seeks', async () => {
    const env = environment(playbackConfig);
    const media = video(env, {ignoreRate: true});
    for (let i = 0; i < 4; i += 1) {
        assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    }
    assert.equal(media.playbackRate, 1);
    assert.equal(media.rates.length, 3);
    assert.equal(media.currentTime, 1);
    assert.deepEqual(media.seeks, []);
});

test('production playback rejects looping creatives without changing their lifecycle', async () => {
    const env = environment(playbackConfig);
    const media = video(env, {loop: true});
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(media.loop, true);
    assert.equal(media.playbackRate, 1);
    assert.deepEqual(media.seeks, []);
});

test('production playback restores the original rate on source reload and hiding', async () => {
    for (const event of ['loadstart', 'emptied', 'hidden']) {
        const env = environment(playbackConfig);
        const media = video(env);
        media.playbackRate = 1.25;
        assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
        assert.equal(media.playbackRate, 2);
        if (event === 'hidden') env.hide(true);
        else env.emit(event, media);
        assert.equal(media.playbackRate, 1.25, event);
        assert.equal(media.paused, false, 'Restoring speed must not call play or pause');
        assert.deepEqual(media.seeks, []);
    }
});

test('production playback leaves completion state untouched and resets when the element replays', async () => {
    const env = environment(playbackConfig);
    const media = video(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    const rateWrites = media.rates.length;
    media.ended = true;
    media.paused = true;
    env.emit('ended', media);
    assert.equal(media.rates.length, rateWrites);
    assert.equal(media.playbackRate, 2);
    assert.equal(media.ended, true);
    assert.equal(media.paused, true);
    media.ended = false;
    media.paused = false;
    env.emit('play', media);
    assert.equal(media.playbackRate, 1);
    assert.deepEqual(media.seeks, []);
});

test('production playback respects a rate changed by the SDK before cleanup', async () => {
    const env = environment(playbackConfig);
    const media = video(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    media.playbackRate = 1.5;
    env.emit('ended', media);
    assert.equal(media.playbackRate, 1.5);
    assert.deepEqual(media.seeks, []);
});

test('source replacement without loadstart releases the prior manual rate', async () => {
    const env = environment(playbackConfig);
    const media = video(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    media.currentSrc = 'https://example.invalid/next-creative.mp4';
    const next = await env.sandbox.__adspeed.inspectAsync();
    assert.equal(media.playbackRate, 1);
    assert.equal((await env.sandbox.__adspeed.skipAsync(next.token)).handled, 1);
    assert.equal(media.playbackRate, 2);
    env.emit('ended', media);
    assert.equal(media.playbackRate, 1);
});

test('production playback selects only one validated child and never closes a sibling', async () => {
    const parent = environment(playbackConfig);
    const child = environment(playbackConfig);
    const sibling = environment(playbackConfig);
    const media = video(child);
    connect(parent, child);
    connect(parent, sibling);
    const closes = installClose(sibling);
    const inspected = await parent.sandbox.__adspeed.inspectAsync();
    assert.equal(inspected.count, 1);
    assert.equal((await parent.sandbox.__adspeed.skipAsync(inspected.token)).handled, 1);
    assert.equal(media.playbackRate, 2);
    assert.deepEqual(media.seeks, []);
    assert.equal(closes(), 0);
});

test('production playback abstains on ambiguous videos or a stale token', async () => {
    const env = environment(playbackConfig);
    const first = video(env);
    const token = (await env.sandbox.__adspeed.inspectAsync()).token;
    const second = video(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync(token)).handled, 0);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 0);
    assert.equal(first.playbackRate, 1);
    assert.equal(second.playbackRate, 1);
    assert.deepEqual(first.seeks, []);
    assert.deepEqual(second.seeks, []);
});

test('hidden or detached manually accelerated videos release their original rate', async () => {
    for (const change of [media => { media.hidden = true; }, media => { media.isConnected = false; }]) {
        const env = environment(playbackConfig);
        const media = video(env);
        assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
        change(media);
        env.observers[0].callback([]);
        env.advance(300);
        assert.equal(media.playbackRate, 1);
        assert.deepEqual(media.seeks, []);
    }
});

test('covering foreground content releases an earlier manual acceleration', async () => {
    const env = environment(playbackConfig);
    const media = video(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    env.document.elementFromPoint = () => ({contains() { return false; }});
    env.observers[0].callback([]);
    env.advance(300);
    assert.equal(media.playbackRate, 1);
    assert.deepEqual(media.seeks, []);
});

test('manual cleanup batches mutations and does not poll when nothing changed', async () => {
    const env = environment(playbackConfig);
    const media = video(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    for (let i = 0; i < 100; i += 1) env.observers[0].callback([]);
    assert.equal(env.tasks.size, 1);
    env.advance(300);
    assert.equal(env.tasks.size, 0);
    assert.equal(media.playbackRate, 2);
    assert.equal(env.observers[0].settings.attributes, true);
});

test('pausing manually accelerated web playback restores speed without resuming it', async () => {
    const env = environment(playbackConfig);
    const media = video(env);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    media.paused = true;
    env.emit('pause', media);
    assert.equal(media.playbackRate, 1);
    assert.equal(media.paused, true);
    assert.deepEqual(media.seeks, []);
});
