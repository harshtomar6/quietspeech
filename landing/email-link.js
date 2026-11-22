/* Send the visitor's Mac a link to this page. Where the browser can share
   (phones and tablets), the system share sheet opens: AirDrop, Messages,
   WhatsApp, Mail and so on. Otherwise the link opens a draft in the
   visitor's email app. This website sends nothing itself. */
(() => {
  const keys = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content'];
  const current = new URLSearchParams(window.location.search);
  let tags = Object.fromEntries(keys.filter(key => current.has(key)).map(key => [key, current.get(key)]));
  if (!Object.keys(tags).length) {
    try {
      const stored = JSON.parse(localStorage.getItem('qs_utm') || 'null');
      const age = Date.now() - stored?.at;
      if (Number.isFinite(age) && age >= 0 && age < 30 * 24 * 60 * 60 * 1000) tags = stored.tags || {};
    } catch { /* The static email links remain usable without browser storage. */ }
  }

  // The product page, with the visitor's campaign tags (or our own), and
  // utm_content marking how it was handed off: mobile_email or mobile_share.
  function destination(path, medium) {
    const url = new URL(path, 'https://quietspeech.app');
    keys.forEach(key => {
      if (typeof tags[key] === 'string' && tags[key]) url.searchParams.set(key, tags[key].slice(0, 100));
    });
    if (!url.searchParams.size) {
      url.searchParams.set('utm_source', 'quietspeech');
      url.searchParams.set('utm_medium', medium);
      url.searchParams.set('utm_campaign', 'mobile_handoff');
    }
    const content = url.searchParams.get('utm_content');
    const mark = `mobile_${medium}`;
    url.searchParams.set('utm_content', content ? `${mark}_${content}`.slice(0, 100) : mark);
    return url;
  }

  const share = typeof navigator !== 'undefined' && typeof navigator.share === 'function'
    ? navigator.share.bind(navigator) : null;

  document.querySelectorAll('[data-send-mac-link]').forEach(link => {
    const path = link.dataset.sendMacLink === '/compare' ? '/compare' : '/';
    const body = `Reminder to open QuietSpeech on my Mac:\r\n\r\n${destination(path, 'email')}\r\n\r\nQuietSpeech needs an Apple silicon Mac running macOS 26 or later. Visit the page for current pricing.`;
    const mailto = `mailto:?subject=${encodeURIComponent('QuietSpeech for my Mac')}&body=${encodeURIComponent(body)}`;
    link.href = mailto;
    if (!share || typeof link.addEventListener !== 'function') return;

    const data = {
      title: 'QuietSpeech for my Mac',
      text: 'Reminder to open QuietSpeech on my Mac. It needs an Apple silicon Mac running macOS 26 or later.',
      url: String(destination(path, 'share')),
    };
    link.addEventListener('click', event => {
      event.preventDefault();
      // A dismissed sheet is the visitor's choice; anything else falls back
      // to the email draft so the button never does nothing.
      share(data).catch(error => {
        if (error?.name !== 'AbortError') window.location.href = mailto;
      });
    });
  });
})();
