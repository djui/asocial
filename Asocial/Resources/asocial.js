// Asocial's page script. Injected at document start into each tab's main frame,
// with __ASOCIAL_CONFIG__ replaced by the tab's enabled filters (see Browser.swift).
(() => {
  if (window.__asocial) return;
  window.__asocial = true;

  const config = __ASOCIAL_CONFIG__;
  const post = (message) => {
    try { window.webkit.messageHandlers.asocial.postMessage(message); } catch (_) {}
  };

  // Redirects. The sites are single-page apps, so watch history changes as well as loads.
  const redirects = config.redirects.map((r) => ({ re: new RegExp(r.pattern), target: r.target }));
  let lastPath = null;
  const route = () => {
    if (document.documentElement) document.documentElement.setAttribute('data-asocial-path', location.pathname);
    const path = location.pathname + location.search;
    if (path === lastPath) return;
    lastPath = path;
    for (const r of redirects) {
      const m = path.match(r.re);
      if (!m) continue;
      const to = r.target.replace(/\$(\d)/g, (_, i) => m[+i] || '');
      if (to !== path) {
        post({ blocked: 1 });
        location.replace(to);
      }
      return;
    }
  };
  for (const name of ['pushState', 'replaceState']) {
    const original = history[name];
    history[name] = function () {
      const result = original.apply(this, arguments);
      setTimeout(route, 0);
      return result;
    };
  }
  addEventListener('popstate', route);
  setInterval(route, 400);
  route();

  // Hidden by selector.
  if (config.selectors.length) {
    const css = config.selectors.map((s) => s + ' { display: none !important; }').join('\n');
    const addStyle = () => {
      const style = document.createElement('style');
      style.id = 'asocial';
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
    };
    if (document.documentElement) addStyle();
    else document.addEventListener('DOMContentLoaded', addStyle);
  }

  // Hidden by label: a feed item showing one of these exact texts goes.
  const labels = new Set(config.labels);
  const isSafeToHide = (el) =>
    el && el !== document.body && el !== document.documentElement &&
    el.offsetHeight < innerHeight * 1.5 &&
    !el.querySelector('[role="navigation"], nav, header, input, textarea, [contenteditable="true"]');
  const feedItem = (el) => {
    if (config.itemSelector) {
      const item = el.closest(config.itemSelector);
      if (item) return item;
    }
    // No markup to go by: climb to the first ancestor tall enough to be a post.
    let node = el;
    while (node.parentElement && node.parentElement !== document.body && node.offsetHeight < 240) node = node.parentElement;
    return node;
  };
  const sweep = () => {
    if (!labels.size || !document.body) return;
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let text = walker.nextNode(); text; text = walker.nextNode()) {
      const value = text.nodeValue;
      if (value.length > 40 || !labels.has(value.trim())) continue;
      const parent = text.parentElement;
      if (!parent || parent.closest('[data-asocial-hidden]')) continue;
      const item = feedItem(parent);
      if (!isSafeToHide(item)) continue;
      item.setAttribute('data-asocial-hidden', '');
      item.style.setProperty('display', 'none', 'important');
      post({ hidden: 1 });
    }
  };
  if (labels.size) {
    let pending = false;
    const schedule = () => {
      if (pending) return;
      pending = true;
      setTimeout(() => { pending = false; sweep(); }, 300);
    };
    const observe = () => {
      new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true, characterData: true });
      sweep();
    };
    if (document.body) observe();
    else document.addEventListener('DOMContentLoaded', observe);
  }

  for (const script of config.scripts) {
    try { new Function(script)(); } catch (error) { console.warn('asocial', error); }
  }
})();
