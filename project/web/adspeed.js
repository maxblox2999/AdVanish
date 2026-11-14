// Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

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
        ? Math.max(1, Math.min(80, requestedRate))
        : 80;
    var speedVideo = !!(configuration && configuration.speedVideo);
    var compressTimers = !!(configuration && configuration.compressTimers);
    var accelerateClock = !!(configuration && configuration.accelerateClock);
    var forceInline = !!(configuration && configuration.forceInline);
    var recognizedAd = !!(configuration && configuration.recognizedAd);
    var contextPolicy = configuration && configuration.recognizedAd === null ? null : recognizedAd;
    var autoComplete = !!(configuration && configuration.autoComplete);
    var autoDismiss = !!(configuration && configuration.autoDismiss);
    var automatic = !(configuration && configuration.automatic === false);
    var compatibilityPlayback = !!(configuration && configuration.compatibilityPlayback);
    var manualContext = false;
    var manualTimingOnly = false;
    var manualTimingSnapshot = null;
    var timerHooks = 0;
    var clockHooks = 0;
    var preventRedirects = !!(configuration && configuration.preventRedirects);
    var hideAppStore = !!(configuration && configuration.hideAppStore);
    var skipChannel = configuration && configuration.skipChannel;
    var nativeTimeout = window.setTimeout;
    var nativeInterval = window.setInterval;
    var nativeClearTimeout = window.clearTimeout;
    var nativeClearInterval = window.clearInterval;
    var nativeDateNow = Date.now;
    var nativePerformance = window.performance;
    var nativePerformanceNow = nativePerformance && nativePerformance.now;
    var states = new WeakMap();
    var animationStates = new WeakMap();
    var animationLeases = new Map();
    var manuallyAccelerated = new Set();
    var manualCleanupHandle = null;
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
        manualRequests: 0,
        interactions: 0,
        interactionFailures: 0,
        redirectsBlocked: 0,
        mediaFailures: 0,
        clockFailures: 0,
        timerFailures: 0,
        animationFailures: 0,
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

    function broadPlaybackActive() {
        return compatibilityPlayback && automatic && !pageHidden();
    }

    function accelerationActive() {
        return broadPlaybackActive() || (recognizedAd && (automatic || manualContext) && !pageHidden());
    }

    function timingAvailable() {
        return timerHooks > 0 || clockHooks > 0
            || (accelerateClock && typeof document.getAnimations === 'function');
    }

    function authorizeTiming(timingOnly, snapshot) {
        if (!recognizedAd || pageHidden() || !timingAvailable()) return false;
        manualContext = true;
        manualTimingOnly = timingOnly === true;
        manualTimingSnapshot = manualTimingOnly ? snapshot : null;
        changeMode(true);
        schedulePoll();
        return true;
    }

    function revokeManualContext() {
        manualContext = false;
        manualTimingOnly = false;
        manualTimingSnapshot = null;
        changeMode(false);
        manuallyAccelerated.forEach(restoreManualRate);
        restoreAnimations();
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

    function exposed(node, allowAncestor) {
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
                        || (allowAncestor !== false && hit && typeof hit.contains === 'function' && hit.contains(node))) return true;
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
            if (state && !automatic && manualContext) {
                contextGeneration += 1;
                revokeManualContext();
            }
            if (state) restoreManualRate(video);
            state = {source: source, manualAttempts: 0, rateAttempts: 0, rateFailed: false};
            states.set(video, state);
        }
        return state;
    }

    function writeSupportedRate(video, state) {
        if (state.writingRate) return false;
        var original = video.playbackRate;
        var requested = state.acceptedRate || rate;
        var tiers = rate > 16 ? [requested, 16, 8, 4, 2] : [requested];
        state.writingRate = true;
        try {
            for (var index = 0, previous = Infinity; index < tiers.length; index += 1) {
                var candidate = tiers[index];
                if (candidate >= previous || candidate > requested || candidate <= 0) continue;
                previous = candidate;
                try {
                    video.playbackRate = candidate;
                    var accepted = video.playbackRate;
                    if (!isFinite(accepted) || Math.abs(accepted - candidate) > 0.001) continue;
                    if (!manuallyAccelerated.has(video) || original !== state.manualRate) state.originalRate = original;
                    state.manualRate = accepted;
                    state.acceptedRate = accepted;
                    manuallyAccelerated.add(video);
                    stats.rateChanges += 1;
                    return true;
                } catch (error) {
                    // Continue to a supported tier without seeking or ending media.
                }
            }
            try {
                if (video.playbackRate !== original) video.playbackRate = original;
            } catch (restoreError) {
                stats.mediaFailures += 1;
            }
            stats.rateFailures += 1;
            return false;
        } finally {
            state.writingRate = false;
        }
    }

    function applyRate(video, state) {
        if (!speedVideo || state.writingRate || state.rateFailed || state.rateAttempts >= maximumRateAttempts) return;
        if (typeof video.duration !== 'number' || !isFinite(video.duration) || video.duration <= 0) return;
        if (Math.abs(video.playbackRate - (state.acceptedRate || rate)) < 0.001) return;
        manuallyAccelerated.forEach(function (existing) {
            if (existing.isConnected === false) restoreManualRate(existing);
        });
        if (!manuallyAccelerated.has(video) && manuallyAccelerated.size >= maximumVideos) return;
        state.rateAttempts += 1;
        if (!writeSupportedRate(video, state)) state.rateFailed = true;
    }

    function restoreManualRate(video) {
        var state = states.get(video);
        if (!state || typeof state.manualRate !== 'number') return;
        manuallyAccelerated.delete(video);
        // Leave completion observers an unchanged ended element. Reset on reload/replay.
        if (video.ended) {
            state.manualEnded = true;
            return;
        }
        try {
            if (video.playbackRate === state.manualRate) video.playbackRate = state.originalRate;
        } catch (error) {
            stats.rateFailures += 1;
        }
        delete state.manualRate;
        delete state.originalRate;
        delete state.manualEnded;
    }

    function releaseAnimation(animation) {
        var lease = animationLeases.get(animation);
        animationLeases.delete(animation);
        if (!lease) return;
        try {
            if (animation.playbackRate === lease.appliedRate) animation.playbackRate = lease.originalRate;
        } catch (error) {
            stats.animationFailures += 1;
        }
    }

    function restoreAnimations() {
        animationLeases.forEach(function (lease, animation) { releaseAnimation(animation); });
    }

    function updateAnimations(active) {
        if (!active || !accelerateClock || typeof document.getAnimations !== 'function') {
            restoreAnimations();
            return;
        }
        var current = new Set();
        try {
            var animations = document.getAnimations();
            for (var index = 0; index < Math.min(animations.length, 64); index += 1) {
                var animation = animations[index];
                var target = animation.effect && animation.effect.target;
                if (!target || animation.playState !== 'running'
                    || (!broadPlaybackActive() && (!visible(target) || !exposed(target)))) continue;
                current.add(animation);
                var lease = animationLeases.get(animation);
                var base = animation.playbackRate;
                if (lease && base === lease.appliedRate) continue;
                if (typeof base !== 'number' || !isFinite(base) || base <= 0) {
                    releaseAnimation(animation);
                    continue;
                }
                var attempts = animationStates.get(animation) || 0;
                if (attempts >= maximumRateAttempts) {
                    releaseAnimation(animation);
                    continue;
                }
                animationStates.set(animation, attempts + 1);
                var applied = base * rate;
                if (!isFinite(applied)) {
                    releaseAnimation(animation);
                    continue;
                }
                try {
                    animation.playbackRate = applied;
                    if (animation.playbackRate !== applied) throw new Error('Animation rate was not accepted');
                    animationLeases.set(animation, {originalRate: base, appliedRate: applied});
                } catch (error) {
                    stats.animationFailures += 1;
                    releaseAnimation(animation);
                }
            }
        } catch (error) {
            stats.animationFailures += 1;
        }
        animationLeases.forEach(function (lease, animation) {
            if (!current.has(animation)) releaseAnimation(animation);
        });
    }

    function manualEligible(video) {
        return playing(video) && !video.loop && typeof video.duration === 'number'
            && isFinite(video.duration) && video.duration > 0
            && typeof video.currentTime === 'number' && isFinite(video.currentTime)
            && typeof video.playbackRate === 'number' && isFinite(video.playbackRate)
            && video.playbackRate > 0;
    }

    function manualAction(video) {
        var state = mediaState(video);
        if (!manualEligible(video) || state.manualAttempts >= 3) return false;
        if (video.playbackRate >= rate) {
            authorizeTiming();
            return true;
        }
        manuallyAccelerated.forEach(function (existing) {
            if (existing.isConnected === false) restoreManualRate(existing);
        });
        if (!manuallyAccelerated.has(video) && manuallyAccelerated.size >= maximumVideos) return false;
        state.manualAttempts += 1;
        stats.manualRequests += 1;
        if (!writeSupportedRate(video, state)) return false;
        authorizeTiming();
        return true;
    }

    function queueManualCleanup() {
        if (!manuallyAccelerated.size || manualCleanupHandle !== null || pageHidden()) return;
        manualCleanupHandle = nativeTimeout.call(window, function () {
            manualCleanupHandle = null;
            manuallyAccelerated.forEach(function (video) {
                try {
                    if (!visible(video) || !exposed(video)) restoreManualRate(video);
                } catch (error) {
                    stats.mediaFailures += 1;
                }
            });
        }, 250);
    }

    function scan() {
        if (refreshing || pageHidden()) {
            if (pageHidden()) {
                changeMode(false);
            }
            return 0;
        }
        refreshing = true;

        try {
            if (!automatic && manualTimingOnly && manualTimingSnapshot && !unchanged(manualTimingSnapshot)) {
                revokeManualContext();
            }
            var videos = typeof document.getElementsByTagName === 'function'
                ? document.getElementsByTagName('video')
                : [];
            var count = Math.min(videos.length, maximumVideos);
            stats.scans += 1;
            for (var index = 0; index < count; index += 1) {
                var video = videos[index];
                try {
                    if (broadPlaybackActive()
                        ? !video || video.paused || video.ended || video.seeking || video.readyState < 2
                        : !playing(video) || !exposed(video)) {
                        continue;
                    }
                    var state = mediaState(video);
                    if (accelerationActive() && (automatic || (!manualTimingOnly && manuallyAccelerated.has(video))) && forceInline) {
                        if (!video.hasAttribute('playsinline')) {
                            video.setAttribute('playsinline', '');
                        }
                        if (!video.hasAttribute('webkit-playsinline')) {
                            video.setAttribute('webkit-playsinline', '');
                        }
                        video.playsInline = true;
                    }
                    if (accelerationActive() && (automatic || (!manualTimingOnly && manuallyAccelerated.has(video)))) applyRate(video, state);
                } catch (error) {
                    stats.mediaFailures += 1;
                }
            }
            changeMode(accelerationActive());
            updateAnimations(accelerationActive());
        } finally {
            refreshing = false;
        }
    }

    function refresh() {
        if (contextPolicy === null) changeAdContext(recognizedMraid());
        if (speedVideo || compressTimers || accelerateClock || autoComplete) scan();
        if (recognizedAd) interact();
        syncFrames();
    }

    function schedulePoll() {
        if (pollHandle !== null || pageHidden() || typeof nativeTimeout !== 'function'
            || !((recognizedAd || contextPolicy === null || broadPlaybackActive()) && (speedVideo || compressTimers || accelerateClock || autoComplete))) {
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
            manualContext = false;
            manualTimingOnly = false;
            manualTimingSnapshot = null;
            contextGeneration += 1;
            if (cancelInteraction) cancelInteraction();
            manuallyAccelerated.forEach(restoreManualRate);
            restoreAnimations();
            if (manualCleanupHandle !== null) {
                nativeClearTimeout.call(window, manualCleanupHandle);
                manualCleanupHandle = null;
            }
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
        try {
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
            timerHooks += 1;
        } catch (error) {
            stats.timerFailures += 1;
        }
    }
    if (compressTimers && typeof nativeInterval === 'function') {
        try {
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
            timerHooks += 1;
        } catch (error) {
            stats.timerFailures += 1;
        }
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
            clockHooks += 1;
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
                clockHooks += 1;
            } catch (error) {
                stats.clockFailures += 1;
            }
        }
    }


    var frameContexts = new WeakMap();
    var interacted = new WeakMap();
    var interactionCount = 0;
    var interactionBusy = false;
    var cancelInteraction = null;
    var gestureSequence = 0;
    var contextGeneration = 0;
    var wrappedMraid = new WeakSet();

    function syncFrames() {
        if (typeof skipChannel !== 'string' || !skipChannel.length) return;
        var nodes = document.querySelectorAll('iframe,frame');
        for (var index = 0; index < Math.min(nodes.length, 64); index += 1) {
            var node = nodes[index];
            var child = node.contentWindow;
            var visibleFrame = !pageHidden() && visible(node) && exposed(node);
            var active = visibleFrame && recognizedAd ? true
                : visibleFrame && contextPolicy === null ? null : false;
            if (!child || frameContexts.get(child) === active) continue;
            try {
                child.postMessage({adSpeedContext: skipChannel, active: active}, '*');
                frameContexts.set(child, active);
            } catch (error) {
                stats.mediaFailures += 1;
            }
        }
    }

    function changeAdContext(active) {
        if (recognizedAd !== active) {
            if (cancelInteraction) cancelInteraction();
            recognizedAd = active;
            manualContext = false;
            manualTimingOnly = false;
            manualTimingSnapshot = null;
            contextGeneration += 1;
            interacted = new WeakMap();
            interactionCount = 0;
            interactionBusy = false;
            if (!active) {
                manuallyAccelerated.forEach(restoreManualRate);
                restoreAnimations();
                if (pollHandle !== null) nativeClearTimeout.call(window, pollHandle);
                pollHandle = null;
            }
        }
    }

    function setAdContext(active) {
        if (active !== null && typeof active !== 'boolean') return false;
        contextPolicy = active;
        changeAdContext(active === null ? recognizedMraid() : active);
        refresh();
        schedulePoll();
        return true;
    }

    function appStoreURL(value) {
        if (typeof value !== 'string') return false;
        var url = value.trim();
        return /^(?:itms|itmss|itms-apps|itms-appss|itms-services):/i.test(url)
            || /^https?:\/\/(?:apps|itunes)\.apple\.com\.?(?::[0-9]+)?(?:[\/?#]|$)/i.test(url);
    }

    function blockRedirect(url) {
        if (!recognizedAd || (!preventRedirects && !(hideAppStore && appStoreURL(url)))) return false;
        stats.redirectsBlocked += 1;
        return true;
    }

    if (typeof document.addEventListener === 'function') {
        document.addEventListener('click', function (event) {
            var node = event.target;
            for (var depth = 0; node && depth < 16; depth += 1, node = node.parentElement) {
                if (String(node.tagName).toLowerCase() !== 'a') continue;
                var url = typeof node.getAttribute === 'function' ? node.getAttribute('href') : null;
                if (hideAppStore && appStoreURL(url) && blockRedirect(url) && typeof event.preventDefault === 'function') {
                    event.preventDefault();
                }
                return;
            }
        }, true);
    }

    if (typeof window.open === 'function') {
        var nativeOpen = window.open;
        try {
            window.open = function () {
                if (blockRedirect(arguments[0])) return null;
                return nativeOpen.apply(this, arguments);
            };
        } catch (error) {
            stats.interactionFailures += 1;
        }
    }

    function readyMraid() {
        var mraid = window.mraid;
        if (!mraid || typeof mraid.getState !== 'function' || typeof mraid.isViewable !== 'function') return false;
        try {
            if (recognizedAd && (preventRedirects || hideAppStore) && !wrappedMraid.has(mraid) && typeof mraid.open === 'function') {
                var originalOpen = mraid.open;
                var guardedOpen = function () {
                    if (blockRedirect(arguments[0])) return;
                    return originalOpen.apply(this, arguments);
                };
                try {
                    mraid.open = guardedOpen;
                    if (mraid.open === guardedOpen) wrappedMraid.add(mraid);
                } catch (error) {
                    stats.interactionFailures += 1;
                }
            }
            var state = mraid.getState();
            return (state === 'default' || state === 'expanded' || state === 'resized')
                && mraid.isViewable() === true;
        } catch (error) {
            return false;
        }
    }

    function recognizedMraid() {
        try {
            return readyMraid() && typeof window.mraid.getPlacementType === 'function'
                && window.mraid.getPlacementType() === 'interstitial';
        } catch (error) {
            return false;
        }
    }

    function interactionReady() {
        if (window.mraid != null) return readyMraid();
        return contextPolicy === true && recognizedAd && !pageHidden()
            && document.readyState !== 'loading';
    }

    function controlAction(node) {
        if (!node || node.disabled || (node.getAttribute && node.getAttribute('aria-disabled') === 'true')) return null;
        var parent = node;
        for (var depth = 0; parent && depth < 16; depth += 1) {
            if (String(parent.tagName).toLowerCase() === 'a') return null;
            parent = parent.parentElement;
        }
        var label = String(node.getAttribute && node.getAttribute('aria-label') || node.textContent || '')
            .trim().toLowerCase().replace(/\s+/g, ' ');
        if (label === 'tap to play' || label === 'start game' || label === 'continue playing') return 'tap';
        return /^swipe (left|right|up|down)$/.test(label) ? label.slice(6) : null;
    }

    function dispatchInput(node, type, x, y, down, gesture) {
        var options = {bubbles: true, cancelable: true, clientX: x, clientY: y,
            button: 0, buttons: down ? 1 : 0, pointerId: gesture, pointerType: 'touch', isPrimary: true};
        var pointer = typeof window.PointerEvent === 'function';
        if (pointer) {
            node.dispatchEvent(new window.PointerEvent(type, options));
        }
        if (typeof window.Touch === 'function' && typeof window.TouchEvent === 'function') {
            var touch = new window.Touch({identifier: gesture, target: node, clientX: x, clientY: y,
                pageX: x, pageY: y, screenX: x, screenY: y});
            var touchType = {pointerdown: 'touchstart', pointermove: 'touchmove',
                pointerup: 'touchend', pointercancel: 'touchcancel'}[type];
            node.dispatchEvent(new window.TouchEvent(touchType, {bubbles: true, cancelable: true,
                touches: down ? [touch] : [], targetTouches: down ? [touch] : [], changedTouches: [touch]}));
            return;
        }
        if (!pointer && typeof window.MouseEvent === 'function') {
            var mouseType = {pointerdown: 'mousedown', pointermove: 'mousemove',
                pointerup: 'mouseup', pointercancel: 'mouseleave'}[type];
            node.dispatchEvent(new window.MouseEvent(mouseType, options));
        }
    }

    function performInteraction(node, action) {
        var rect = node.getBoundingClientRect();
        var startX = rect.left + rect.width / 2;
        var startY = rect.top + rect.height / 2;
        var deltaX = action === 'left' ? -rect.width / 3 : action === 'right' ? rect.width / 3 : 0;
        var deltaY = action === 'up' ? -rect.height / 3 : action === 'down' ? rect.height / 3 : 0;
        var started = contextGeneration;
        var gesture = ++gestureSequence;
        var canceled = false;
        var step = 0;
        interactionBusy = true;
        function cancel() {
            canceled = true;
            try {
                dispatchInput(node, 'pointercancel', startX, startY, false, gesture);
            } catch (error) {
                stats.interactionFailures += 1;
            }
            if (cancelInteraction === cancel) {
                cancelInteraction = null;
                interactionBusy = false;
            }
        }
        cancelInteraction = cancel;
        dispatchInput(node, 'pointerdown', startX, startY, true, gesture);
        function finish() {
            try {
                if (canceled) return;
                if (started !== contextGeneration || !recognizedAd || pageHidden() || !visible(node)
                    || !exposed(node) || !interactionReady()) {
                    cancel();
                    return;
                }
                step += 1;
                if (action !== 'tap' && step <= 6) {
                    dispatchInput(node, 'pointermove', startX + deltaX * step / 6,
                        startY + deltaY * step / 6, true, gesture);
                    nativeTimeout.call(window, finish, 16);
                    return;
                }
                dispatchInput(node, 'pointerup', startX + deltaX, startY + deltaY, false, gesture);
                if (action === 'tap' && typeof window.MouseEvent === 'function') {
                    node.dispatchEvent(new window.MouseEvent('click', {bubbles: true, cancelable: true,
                        clientX: startX, clientY: startY, button: 0, detail: 1}));
                }
                if (cancelInteraction === cancel) {
                    cancelInteraction = null;
                    interactionBusy = false;
                }
                stats.interactions += 1;
            } catch (error) {
                cancel();
                stats.interactionFailures += 1;
            }
        }
        nativeTimeout.call(window, finish, 16);
    }

    function interact() {
        readyMraid();
        if (!automatic || !autoComplete || !recognizedAd || pageHidden() || interactionBusy || interactionCount >= 12 || !interactionReady()) return;
        var controls = document.querySelectorAll('button,[role="button"],[aria-label]');
        for (var index = 0; index < Math.min(controls.length, 128); index += 1) {
            var node = controls[index];
            var action = controlAction(node);
            if (!action || interacted.get(node) === action || !visible(node) || !exposed(node)) continue;
            interacted.set(node, action);
            interactionCount += 1;
            try {
                performInteraction(node, action);
            } catch (error) {
                interactionBusy = false;
                stats.interactionFailures += 1;
            }
            break;
        }
    }

    if (accelerateClock && typeof window.requestAnimationFrame === 'function' && performanceClock) {
        var nativeAnimationFrame = window.requestAnimationFrame;
        try {
            window.requestAnimationFrame = function (callback) {
                if (typeof callback !== 'function') return nativeAnimationFrame.apply(this, arguments);
                return nativeAnimationFrame.call(this, function () {
                    if (pageHidden()) changeMode(false);
                    callback.call(window, advance(performanceClock));
                });
            };
        } catch (error) {
            stats.clockFailures += 1;
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

    function countdownSurface() {
        var nodes = document.querySelectorAll('div[id],span[id],div[class],span[class]');
        for (var index = 0; index < Math.min(nodes.length, 128); index += 1) {
            var node = nodes[index];
            var marker = String(node.id || '') + ' ' + String(node.className || '');
            marker = marker.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase();
            if (!/(?:^|[\s_-])(?:countdown|count-down|timer)(?:$|[\s_-])/.test(marker)) continue;
            var label = String(node.textContent || '').trim();
            if (!/^(?:(?:skip|close|reward|continue)(?:\s+ad)?\s+in\s+)?\d{1,3}(?:\s*(?:s|secs?|seconds?))?$/i.test(label)) continue;
            var interactive = false;
            for (var parent = node, depth = 0; parent && depth < 16; parent = parent.parentElement, depth += 1) {
                var tag = String(parent.tagName).toLowerCase();
                var role = parent.getAttribute && parent.getAttribute('role');
                if (tag === 'button' || tag === 'a' || role === 'button' || role === 'link') {
                    interactive = true;
                    break;
                }
            }
            if (!interactive && !parent && visible(node) && exposed(node)) return node;
        }
        return null;
    }

    function playableSurface() {
        var nodes = document.querySelectorAll('canvas,[role="timer"],time');
        for (var index = 0; index < Math.min(nodes.length, 64); index += 1) {
            if (visible(nodes[index]) && exposed(nodes[index])) return nodes[index];
        }
        var controls = document.querySelectorAll('button,[role="button"],[aria-label]');
        for (var controlIndex = 0; controlIndex < Math.min(controls.length, 128); controlIndex += 1) {
            var node = controls[controlIndex];
            if (controlAction(node) && visible(node) && exposed(node)) return node;
        }
        if (accelerateClock && typeof document.getAnimations === 'function') {
            try {
                var animations = document.getAnimations();
                for (var animationIndex = 0; animationIndex < Math.min(animations.length, 64); animationIndex += 1) {
                    var animation = animations[animationIndex];
                    var target = animation.effect && animation.effect.target;
                    if (target && animation.playState === 'running' && visible(target) && exposed(target)) return target;
                }
            } catch (error) {
                stats.animationFailures += 1;
            }
        }
        return countdownSurface();
    }

    function capture() {
        var frames = frameCandidates();
        var snapshot = {generation: generation, context: contextGeneration, videos: [], children: frames.children,
            unresolved: frames.unresolved, blockedMedia: false, candidates: []};
        snapshot.timingNode = recognizedAd && !pageHidden() && timingAvailable()
            && document.readyState !== 'loading' && (contextPolicy === true || recognizedMraid())
            ? playableSurface() : null;
        snapshot.timing = snapshot.timingNode !== null;
        if (pageHidden()) snapshot.unresolved = 1;
        try {
            var videos = document.getElementsByTagName('video');
            var count = Math.min(videos.length, maximumVideos);
            if (videos.length > count) snapshot.unresolved = 1;
            for (var index = 0; index < count; index += 1) {
                var video = videos[index];
                if (!visible(video)) continue;
                var mediaExposed = exposed(video);
                var source = String(video.currentSrc || video.src || '');
                snapshot.videos.push({node: video, source: source, paused: !!video.paused,
                    ended: !!video.ended, loop: !!video.loop, exposed: mediaExposed,
                    seeking: !!video.seeking, ready: video.readyState, duration: video.duration});
                if (video.ended) {
                    snapshot.blockedMedia = true;
                    continue;
                }
                if (!mediaExposed || !manualEligible(video) || mediaState(video).manualAttempts >= 3) {
                    snapshot.blockedMedia = true;
                    if (!snapshot.timing) snapshot.unresolved = 1;
                } else snapshot.candidates.push(video);
            }
        } catch (error) {
            snapshot.unresolved = 1;
        }
        return snapshot;
    }

    function unchanged(snapshot) {
        if (pageHidden() || generation !== snapshot.generation || contextGeneration !== snapshot.context) return false;
        var current = capture();
        if (current.unresolved !== snapshot.unresolved || current.videos.length !== snapshot.videos.length
            || current.children.length !== snapshot.children.length || current.timing !== snapshot.timing
            || current.timingNode !== snapshot.timingNode
            || current.blockedMedia !== snapshot.blockedMedia) return false;
        for (var index = 0; index < snapshot.videos.length; index += 1) {
            var before = snapshot.videos[index];
            var after = current.videos[index];
            if (before.node !== after.node || before.source !== after.source || before.paused !== after.paused
                || before.ended !== after.ended || before.loop !== after.loop || before.exposed !== after.exposed
                || before.seeking !== after.seeking || before.ready !== after.ready
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
            var timingOnly = snapshot.timing && snapshot.blockedMedia && snapshot.candidates.length <= 1;
            var count = timingOnly ? 0 : Math.min(2, snapshot.candidates.length);
            var unresolved = 0;
            var route = !timingOnly && snapshot.candidates.length === 1 ? {video: snapshot.candidates[0]} : null;
            results.forEach(function (result, index) {
                count = Math.min(2, count + result.count);
                if (result.unresolved) unresolved = 1;
                if (result.count === 1 && !result.unresolved) {
                    route = {child: snapshot.children[index], token: result.token};
                }
            });
            if (!count && !unresolved && snapshot.timing) {
                count = 1;
                route = {timing: true};
            }
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
            if (record.route.timing) {
                var timing = authorizeTiming(true, record.snapshot);
                if (timing) refresh();
                return {handled: timing ? 1 : 0, unresolved: timing ? 0 : 1, kind: 'timing'};
            }
            if (record.route.video) {
                var video = record.route.video;
                if (!manualEligible(video)) return {handled: 0, unresolved: 1};
                var handled = manualAction(video) ? 1 : 0;
                if (handled) refresh();
                return {handled: handled, unresolved: handled ? 0 : 1, kind: 'video'};
            }
            if (depth >= maximumFrameDepth) return {handled: 0, unresolved: 1};
            return query(record.route.child.source, 'act', record.route.token, depth).then(function (result) {
                if (!result.handled && !unchanged(record.snapshot)) return {handled: 0, unresolved: 1};
                if (result.handled) {
                    authorizeTiming(result.kind === 'timing', record.snapshot);
                    refresh();
                }
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
        if (snapshot.unresolved || snapshot.children.length) return 0;
        if (snapshot.timing && (snapshot.candidates.length === 0 || (snapshot.blockedMedia && snapshot.candidates.length === 1))) {
            var timing = authorizeTiming(true, snapshot);
            if (timing) refresh();
            return timing ? 1 : 0;
        }
        if (snapshot.candidates.length !== 1) return 0;
        var video = snapshot.candidates[0];
        var handled = manualAction(video);
        if (handled) refresh();
        return handled ? 1 : 0;
    }

    var completedCloseNodes = new WeakMap();
    var closeSnapshot = null;
    var closeRequests = 0;
    var closeSequence = 0;

    function closeRole(node, adapter) {
        if (adapter === 'mintegral') return String(node.getAttribute && node.getAttribute('id') || '');
        if (adapter === 'google' && String(node.tagName).toLowerCase() === 'div') {
            var roles = String(node.getAttribute('class') || '').split(/\s+/).filter(function (value) {
                return value === 'simidCloseButtonButton' || value === 'simidRewardGrantedCloseButton';
            });
            if (roles.length === 1) return roles[0];
        }
        return String(node.getAttribute && node.getAttribute('aria-label') || node.textContent || '')
            .trim().toLowerCase().replace(/\s+/g, ' ');
    }

    function closeControl(node, adapter) {
        if (!node || node.disabled || (node.getAttribute && node.getAttribute('aria-disabled') === 'true')) return false;
        for (var parent = node, depth = 0; parent && depth < 16; parent = parent.parentElement, depth += 1) {
            if (String(parent.tagName).toLowerCase() === 'a') return false;
        }
        var label = closeRole(node, adapter);
        if (adapter === 'mintegral') {
            if (String(node.tagName).toLowerCase() !== 'div' ||
                (label !== 'm-playable-skip' && label !== 'm-playable-close')) return false;
            var classes = String(node.getAttribute('class') || '').split(/\s+/);
            if (classes.indexOf(label) < 0) return false;
            var bounds = node.getBoundingClientRect();
            if (bounds.width < 16 || bounds.height < 16 || bounds.width > 96 || bounds.height > 96 ||
                bounds.top + bounds.height / 2 > window.innerHeight * 0.25 ||
                (bounds.left + bounds.width / 2 > window.innerWidth * 0.25 &&
                 bounds.left + bounds.width / 2 < window.innerWidth * 0.75)) return false;
            if (window.getComputedStyle(node).pointerEvents === 'none') return false;
            return visible(node) && exposed(node, false);
        }
        if (adapter === 'google' && /^(?:simidCloseButtonButton|simidRewardGrantedCloseButton)$/.test(label)) {
            var box = node.getBoundingClientRect();
            if (box.width < 16 || box.height < 16 || box.width > 96 || box.height > 96 ||
                box.top + box.height / 2 > window.innerHeight * 0.25 ||
                (box.left + box.width / 2 > window.innerWidth * 0.25 &&
                 box.left + box.width / 2 < window.innerWidth * 0.75)) return false;
            return window.getComputedStyle(node).pointerEvents !== 'none' && visible(node) && exposed(node, false);
        }
        if (!/^(?:close(?: ad)?|dismiss(?: ad)?|x|×|✕|✖|fermer|cerrar|schließen|fechar|chiudi|閉じる|닫기|关闭|關閉)$/.test(label)) return false;
        if (/^(?:x|×|✕|✖)$/.test(label)) {
            var rect = node.getBoundingClientRect();
            if (rect.top + rect.height / 2 > window.innerHeight * 0.25 ||
                (rect.left + rect.width / 2 > window.innerWidth * 0.25 &&
                 rect.left + rect.width / 2 < window.innerWidth * 0.75)) return false;
        }
        return visible(node) && exposed(node, false);
    }

    function inspectClose(adapter) {
        closeSnapshot = null;
        if (adapter && adapter !== 'unity' && adapter !== 'mintegral' && adapter !== 'google') return null;
        if (!automatic || !autoDismiss || !recognizedAd || pageHidden() || closeRequests >= 8) return null;
        var selector = 'button,[role="button"],[aria-label]';
        if (adapter === 'mintegral') selector = '[id="m-playable-skip"],[id="m-playable-close"]';
        if (adapter === 'google') selector += ',.simidCloseButtonButton,.simidRewardGrantedCloseButton';
        var nodes = document.querySelectorAll(selector);
        var selected = null;
        for (var index = 0; index < Math.min(nodes.length, 128); index += 1) {
            var node = nodes[index];
            var completed = completedCloseNodes.get(node);
            var previous = completed && completed.get(closeRole(node, adapter));
            if ((previous && (previous.attempts >= 5 || realNow() - previous.time < 750)) ||
                !closeControl(node, adapter)) continue;
            if (selected) return null;
            selected = node;
        }
        if (!selected) return null;
        var token = String(dateNow()) + ':' + String(++closeSequence);
        closeSnapshot = {node: selected, role: closeRole(selected, adapter), adapter: adapter, token: token,
            context: contextGeneration, expires: dateNow() + 2000};
        return token;
    }

    function closeCompletedAd(token) {
        var snapshot = closeSnapshot;
        closeSnapshot = null;
        if (!snapshot || snapshot.token !== token || snapshot.expires < dateNow() ||
            snapshot.context !== contextGeneration || !automatic || !autoDismiss || !recognizedAd ||
            pageHidden() || closeRequests >= 8 || !closeControl(snapshot.node, snapshot.adapter) ||
            snapshot.role !== closeRole(snapshot.node, snapshot.adapter)) return false;
        var completed = completedCloseNodes.get(snapshot.node);
        if (!completed) {
            completed = new Map();
            completedCloseNodes.set(snapshot.node, completed);
        }
        var previous = completed.get(snapshot.role);
        if (previous && (previous.attempts >= 5 || realNow() - previous.time < 750)) return false;
        completed.set(snapshot.role, {attempts: previous ? previous.attempts + 1 : 1, time: realNow()});
        closeRequests += 1;
        try {
            if (typeof snapshot.node.click === 'function') snapshot.node.click();
            else if (typeof window.MouseEvent === 'function') {
                snapshot.node.dispatchEvent(new window.MouseEvent('click', {bubbles: true, cancelable: true}));
            } else return false;
            return true;
        } catch (error) {
            stats.interactionFailures += 1;
            return false;
        }
    }

    var api = Object.freeze({
        version: 4,
        setAdContext: setAdContext,
        inspectClose: inspectClose,
        closeCompletedAd: closeCompletedAd,
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
                kind: result.kind,
                unresolved: result && result.unresolved, valid: result === true}, '*');
        } catch (error) {
            // The parent can disappear while discovery is pending.
        }
    }

    if (typeof window.addEventListener === 'function' && typeof skipChannel === 'string' && skipChannel.length) {
        window.addEventListener('message', function (event) {
            var data = event.data;
            if (data && data.adSpeedContextRequest === skipChannel) {
                var nodes = document.querySelectorAll('iframe,frame');
                for (var index = 0; index < Math.min(nodes.length, 64); index += 1) {
                    var frame = nodes[index];
                    if (frame.contentWindow !== event.source) continue;
                    frameContexts.delete(event.source);
                    syncFrames();
                    return;
                }
                return;
            }
            if (event.source === window.parent && event.source !== window && data
                && data.adSpeedContext === skipChannel && (data.active === null || typeof data.active === 'boolean')) {
                setAdContext(data.active);
                return;
            }
            if (!data) return;
            var record = pendingMessages.get(data.id);
            if (record && data.adSpeedReply === skipChannel && record.source === event.source
                && data.phase === record.phase) {
                var bounded = data.unresolved === 0 || data.unresolved === 1;
                var valid = record.phase === 'inspect'
                    ? bounded && (data.count === 0 || data.count === 1 || data.count === 2)
                        && (data.count > 1 || data.unresolved || validIdentifier(data.token))
                    : record.phase === 'validate' ? typeof data.valid === 'boolean'
                    : bounded && (data.handled === 0 || data.handled === 1)
                        && (data.kind === undefined || data.kind === 'timing' || data.kind === 'video');
                if (!valid) return;
                pendingMessages.delete(data.id);
                nativeClearTimeout.call(window, record.timer);
                record.resolve(record.phase === 'inspect'
                    ? {count: data.count, unresolved: data.unresolved, token: data.token}
                    : record.phase === 'validate' ? data.valid
                    : {handled: data.handled, unresolved: data.unresolved, kind: data.kind});
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
        if (window.parent !== window) {
            try {
                window.parent.postMessage({adSpeedContextRequest: skipChannel}, '*');
            } catch (error) {
                stats.mediaFailures += 1;
            }
        }
    }

    if (typeof document.addEventListener === 'function') {
        var mediaEvents = ['play', 'pause', 'ended', 'loadedmetadata', 'durationchange', 'ratechange', 'seeked'];
        for (var eventIndex = 0; eventIndex < mediaEvents.length; eventIndex += 1) {
            document.addEventListener(mediaEvents[eventIndex], refresh, true);
        }
        function sourceChanged(event) {
            generation += 1;
            if (!automatic) {
                revokeManualContext();
            }
            if (event.target && String(event.target.tagName).toLowerCase() === 'video') {
                restoreManualRate(event.target);
                states.delete(event.target);
            }
            refresh();
        }
        document.addEventListener('loadstart', sourceChanged, true);
        document.addEventListener('emptied', sourceChanged, true);
        document.addEventListener('ended', function (event) { restoreManualRate(event.target); }, true);
        document.addEventListener('pause', function (event) { restoreManualRate(event.target); }, true);
        document.addEventListener('play', function (event) {
            var state = states.get(event.target);
            if (state && state.manualEnded) restoreManualRate(event.target);
        }, true);
        document.addEventListener('visibilitychange', visibilityChanged, false);
    }
    if (typeof window.MutationObserver === 'function') {
        var observer = new window.MutationObserver(function () {
            refresh();
            queueManualCleanup();
        });
        var observed = {childList: true, subtree: true};
        observed.attributes = true;
        observed.attributeFilter = ['hidden', 'style', 'class', 'aria-label', 'disabled'];
        observer.observe(document, observed);
    }
    refresh();
    schedulePoll();
}());
