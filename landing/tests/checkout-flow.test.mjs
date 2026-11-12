import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';

const ads = await readFile(new URL('../ads.js', import.meta.url), 'utf8');
const purchase = await readFile(new URL('../purchase.js', import.meta.url), 'utf8');
const id = 'e44e96fe-996b-42bf-904c-dab03b150fa1';
const paid = {verified:true, transaction_id:id, value:29, currency:'USD'};

async function checkout(receipt, choice = 'allow', checkoutId = id) {
  const storage = new Map([['qs_ad_consent', JSON.stringify({choice,at:Date.now()})]]);
  const listeners = {}, goals = [], scripts = [], requests = [];
  const window = {
    addEventListener(name, fn) { listeners[name] = fn; },
    dispatchEvent(event) { listeners[event.type]?.(event); },
    minilytics(...args) { goals.push(args); },
  };
  const context = vm.createContext({
    window, Date, Set, URLSearchParams,
    location:{search:`?checkout_id=${checkoutId}`},
    CustomEvent: class { constructor(type, init) {this.type=type;this.detail=init.detail;} },
    localStorage:{getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,value)},
    document:{
      createElement:()=>({}), head:{append(element){if(element.src)scripts.push(element.src);}},
      addEventListener(){},
    },
    setTimeout:fn=>fn(),
    fetch:async(url, options)=>{
      requests.push({url,options});
      return {ok:true,json:async()=>url==='/ads-config.json'
        ? {tag_id:'AW-123',purchase_label:'test-label'} : receipt};
    },
  });
  vm.runInContext(ads,context);
  await new Promise(resolve=>setImmediate(resolve));
  const run = () => vm.runInContext(purchase,context);
  await run();
  return {window,goals,scripts,requests,run,
    conversions:()=>window.dataLayer?.filter(args=>args[0]==='event')||[]};
}

test('success URL alone never emits purchase goals or Google conversions',async()=>{
  const unpaid=await checkout({verified:false});
  assert.equal(unpaid.goals.length,0);assert.equal(unpaid.conversions().length,0);
  const invalid=await checkout(paid,'allow','forged');
  assert.equal(invalid.requests.filter(x=>x.url==='/api/verify-purchase').length,0);
  assert.equal(invalid.goals.length,0);assert.equal(invalid.conversions().length,0);
  const wrongOrder=await checkout({...paid,transaction_id:'another-order'});
  assert.equal(wrongOrder.goals.length,0);assert.equal(wrongOrder.conversions().length,0);
});

test('verified payment reaches both measurement channels once, including on revisit',async()=>{
  const page=await checkout(paid);
  assert.equal(page.goals.length,1);assert.equal(page.conversions().length,1);
  const event=page.conversions()[0][2];
  assert.equal(event.transaction_id,id);assert.equal(event.value,29);assert.equal(event.currency,'USD');
  assert.equal(event.send_to,'AW-123/test-label');
  event.event_callback();
  await page.run();
  assert.equal(page.goals.length,1);assert.equal(page.conversions().length,1);
  assert.deepEqual(JSON.parse(page.requests.find(x=>x.url==='/api/verify-purchase').options.body),{checkout_id:id});
});

test('declining Google measurement still permits verified first-party purchase reporting',async()=>{
  const page=await checkout(paid,'deny');
  assert.equal(page.goals.length,1);assert.equal(page.scripts.length,0);
  assert.equal(page.conversions().length,0);
});
