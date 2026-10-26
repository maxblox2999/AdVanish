#pragma once

static const char kAdSpeedWebScript[] = R"ADSPEEDJS((function () {
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

    function exposed(node) {
        if (typeof document.elementFromPoint !== 'function') return false;
        var rect = node.getBoundingClientRect();
        var left = Math.max(0, rect.left);
        var top = Math.max(0, rect.top);
        var right = Math.min(window.innerWidth, rect.right);
        var bottom = Math.min(window.innerHeight, rect.bottom);
        if (right <= left || bottom <= top) return false;
        try {
            for (var x = 1; x <= 3; x += 1) {
                for (var y = 1; y <= 3; y += 1) {
                    var hit = document.elementFromPoint(left + (right - left) * x / 4,
                        top + (bottom - top) * y / 4);
                    if (hit === node || (hit && typeof node.contains === 'function' && node.contains(hit))
                        || (hit && typeof hit.contains === 'function' && hit.contains(node))) return true;
                }
            }
        } catch (error) {
            return false;
        }
        return false;
    }

    function mediaState(video) {
        var source = String(video.currentSrc || video.src || '');
        var state = states.get(video);
        if (!state || state.source !== source) {
            state = {source: source, attempted: false, manualAttempts: 0, rateAttempts: 0, rateFailed: false};
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
        if ((!explicit && state.attempted) || (explicit && state.manualAttempts >= 3)) {
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
        if (explicit) state.manualAttempts += 1;
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

    var requestSequence = 0;
    var requestPrefix = String(dateNow()) + ':' + String(Math.floor(Math.random() * 0x100000000)) + ':';
    var generation = 0;
    var snapshots = new Map();
    var pendingMessages = new Map();
    var receivedMessages = new Map();
    var activeInspection = null;
    var activeRequest = null;
    var maximumFrameDepth = 8;
    var snapshotLifetime = 5000;

    function realNow() {
        return performanceClock ? performanceNow() : dateNow();
    }

    function identifier() {
        return requestPrefix + (++requestSequence);
    }

    function validIdentifier(value) {
        return typeof value === 'string' && /^[0-9:.]{1,96}$/.test(value);
    }

    function unknown() {
        return {count: 0, unresolved: 1, token: null};
    }

    function frameCandidates() {
        var result = {children: [], unresolved: 0};
        try {
            var nodes = document.querySelectorAll('iframe,frame');
            var count = Math.min(nodes.length, 64);
            if (nodes.length > count || (window.frames && window.frames.length > nodes.length)) {
                result.unresolved = 1;
            }
            for (var index = 0; index < count; index += 1) {
                var node = nodes[index];
                if (!visible(node)) continue;
                if (!exposed(node)) {
                    result.unresolved = 1;
                    continue;
                }
                var child = node.contentWindow;
                if (!child || typeof child.postMessage !== 'function') {
                    result.unresolved = 1;
                } else if (!result.children.some(function (entry) { return entry.source === child; })) {
                    result.children.push({source: child, node: node});
                }
            }
        } catch (error) {
            result.unresolved = window.frames && window.frames.length ? 1 : 0;
        }
        return result;
    }

    function seekableTarget(video) {
        if (!playing(video)) return null;
        var duration = video.duration;
        var current = video.currentTime;
        if (typeof duration !== 'number' || !isFinite(duration) || duration <= 0
            || typeof current !== 'number' || !isFinite(current) || current < 0) return null;
        var target = duration - Math.min(0.25, duration / 10);
        if (target <= current + 0.05) return null;
        var ranges = video.seekable;
        var count = ranges ? Math.min(ranges.length, 32) : 0;
        for (var index = 0; index < count; index += 1) {
            if (ranges.start(index) <= target && ranges.end(index) >= target) return target;
        }
        return null;
    }

    function capture() {
        var frames = frameCandidates();
        var snapshot = {generation: generation, videos: [], children: frames.children,
            unresolved: frames.unresolved, candidates: []};
        if (pageHidden()) snapshot.unresolved = 1;
        try {
            var videos = document.getElementsByTagName('video');
            var count = Math.min(videos.length, maximumVideos);
            if (videos.length > count) snapshot.unresolved = 1;
            for (var index = 0; index < count; index += 1) {
                var video = videos[index];
                if (!visible(video)) continue;
                if (!exposed(video)) {
                    snapshot.unresolved = 1;
                    continue;
                }
                var source = String(video.currentSrc || video.src || '');
                snapshot.videos.push({node: video, source: source, paused: !!video.paused,
                    ended: !!video.ended, seeking: !!video.seeking, ready: video.readyState,
                    duration: video.duration});
                if (video.ended) continue;
                var target = seekableTarget(video);
                if (target === null || mediaState(video).manualAttempts >= 3) snapshot.unresolved = 1;
                else snapshot.candidates.push(video);
            }
        } catch (error) {
            snapshot.unresolved = 1;
        }
        return snapshot;
    }

    function unchanged(snapshot) {
        if (pageHidden() || generation !== snapshot.generation) return false;
        var current = capture();
        if (current.unresolved !== snapshot.unresolved || current.videos.length !== snapshot.videos.length
            || current.children.length !== snapshot.children.length) return false;
        for (var index = 0; index < snapshot.videos.length; index += 1) {
            var before = snapshot.videos[index];
            var after = current.videos[index];
            if (before.node !== after.node || before.source !== after.source || before.paused !== after.paused
                || before.ended !== after.ended || before.seeking !== after.seeking || before.ready !== after.ready
                || !Object.is(before.duration, after.duration)) return false;
        }
        for (var frameIndex = 0; frameIndex < snapshot.children.length; frameIndex += 1) {
            if (snapshot.children[frameIndex].node !== current.children[frameIndex].node
                || snapshot.children[frameIndex].source !== current.children[frameIndex].source) return false;
        }
        return true;
    }

    function query(source, phase, token, depth) {
        if (pendingMessages.size >= 64 || typeof skipChannel !== 'string' || !skipChannel.length) {
            return Promise.resolve(phase === 'inspect' ? unknown() : phase === 'validate' ? false : {handled: 0, unresolved: 1});
        }
        return new Promise(function (resolve) {
            var id = identifier();
            var fallback = phase === 'inspect' ? unknown() : phase === 'validate' ? false : {handled: 0, unresolved: 1};
            var record = {source: source, phase: phase, resolve: resolve, timer: null};
            record.timer = nativeTimeout.call(window, function () {
                if (!pendingMessages.delete(id)) return;
                resolve(fallback);
            }, 800 - depth * 80);
            pendingMessages.set(id, record);
            try {
                source.postMessage({adSpeedProtocol: skipChannel, phase: phase, id: id,
                    token: token, depth: depth + 1}, '*');
                stats.frameRequests += 1;
            } catch (error) {
                pendingMessages.delete(id);
                nativeClearTimeout.call(window, record.timer);
                resolve(fallback);
            }
        });
    }

    function inspect(depth) {
        if (activeInspection) {
            return activeInspection.depth === depth ? activeInspection.promise : Promise.resolve(unknown());
        }
        var snapshot = capture();
        if (snapshot.unresolved || (snapshot.children.length && depth >= maximumFrameDepth)) {
            return Promise.resolve(unknown());
        }
        var record = {depth: depth, promise: null};
        activeInspection = record;
        record.promise = Promise.all(snapshot.children.map(function (child) {
            return query(child.source, 'inspect', null, depth);
        })).then(function (results) {
            if (!unchanged(snapshot)) return unknown();
            var count = Math.min(2, snapshot.candidates.length);
            var unresolved = 0;
            var route = snapshot.candidates.length === 1 ? {video: snapshot.candidates[0]} : null;
            results.forEach(function (result, index) {
                count = Math.min(2, count + result.count);
                if (result.unresolved) unresolved = 1;
                if (result.count === 1 && !result.unresolved) {
                    route = {child: snapshot.children[index], token: result.token};
                }
            });
            if (count > 1 || unresolved) return {count: count, unresolved: unresolved, token: null};
            var token = identifier();
            if (snapshots.size >= 8) snapshots.delete(snapshots.keys().next().value);
            snapshots.set(token, {snapshot: snapshot, route: route, children: results, created: realNow()});
            return {count: count, unresolved: 0, token: token};
        }, function () {
            return unknown();
        }).then(function (result) {
            if (activeInspection === record) activeInspection = null;
            return result;
        });
        return record.promise;
    }

    function validSnapshot(record) {
        if (!record || !unchanged(record.snapshot)) return false;
        var elapsed = realNow() - record.created;
        return isFinite(elapsed) && elapsed >= 0 && elapsed <= snapshotLifetime;
    }

    function validate(token, depth) {
        var record = snapshots.get(token);
        if (!validSnapshot(record) || depth > maximumFrameDepth) return Promise.resolve(false);
        if (record.snapshot.children.length && depth >= maximumFrameDepth) return Promise.resolve(false);
        return Promise.all(record.snapshot.children.map(function (child, index) {
            var result = record.children[index];
            if (!result || result.unresolved || !validIdentifier(result.token)) return Promise.resolve(false);
            return query(child.source, 'validate', result.token, depth);
        })).then(function (results) {
            return snapshots.get(token) === record && validSnapshot(record)
                && results.every(function (valid) { return valid === true; });
        }, function () {
            return false;
        });
    }

    function act(token, depth) {
        var record = snapshots.get(token);
        return validate(token, depth).then(function (valid) {
            if (!valid || snapshots.get(token) !== record || !record.route || !validSnapshot(record)) {
                return {handled: 0, unresolved: 1};
            }
            snapshots.delete(token);
            if (record.route.video) {
                var video = record.route.video;
                if (seekableTarget(video) === null) return {handled: 0, unresolved: 1};
                var handled = skipVideo(video, mediaState(video), true) ? 1 : 0;
                return {handled: handled, unresolved: handled ? 0 : 1};
            }
            if (depth >= maximumFrameDepth) return {handled: 0, unresolved: 1};
            return query(record.route.child.source, 'act', record.route.token, depth).then(function (result) {
                if (!result.handled && !unchanged(record.snapshot)) return {handled: 0, unresolved: 1};
                return result;
            });
        }, function () {
            return {handled: 0, unresolved: 1};
        });
    }

    function requestSkipAsync(token) {
        if (typeof token === 'string') return act(token, 0);
        if (activeRequest) return activeRequest;
        activeRequest = inspect(0).then(function (result) {
            if (result.unresolved || result.count > 1) return {handled: 0, unresolved: 1};
            if (!result.count) return {handled: 0, unresolved: 0};
            return act(result.token, 0);
        }).then(function (result) {
            activeRequest = null;
            return result;
        }, function () {
            activeRequest = null;
            return {handled: 0, unresolved: 1};
        });
        return activeRequest;
    }

    function requestSkip() {
        var snapshot = capture();
        if (snapshot.unresolved || snapshot.children.length || snapshot.candidates.length !== 1) return 0;
        var video = snapshot.candidates[0];
        return skipVideo(video, mediaState(video), true) ? 1 : 0;
    }

    var api = Object.freeze({
        version: 3,
        skip: requestSkip,
        inspectAsync: function () { return inspect(0); },
        validateAsync: function (token) { return validate(token, 0); },
        skipAsync: requestSkipAsync,
        stats: stats
    });
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

    function replyToParent(parent, request, result) {
        try {
            parent.postMessage({adSpeedReply: skipChannel, id: request.id, phase: request.phase,
                count: result.count, token: result.token, handled: result.handled,
                unresolved: result && result.unresolved, valid: result === true}, '*');
        } catch (error) {
            // The parent can disappear while discovery is pending.
        }
    }

    if (typeof window.addEventListener === 'function' && typeof skipChannel === 'string' && skipChannel.length) {
        window.addEventListener('message', function (event) {
            var data = event.data;
            if (!data) return;
            var record = pendingMessages.get(data.id);
            if (record && data.adSpeedReply === skipChannel && record.source === event.source
                && data.phase === record.phase) {
                var bounded = data.unresolved === 0 || data.unresolved === 1;
                var valid = record.phase === 'inspect'
                    ? bounded && (data.count === 0 || data.count === 1 || data.count === 2)
                        && (data.count > 1 || data.unresolved || validIdentifier(data.token))
                    : record.phase === 'validate' ? typeof data.valid === 'boolean'
                    : bounded && (data.handled === 0 || data.handled === 1);
                if (!valid) return;
                pendingMessages.delete(data.id);
                nativeClearTimeout.call(window, record.timer);
                record.resolve(record.phase === 'inspect'
                    ? {count: data.count, unresolved: data.unresolved, token: data.token}
                    : record.phase === 'validate' ? data.valid
                    : {handled: data.handled, unresolved: data.unresolved});
                return;
            }
            if (window.parent === window || event.source !== window.parent || data.adSpeedProtocol !== skipChannel
                || (data.phase !== 'inspect' && data.phase !== 'act' && data.phase !== 'validate')
                || !validIdentifier(data.id) || typeof data.depth !== 'number' || data.depth < 1
                || data.depth > maximumFrameDepth || Math.floor(data.depth) !== data.depth
                || (data.phase !== 'inspect' && !validIdentifier(data.token))) return;
            var key = data.phase + ':' + data.id;
            var received = receivedMessages.get(key);
            if (received) {
                if (received.complete) replyToParent(event.source, data, received.result);
                return;
            }
            if (receivedMessages.size >= 16) receivedMessages.delete(receivedMessages.keys().next().value);
            received = {result: null, complete: false};
            receivedMessages.set(key, received);
            var response = data.phase === 'inspect' ? inspect(data.depth)
                : data.phase === 'validate' ? validate(data.token, data.depth) : act(data.token, data.depth);
            var parent = event.source;
            response.then(function (result) {
                received.result = result;
                received.complete = true;
                replyToParent(parent, data, result);
            });
        }, false);
    }

    if (typeof document.addEventListener === 'function') {
        var mediaEvents = ['play', 'pause', 'ended', 'loadedmetadata', 'durationchange', 'ratechange', 'seeked'];
        for (var eventIndex = 0; eventIndex < mediaEvents.length; eventIndex += 1) {
            document.addEventListener(mediaEvents[eventIndex], refresh, true);
        }
        function sourceChanged(event) {
            generation += 1;
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
)ADSPEEDJS";
