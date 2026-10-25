(function () {
    'use strict';

    if (typeof window === 'undefined' || typeof document === 'undefined') {
        return;
    }
    if (Object.prototype.hasOwnProperty.call(window, '__adspeed')) {
        return;
    }

    var configuration = __ADSPEED_CONFIG__;
    var requestedRate = configuration && configuration.rate;
    var rate = typeof requestedRate === 'number' && isFinite(requestedRate)
        ? Math.max(1, Math.min(16, requestedRate))
        : 8;
    var speedVideo = !!(configuration && configuration.speedVideo);
    var compressTimers = !!(configuration && configuration.compressTimers);
    var accelerateClock = !!(configuration && configuration.accelerateClock);
    var forceInline = !!(configuration && configuration.forceInline);
    var autoSkip = !!(configuration && configuration.autoSkip);
    var manualClose = !!(configuration && configuration.manualClose);
    var skipChannel = configuration && configuration.skipChannel;
    var nativeTimeout = window.setTimeout;
    var nativeInterval = window.setInterval;
    var nativeClearTimeout = window.clearTimeout;
    var nativeClearInterval = window.clearInterval;
    var nativeDateNow = Date.now;
    var nativePerformance = window.performance;
    var nativePerformanceNow = nativePerformance && nativePerformance.now;
    var states = new WeakMap();
    var pollHandle = null;
    var refreshing = false;
    var fast = false;
    var maximumVideos = 64;
    var maximumRateAttempts = 8;
    var stats = {
        rate: rate,
        polls: 0,
        scans: 0,
        rateChanges: 0,
        rateFailures: 0,
        skipAttempts: 0,
        skipped: 0,
        seekFailures: 0,
        mediaFailures: 0,
        clockFailures: 0,
        closeRequests: 0,
        closeFailures: 0,
        frameRequests: 0
    };

    function dateNow() {
        return nativeDateNow.call(Date);
    }

    function performanceNow() {
        return nativePerformanceNow.call(nativePerformance);
    }

    function clock(reader) {
        var initial = reader();
        return {reader: reader, real: initial, value: initial};
    }

    var dateClock = clock(dateNow);
    var performanceClock = typeof nativePerformanceNow === 'function'
        ? clock(performanceNow)
        : null;
    var timerClock = clock(performanceClock ? performanceNow : dateNow);

    function advance(state) {
        var real = state.reader();
        if (typeof real === 'number' && isFinite(real) && real > state.real) {
            state.value += (real - state.real) * (fast ? rate : 1);
            state.real = real;
        }
        return state.value;
    }

    function changeMode(nextFast) {
        if (fast === nextFast) {
            return;
        }
        advance(dateClock);
        if (performanceClock) {
            advance(performanceClock);
        }
        advance(timerClock);
        fast = nextFast;
    }

    function pageHidden() {
        return document.hidden === true || document.visibilityState === 'hidden';
    }

    function visible(video) {
        if (pageHidden() || video.isConnected === false) {
            return false;
        }
        var node = video;
        var depth = 0;
        while (node && depth < 32) {
            if (node.hidden) {
                return false;
            }
            if (typeof window.getComputedStyle === 'function') {
                var style = window.getComputedStyle(node);
                if (style && (style.display === 'none' || style.visibility === 'hidden'
                    || style.visibility === 'collapse' || parseFloat(style.opacity) === 0)) {
                    return false;
                }
            }
            node = node.parentElement;
            depth += 1;
        }
        if (typeof video.getBoundingClientRect !== 'function') {
            return false;
        }
        var rect = video.getBoundingClientRect();
        if (!rect || rect.width <= 0 || rect.height <= 0) {
            return false;
        }
        if (window.innerWidth > 0 && (rect.right <= 0 || rect.left >= window.innerWidth)) {
            return false;
        }
        if (window.innerHeight > 0 && (rect.bottom <= 0 || rect.top >= window.innerHeight)) {
            return false;
        }
        return true;
    }

    function playing(video) {
        return video && !video.paused && !video.ended && !video.seeking
            && video.readyState >= 2 && visible(video);
    }

    function mediaState(video) {
        var source = String(video.currentSrc || video.src || '');
        var state = states.get(video);
        if (!state || state.source !== source) {
            state = {source: source, attempted: false, rateAttempts: 0, rateFailed: false};
            states.set(video, state);
        }
        return state;
    }

    function applyRate(video, state) {
        if (!speedVideo || state.rateFailed || state.rateAttempts >= maximumRateAttempts) {
            return;
        }
        if (typeof video.duration !== 'number' || !isFinite(video.duration) || video.duration <= 0) {
            return;
        }
        if (Math.abs(video.playbackRate - rate) < 0.001) {
            return;
        }
        state.rateAttempts += 1;
        try {
            video.playbackRate = rate;
            if (Math.abs(video.playbackRate - rate) < 0.001) {
                stats.rateChanges += 1;
            } else {
                state.rateFailed = true;
                stats.rateFailures += 1;
            }
        } catch (error) {
            state.rateFailed = true;
            stats.rateFailures += 1;
        }
    }

    function skipVideo(video, state, explicit) {
        if (state.attempted) {
            return false;
        }
        var duration = video.duration;
        var current = video.currentTime;
        if (typeof duration !== 'number' || !isFinite(duration) || duration <= 0
            || typeof current !== 'number' || !isFinite(current) || current < 0) {
            return false;
        }
        var target = duration - Math.min(0.25, duration / 10);
        if (target <= current + 0.05) {
            return false;
        }
        var ranges = video.seekable;
        var seekable = false;
        var count = ranges ? Math.min(ranges.length, 32) : 0;
        for (var index = 0; index < count; index += 1) {
            if (ranges.start(index) <= target && ranges.end(index) >= target) {
                seekable = true;
                break;
            }
        }
        if (!seekable) {
            return false;
        }
        var looping = video.loop === true;
        if (looping && !explicit) return false;
        state.attempted = true;
        stats.skipAttempts += 1;
        try {
            if (looping) {
                video.loop = false;
                if (video.loop) throw new Error('Loop cannot be disabled');
            }
            video.currentTime = target;
            stats.skipped += 1;
            return true;
        } catch (error) {
            if (looping) {
                try {
                    video.loop = true;
                } catch (restoreError) {
                    stats.mediaFailures += 1;
                }
            }
            stats.seekFailures += 1;
            return false;
        }
    }

    function scan(shouldSkip, explicit) {
        if (refreshing || pageHidden()) {
            if (pageHidden()) {
                changeMode(false);
            }
            return 0;
        }
        refreshing = true;
        var hasVideo = false;
        var skipped = 0;
        try {
            var videos = typeof document.getElementsByTagName === 'function'
                ? document.getElementsByTagName('video')
                : [];
            var count = Math.min(videos.length, maximumVideos);
            stats.scans += 1;
            for (var index = 0; index < count; index += 1) {
                var video = videos[index];
                try {
                    if (!playing(video)) {
                        continue;
                    }
                    hasVideo = true;
                    var state = mediaState(video);
                    if (forceInline) {
                        if (!video.hasAttribute('playsinline')) {
                            video.setAttribute('playsinline', '');
                        }
                        if (!video.hasAttribute('webkit-playsinline')) {
                            video.setAttribute('webkit-playsinline', '');
                        }
                        video.playsInline = true;
                    }
                    applyRate(video, state);
                    if (shouldSkip && skipVideo(video, state, explicit)) {
                        skipped += 1;
                    }
                } catch (error) {
                    stats.mediaFailures += 1;
                }
            }
            changeMode(!(speedVideo && hasVideo));
        } finally {
            refreshing = false;
        }
        return skipped;
    }

    function refresh() {
        if (speedVideo || compressTimers || accelerateClock || autoSkip) scan(autoSkip);
    }

    function schedulePoll() {
        if (pollHandle !== null || pageHidden() || typeof nativeTimeout !== 'function'
            || !(speedVideo || compressTimers || accelerateClock || autoSkip)) {
            return;
        }
        pollHandle = nativeTimeout.call(window, function () {
            pollHandle = null;
            if (pageHidden()) {
                changeMode(false);
                return;
            }
            stats.polls += 1;
            refresh();
            schedulePoll();
        }, 250);
    }

    function visibilityChanged() {
        if (pageHidden()) {
            changeMode(false);
            if (pollHandle !== null && typeof nativeClearTimeout === 'function') {
                nativeClearTimeout.call(window, pollHandle);
                pollHandle = null;
            }
            return;
        }
        refresh();
        schedulePoll();
    }

    function timerDelay(value) {
        var converted = Number(value) >> 0;
        return Math.max(0, converted);
    }

    if (compressTimers && typeof nativeTimeout === 'function') {
        window.setTimeout = function (callback, delay) {
            var args = Array.prototype.slice.call(arguments);
            var period = timerDelay(delay);
            if (typeof callback === 'function' && period > 0
                && typeof nativeInterval === 'function' && typeof nativeClearInterval === 'function') {
                var next = advance(timerClock) + period;
                var handle;
                args[0] = function () {
                    if (pageHidden()) {
                        changeMode(false);
                    }
                    if (advance(timerClock) + 0.001 < next) {
                        return;
                    }
                    nativeClearInterval.call(window, handle);
                    return callback.apply(this, arguments);
                };
                args[1] = period / rate;
                handle = nativeInterval.apply(this, args);
                return handle;
            }
            if (args.length > 1) {
                args[1] = period / (fast && !pageHidden() ? rate : 1);
            }
            return nativeTimeout.apply(this, args);
        };
    }
    if (compressTimers && typeof nativeInterval === 'function') {
        window.setInterval = function (callback, delay) {
            var args = Array.prototype.slice.call(arguments);
            var period = timerDelay(delay);
            if (typeof callback !== 'function' || period === 0) {
                if (args.length > 1) {
                    args[1] = period / (fast && !pageHidden() ? rate : 1);
                }
                return nativeInterval.apply(this, args);
            }
            var next = advance(timerClock) + period;
            args[0] = function () {
                if (pageHidden()) {
                    changeMode(false);
                }
                var now = advance(timerClock);
                if (now + 0.001 < next) {
                    return;
                }
                next += (Math.floor((now - next) / period) + 1) * period;
                return callback.apply(this, arguments);
            };
            args[1] = period / rate;
            return nativeInterval.apply(this, args);
        };
    }

    if (accelerateClock) {
        try {
            Object.defineProperty(Date, 'now', {
                configurable: true,
                writable: true,
                value: function () {
                    return Math.floor(advance(dateClock));
                }
            });
        } catch (error) {
            stats.clockFailures += 1;
        }
        if (performanceClock) {
            try {
                Object.defineProperty(nativePerformance, 'now', {
                    configurable: true,
                    writable: true,
                    value: function () {
                        return advance(performanceClock);
                    }
                });
            } catch (error) {
                stats.clockFailures += 1;
            }
        }
    }

    function closeAd() {
        var result = 0;
        if (manualClose && !pageHidden()) {
            try {
                var bridge = window.mraid;
                if (bridge && typeof bridge.close === 'function'
                    && typeof bridge.getState === 'function') {
                    var state = bridge.getState();
                    var placement = typeof bridge.getPlacementType === 'function'
                        ? bridge.getPlacementType() : null;
                    var viewable = typeof bridge.isViewable !== 'function' || bridge.isViewable();
                    if (viewable && (state === 'default' || state === 'expanded' || state === 'resized')
                        && (placement === 'interstitial' || state === 'expanded' || state === 'resized')) {
                        bridge.close();
                        stats.closeRequests += 1;
                        result += 1;
                    }
                }
            } catch (error) {
                stats.closeFailures += 1;
            }
        }
        return result;
    }

    function requestSkip() {
        if (pageHidden()) return 0;
        var result = scan(true, true);
        if (!result) result = closeAd();
        if (typeof skipChannel === 'string' && skipChannel.length) {
            var count = window.frames ? Math.min(window.frames.length, 64) : 0;
            for (var index = 0; index < count; index += 1) {
                try {
                    window.frames[index].postMessage({adSpeedSkip: skipChannel}, '*');
                    stats.frameRequests += 1;
                } catch (error) {
                    // A frame can disappear between enumeration and delivery.
                }
            }
        }
        return result;
    }

    var requestSequence = 0;
    var requestPrefix = String(dateNow()) + ':' + String(Math.floor(Math.random() * 0x100000000)) + ':';
    var pendingChildren = null;
    var activeRequest = null;
    var receivedRequests = new Map();
    var maximumFrameDepth = 8;

    function frameCandidates() {
        var result = {children: [], unresolved: 0};
        try {
            var nodes = document.querySelectorAll('iframe,frame');
            var count = Math.min(nodes.length, 64);
            if (nodes.length > count || (window.frames && window.frames.length > nodes.length)) {
                result.unresolved += 1;
            }
            for (var index = 0; index < count; index += 1) {
                var node = nodes[index];
                if (!visible(node)) continue;
                var child = node.contentWindow;
                if (!child || typeof child.postMessage !== 'function') {
                    result.unresolved += 1;
                } else if (!result.children.some(function (entry) { return entry.source === child; })) {
                    result.children.push({source: child, node: node, pending: true});
                }
            }
        } catch (error) {
            result.unresolved += window.frames && window.frames.length ? 1 : 0;
        }
        return result;
    }

    function relayChildren(depth) {
        var candidates = frameCandidates();
        if (!candidates.children.length) return Promise.resolve({handled: 0, unresolved: candidates.unresolved});
        if (depth >= maximumFrameDepth || typeof skipChannel !== 'string' || !skipChannel.length) {
            return Promise.resolve({handled: 0, unresolved: candidates.unresolved + candidates.children.length});
        }
        return new Promise(function (resolve) {
            var record = {
                id: requestPrefix + (++requestSequence),
                children: candidates.children,
                remaining: candidates.children.length,
                handled: 0,
                unresolved: candidates.unresolved,
                timer: null,
                finish: function () {
                    if (pendingChildren !== record) return;
                    pendingChildren = null;
                    nativeClearTimeout.call(window, record.timer);
                    resolve({handled: record.handled, unresolved: Math.min(4096, record.unresolved + record.remaining)});
                }
            };
            pendingChildren = record;
            record.timer = nativeTimeout.call(window, record.finish, 800 - depth * 80);
            record.children.forEach(function (entry) {
                try {
                    entry.source.postMessage({adSpeedRequest: skipChannel, id: record.id, depth: depth + 1}, '*');
                    stats.frameRequests += 1;
                } catch (error) {
                    entry.pending = false;
                    record.remaining -= 1;
                    record.unresolved += 1;
                }
            });
            if (!record.remaining) record.finish();
        });
    }

    function requestSkipAsync(depth) {
        if (activeRequest) return activeRequest;
        if (pageHidden()) return Promise.resolve({handled: 0, unresolved: 1});
        var local = scan(true, true);
        if (local) return Promise.resolve({handled: local, unresolved: 0});
        activeRequest = relayChildren(depth).then(function (result) {
            if (pageHidden()) result.unresolved = Math.min(4096, result.unresolved + 1);
            if (!result.handled && !result.unresolved) result.handled = closeAd();
            activeRequest = null;
            return result;
        }, function () {
            activeRequest = null;
            return {handled: 0, unresolved: 1};
        });
        return activeRequest;
    }

    function validCount(value) {
        return typeof value === 'number' && isFinite(value) && value >= 0 && value <= 4096
            && Math.floor(value) === value;
    }

    function replyToParent(parent, id, result) {
        try {
            parent.postMessage({adSpeedReply: skipChannel, id: id,
                handled: result.handled, unresolved: result.unresolved}, '*');
        } catch (error) {
            // The parent can navigate while the request is pending.
        }
    }

    var api = {
        version: 2,
        skip: function () {
            return requestSkip();
        },
        skipAsync: function () {
            return requestSkipAsync(0);
        },
        stats: stats
    };
    try {
        Object.defineProperty(window, '__adspeed', {
            configurable: false,
            enumerable: false,
            writable: false,
            value: api
        });
    } catch (error) {
        return;
    }

    if (typeof window.addEventListener === 'function' && typeof skipChannel === 'string' && skipChannel.length) {
        window.addEventListener('message', function (event) {
            var data = event.data;
            if (!data) return;
            var record = pendingChildren;
            if (record && data.adSpeedReply === skipChannel && data.id === record.id
                && validCount(data.handled) && validCount(data.unresolved)) {
                var entry = record.children.find(function (child) { return child.source === event.source; });
                if (!entry || !entry.pending) return;
                entry.pending = false;
                record.remaining -= 1;
                record.handled = Math.min(4096, record.handled + data.handled);
                record.unresolved = Math.min(4096, record.unresolved + data.unresolved);
                if (!visible(entry.node)) record.unresolved += 1;
                if (!record.remaining) record.finish();
                return;
            }
            if (window.parent === window || event.source !== window.parent) return;
            if (data.adSpeedSkip === skipChannel) {
                requestSkip();
                return;
            }
            if (data.adSpeedRequest !== skipChannel || typeof data.id !== 'string'
                || !/^[0-9:.]{1,96}$/.test(data.id) || typeof data.depth !== 'number'
                || data.depth < 1 || data.depth > maximumFrameDepth || Math.floor(data.depth) !== data.depth) return;
            var received = receivedRequests.get(data.id);
            if (received) {
                if (received.result) replyToParent(event.source, data.id, received.result);
                return;
            }
            if (receivedRequests.size >= 16) receivedRequests.delete(receivedRequests.keys().next().value);
            received = {result: null};
            receivedRequests.set(data.id, received);
            var response = activeRequest ? Promise.resolve({handled: 0, unresolved: 1})
                : requestSkipAsync(data.depth);
            var parent = event.source;
            var id = data.id;
            response.then(function (result) {
                received.result = result;
                replyToParent(parent, id, result);
            });
        }, false);
    }

    if (typeof document.addEventListener === 'function') {
        var mediaEvents = ['play', 'pause', 'ended', 'loadedmetadata', 'durationchange', 'ratechange', 'seeked'];
        for (var eventIndex = 0; eventIndex < mediaEvents.length; eventIndex += 1) {
            document.addEventListener(mediaEvents[eventIndex], refresh, true);
        }
        function sourceChanged(event) {
            if (event.target && String(event.target.tagName).toLowerCase() === 'video') {
                states.delete(event.target);
            }
            refresh();
        }
        document.addEventListener('loadstart', sourceChanged, true);
        document.addEventListener('emptied', sourceChanged, true);
        document.addEventListener('visibilitychange', visibilityChanged, false);
    }
    if (typeof window.MutationObserver === 'function') {
        var observer = new window.MutationObserver(refresh);
        observer.observe(document, {childList: true, subtree: true});
    }
    refresh();
    schedulePoll();
}());
