import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';

const code = await readFile(new URL('../ads.js', import.meta.url), 'utf8');
const turn = () => new Promise((resolve) => setImmediate(resolve));
async function browser(choice) {
  const storage = new Map(), listeners = {}, scripts = [], boxes = [];
  if(choice) storage.set('qs_ad_consent',JSON.stringify({choice,at:Date.now()}));
  const element = () => ({setAttribute(){},addEventListener(name,fn){this[name]=fn;},remove(){this.removed=true;}});
  const document = {
    createElement:element, head:{append(x){if(x.src)scripts.push(x);}},body:{append(x){boxes.push(x);}},
    querySelector(){return boxes.findLast(x=>!x.removed);},addEventListener(){},
  };
  const window = {addEventListener(name,fn){listeners[name]=fn;}};
  const localStorage = {getItem:k=>storage.get(k)??null,setItem:(k,v)=>storage.set(k,v)};
  vm.runInNewContext(code,{window,document,localStorage,Date,Set,fetch:async()=>({ok:true,json:async()=>({tag_id:'AW-123',purchase_label:'test-label'})})});
  await turn();await turn();
  return {window,scripts,boxes,listeners,storage,choose(choice){boxes.at(-1).click({target:{closest:()=>({dataset:{choice}})}});}};
}
test('Google tag does not load before consent or after decline', async()=>{
  const b=await browser();assert.equal(b.scripts.length,0);assert.equal(b.boxes.length,1);
  b.choose('deny');assert.equal(b.scripts.length,0);assert.equal(b.window.dataLayer,undefined);
  const denied=await browser('deny');assert.equal(denied.scripts.length,0);assert.equal(denied.boxes.length,0);
});
test('consent loads one tag, disables personalization, and only a verified receipt triggers a sale',async()=>{
  const b=await browser();b.choose('allow');assert.equal(b.scripts.length,1);
  let events=b.window.dataLayer.map(x=>Array.from(x));
  assert.equal(events.filter(x=>x[0]==='event').length,0);
  assert.equal(events.find(x=>x[0]==='consent'&&x[1]==='default')[2].ad_storage,'denied');
  assert.equal(events.find(x=>x[0]==='config')[2].allow_ad_personalization_signals,false);
  for(const bad of [{verified:false,transaction_id:'unpaid',value:29,currency:'USD'},{verified:true,transaction_id:'wrong-currency',value:29,currency:'EUR'},{verified:true,transaction_id:'no-value',value:0,currency:'USD'}])
    b.listeners['qs:verified-purchase']({detail:bad});
  assert.equal(b.window.dataLayer.map(x=>Array.from(x)).filter(x=>x[0]==='event').length,0);
  const receipt={verified:true,transaction_id:'receipt-1',value:25,currency:'USD'};
  b.listeners['qs:verified-purchase']({detail:receipt});b.listeners['qs:verified-purchase']({detail:receipt});
  events=b.window.dataLayer.map(x=>Array.from(x)).filter(x=>x[0]==='event');assert.equal(events.length,1);
  assert.equal(events[0][2].value,25);assert.equal(events[0][2].currency,'USD');assert.equal(events[0][2].transaction_id,'receipt-1');
  assert.equal(events[0][2].send_to,'AW-123/test-label');
});
test('a verified purchase waits for consent instead of sending before the choice',async()=>{
  const b=await browser();b.listeners['qs:verified-purchase']({detail:{verified:true,transaction_id:'receipt-2',value:29,currency:'USD'}});
  assert.equal(b.scripts.length,0);b.choose('allow');
  assert.equal(b.window.dataLayer.map(x=>Array.from(x)).filter(x=>x[0]==='event').length,1);
});
