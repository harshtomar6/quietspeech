import test from 'node:test';
import assert from 'node:assert/strict';
import handler, { purchaseReceipt } from '../api/verify-purchase.mjs';

const id = 'e44e96fe-996b-42bf-904c-dab03b150fa1';
const product = 'test-product';
const paid = { id, status: 'succeeded', product_id: product, currency: 'usd', net_amount: 2900, customer_email: 'not-returned@example.test' };

test('receipt contains paid value and ID, without customer details', () => {
  assert.deepEqual(purchaseReceipt(paid, product, id), { verified: true, transaction_id: id, value: 29, currency: 'USD' });
});
test('an unpaid, merely confirmed or unrelated checkout never becomes a receipt', () => {
  for (const patch of [{status:'open'},{status:'confirmed'},{status:'failed'},{status:'expired'},{product_id:'another-product'},{id:'another-checkout'},{currency:'eur'},{net_amount:0},{net_amount:-1},{net_amount:NaN},{net_amount:'2900'}])
    assert.equal(purchaseReceipt({...paid,...patch}, product, id), null);
  assert.equal(purchaseReceipt(paid, '', id), null);
});

function response() { return { headers:{}, setHeader(k,v){this.headers[k]=v;}, status(n){this.code=n;return this;}, json(x){this.body=x;return this;} }; }
test('verification rejects invalid IDs and fails closed without configuration', async () => {
  const saved = { token:process.env.POLAR_ACCESS_TOKEN, product:process.env.POLAR_PRODUCT_ID };
  delete process.env.POLAR_ACCESS_TOKEN; delete process.env.POLAR_PRODUCT_ID;
  try {
    let res=response(); await handler({method:'POST',body:{checkout_id:'forged'},headers:{}},res); assert.equal(res.code,400);
    res=response(); await handler({method:'POST',body:{checkout_id:id},headers:{}},res); assert.equal(res.code,503);assert.deepEqual(res.body,{verified:false});
    res=response(); await handler({method:'GET',headers:{}},res);assert.equal(res.code,405);
  } finally {
    if(saved.token===undefined)delete process.env.POLAR_ACCESS_TOKEN;else process.env.POLAR_ACCESS_TOKEN=saved.token;
    if(saved.product===undefined)delete process.env.POLAR_PRODUCT_ID;else process.env.POLAR_PRODUCT_ID=saved.product;
  }
});
test('only Polar success for the configured product is returned; API failures stay private', async () => {
  const originalFetch=globalThis.fetch, oldToken=process.env.POLAR_ACCESS_TOKEN, oldProduct=process.env.POLAR_PRODUCT_ID;
  process.env.POLAR_ACCESS_TOKEN='test-token';process.env.POLAR_PRODUCT_ID=product;
  try {
    for(const [upstream,wantedCode,wantedReceipt] of [
      [{ok:true,status:200,json:async()=>paid},200,true],
      [{ok:true,status:200,json:async()=>({...paid,status:'confirmed'})},200,false],
      [{ok:false,status:404},200,false],
      [{ok:false,status:401},503,false],
      [{ok:false,status:500},503,false],
    ]) {
      globalThis.fetch=async(url,options)=>{assert.equal(url,`https://api.polar.sh/v1/checkouts/${id}`);assert.equal(options.headers.Authorization,'Bearer test-token');return upstream;};
      const res=response();await handler({method:'POST',body:{checkout_id:id},headers:{origin:'https://quietspeech.app'}},res);
      assert.equal(res.code,wantedCode);assert.equal(res.body.verified,wantedReceipt);assert.ok(!JSON.stringify(res.body).includes('customer_email'));
      assert.equal(res.headers['Cache-Control'],'private, no-store');
    }
    globalThis.fetch=async()=>{throw new Error('private upstream failure');};
    const res=response();await handler({method:'POST',body:{checkout_id:id},headers:{}},res);assert.deepEqual(res.body,{verified:false});assert.equal(res.code,503);
  } finally {
    globalThis.fetch=originalFetch;
    if(oldToken===undefined)delete process.env.POLAR_ACCESS_TOKEN;else process.env.POLAR_ACCESS_TOKEN=oldToken;
    if(oldProduct===undefined)delete process.env.POLAR_PRODUCT_ID;else process.env.POLAR_PRODUCT_ID=oldProduct;
  }
});
