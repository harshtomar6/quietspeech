/* Advertising measurement is optional. No Google request before consent. */
(() => {
  'use strict';
  const KEY = 'qs_ad_consent';
  const AGE = 180 * 24 * 60 * 60 * 1000;
  let config, loaded = false, receipt;
  const pending = new Set();
  const read = () => {
    try { const x = JSON.parse(localStorage.getItem(KEY)); return x && Date.now() - x.at < AGE ? x.choice : null; }
    catch { return null; }
  };
  const save = (choice) => { try { localStorage.setItem(KEY, JSON.stringify({ choice, at: Date.now() })); } catch {} };
  const consent = (granted) => ({ ad_storage: granted ? 'granted' : 'denied', analytics_storage: 'denied', ad_user_data: granted ? 'granted' : 'denied', ad_personalization: 'denied' });
  const fire = () => {
    if (!receipt?.verified || typeof receipt.transaction_id !== 'string' ||
        !Number.isFinite(receipt.value) || receipt.value <= 0 || receipt.currency !== 'USD' ||
        !loaded || read() !== 'allow') return;
    const id = receipt.transaction_id;
    if (pending.has(id)) return;
    try { if (JSON.parse(localStorage.getItem('qs_ads_purchases') || '[]').includes(id)) return; } catch {}
    pending.add(id);
    window.gtag('event', 'conversion', {
      send_to: `${config.tag_id}/${config.purchase_label}`,
      transaction_id: id, value: receipt.value, currency: receipt.currency,
      event_callback() {
        try { const seen = JSON.parse(localStorage.getItem('qs_ads_purchases') || '[]'); seen.push(id); localStorage.setItem('qs_ads_purchases', JSON.stringify(seen.slice(-50))); } catch {}
      },
    });
  };
  const load = () => {
    if (loaded || !config || read() !== 'allow') return;
    loaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
    window.gtag('consent', 'default', consent(false));
    window.gtag('consent', 'update', consent(true));
    window.gtag('js', new Date());
    window.gtag('config', config.tag_id, { allow_google_signals: false, allow_ad_personalization_signals: false });
    const tag = document.createElement('script');
    tag.async = true;
    tag.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(config.tag_id)}`;
    document.head.append(tag);
    fire();
  };
  const style = document.createElement('style');
  style.textContent = '.qs-consent{position:fixed;z-index:10000;left:20px;right:20px;bottom:20px;max-width:680px;margin:auto;padding:20px;border:1px solid #4d6570;border-radius:14px;background:#111a22;color:#edf5fa;box-shadow:0 10px 50px #0008;font:14px/1.6 system-ui}.qs-consent p{margin:0 0 14px}.qs-consent a{color:#8ce7eb;text-decoration:underline}.qs-consent-actions{display:flex;gap:12px;flex-wrap:wrap}.qs-consent button{padding:9px 18px;border-radius:7px;border:1px solid #7ba6b2;background:#182b34;color:#fff;font:inherit;cursor:pointer}.qs-consent-settings{font:inherit;color:inherit;background:none;border:0;text-decoration:underline;cursor:pointer;padding:0}@media(min-width:681px){.qs-consent{right:auto;max-width:420px;margin:0}}';
  document.head.append(style);
  const show = () => {
    document.querySelector('.qs-consent')?.remove();
    const box = document.createElement('section');
    box.className = 'qs-consent';
    box.setAttribute('aria-label', 'Advertising measurement preference');
    box.innerHTML = '<p>Allow Google to measure which ads lead to a visit or purchase? This is optional and doesn’t affect checkout. <a href="/website-privacy">Website privacy</a></p><div class="qs-consent-actions"><button type="button" data-choice="deny">Decline</button><button type="button" data-choice="allow">Allow measurement</button></div>';
    box.addEventListener('click', (event) => {
      const choice = event.target.closest('[data-choice]')?.dataset.choice;
      if (!choice) return;
      save(choice);
      if (loaded) window.gtag('consent', 'update', consent(choice === 'allow'));
      if (choice === 'allow') { load(); fire(); }
      box.remove();
    });
    document.body.append(box);
  };
  document.addEventListener('click', (event) => {
    if (event.target.closest('[data-ad-preferences]')) { event.preventDefault(); show(); }
  });
  window.addEventListener('qs:verified-purchase', (event) => { receipt = event.detail; fire(); });
  if (window.qsVerifiedPurchase) receipt = window.qsVerifiedPurchase;
  fetch('/ads-config.json', { cache: 'no-cache' }).then((r) => r.ok ? r.json() : null).then((x) => {
    if (!/^AW-\d+$/.test(x?.tag_id) || !/^[A-Za-z0-9_-]+$/.test(x?.purchase_label)) return;
    config = x;
    if (read() === 'allow') load();
    else if (!read()) show();
  }).catch(() => {});
})();
