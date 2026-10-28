// AdVanish contributions: Copyright (C) 2026 maxblox2999.
// GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const os = require('node:os');
const root = __dirname;
const source = fs.readFileSync(path.join(root, '../../web/adspeed.js'), 'utf8');
const sourceSha256 = crypto.createHash('sha256').update(source).digest('hex');
const config = {
    rate: 16,
    recognizedAd: false,
    autoComplete: true,
    preventRedirects: true,
    speedVideo: true,
    compressTimers: true,
    accelerateClock: true,
    forceInline: false,
    skipChannel: 'browser-verification-session'
};
let portA;
let portB;
function html(child, playback, automatic) {
    return `<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#eee}video{display:block;width:320px;height:180px}iframe{width:360px;height:210px;border:0}</style><script>window.realNow=performance.now.bind(performance);window.realTimeout=setTimeout.bind(window);</script><script src="/engine.js?playback=${playback ? 1 : 0}&automatic=${automatic ? 1 : 0}"></script><script>
    window.fixture = {messages:[],closes:0,errors:[]};
    window.addEventListener('error',e=>fixture.errors.push(String(e.message)));
    window.addEventListener('unhandledrejection',e=>fixture.errors.push(String(e.reason)));
    window.mraid={close(){fixture.closes++},getState(){return 'default'},getPlacementType(){return 'interstitial'},isViewable(){return true}};
    window.sleep=ms=>new Promise(r=>realTimeout(r,ms));
    window.until=async (fn,label,ms=6000)=>{const end=realNow()+ms;while(realNow()<end){if(fn())return;await sleep(20)}throw Error('Timeout: '+label)};
    window.addVideo=async (loop=false)=>{const v=document.createElement('video');v.muted=true;v.playsInline=true;v.loop=loop;v.src='/fixture.mp4?n='+Math.random();v.preload='auto';v.dataset.seeks='0';v.addEventListener('seeking',()=>{v.dataset.seeks=String(Number(v.dataset.seeks)+1);if(parent!==window)report('seeking')});v.addEventListener('ended',()=>{if(parent!==window)report('ended')});document.body.append(v);await v.play();await until(()=>v.readyState>=3&&Number.isFinite(v.duration)&&v.seekable.length&&!v.paused&&!v.seeking&&v.currentTime>0.1,'video ready');return v};
    window.state=()=>({closes:fixture.closes,virtual:performance.now(),real:realNow(),timerDone:!!fixture.timerDone,videos:Array.from(document.querySelectorAll('video')).map(v=>({ended:v.ended,seeks:Number(v.dataset.seeks),current:v.currentTime,duration:v.duration,loop:v.loop,paused:v.paused,rate:v.playbackRate})),errors:fixture.errors});
    window.report=phase=>parent.postMessage({fixtureReport:true,phase,state:state()},'*');
    window.addEventListener('message',async e=>{
        if(e.data&&e.data.fixtureReport)fixture.messages.push({source:e.source,phase:e.data.phase,state:e.data.state});
        if(e.data&&e.data.fixtureCommand==='add-video'){await addVideo();report('added')}
        if(e.data&&e.data.fixtureCommand==='state')report('state');
        if(e.data&&e.data.fixtureCommand==='sample')report(e.data.id);
        if(e.data&&e.data.fixtureCommand==='playable'){
            delete window.mraid;
            const canvas=document.createElement('canvas');canvas.width=320;canvas.height=180;document.body.append(canvas);
            setTimeout(()=>{fixture.timerDone=true;report('playable-timer')},1600);
            report('playable-ready');
        }
    });
    window.addFrame=async video=>{const frame=document.createElement('iframe');frame.src='http://127.0.0.1:${portB}/child?video='+(video?'1':'0')+'&playback=${playback ? 1 : 0}&automatic=${automatic ? 1 : 0}';document.body.append(frame);await until(()=>fixture.messages.some(m=>m.source===frame.contentWindow&&m.phase==='ready'),'frame ready');return frame};
    ${child ? `window.addEventListener('DOMContentLoaded',async()=>{try{if(new URL(location.href).searchParams.get('video')==='1')await addVideo();report('ready')}catch(e){fixture.errors.push(String(e));report('error')}});` : ''}
    </script><body></body>`;
}
function serve(req, res) {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname === '/engine.js') {
        const script = source.replace('__ADSPEED_CONFIG__', JSON.stringify({
            ...config, automatic: url.searchParams.get('automatic') !== '0'
        }));
        res.writeHead(200, { 'Content-Type': 'text/javascript' });
        res.end(script);
        return;
    }
    if (url.pathname === '/fixture.mp4') {
        const data = fs.readFileSync(path.join(root, '../ios/fixture.mp4'));
        let start = 0;
        let end = data.length - 1;
        const range = /bytes=(\d+)-(\d*)/.exec(req.headers.range || '');
        if (range) {
            start = Number(range[1]);
            if (range[2]) end = Math.min(end, Number(range[2]));
            res.writeHead(206, {
                'Content-Type': 'video/mp4',
                'Accept-Ranges': 'bytes',
                'Content-Range': `bytes ${start}-${end}/${data.length}`,
                'Content-Length': end - start + 1
            });
        } else
            res.writeHead(200, {
                'Content-Type': 'video/mp4',
                'Accept-Ranges': 'bytes',
                'Content-Length': data.length
            });
        res.end(data.subarray(start, end + 1));
        return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(html(url.pathname === '/child', url.searchParams.get('playback') === '1', url.searchParams.get('automatic') !== '0'));
}
const serverA = http.createServer(serve);
const serverB = http.createServer(serve);
let browser;
let profile;
let socket;
let next = 1;
const pending = new Map();
function command(method, params = {}, sessionId) {
    return new Promise((resolve, reject) => {
        const id = next++;
        const timer = setTimeout(() => {
            pending.delete(id);
            reject(Error('CDP timeout ' + method));
        }, 20000);
        pending.set(id, { resolve, reject, timer });
        socket.send(JSON.stringify({ id, method, params, sessionId }));
    });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function evaluate(sessionId, expression) {
    const r = await command(
        'Runtime.evaluate',
        { expression, awaitPromise: true, returnByValue: true },
        sessionId
    );
    if (r.exceptionDetails) throw Error(JSON.stringify(r.exceptionDetails));
    return r.result.value;
}
async function runCase(name, body, verify, playback = false, automatic = true) {
    const { targetId } = await command('Target.createTarget', {
        url: `http://127.0.0.1:${portA}/?case=${name}&playback=${playback ? 1 : 0}&automatic=${automatic ? 1 : 0}`
    });
    const { sessionId } = await command('Target.attachToTarget', { targetId, flatten: true });
    try {
        await command('Target.activateTarget', { targetId });
        await command('Emulation.setFocusEmulationEnabled', { enabled: true }, sessionId);
        await command('Runtime.enable', {}, sessionId);
        for (let i = 0; i < 100; i++) {
            if (await evaluate(sessionId, '!!(window.fixture&&document.body&&window.__adspeed)')) break;
            await sleep(30);
        }
        const value = await evaluate(sessionId, `(async()=>{${body}})()`);
        verify(value);
        console.log(JSON.stringify({ case: name, passed: true, ...value }));
        return { case: name, passed: true, ...value };
    } finally {
        await command('Target.closeTarget', { targetId });
    }
}
async function main() {
    const output = path.join(root, '../../dist/browser.json');
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.rmSync(output, { force: true });
    const executable =
        process.env.BROWSER_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
    if (!fs.existsSync(executable)) {
        throw new Error('Set BROWSER_PATH to an installed Chromium browser executable');
    }
    await new Promise((r) => serverA.listen(0, '127.0.0.1', r));
    portA = serverA.address().port;
    await new Promise((r) => serverB.listen(0, '127.0.0.1', r));
    portB = serverB.address().port;
    profile = fs.mkdtempSync(path.join(os.tmpdir(), 'advanish-browser-'));
    browser = spawn(
        executable,
        [
            '--headless=new',
            '--disable-gpu',
            '--no-first-run',
            '--no-default-browser-check',
            '--autoplay-policy=no-user-gesture-required',
            '--remote-debugging-port=0',
            '--user-data-dir=' + profile,
            'about:blank'
        ],
        { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] }
    );
    let stderr = '';
    browser.stderr.on('data', (d) => (stderr += d));
    const portFile = path.join(profile, 'DevToolsActivePort');
    for (let i = 0; i < 200 && !fs.existsSync(portFile); i++) {
        if (browser.exitCode !== null) throw Error('Browser exited ' + browser.exitCode + ' ' + stderr);
        await sleep(50);
    }
    const [port, endpoint] = fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/);
    socket = new WebSocket('ws://127.0.0.1:' + port + endpoint);
    await new Promise((r, j) => {
        socket.onopen = r;
        socket.onerror = j;
    });
    socket.onmessage = (e) => {
        const d = JSON.parse(e.data);
        const p = pending.get(d.id);
        if (!p) return;
        pending.delete(d.id);
        clearTimeout(p.timer);
        if (d.error) p.reject(Error(JSON.stringify(d.error)));
        else p.resolve(d.result);
    };
    const version = await command('Browser.getVersion');
    const cases = [];
    cases.push(
        await runCase(
            'single-video-natural-ended',
            `const v=await addVideo();const before=v.currentTime;const inspection=await __adspeed.inspectAsync();const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);await until(()=>v.ended,'natural ended',3000);const repeat=await __adspeed.skipAsync();return {before,inspection,valid,action,repeat,...state()};`,
            (r) => {
                assert.equal(r.inspection.count, 1);
                assert.equal(r.valid, true);
                assert.equal(r.action.handled, 1);
                assert.equal(r.videos[0].ended, true);
                assert.equal(r.videos[0].seeks, 0);
                assert.equal(r.closes, 0);
                assert.equal(r.repeat.handled, 0);
                assert.deepEqual(r.errors, []);
            }
        )
    );
    cases.push(
        await runCase(
            'two-local-videos-abstain',
            `await addVideo();await addVideo();const inspection=await __adspeed.inspectAsync();const action=await __adspeed.skipAsync();return {inspection,action,...state()};`,
            (r) => {
                assert.equal(r.inspection.count, 2);
                assert.equal(r.action.handled, 0);
                assert.equal(r.action.unresolved, 1);
                assert.equal(
                    r.videos.reduce((n, v) => n + v.seeks, 0),
                    0
                );
                assert.equal(r.closes, 0);
            }
        )
    );
    cases.push(
        await runCase(
            'cross-origin-child-speed-ended',
            `const f=await addFrame(true);const inspection=await __adspeed.inspectAsync();const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='ended'),'child ended',3000);return {inspection,valid,action,child:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,...state()};`,
            (r) => {
                assert.equal(r.inspection.count, 1);
                assert.equal(r.valid, true);
                assert.equal(r.action.handled, 1);
                assert.equal(r.child.videos[0].ended, true);
                assert.equal(r.child.videos[0].seeks, 0);
                assert.equal(r.child.closes, 0);
                assert.equal(r.closes, 0);
            }
        )
    );
    cases.push(
        await runCase(
            'sibling-frame-single-action',
            `const f=await addFrame(true);const empty=await addFrame(false);const inspection=await __adspeed.inspectAsync();const action=await __adspeed.skipAsync(inspection.token);await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='ended'),'child ended',3000);empty.contentWindow.postMessage({fixtureCommand:'state'},'*');await until(()=>fixture.messages.some(m=>m.source===empty.contentWindow&&m.phase==='state'),'empty state');return {inspection,action,videoChild:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,emptyChild:fixture.messages.filter(m=>m.source===empty.contentWindow).at(-1).state,...state()};`,
            (r) => {
                assert.equal(r.inspection.count, 1);
                assert.equal(r.action.handled, 1);
                assert.equal(r.videoChild.videos[0].seeks, 0);
                assert.equal(r.emptyChild.closes, 0);
                assert.equal(r.closes, 0);
            }
        )
    );
    cases.push(
        await runCase(
            'root-and-frame-ambiguous',
            `await addVideo();const f=await addFrame(true);const inspection=await __adspeed.inspectAsync();const action=await __adspeed.skipAsync();f.contentWindow.postMessage({fixtureCommand:'state'},'*');await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='state'),'child state');return {inspection,action,child:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,...state()};`,
            (r) => {
                assert.equal(r.inspection.count, 2);
                assert.equal(r.action.handled, 0);
                assert.equal(r.videos[0].seeks, 0);
                assert.equal(r.child.videos[0].seeks, 0);
                assert.equal(r.closes, 0);
            }
        )
    );
    cases.push(
        await runCase(
            'empty-snapshot-stale-on-new-video',
            `const inspection=await __adspeed.inspectAsync();await addVideo();const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);return {inspection,valid,action,...state()};`,
            (r) => {
                assert.equal(r.inspection.count, 0);
                assert.equal(r.valid, false);
                assert.equal(r.action.handled, 0);
                assert.equal(r.videos[0].seeks, 0);
                assert.equal(r.closes, 0);
            }
        )
    );
    cases.push(
        await runCase(
            'single-use-token',
            `const v=await addVideo();const inspection=await __adspeed.inspectAsync();const actions=await Promise.all([__adspeed.skipAsync(inspection.token),__adspeed.skipAsync(inspection.token)]);await until(()=>v.ended,'natural ended',3000);return {inspection,actions,...state()};`,
            (r) => {
                assert.equal(
                    r.actions.reduce((n, a) => n + a.handled, 0),
                    1
                );
                assert.equal(r.videos[0].seeks, 0);
                assert.equal(r.closes, 0);
            }
        )
    );
    cases.push(
        await runCase(
            'child-empty-snapshot-invalidates-new-child-media',
            `const f=await addFrame(false);const inspection=await __adspeed.inspectAsync();f.contentWindow.postMessage({fixtureCommand:'add-video'},'*');await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='added'),'child new video');const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);f.contentWindow.postMessage({fixtureCommand:'state'},'*');await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='state'),'child state');return {inspection,valid,action,child:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,...state()};`,
            (r) => {
                assert.equal(r.inspection.count, 0);
                assert.equal(r.valid, false);
                assert.equal(r.action.handled, 0);
                assert.equal(r.child.videos[0].seeks, 0);
                assert.equal(r.child.closes, 0);
            }
        )
    );
    cases.push(
        await runCase(
            'opaque-overlay-abstains',
            `
        const v = await addVideo();
        const overlay = document.createElement('div');
        overlay.style.cssText = 'position:fixed;inset:0;background:black;z-index:999';
        document.body.append(overlay);
        const inspection = await __adspeed.inspectAsync();
        const action = await __adspeed.skipAsync();
        return {inspection, action, ...state()};
    `,
            (result) => {
                assert.equal(result.inspection.unresolved, 1);
                assert.equal(result.action.handled, 0);
                assert.equal(result.videos[0].seeks, 0);
                assert.equal(result.closes, 0);
                assert.deepEqual(result.errors, []);
            }
        )
    );
    cases.push(
        await runCase(
            'covering-empty-iframe-abstains',
            `
        const v = await addVideo();
        const frame = await addFrame(false);
        frame.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;z-index:999;background:white';
        const inspection = await __adspeed.inspectAsync();
        const action = await __adspeed.skipAsync();
        return {inspection, action, ...state()};
    `,
            (result) => {
                assert.equal(result.inspection.unresolved, 1);
                assert.equal(result.action.handled, 0);
                assert.equal(result.videos[0].seeks, 0);
                assert.equal(result.closes, 0);
                assert.deepEqual(result.errors, []);
            }
        )
    );
    cases.push(
        await runCase(
            'production-manual-playback-without-seek',
            `
        const v = await addVideo();
        const before = v.currentTime;
        const action = await __adspeed.skipAsync();
        const requested = {rate: v.playbackRate, time: v.currentTime, before};
        await until(() => v.ended, 'normal playback ended', 8000).catch(error => {
            throw new Error(error.message + ': ' + JSON.stringify({requested, ...state(),
                hidden: document.hidden, stats: __adspeed.stats}));
        });
        return {action, requested, ...state()};
    `,
            (result) => {
                assert.equal(result.action.handled, 1);
                assert.equal(result.requested.rate, 16);
                assert.ok(result.requested.time < result.requested.before + 0.25);
                assert.equal(result.videos[0].seeks, 0);
                assert.equal(result.videos[0].ended, true);
                assert.equal(result.videos[0].rate, 16);
                assert.equal(result.closes, 0);
                assert.deepEqual(result.errors, []);
            },
            true
        )
    );
    cases.push(
        await runCase(
            'production-cross-origin-playback-without-seek',
            `
        const f = await addFrame(true);
        const action = await __adspeed.skipAsync();
        await until(() => fixture.messages.some(m => m.source === f.contentWindow && m.phase === 'ended'),
            'child natural completion', 8000);
        f.contentWindow.postMessage({fixtureCommand: 'state'}, '*');
        await until(() => fixture.messages.some(m => m.source === f.contentWindow && m.phase === 'state'), 'child state');
        return {action, child: fixture.messages.filter(m => m.source === f.contentWindow).at(-1).state, ...state()};
    `,
            (result) => {
                assert.equal(result.action.handled, 1);
                assert.equal(result.child.videos[0].seeks, 0);
                assert.equal(result.child.videos[0].ended, true);
                assert.equal(result.child.videos[0].rate, 16);
                assert.equal(result.child.closes, 0);
                assert.deepEqual(result.child.errors, []);
            },
            true
        )
    );
    cases.push(
        await runCase(
            'production-loop-is-untouched',
            `
        await addVideo(true);
        const action = await __adspeed.skipAsync();
        return {action, ...state()};
    `,
            (result) => {
                assert.equal(result.action.handled, 0);
                assert.equal(result.videos[0].rate, 1);
                assert.equal(result.videos[0].loop, true);
                assert.equal(result.videos[0].seeks, 0);
                assert.equal(result.closes, 0);
            },
            true
        )
    );
    cases.push(
        await runCase(
            'production-ignored-rate-does-not-seek',
            `
        const v = await addVideo();
        Object.defineProperty(v, 'playbackRate', {get() { return 1; }, set(value) {}});
        const action = await __adspeed.skipAsync();
        return {action, ...state()};
    `,
            (result) => {
                assert.equal(result.action.handled, 0);
                assert.equal(result.videos[0].rate, 1);
                assert.equal(result.videos[0].seeks, 0);
                assert.equal(result.closes, 0);
                assert.deepEqual(result.errors, []);
            },
            true
        )
    );
    for (const change of ['hidden', 'removed', 'covered', 'paused']) {
        cases.push(
            await runCase(
                'production-cleanup-' + change,
                `
        const v = await addVideo();
        const action = await __adspeed.skipAsync();
        const changed = '${change}';
        if (changed === 'hidden') v.hidden = true;
        if (changed === 'removed') v.remove();
        if (changed === 'covered') {
            const cover = document.createElement('div');
            cover.style.cssText = 'position:fixed;inset:0;background:black;z-index:999';
            document.body.append(cover);
        }
        if (changed === 'paused') v.pause();
        await until(() => v.playbackRate === 1, 'manual rate released');
        return {action, rate: v.playbackRate, seeks: Number(v.dataset.seeks), paused: v.paused, ...state()};
    `,
                (result) => {
                    assert.equal(result.action.handled, 1);
                    assert.equal(result.rate, 1);
                    assert.equal(result.seeks, 0);
                    assert.equal(result.closes, 0);
                    if (change === 'paused') assert.equal(result.paused, true);
                    assert.deepEqual(result.errors, []);
                },
                true
            )
        );
    }
    cases.push(await runCase('recognized-video-16x-timers-natural-completion', `
        const v = await addVideo();
        const started = realNow();
        const virtualStarted = performance.now();
        let timerFinished = false;
        __adspeed.setAdContext(true);
        setTimeout(() => timerFinished = true, 4000);
        const requestedRate = v.playbackRate;
        const manual = await __adspeed.skipAsync();
        await until(() => v.ended && timerFinished, 'actual video and timer completion', 4000);
        const elapsed = realNow() - started;
        const virtualElapsed = performance.now() - virtualStarted;
        __adspeed.setAdContext(false);
        return {requestedRate, manual, elapsed, virtualElapsed, timerFinished, ...state()};
    `, result => {
        assert.equal(result.requestedRate, 16);
        assert.equal(result.manual.handled, 1);
        assert.equal(result.videos[0].ended, true);
        assert.equal(result.videos[0].seeks, 0);
        assert.equal(result.timerFinished, true);
        assert.ok(result.elapsed < 4000);
        assert.ok(result.virtualElapsed > result.elapsed * 10);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('mraid-semantic-tap-swipe-playable-progression', `
        let redirectCalls = 0;
        let rewardCalls = 0;
        let complete = false;
        let movements = 0;
        let startX = 0;
        mraid.open = () => redirectCalls++;
        window.gameEnd = () => rewardCalls++;
        const started = realNow();
        function button(label) {
            const node = document.createElement('button');
            node.textContent = label;
            node.style.cssText = 'display:block;position:fixed;left:20px;top:40px;width:300px;height:300px';
            document.body.append(node);
            return node;
        }
        const start = button('Tap to play');
        start.addEventListener('click', () => {
            start.remove();
            const swipe = button('Swipe left');
            swipe.addEventListener('pointerdown', event => startX = event.clientX);
            swipe.addEventListener('pointermove', () => movements++);
            swipe.addEventListener('pointerup', event => {
                if (event.clientX >= startX - 50 || movements !== 6) return;
                swipe.remove();
                const next = button('Continue playing');
                next.addEventListener('click', () => {
                    next.remove();
                    mraid.open('https://apps.apple.com/app/id0');
                    window.open('https://apps.apple.com/app/id0');
                    setTimeout(() => complete = true, 4000);
                });
            });
        });
        await sleep(100);
        const unrecognizedActions = __adspeed.stats.interactions;
        __adspeed.setAdContext(true);
        await until(() => complete, 'playable actual input and timer completion', 5000);
        return {unrecognizedActions, complete, movements, redirectCalls, rewardCalls,
            elapsed: realNow() - started, stats: {...__adspeed.stats}, ...state()};
    `, result => {
        assert.equal(result.unrecognizedActions, 0);
        assert.equal(result.complete, true);
        assert.equal(result.movements, 6);
        assert.equal(result.stats.interactions, 3);
        assert.equal(result.stats.redirectsBlocked, 2);
        assert.equal(result.redirectCalls, 0);
        assert.equal(result.rewardCalls, 0);
        assert.equal(result.closes, 0);
        assert.ok(result.elapsed < 5000);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('unknown-canvas-and-install-actions-abstain', `
        document.body.innerHTML = '<canvas width="320" height="320"></canvas><button>Install</button><button>Play</button>';
        let inputs = 0;
        document.addEventListener('click', () => inputs++);
        document.addEventListener('pointerdown', () => inputs++);
        __adspeed.setAdContext(true);
        await sleep(700);
        return {inputs, stats: {...__adspeed.stats}, ...state()};
    `, result => {
        assert.equal(result.inputs, 0);
        assert.equal(result.stats.interactions, 0);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('16x-animation-clock-and-native-cancellation', `
        __adspeed.setAdContext(true);
        let canceled = false;
        const handle = requestAnimationFrame(() => canceled = true);
        cancelAnimationFrame(handle);
        const frames = [];
        await new Promise(resolve => {
            requestAnimationFrame(first => {
                const real = realNow();
                requestAnimationFrame(second => {
                    frames.push({delta: second - first, realDelta: realNow() - real});
                    resolve();
                });
            });
        });
        __adspeed.setAdContext(false);
        return {canceled, frames, ...state()};
    `, result => {
        assert.equal(result.canceled, false);
        assert.ok(result.frames[0].delta > result.frames[0].realDelta * 8);
        assert.ok(result.frames[0].delta < result.frames[0].realDelta * 24);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('interactive-context-loss-cancels-swipe', `
        const node = document.createElement('button');
        node.textContent = 'Swipe right';
        node.style.cssText = 'width:300px;height:300px';
        const events = [];
        for (const type of ['pointerdown','pointermove','pointerup','pointercancel','click']) {
            node.addEventListener(type, () => events.push(type));
        }
        document.body.append(node);
        __adspeed.setAdContext(true);
        await sleep(40);
        __adspeed.setAdContext(false);
        await sleep(150);
        return {events, ...state()};
    `, result => {
        assert.equal(result.events[0], 'pointerdown');
        assert.equal(result.events.at(-1), 'pointercancel');
        assert.equal(result.events.includes('pointerup'), false);
        assert.equal(result.events.includes('click'), false);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('manual-only-video-and-playable-timing-require-a-press', `
        const video = await addVideo();
        let inputs = 0;
        const button = document.createElement('button');
        button.textContent = 'Tap to play';
        button.style.cssText = 'display:block;width:300px;height:100px';
        button.addEventListener('click', () => inputs++);
        document.body.append(button);
        __adspeed.setAdContext(true);
        const beforeReal = realNow();
        const beforeVirtual = performance.now();
        await sleep(350);
        const untouched = {rate: video.playbackRate, real: realNow() - beforeReal,
            virtual: performance.now() - beforeVirtual, inputs};
        const action = await __adspeed.skipAsync();
        const requestedRate = video.playbackRate;
        const speedReal = realNow();
        const speedVirtual = performance.now();
        await sleep(150);
        const accelerated = {real: realNow() - speedReal, virtual: performance.now() - speedVirtual};
        __adspeed.setAdContext(false);
        __adspeed.setAdContext(true);
        const resetReal = realNow();
        const resetVirtual = performance.now();
        await sleep(150);
        return {untouched, action, requestedRate, accelerated, reset: {rate: video.playbackRate,
            real: realNow() - resetReal, virtual: performance.now() - resetVirtual}, inputs, ...state()};
    `, result => {
        assert.equal(result.untouched.rate, 1);
        assert.ok(result.untouched.virtual < result.untouched.real * 1.5);
        assert.equal(result.action.kind, 'video');
        assert.equal(result.action.handled, 1);
        assert.equal(result.requestedRate, 16);
        assert.ok(result.accelerated.virtual > result.accelerated.real * 10);
        assert.equal(result.reset.rate, 1);
        assert.ok(result.reset.virtual < result.reset.real * 1.5);
        assert.equal(result.inputs, 0);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }, true, false));
    cases.push(await runCase('manual-only-canvas-timing-and-static-end-card', `
        __adspeed.setAdContext(true);
        const staticInspection = await __adspeed.inspectAsync();
        const canvas = document.createElement('canvas');
        canvas.width = 320;
        canvas.height = 180;
        document.body.append(canvas);
        const inspection = await __adspeed.inspectAsync();
        const started = realNow();
        let timerFinished = false;
        const action = await __adspeed.skipAsync(inspection.token);
        setTimeout(() => timerFinished = true, 4000);
        await until(() => timerFinished, 'manual canvas timer', 2500);
        return {staticInspection, inspection, action, elapsed: realNow() - started,
            interactions: __adspeed.stats.interactions, ...state()};
    `, result => {
        assert.equal(result.staticInspection.count, 0);
        assert.equal(result.inspection.count, 1);
        assert.equal(result.action.handled, 1);
        assert.equal(result.action.kind, 'timing');
        assert.ok(result.elapsed < 2500);
        assert.equal(result.interactions, 0);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }, false, false));
    for (const automatic of [true, false]) {
        cases.push(await runCase('nested-mraid-parent-child-without-bridge-' + (automatic ? 'automatic' : 'manual'), `
            const frame = await addFrame(false);
            frame.contentWindow.postMessage({fixtureCommand: 'playable'}, '*');
            await until(() => fixture.messages.some(item => item.phase === 'playable-ready'), 'child canvas ready');
            __adspeed.setAdContext(null);
            await sleep(200);
            frame.contentWindow.postMessage({fixtureCommand: 'sample', id: 'before'}, '*');
            await until(() => fixture.messages.some(item => item.phase === 'before'), 'child before sample');
            const before = fixture.messages.find(item => item.phase === 'before').state;
            const inspection = await __adspeed.inspectAsync();
            const action = ${automatic ? 'null' : 'await __adspeed.skipAsync(inspection.token)'};
            await until(() => fixture.messages.some(item => item.phase === 'playable-timer'), 'child timer accelerated', 1500);
            frame.contentWindow.postMessage({fixtureCommand: 'sample', id: 'after'}, '*');
            await until(() => fixture.messages.some(item => item.phase === 'after'), 'child after sample');
            const after = fixture.messages.find(item => item.phase === 'after').state;
            return {inspection, action, before, after, ...state()};
        `, result => {
            assert.equal(result.inspection.count, 1);
            if (!automatic) {
                assert.equal(result.action.handled, 1);
                assert.equal(result.action.kind, 'timing');
                assert.ok(result.after.virtual - result.before.virtual > (result.after.real - result.before.real) * 8);
            }
            assert.equal(result.after.timerDone, true);
            assert.equal(result.after.closes, 0);
            assert.deepEqual(result.after.errors, []);
            assert.deepEqual(result.errors, []);
        }, false, automatic));
    }
    cases.push(await runCase('css-and-web-animations-16x-pause-base-rate-cleanup', `
        const style = document.createElement('style');
        style.textContent = '@keyframes fixtureMove{from{transform:translateX(0)}to{transform:translateX(40px)}}.animated{width:100px;height:100px;background:#345;animation:fixtureMove 16s linear infinite}';
        document.head.append(style);
        const css = document.createElement('div');
        css.className = 'animated';
        document.body.append(css);
        const target = document.createElement('div');
        target.style.cssText = 'width:100px;height:100px;background:#567';
        document.body.append(target);
        const web = target.animate([{transform:'translateX(0)'},{transform:'translateX(40px)'}],
            {duration:16000,iterations:Infinity});
        await web.ready;
        const cssAnimation = css.getAnimations()[0];
        __adspeed.setAdContext(true);
        const requested = [web.playbackRate, cssAnimation.playbackRate];
        const originalTime = web.currentTime;
        const started = realNow();
        await sleep(150);
        const progression = {real: realNow() - started, animated: web.currentTime - originalTime};
        web.pause();
        await web.ready;
        await until(() => web.playbackRate === 1, 'paused animation releases speed');
        const paused = {state:web.playState,rate:web.playbackRate};
        cssAnimation.playbackRate = 0.5;
        await until(() => cssAnimation.playbackRate === 8, 'new SDK base rate');
        __adspeed.setAdContext(false);
        return {requested, progression, paused, restored:cssAnimation.playbackRate, ...state()};
    `, result => {
        assert.deepEqual(result.requested, [16, 16]);
        assert.ok(result.progression.animated > result.progression.real * 8);
        assert.equal(result.paused.state, 'paused');
        assert.equal(result.paused.rate, 1);
        assert.equal(result.restored, 0.5);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }));
    const report = {
        sourceSha256,
        browser: version,
        focusEmulated: true,
        fixture: 'Locally generated12-second H264MP4,160x90,15fps,noaudio',
        origins: [`http://127.0.0.1:${portA}`, `http://127.0.0.1:${portB}`],
        passed: cases.length,
        cases
    };
    fs.writeFileSync(output, JSON.stringify(report, null, 2));
    console.log(JSON.stringify({ passed: cases.length, sourceSha256, browser: version.product }));
}
main()
    .catch((e) => {
        console.error(e);
        process.exitCode = 1;
    })
    .finally(async () => {
        if (socket && socket.readyState === 1) {
            try {
                await command('Browser.close');
            } catch {}
            socket.close();
        }
        if (serverA.listening) serverA.close();
        if (serverB.listening) serverB.close();
        if (browser && browser.exitCode === null) {
            await Promise.race([new Promise((resolve) => browser.once('exit', resolve)), sleep(3000)]);
            if (browser.exitCode === null) browser.kill();
        }
        if (profile && (!browser || browser.exitCode !== null)) {
            const resolved = path.resolve(profile);
            const temporaryRoot = path.resolve(os.tmpdir()) + path.sep;
            if (
                resolved.startsWith(temporaryRoot) &&
                path.basename(resolved).startsWith('advanish-browser-')
            ) {
                fs.rmSync(resolved, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
            }
        }
    });
