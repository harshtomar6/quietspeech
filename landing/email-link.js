/* Prepare a draft in the visitor's email app; this website sends no email. */
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
  document.querySelectorAll('[data-send-mac-link]').forEach(link => {
    const path = link.dataset.sendMacLink === '/compare' ? '/compare' : '/';
    const destination = new URL(path, 'https://quietspeech.app');
    keys.forEach(key => {
      if (typeof tags[key] === 'string' && tags[key]) destination.searchParams.set(key, tags[key].slice(0, 100));
    });
    if (!destination.searchParams.size) {
      destination.searchParams.set('utm_source', 'quietspeech');
      destination.searchParams.set('utm_medium', 'email');
      destination.searchParams.set('utm_campaign', 'mobile_handoff');
    }
    const content = destination.searchParams.get('utm_content');
    destination.searchParams.set('utm_content', content ? `mobile_email_${content}`.slice(0, 100) : 'mobile_email');
    const body = `Reminder to open QuietSpeech on my Mac:\r\n\r\n${destination}\r\n\r\nQuietSpeech needs an Apple silicon Mac running macOS 26 or later. Visit the page for current pricing.`;
    link.href = `mailto:?subject=${encodeURIComponent('QuietSpeech for my Mac')}&body=${encodeURIComponent(body)}`;
  });
})();
