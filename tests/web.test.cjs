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
    const document = {
        hidden: !!options.hidden,
        visibilityState: options.hidden ? 'hidden' : 'visible',
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
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(media.seeks.length, 1);
    assert.equal(media.playbackRate, 8);
    assert.equal(env.sandbox.__adspeed.stats.seekFailures, 1);
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

test('all media scans have a fixed upper bound', () => {
    const env = environment({speedVideo: false});
    for (let index = 0; index < 80; index++) {
        video(env);
    }
    assert.equal(env.sandbox.__adspeed.skip(), 64);
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

test('manual requests use the standard interstitial close API without fake events', () => {
    const env = environment({speedVideo: false, manualClose: true});
    let closes = 0;
    env.sandbox.mraid = {
        getState: () => 'default',
        getPlacementType: () => 'interstitial',
        isViewable: () => true,
        close() { closes += 1; }
    };
    env.advance(1000);
    assert.equal(closes, 0);
    assert.equal(env.sandbox.__adspeed.skip(), 1);
    assert.equal(closes, 1);
    assert.equal(env.sandbox.__adspeed.stats.closeRequests, 1);
});

test('manual close respects hidden, loading, inline and nonviewable ad containers', () => {
    for (const settings of [
        {state: 'loading', placement: 'interstitial', viewable: true},
        {state: 'hidden', placement: 'interstitial', viewable: true},
        {state: 'unexpected', placement: 'interstitial', viewable: true},
        {state: 'default', placement: 'inline', viewable: true},
        {state: 'default', placement: 'interstitial', viewable: false}
    ]) {
        const env = environment({speedVideo: false, manualClose: true});
        let closes = 0;
        env.sandbox.mraid = {
            getState: () => settings.state,
            getPlacementType: () => settings.placement,
            isViewable: () => settings.viewable,
            close() { closes += 1; }
        };
        assert.equal(env.sandbox.__adspeed.skip(), 0);
        assert.equal(closes, 0);
    }
});

test('a media-tail request finishes naturally before requesting an ad close', () => {
    const env = environment({speedVideo: false, manualClose: true});
    const media = video(env);
    let closes = 0;
    env.sandbox.mraid = {
        getState: () => 'default',
        getPlacementType: () => 'interstitial',
        close() { closes += 1; }
    };
    assert.equal(env.sandbox.__adspeed.skip(), 1);
    assert.equal(media.seeks.length, 1);
    assert.equal(closes, 0);
});

test('close errors remain a failed request and do not report completion', () => {
    const env = environment({speedVideo: false, manualClose: true});
    env.sandbox.mraid = {
        getState: () => 'default',
        getPlacementType: () => 'interstitial',
        close() { throw new Error('SDK rejects early close'); }
    };
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(env.sandbox.__adspeed.stats.closeFailures, 1);
    assert.equal(env.sandbox.__adspeed.stats.closeRequests, 0);
});

test('manual requests relay into cross-origin child frames using the session channel', () => {
    const env = environment({speedVideo: false, skipChannel: 'session-token'});
    const messages = [];
    env.sandbox.frames = [{postMessage(data, origin) { messages.push({data, origin}); }}];
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(messages.length, 1);
    assert.equal(messages[0].data.adSpeedSkip, 'session-token');
    assert.equal(messages[0].origin, '*');
    assert.equal(env.sandbox.__adspeed.stats.frameRequests, 1);
});

test('frame relay accepts only its parent and the current channel, once per installation', () => {
    const env = environment({speedVideo: false, skipChannel: 'session-token'});
    const media = video(env);
    const parent = {};
    env.sandbox.parent = parent;
    env.inject();
    const handlers = env.windowListeners.get('message');
    assert.equal(handlers.length, 1);
    handlers[0]({source: {}, data: {adSpeedSkip: 'session-token'}});
    handlers[0]({source: parent, data: {adSpeedSkip: 'wrong-token'}});
    assert.equal(media.seeks.length, 0);
    handlers[0]({source: parent, data: {adSpeedSkip: 'session-token'}});
    assert.equal(media.seeks.length, 1);
});

test('hidden pages neither relay requests nor close ads, with frame work capped', () => {
    const env = environment({speedVideo: false, skipChannel: 'session-token', manualClose: true});
    let posts = 0;
    let closes = 0;
    env.sandbox.frames = Array.from({length: 100}, () => ({postMessage() { posts += 1; }}));
    env.sandbox.mraid = {
        getState: () => 'default', getPlacementType: () => 'interstitial', close() { closes += 1; }
    };
    env.hide(true);
    assert.equal(env.sandbox.__adspeed.skip(), 0);
    assert.equal(posts, 0);
    assert.equal(closes, 0);
    env.hide(false);
    env.sandbox.__adspeed.skip();
    assert.equal(posts, 64);
    assert.equal(closes, 1);
});
