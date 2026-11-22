import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';

const script = await readFile(new URL('../email-link.js', import.meta.url), 'utf8');
function draft({search='',stored=null,storageBlocked=false,path='/compare'}={}) {
  const link={dataset:{sendMacLink:path},href:'mailto:?subject=fallback'};
  vm.runInNewContext(script,{
    URL,URLSearchParams,Date,encodeURIComponent,
    window:{location:{search}},
    document:{querySelectorAll:()=>[link]},
    localStorage:{getItem(){if(storageBlocked)throw Error('blocked');return JSON.stringify(stored);}},
  });
  const mail=new URL(link.href), body=mail.searchParams.get('body');
  return {mail,body,destination:new URL(body.match(/https:\/\/\S+/)[0])};
}

test('email draft contains the Mac requirements and correct page, with no recipient or automatic send',()=>{
  const {mail,body,destination}=draft();
  assert.equal(mail.protocol,'mailto:');assert.equal(mail.pathname,'');
  assert.equal(mail.searchParams.get('subject'),'QuietSpeech for my Mac');
  assert.match(body,/Apple silicon Mac running macOS 26 or later/);
  assert.equal(destination.origin,'https://quietspeech.app');assert.equal(destination.pathname,'/compare');
  assert.equal(destination.searchParams.get('utm_medium'),'email');
  assert.equal(draft({path:'/'}).destination.pathname,'/');
});

test('handoff retains campaign tags but excludes ad-click, visitor and checkout identifiers',()=>{
  const {destination,mail}=draft({search:'?utm_source=google&utm_medium=cpc&utm_campaign=canada&utm_content=creative-1&gclid=private-click&reference_id=private-visitor&checkout_id=private-checkout&email=private@example.test'});
  assert.equal(destination.searchParams.get('utm_source'),'google');
  assert.equal(destination.searchParams.get('utm_medium'),'cpc');
  assert.equal(destination.searchParams.get('utm_campaign'),'canada');
  assert.equal(destination.searchParams.get('utm_content'),'mobile_email_creative-1');
  assert.ok(!mail.href.includes('private'));
});

test('recent campaign tags survive a later visit, but stale storage and blocked storage use the generic link',()=>{
  const recent={tags:{utm_source:'launch',utm_campaign:'november'},at:Date.now()};
  assert.equal(draft({stored:recent}).destination.searchParams.get('utm_source'),'launch');
  const expired={...recent,at:Date.now()-31*24*60*60*1000};
  assert.equal(draft({stored:expired}).destination.searchParams.get('utm_source'),'quietspeech');
  assert.equal(draft({storageBlocked:true}).destination.origin,'https://quietspeech.app');
  assert.equal(draft({search:'?utm_source=google',stored:recent}).destination.searchParams.get('utm_campaign'),null);
});

test('email links stay on the product site and bound campaign input',()=>{
  const {destination}=draft({path:'https://another.example/',search:'?utm_term='+encodeURIComponent('word '.repeat(100))});
  assert.equal(destination.origin,'https://quietspeech.app');assert.equal(destination.pathname,'/');
  assert.equal(destination.searchParams.get('utm_term').length,100);
});

function shareSetup({share, path='/'}={}) {
  let handler=null; const shared=[]; const win={location:{search:'',href:''}};
  const link={dataset:{sendMacLink:path},href:'',addEventListener(type,fn){if(type==='click')handler=fn;}};
  vm.runInNewContext(script,{
    URL,URLSearchParams,Date,encodeURIComponent,String,
    window:win, navigator: share ? {share:(data)=>{shared.push(data);return share(data);}} : {},
    document:{querySelectorAll:()=>[link]},
    localStorage:{getItem(){return null;}},
  });
  return {link,handler,shared,win};
}

test('where the browser can share, a tap opens the share sheet with a tagged link instead of the email draft',async()=>{
  const {handler,shared,link}=shareSetup({share:async()=>{}});
  let prevented=false; handler({preventDefault(){prevented=true;}}); await Promise.resolve();
  assert.ok(prevented);
  assert.equal(shared.length,1);
  const url=new URL(shared[0].url);
  assert.equal(url.origin,'https://quietspeech.app');
  assert.equal(url.searchParams.get('utm_medium'),'share');
  assert.equal(url.searchParams.get('utm_content'),'mobile_share');
  assert.match(shared[0].text,/Apple silicon Mac running macOS 26 or later/);
  assert.ok(link.href.startsWith('mailto:'),'the email draft stays as the link target');
});

test('a dismissed share sheet does nothing; a failed share falls back to the email draft',async()=>{
  const cancelled=shareSetup({share:()=>Promise.reject(Object.assign(new Error('x'),{name:'AbortError'}))});
  cancelled.handler({preventDefault(){}}); await new Promise(r=>setTimeout(r,0));
  assert.equal(cancelled.win.location.href,'');
  const failed=shareSetup({share:()=>Promise.reject(Object.assign(new Error('x'),{name:'NotAllowedError'}))});
  failed.handler({preventDefault(){}}); await new Promise(r=>setTimeout(r,0));
  assert.ok(failed.win.location.href.startsWith('mailto:'));
});

test('without share support the link is a plain email draft and no click handler is added',()=>{
  const {handler,link}=shareSetup();
  assert.equal(handler,null);
  assert.ok(link.href.startsWith('mailto:'));
});
