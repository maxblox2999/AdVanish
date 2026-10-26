const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const {spawn} = require('node:child_process');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const os = require('node:os');
const root = __dirname;
const source = fs.readFileSync(path.join(root, '../../web/adspeed.js'), 'utf8');
const sourceSha256 = crypto.createHash('sha256').update(source).digest('hex');
const config = {speedVideo:false,compressTimers:false,accelerateClock:false,forceInline:false,autoSkip:false,manualClose:true,skipChannel:'browser-verification-session'};
const engine = source.replace('__ADSPEED_CONFIG__', JSON.stringify(config));
let portA;
let portB;
function html(child, playback) {
    return `<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#eee}video{display:block;width:320px;height:180px}iframe{width:360px;height:210px;border:0}</style><script src="/engine.js?playback=${playback ? 1 : 0}"></script><script>
    window.fixture = {messages:[],closes:0,errors:[]};
    window.addEventListener('error',e=>fixture.errors.push(String(e.message)));
    window.addEventListener('unhandledrejection',e=>fixture.errors.push(String(e.reason)));
    window.mraid={close(){fixture.closes++},getState(){return 'default'},getPlacementType(){return 'interstitial'},isViewable(){return true}};
    window.sleep=ms=>new Promise(r=>setTimeout(r,ms));
    window.until=async (fn,label,ms=6000)=>{const end=performance.now()+ms;while(performance.now()<end){if(fn())return;await sleep(20)}throw Error('Timeout: '+label)};
    window.addVideo=async (loop=false)=>{const v=document.createElement('video');v.muted=true;v.playsInline=true;v.loop=loop;v.src='/fixture.mp4?n='+Math.random();v.preload='auto';v.dataset.seeks='0';v.addEventListener('seeking',()=>{v.dataset.seeks=String(Number(v.dataset.seeks)+1);if(parent!==window)report('seeking')});v.addEventListener('ended',()=>{if(parent!==window)report('ended')});document.body.append(v);await v.play();await until(()=>v.readyState>=3&&Number.isFinite(v.duration)&&v.seekable.length&&!v.paused&&!v.seeking&&v.currentTime>0.1,'video ready');return v};
    window.state=()=>({closes:fixture.closes,videos:Array.from(document.querySelectorAll('video')).map(v=>({ended:v.ended,seeks:Number(v.dataset.seeks),current:v.currentTime,duration:v.duration,loop:v.loop,paused:v.paused,rate:v.playbackRate})),errors:fixture.errors});
    window.report=phase=>parent.postMessage({fixtureReport:true,phase,state:state()},'*');
    window.addEventListener('message',async e=>{if(e.data&&e.data.fixtureReport)fixture.messages.push({source:e.source,phase:e.data.phase,state:e.data.state});if(e.data&&e.data.fixtureCommand==='add-video'){await addVideo();report('added')}if(e.data&&e.data.fixtureCommand==='state')report('state')});
    window.addFrame=async video=>{const frame=document.createElement('iframe');frame.src='http://127.0.0.1:${portB}/child?video='+(video?'1':'0')+'&playback=${playback ? 1 : 0}';document.body.append(frame);await until(()=>fixture.messages.some(m=>m.source===frame.contentWindow&&m.phase==='ready'),'frame ready');return frame};
    ${child ? `window.addEventListener('DOMContentLoaded',async()=>{try{if(new URL(location.href).searchParams.get('video')==='1')await addVideo();report('ready')}catch(e){fixture.errors.push(String(e));report('error')}});` : ''}
    </script><body></body>`;
}
function serve(req,res){
    const url = new URL(req.url,'http://127.0.0.1');
    if (url.pathname === '/engine.js') {
        const script = url.searchParams.get('playback') === '1'
            ? source.replace('__ADSPEED_CONFIG__', JSON.stringify({...config, manualPlayback: true})) : engine;
        res.writeHead(200, {'Content-Type': 'text/javascript'});
        res.end(script);
        return;
    }
    if(url.pathname==='/fixture.mp4'){
        const data=fs.readFileSync(path.join(root,'../ios/fixture.mp4'));
        let start=0;let end=data.length-1;
        const range=/bytes=(\d+)-(\d*)/.exec(req.headers.range||'');
        if(range){start=Number(range[1]);if(range[2])end=Math.min(end,Number(range[2]));res.writeHead(206,{'Content-Type':'video/mp4','Accept-Ranges':'bytes','Content-Range':`bytes ${start}-${end}/${data.length}`,'Content-Length':end-start+1});}
        else res.writeHead(200,{'Content-Type':'video/mp4','Accept-Ranges':'bytes','Content-Length':data.length});
        res.end(data.subarray(start,end+1));return;
    }
    res.writeHead(200,{'Content-Type':'text/html'});res.end(html(url.pathname==='/child', url.searchParams.get('playback') === '1'));
}
const serverA=http.createServer(serve);
const serverB=http.createServer(serve);
let browser;
let profile;
let socket;
let next=1;
const pending=new Map();
function command(method,params={},sessionId){return new Promise((resolve,reject)=>{const id=next++;const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method))},20000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params,sessionId}));});}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function evaluate(sessionId,expression){const r=await command('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true},sessionId);if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
async function runCase(name,body,verify,playback=false){
    const {targetId}=await command('Target.createTarget',{url:`http://127.0.0.1:${portA}/?case=${name}&playback=${playback ? 1 : 0}`});
    const {sessionId}=await command('Target.attachToTarget',{targetId,flatten:true});
    try{
        await command('Runtime.enable',{},sessionId);
        for(let i=0;i<100;i++){if(await evaluate(sessionId,'!!(window.fixture&&document.body&&window.__adspeed)'))break;await sleep(30);}
        const value=await evaluate(sessionId,`(async()=>{${body}})()`);
        verify(value);
        console.log(JSON.stringify({case:name,passed:true,...value}));
        return {case:name,passed:true,...value};
    }finally{await command('Target.closeTarget',{targetId});}
}
async function main(){
    await new Promise(r=>serverA.listen(0,'127.0.0.1',r));portA=serverA.address().port;
    await new Promise(r=>serverB.listen(0,'127.0.0.1',r));portB=serverB.address().port;
    profile = fs.mkdtempSync(path.join(os.tmpdir(), 'advanish-browser-'));
    const executable = process.env.BROWSER_PATH || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
    browser=spawn(executable,['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--autoplay-policy=no-user-gesture-required','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:['ignore','ignore','pipe']});
    let stderr='';browser.stderr.on('data',d=>stderr+=d);
    const portFile=path.join(profile,'DevToolsActivePort');
    for(let i=0;i<200&&!fs.existsSync(portFile);i++){if(browser.exitCode!==null)throw Error('Browser exited '+browser.exitCode+' '+stderr);await sleep(50);}
    const [port,endpoint]=fs.readFileSync(portFile,'utf8').trim().split(/\r?\n/);
    socket=new WebSocket('ws://127.0.0.1:'+port+endpoint);
    await new Promise((r,j)=>{socket.onopen=r;socket.onerror=j});
    socket.onmessage=e=>{const d=JSON.parse(e.data);const p=pending.get(d.id);if(!p)return;pending.delete(d.id);clearTimeout(p.timer);if(d.error)p.reject(Error(JSON.stringify(d.error)));else p.resolve(d.result)};
    const version=await command('Browser.getVersion');
    const cases=[];
    cases.push(await runCase('single-video-natural-ended',`const v=await addVideo();const before=v.currentTime;const inspection=await __adspeed.inspectAsync();const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);await until(()=>v.ended,'natural ended',3000);const repeat=await __adspeed.skipAsync();return {before,inspection,valid,action,repeat,...state()};`,r=>{assert.equal(r.inspection.count,1);assert.equal(r.valid,true);assert.equal(r.action.handled,1);assert.equal(r.videos[0].ended,true);assert.equal(r.videos[0].seeks,1);assert.equal(r.closes,0);assert.equal(r.repeat.handled,0);assert.deepEqual(r.errors,[])}));
    cases.push(await runCase('two-local-videos-abstain',`await addVideo();await addVideo();const inspection=await __adspeed.inspectAsync();const action=await __adspeed.skipAsync();return {inspection,action,...state()};`,r=>{assert.equal(r.inspection.count,2);assert.equal(r.action.handled,0);assert.equal(r.action.unresolved,1);assert.equal(r.videos.reduce((n,v)=>n+v.seeks,0),0);assert.equal(r.closes,0)}));
    cases.push(await runCase('cross-origin-child-seek-ended',`const f=await addFrame(true);const inspection=await __adspeed.inspectAsync();const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='ended'),'child ended',3000);return {inspection,valid,action,child:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,...state()};`,r=>{assert.equal(r.inspection.count,1);assert.equal(r.valid,true);assert.equal(r.action.handled,1);assert.equal(r.child.videos[0].ended,true);assert.equal(r.child.videos[0].seeks,1);assert.equal(r.child.closes,0);assert.equal(r.closes,0)}));
    cases.push(await runCase('sibling-frame-single-action',`const f=await addFrame(true);const empty=await addFrame(false);const inspection=await __adspeed.inspectAsync();const action=await __adspeed.skipAsync(inspection.token);await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='ended'),'child ended',3000);empty.contentWindow.postMessage({fixtureCommand:'state'},'*');await until(()=>fixture.messages.some(m=>m.source===empty.contentWindow&&m.phase==='state'),'empty state');return {inspection,action,videoChild:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,emptyChild:fixture.messages.filter(m=>m.source===empty.contentWindow).at(-1).state,...state()};`,r=>{assert.equal(r.inspection.count,1);assert.equal(r.action.handled,1);assert.equal(r.videoChild.videos[0].seeks,1);assert.equal(r.emptyChild.closes,0);assert.equal(r.closes,0)}));
    cases.push(await runCase('root-and-frame-ambiguous',`await addVideo();const f=await addFrame(true);const inspection=await __adspeed.inspectAsync();const action=await __adspeed.skipAsync();f.contentWindow.postMessage({fixtureCommand:'state'},'*');await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='state'),'child state');return {inspection,action,child:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,...state()};`,r=>{assert.equal(r.inspection.count,2);assert.equal(r.action.handled,0);assert.equal(r.videos[0].seeks,0);assert.equal(r.child.videos[0].seeks,0);assert.equal(r.closes,0)}));
    cases.push(await runCase('empty-snapshot-stale-on-new-video',`const inspection=await __adspeed.inspectAsync();await addVideo();const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);return {inspection,valid,action,...state()};`,r=>{assert.equal(r.inspection.count,0);assert.equal(r.valid,false);assert.equal(r.action.handled,0);assert.equal(r.videos[0].seeks,0);assert.equal(r.closes,0)}));
    cases.push(await runCase('single-use-token',`const v=await addVideo();const inspection=await __adspeed.inspectAsync();const actions=await Promise.all([__adspeed.skipAsync(inspection.token),__adspeed.skipAsync(inspection.token)]);await until(()=>v.ended,'natural ended',3000);return {inspection,actions,...state()};`,r=>{assert.equal(r.actions.reduce((n,a)=>n+a.handled,0),1);assert.equal(r.videos[0].seeks,1);assert.equal(r.closes,0)}));
    cases.push(await runCase('loop-video-natural-ended',`const v=await addVideo(true);const inspection=await __adspeed.inspectAsync();const action=await __adspeed.skipAsync(inspection.token);await until(()=>v.ended,'loop disabled ended',3000);return {inspection,action,...state()};`,r=>{assert.equal(r.action.handled,1);assert.equal(r.videos[0].loop,false);assert.equal(r.videos[0].ended,true);assert.equal(r.closes,0)}));
    cases.push(await runCase('child-empty-snapshot-invalidates-new-child-media',`const f=await addFrame(false);const inspection=await __adspeed.inspectAsync();f.contentWindow.postMessage({fixtureCommand:'add-video'},'*');await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='added'),'child new video');const valid=await __adspeed.validateAsync(inspection.token);const action=await __adspeed.skipAsync(inspection.token);f.contentWindow.postMessage({fixtureCommand:'state'},'*');await until(()=>fixture.messages.some(m=>m.source===f.contentWindow&&m.phase==='state'),'child state');return {inspection,valid,action,child:fixture.messages.filter(m=>m.source===f.contentWindow).at(-1).state,...state()};`,r=>{assert.equal(r.inspection.count,0);assert.equal(r.valid,false);assert.equal(r.action.handled,0);assert.equal(r.child.videos[0].seeks,0);assert.equal(r.child.closes,0)}));
    cases.push(await runCase('opaque-overlay-abstains', `
        const v = await addVideo();
        const overlay = document.createElement('div');
        overlay.style.cssText = 'position:fixed;inset:0;background:black;z-index:999';
        document.body.append(overlay);
        const inspection = await __adspeed.inspectAsync();
        const action = await __adspeed.skipAsync();
        return {inspection, action, ...state()};
    `, result => {
        assert.equal(result.inspection.unresolved, 1);
        assert.equal(result.action.handled, 0);
        assert.equal(result.videos[0].seeks, 0);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('covering-empty-iframe-abstains', `
        const v = await addVideo();
        const frame = await addFrame(false);
        frame.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;z-index:999;background:white';
        const inspection = await __adspeed.inspectAsync();
        const action = await __adspeed.skipAsync();
        return {inspection, action, ...state()};
    `, result => {
        assert.equal(result.inspection.unresolved, 1);
        assert.equal(result.action.handled, 0);
        assert.equal(result.videos[0].seeks, 0);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('ignored-seek-restores-loop', `
        const v = await addVideo(true);
        const before = v.currentTime;
        Object.defineProperty(v, 'currentTime', {
            configurable: true,
            get() { return before; },
            set(value) {}
        });
        const action = await __adspeed.skipAsync();
        const rejected = {action, loop: v.loop, skipped: __adspeed.stats.skipped,
            failures: __adspeed.stats.seekFailures};
        delete v.currentTime;
        const retry = await __adspeed.skipAsync();
        await until(() => v.ended, 'retry naturally ended', 3000);
        return {rejected, retry, ...state()};
    `, result => {
        assert.equal(result.rejected.action.handled, 0);
        assert.equal(result.rejected.action.unresolved, 1);
        assert.equal(result.rejected.loop, true);
        assert.equal(result.rejected.skipped, 0);
        assert.equal(result.rejected.failures, 1);
        assert.equal(result.retry.handled, 1);
        assert.equal(result.videos[0].ended, true);
        assert.equal(result.videos[0].seeks, 1);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }));
    cases.push(await runCase('production-manual-playback-without-seek', `
        const v = await addVideo();
        const before = v.currentTime;
        const action = await __adspeed.skipAsync();
        const requested = {rate: v.playbackRate, time: v.currentTime, before};
        await until(() => v.ended, 'normal playback ended', 8000).catch(error => {
            throw new Error(error.message + ': ' + JSON.stringify({requested, ...state(),
                hidden: document.hidden, stats: __adspeed.stats}));
        });
        return {action, requested, ...state()};
    `, result => {
        assert.equal(result.action.handled, 1);
        assert.equal(result.requested.rate, 2);
        assert.ok(result.requested.time < result.requested.before + 0.25);
        assert.equal(result.videos[0].seeks, 0);
        assert.equal(result.videos[0].ended, true);
        assert.equal(result.videos[0].rate, 2);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }, true));
    cases.push(await runCase('production-cross-origin-playback-without-seek', `
        const f = await addFrame(true);
        const action = await __adspeed.skipAsync();
        await until(() => fixture.messages.some(m => m.source === f.contentWindow && m.phase === 'ended'),
            'child natural completion', 8000);
        f.contentWindow.postMessage({fixtureCommand: 'state'}, '*');
        await until(() => fixture.messages.some(m => m.source === f.contentWindow && m.phase === 'state'), 'child state');
        return {action, child: fixture.messages.filter(m => m.source === f.contentWindow).at(-1).state, ...state()};
    `, result => {
        assert.equal(result.action.handled, 1);
        assert.equal(result.child.videos[0].seeks, 0);
        assert.equal(result.child.videos[0].ended, true);
        assert.equal(result.child.videos[0].rate, 2);
        assert.equal(result.child.closes, 0);
        assert.deepEqual(result.child.errors, []);
    }, true));
    cases.push(await runCase('production-loop-is-untouched', `
        await addVideo(true);
        const action = await __adspeed.skipAsync();
        return {action, ...state()};
    `, result => {
        assert.equal(result.action.handled, 0);
        assert.equal(result.videos[0].rate, 1);
        assert.equal(result.videos[0].loop, true);
        assert.equal(result.videos[0].seeks, 0);
        assert.equal(result.closes, 0);
    }, true));
    cases.push(await runCase('production-ignored-rate-does-not-seek', `
        const v = await addVideo();
        Object.defineProperty(v, 'playbackRate', {get() { return 1; }, set(value) {}});
        const action = await __adspeed.skipAsync();
        return {action, ...state()};
    `, result => {
        assert.equal(result.action.handled, 0);
        assert.equal(result.videos[0].rate, 1);
        assert.equal(result.videos[0].seeks, 0);
        assert.equal(result.closes, 0);
        assert.deepEqual(result.errors, []);
    }, true));
    const report={sourceSha256,browser:version,fixture:'Locally generated12-second H264MP4,160x90,15fps,noaudio',origins:[`http://127.0.0.1:${portA}`,`http://127.0.0.1:${portB}`],passed:cases.length,cases};
    const output = path.join(root, '../../dist/browser.json');
    fs.mkdirSync(path.dirname(output), {recursive: true});
    fs.writeFileSync(output, JSON.stringify(report, null, 2));
    console.log(JSON.stringify({passed:cases.length,sourceSha256,browser:version.product}));
}
main().catch(e=>{console.error(e);process.exitCode=1}).finally(async()=>{
    if(socket&&socket.readyState===1){try{await command('Browser.close')}catch{}socket.close()}
    serverA.close();serverB.close();
    if (browser && browser.exitCode === null) {
        await Promise.race([new Promise(resolve => browser.once('exit', resolve)), sleep(3000)]);
        if (browser.exitCode === null) browser.kill();
    }
    if (profile && (!browser || browser.exitCode !== null)) {
        const resolved = path.resolve(profile);
        const temporaryRoot = path.resolve(os.tmpdir()) + path.sep;
        if (resolved.startsWith(temporaryRoot) && path.basename(resolved).startsWith('advanish-browser-')) {
            fs.rmSync(resolved, {recursive: true, force: true, maxRetries: 5, retryDelay: 100});
        }
    }
});
