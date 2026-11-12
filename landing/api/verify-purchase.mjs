const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Return only the information needed for measurement, never customer details.
export function purchaseReceipt(checkout, productId, checkoutId) {
  if (!productId || checkout?.id !== checkoutId || checkout.status !== 'succeeded' ||
      checkout.product_id !== productId || checkout.currency !== 'usd' ||
      !Number.isSafeInteger(checkout.net_amount) || checkout.net_amount <= 0) return null;
  return { verified: true, transaction_id: checkout.id, value: checkout.net_amount / 100, currency: 'USD' };
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ verified: false });
  }
  const origin = req.headers?.origin;
  if (origin && origin !== 'https://quietspeech.app' && origin !== 'http://localhost:4173')
    return res.status(403).json({ verified: false });
  let body;
  try { body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body; }
  catch { return res.status(400).json({ verified: false }); }
  const id = body?.checkout_id;
  if (typeof id !== 'string' || !UUID.test(id)) return res.status(400).json({ verified: false });
  const token = process.env.POLAR_ACCESS_TOKEN;
  const productId = process.env.POLAR_PRODUCT_ID;
  if (!token || !productId) return res.status(503).json({ verified: false });
  try {
    const response = await fetch(`https://api.polar.sh/v1/checkouts/${encodeURIComponent(id)}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      signal: AbortSignal.timeout(6000),
    });
    if (response.status === 404) return res.status(200).json({ verified: false });
    if (!response.ok) return res.status(503).json({ verified: false });
    const receipt = purchaseReceipt(await response.json(), productId, id);
    return res.status(200).json(receipt || { verified: false });
  } catch {
    return res.status(503).json({ verified: false });
  }
}
