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
    const controls = [];
    const document = {
        hidden: !!options.hidden,
        visibilityState: options.hidden ? 'hidden' : 'visible',
        // Default fixtures model unobstructed media under one container. Tests
        // for occlusion replace this with the actual frontmost fixture node.
        elementFromPoint() {
            return {contains(node) { return videos.includes(node) || frameNodes.includes(node) || controls.includes(node); }};
        },
        querySelectorAll(selector) {
            if (selector === 'iframe,frame') return frameNodes;
            assert.equal(selector, 'button,[role="button"],[aria-label]');
            return controls;
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
    const nativeFrameTimer = sandbox.setTimeout;
    sandbox.requestAnimationFrame = (callback) => nativeFrameTimer(() => callback(now), 16);
    sandbox.cancelAnimationFrame = sandbox.clearTimeout;
    sandbox.open = options.open || (() => 'opened');
    sandbox.MouseEvent = class { constructor(type, options) { this.type = type; Object.assign(this, options); } };
    sandbox.PointerEvent = sandbox.MouseEvent;
    if (options.noPerformance) {
        delete sandbox.performance;
    }
    vm.createContext(sandbox);
    const config = Object.assign({rate: 8, speedVideo: true, recognizedAd: true}, configuration);
    const script = source.replace('__ADSPEED_CONFIG__', JSON.stringify(config));
    const api = {
        sandbox,
        document,
        videos,
        frameNodes,
        controls,
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

test('clamps finite rate and replaces malformed values with 16', () => {
    for (const [input, expected] of [[0, 1], [-4, 1], [100, 16], [4, 4], [null, 16], ['bad', 16]]) {
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
    assert.equal(media.seeks.length, 0);
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
        {style: {display: 'none'}},
        {style: {visibility: 'hidden'}},
        {style: {opacity: '0'}},
        {parentElement: {hidden: true}},
        {rectangle: {left: 401, right: 450, top: 0, bottom: 20, width: 49, height: 20}},
        {rectangle: {left: 0, right: 0, top: 0, bottom: 0, width: 0, height: 0}}
    ];
    for (const properties of cases) {
        const env = environment({speedVideo: false, recognizedAd: false});
        const media = video(env, properties);
        env.emit('play', media);
        assert.equal(env.sandbox.__adspeed.skip(), 0, JSON.stringify(properties));
        assert.equal(media.seeks.length, 0);
    }
});

test('pausing is preserved and resuming makes a video eligible', () => {
    const env = environment({recognizedAd: true});
    const media = video(env, {paused: true});
    env.emit('play', media);
    env.advance(250);
    assert.equal(media.seeks.length, 0);
    assert.equal(media.rates.length, 0);
    media.paused = false;
    env.emit('play', media);
    assert.equal(media.seeks.length, 0);
    assert.equal(media.playbackRate, 8);
    media.paused = true;
    env.emit('pause', media);
    env.advance(250);
    assert.equal(media.paused, true);
    assert.equal(media.seeks.length, 0);
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
    const env = environment({compressTimers: true});
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

test('hidden-page startup does not scan or accelerate until foregrounded', () => {
    const env = environment({recognizedAd: true}, {hidden: true});
    const media = video(env);
    env.emit('play', media);
    assert.equal(env.tasks.size, 0);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(env.sandbox.__adspeed.stats.scans, 0);
    env.hide(false);
    assert.equal(media.seeks.length, 0);
    assert.equal(env.tasks.size, 1);
});

test('generated C++ header embeds the exact JavaScript and one config token', () => {
    const header = fs.readFileSync(path.join(root, 'AdSpeedWebScript.h'), 'utf8');
    const opening = 'static const char kAdSpeedWebScript[] = R"ADSPEEDJS(';
    const content = header.slice(header.indexOf(opening) + opening.length, header.lastIndexOf(')ADSPEEDJS";'));
    assert.equal(content, source.replace(/\r\n/g, '\n'));
    assert.equal(content.split('__ADSPEED_CONFIG__').length - 1, 1);
});

test('manual mode leaves video, native timers, and clocks unchanged until requested', () => {
    const env = environment({speedVideo: false, recognizedAd: false});
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
    assert.equal(media.seeks.length, 0);
    assert.equal(media.playbackRate, 8);
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

const manualConfig = {rate: 16, speedVideo: false, recognizedAd: false, skipChannel: 'session-token'};

async function settle() {
    for (let index = 0; index < 20; index++) await Promise.resolve();
}

function inspectionReply(request, overrides = {}) {
    return Object.assign({adSpeedReply: 'session-token', phase: request.phase, id: request.id,
        count: 0, unresolved: 0, token: '123:456:9'}, overrides);
}

test('inspection and validation are side-effect free and tokens authorize one local speed request', async () => {
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
    assert.equal(media.currentTime, 1);
    assert.equal(media.playbackRate, 16);
    assert.equal(media.ended, false);
    assert.equal((await env.sandbox.__adspeed.skipAsync(inspected.token)).handled, 0);
    assert.equal(media.seeks.length, 0);
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
    assert.equal('closeRequests' in env.sandbox.__adspeed.stats, false);
});

test('two local videos are ambiguous and neither is accelerated', async () => {
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
    assert.equal(ad.seeks.length, 0);
    assert.equal(ad.playbackRate, 16);
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
    assert.equal(media.seeks.length, 0);
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

const playbackConfig = manualConfig;

test('production manual playback preserves time and clocks and requests configured 16x after pressing', async () => {
    const env = environment(playbackConfig);
    const media = video(env, {ranges: []});
    env.emit('play', media);
    env.advance(2000);
    assert.equal(media.playbackRate, 1);
    assert.equal(media.currentTime, 1);
    assert.equal(env.tasks.size, 0);
    assert.equal((await env.sandbox.__adspeed.skipAsync()).handled, 1);
    assert.equal(media.playbackRate, 16);
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
        assert.equal(media.playbackRate, 16);
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
    assert.equal(media.playbackRate, 16);
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
    assert.equal(media.playbackRate, 16);
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
    assert.equal(media.playbackRate, 16);
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
    assert.equal(media.playbackRate, 16);
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

const adConfig = {rate: 16, speedVideo: true, compressTimers: true, accelerateClock: true,
    recognizedAd: false, autoComplete: true, preventRedirects: true, skipChannel: 'session-token'};

function control(env, label, overrides = {}) {
    const events = [];
    const node = Object.assign({tagName: 'BUTTON', textContent: label, isConnected: true,
        parentElement: null, style: {}, disabled: false,
        getAttribute() { return null; },
        getBoundingClientRect() { return {left: 20, top: 40, right: 320, bottom: 340, width: 300, height: 300}; },
        dispatchEvent(event) { events.push(event); return true; }
    }, overrides);
    node.events = events;
    env.controls.push(node);
    return node;
}

test('recognized ad context enables 16x video and timers together without a seek', () => {
    const env = environment(adConfig);
    const media = video(env);
    env.emit('play', media);
    env.advance(100);
    assert.equal(media.playbackRate, 1);
    assert.equal(env.sandbox.performance.now(), 100);
    env.sandbox.__adspeed.setAdContext(true);
    assert.equal(media.playbackRate, 16);
    let fired = 0;
    env.sandbox.setTimeout(() => fired++, 1600);
    env.advance(100);
    assert.equal(fired, 1);
    assert.equal(env.sandbox.performance.now(), 1700);
    assert.deepEqual(media.seeks, []);
    env.sandbox.__adspeed.setAdContext(false);
    assert.equal(media.playbackRate, 1);
    env.advance(100);
    assert.equal(env.sandbox.performance.now(), 1800);
});

test('existing scheduled timeout follows context transitions and fires once', () => {
    const env = environment(adConfig);
    let fired = 0;
    env.sandbox.setTimeout(() => fired++, 1600);
    env.advance(100);
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(100);
    assert.equal(fired, 1);
    env.sandbox.__adspeed.setAdContext(false);
    env.advance(2000);
    assert.equal(fired, 1);
});

test('16x clocks remain monotonic across hiding and returning to ordinary content', () => {
    const env = environment(adConfig);
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(100);
    assert.equal(env.sandbox.performance.now(), 1600);
    env.hide(true);
    env.advance(100);
    assert.equal(env.sandbox.performance.now(), 1700);
    env.hide(false);
    env.advance(100);
    assert.equal(env.sandbox.performance.now(), 3300);
    env.sandbox.__adspeed.setAdContext(false);
    env.advance(100);
    assert.equal(env.sandbox.performance.now(), 3400);
});

test('animation frame timestamps share the accelerated monotonic performance clock', () => {
    const env = environment(adConfig);
    const frames = [];
    env.sandbox.__adspeed.setAdContext(true);
    env.sandbox.requestAnimationFrame(value => frames.push(value));
    env.advance(16);
    assert.deepEqual(frames, [256]);
    assert.equal(frames[0], env.sandbox.performance.now());
    const canceled = env.sandbox.requestAnimationFrame(value => frames.push(value));
    env.sandbox.cancelAnimationFrame(canceled);
    env.advance(16);
    assert.equal(frames.length, 1);
    env.hide(true);
    env.sandbox.requestAnimationFrame(value => frames.push(value));
    env.advance(16);
    assert.equal(frames[1], 528);
});

test('automatic and manual acceleration coexist without resetting time or duplicating rate writes', async () => {
    const env = environment(adConfig);
    const media = video(env);
    env.sandbox.__adspeed.setAdContext(true);
    const writes = media.rates.length;
    const first = await env.sandbox.__adspeed.skipAsync();
    const second = await env.sandbox.__adspeed.skipAsync();
    assert.equal(first.handled, 1);
    assert.equal(second.handled, 1);
    assert.equal(media.rates.length, writes);
    assert.equal(media.playbackRate, 16);
    assert.equal(media.currentTime, 1);
    assert.deepEqual(media.seeks, []);
});

test('automatic rate rejection is bounded and never substitutes seeking or completion', () => {
    for (const properties of [{throwRate: true}, {ignoreRate: true}]) {
        const env = environment(adConfig);
        const media = video(env, properties);
        const closes = installClose(env);
        env.sandbox.__adspeed.setAdContext(true);
        env.advance(3000);
        assert.equal(media.rates.length, 1);
        assert.equal(media.playbackRate, 1);
        assert.equal(media.ended, false);
        assert.equal(media.paused, false);
        assert.deepEqual(media.seeks, []);
        assert.equal(closes(), 0);
    }
});

test('automatic scans bound media work and preserve live and looping lifecycles', () => {
    const env = environment(adConfig);
    const looping = video(env, {loop: true});
    const live = video(env, {duration: Infinity});
    for (let index = 0; index < 70; index++) video(env);
    env.sandbox.__adspeed.setAdContext(true);
    assert.equal(looping.playbackRate, 16);
    assert.equal(looping.loop, true);
    assert.equal(live.playbackRate, 1);
    assert.equal(env.videos[64].playbackRate, 1);
    assert.equal(env.videos.reduce((sum, item) => sum + item.seeks.length, 0), 0);
});

test('automatic context removal and source reload restore the original video rate', () => {
    const env = environment(adConfig);
    const media = video(env);
    media.playbackRate = 1.25;
    env.sandbox.__adspeed.setAdContext(true);
    assert.equal(media.playbackRate, 16);
    env.sandbox.__adspeed.setAdContext(false);
    assert.equal(media.playbackRate, 1.25);
    env.emit('loadstart', media);
    assert.equal(media.playbackRate, 1.25);
    assert.deepEqual(media.seeks, []);
});

test('unrecognized content receives no automatic actions, redirects block, or acceleration', () => {
    const env = environment(adConfig);
    installClose(env);
    const node = control(env, 'Tap to play');
    env.observers[0].callback([]);
    env.advance(1000);
    assert.equal(node.events.length, 0);
    assert.equal(env.sandbox.open('https://example.invalid'), 'opened');
    assert.equal(env.sandbox.performance.now(), 1000);
});

test('supported semantic start control receives a single tap while acceleration remains active', () => {
    const env = environment(adConfig);
    const closes = installClose(env);
    const node = control(env, 'Tap to play');
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(1000);
    assert.deepEqual(node.events.map(event => event.type), ['pointerdown', 'pointerup', 'click']);
    assert.equal(env.sandbox.__adspeed.stats.interactions, 1);
    assert.equal(env.sandbox.performance.now(), 16000);
    assert.equal(closes(), 0);
});

for (const direction of ['left', 'right', 'up', 'down']) {
    test('supported swipe ' + direction + ' produces bounded movement without completion calls', () => {
        const env = environment(adConfig);
        const closes = installClose(env);
        const node = control(env, 'Swipe ' + direction);
        env.sandbox.__adspeed.setAdContext(true);
        env.advance(200);
        assert.equal(node.events[0].type, 'pointerdown');
        assert.equal(node.events.at(-1).type, 'pointerup');
        assert.equal(node.events.filter(event => event.type === 'pointermove').length, 6);
        const start = node.events[0];
        const end = node.events.at(-1);
        if (direction === 'left') assert.ok(end.clientX < start.clientX);
        if (direction === 'right') assert.ok(end.clientX > start.clientX);
        if (direction === 'up') assert.ok(end.clientY < start.clientY);
        if (direction === 'down') assert.ok(end.clientY > start.clientY);
        assert.equal(node.events.some(event => event.type === 'click'), false);
        assert.equal(closes(), 0);
    });
}

test('interactive actions wait for MRAID ready and actual viewability', () => {
    const env = environment(adConfig);
    installClose(env);
    let state = 'loading';
    let viewable = false;
    env.sandbox.mraid.getState = () => state;
    env.sandbox.mraid.isViewable = () => viewable;
    const node = control(env, 'Start game');
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(300);
    assert.equal(node.events.length, 0);
    state = 'default';
    env.advance(300);
    assert.equal(node.events.length, 0);
    viewable = true;
    env.advance(300);
    assert.equal(node.events.at(-1).type, 'click');
});

test('unknown canvas, install controls, links, disabled and covered controls remain untouched', () => {
    const env = environment(adConfig);
    installClose(env);
    const controls = [control(env, 'Install'), control(env, 'Play'),
        control(env, 'Start game', {disabled: true}),
        control(env, 'Tap to play', {parentElement: {tagName: 'A'}}),
        control(env, 'Tap to play', {hidden: true})];
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(1000);
    assert.equal(controls.reduce((sum, node) => sum + node.events.length, 0), 0);
    const covered = control(env, 'Continue playing');
    env.document.elementFromPoint = () => ({tagName: 'CANVAS'});
    env.advance(500);
    assert.equal(covered.events.length, 0);
});

test('interaction work is bounded across changing creatives within one ad context', () => {
    const env = environment(adConfig);
    installClose(env);
    for (let index = 0; index < 30; index++) control(env, 'Continue playing');
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(10000);
    assert.equal(env.sandbox.__adspeed.stats.interactions, 12);
    assert.equal(env.controls.filter(node => node.events.length).length, 12);
});

test('leaving ad context cancels an in-progress swipe without a click', () => {
    const env = environment(adConfig);
    installClose(env);
    const node = control(env, 'Swipe left');
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(32);
    env.sandbox.__adspeed.setAdContext(false);
    env.advance(100);
    assert.equal(node.events.at(-1).type, 'pointercancel');
    assert.equal(node.events.some(event => event.type === 'pointerup' || event.type === 'click'), false);
});

test('redirect prevention is scoped to an active ad and preserves original receivers and results', () => {
    const calls = [];
    const receiver = {owner: true};
    const env = environment(adConfig, {open(...args) { calls.push({receiver: this, args}); return 'original'; }});
    installClose(env);
    const mraid = env.sandbox.mraid;
    mraid.open = function (...args) { calls.push({receiver: this, args}); return 'mraid'; };
    assert.equal(env.sandbox.open.call(receiver, 'ordinary'), 'original');
    env.sandbox.__adspeed.setAdContext(true);
    assert.equal(env.sandbox.open('blocked'), null);
    assert.equal(mraid.open('blocked'), undefined);
    assert.equal(calls.length, 1);
    env.sandbox.__adspeed.setAdContext(false);
    assert.equal(mraid.open('ordinary'), 'mraid');
    assert.equal(calls[0].receiver, receiver);
    assert.equal(calls[1].receiver, mraid);
    assert.equal(env.sandbox.__adspeed.stats.redirectsBlocked, 2);
});

test('ad context messages require the actual parent and matching session channel', () => {
    const env = environment(adConfig);
    const parent = {postMessage() {}};
    env.sandbox.parent = parent;
    const media = video(env);
    message(env, {}, {adSpeedContext: 'session-token', active: true});
    message(env, parent, {adSpeedContext: 'wrong', active: true});
    assert.equal(media.playbackRate, 1);
    message(env, parent, {adSpeedContext: 'session-token', active: true});
    assert.equal(media.playbackRate, 16);
    message(env, parent, {adSpeedContext: 'session-token', active: false});
    assert.equal(media.playbackRate, 1);
});

test('visible child frames inherit ad context and lose it when covered', () => {
    const parent = environment(adConfig);
    const child = environment(adConfig);
    const media = video(child);
    connect(parent, child);
    parent.sandbox.__adspeed.setAdContext(true);
    assert.equal(media.playbackRate, 16);
    parent.document.elementFromPoint = () => ({tagName: 'DIV'});
    parent.observers[0].callback([]);
    assert.equal(media.playbackRate, 1);
});

test('visible unknown surfaces recognize only ready viewable interstitial MRAID and honor explicit inactivity', () => {
    const env = environment(adConfig);
    const media = video(env);
    env.sandbox.__adspeed.setAdContext(null);
    env.advance(250);
    assert.equal(media.playbackRate, 1);
    installClose(env);
    env.sandbox.mraid.getPlacementType = () => 'inline';
    env.advance(250);
    assert.equal(media.playbackRate, 1);
    env.sandbox.mraid.getPlacementType = () => 'interstitial';
    env.advance(250);
    assert.equal(media.playbackRate, 16);
    env.sandbox.__adspeed.setAdContext(false);
    env.advance(500);
    assert.equal(media.playbackRate, 1);
    assert.equal(env.tasks.size, 0);
});

test('automatic acceleration restores a newer rate chosen by the SDK', () => {
    const env = environment(adConfig);
    const media = video(env);
    env.sandbox.__adspeed.setAdContext(true);
    media.playbackRate = 2;
    assert.equal(media.playbackRate, 16);
    env.sandbox.__adspeed.setAdContext(false);
    assert.equal(media.playbackRate, 2);
});

test('a label change on the same playable control permits its next semantic action once', () => {
    const env = environment(adConfig);
    installClose(env);
    const node = control(env, 'Tap to play');
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(100);
    node.textContent = 'Swipe left';
    env.observers[0].callback([]);
    env.advance(200);
    assert.equal(env.sandbox.__adspeed.stats.interactions, 2);
    env.advance(1000);
    assert.equal(env.sandbox.__adspeed.stats.interactions, 2);
});

test('ordinary pages retain unmodified animation frame timing', () => {
    const env = environment(adConfig);
    let timestamp = 0;
    env.sandbox.requestAnimationFrame(value => timestamp = value);
    env.advance(16);
    assert.equal(timestamp, 16);
});

test('initial nullable context detects a late ready MRAID bridge without native polling', () => {
    const env = environment({...adConfig, recognizedAd: null});
    const media = video(env);
    env.advance(250);
    assert.equal(media.playbackRate, 1);
    installClose(env);
    env.advance(250);
    assert.equal(media.playbackRate, 16);
});

test('an old gesture cannot cancel or release a new context gesture', () => {
    const env = environment(adConfig);
    installClose(env);
    const old = control(env, 'Swipe left');
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(32);
    env.sandbox.__adspeed.setAdContext(false);
    assert.equal(old.events.at(-1).type, 'pointercancel');
    old.hidden = true;
    const next = control(env, 'Swipe right');
    env.sandbox.__adspeed.setAdContext(true);
    env.advance(200);
    assert.equal(next.events.at(-1).type, 'pointerup');
    assert.notEqual(old.events[0].pointerId, next.events[0].pointerId);
    assert.equal(next.events.some(event => event.type === 'pointercancel'), false);
});
