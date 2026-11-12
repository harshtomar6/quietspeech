/* A success-page URL is not proof of payment. Verify with Polar server-side. */
(async () => {
  const id = new URLSearchParams(location.search).get('checkout_id');
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id || '')) return;
  for (const delay of [0, 1500, 3500]) {
    if (delay) await new Promise((resolve) => setTimeout(resolve, delay));
    let receipt;
    try {
      const response = await fetch('/api/verify-purchase', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ checkout_id: id }), cache: 'no-store',
      });
      if (!response.ok) continue;
      receipt = await response.json();
    } catch { continue; }
    if (!receipt.verified || receipt.transaction_id !== id || receipt.currency !== 'USD' || !Number.isFinite(receipt.value) || receipt.value <= 0) continue;
    window.qsVerifiedPurchase = receipt;
    window.dispatchEvent(new CustomEvent('qs:verified-purchase', { detail: receipt }));
    try {
      const seen = JSON.parse(localStorage.getItem('qs_purchases') || '[]');
      if (seen.includes(id)) return;
      seen.push(id); localStorage.setItem('qs_purchases', JSON.stringify(seen.slice(-50)));
    } catch {}
    window.minilytics = window.minilytics || function () { (window.minilytics.q = window.minilytics.q || []).push(arguments); };
    window.minilytics('goal', 'purchase', { checkout_id: id, value: receipt.value, currency: receipt.currency });
    return;
  }
})();
