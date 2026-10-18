/* Storefront script (site/). Vanilla JS, no build step, no libraries, no secret.
   It talks ONLY to the public RPCs (web_site_config, web_catalog_v2, web_quote, web_checkout_submit, web_order_track,
   web_order_cancel_request, web_custom_request) and to the public-read bucket, using the publishable key in config.js.
   Page is chosen by <body data-page="...">. Text: Bangla (bn) and English (en); the choice is remembered on this device. */
(function () {
  'use strict';
  var CFG = window.SITE_CONFIG || {};
  var PAGE = document.body.getAttribute('data-page') || 'home';
  var LANG_KEY = 'site_lang', CART_KEY = 'site_cart', DEV_KEY = 'site_dev', SUB_KEY = 'site_sub', UTM_KEY = 'site_utm', CONSENT_KEY = 'site_consent';

  /* ---------- small helpers ---------- */
  function $(s, el) { return (el || document).querySelector(s); }
  function $$(s, el) { return Array.prototype.slice.call((el || document).querySelectorAll(s)); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function store(key, val) { try { if (val === undefined) { return window.localStorage.getItem(key); } window.localStorage.setItem(key, val); return val; } catch (e) { return null; } }
  function ss(key, val) { try { if (val === undefined) { return window.sessionStorage.getItem(key); } if (val === null) { window.sessionStorage.removeItem(key); return null; } window.sessionStorage.setItem(key, val); return val; } catch (e) { return null; } }
  function uuid() {
    if (window.crypto && crypto.randomUUID) { return crypto.randomUUID(); }
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) { var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); });
  }
  function lang() { return store(LANG_KEY) === 'en' ? 'en' : 'bn'; }
  function pickLang(o) { if (!o) { return ''; } if (typeof o === 'string') { return o; } return (lang() === 'en' && o.en) ? o.en : (o.bn || o.en || ''); }
  function money(n) { var v = Number(n) || 0; return '৳' + v.toLocaleString('en-US', { maximumFractionDigits: 2 }); }
  function deviceKey() { var k = store(DEV_KEY); if (!k) { k = uuid(); store(DEV_KEY, k); } return k; }
  function safeUrl(u) { return /^https:\/\//i.test(String(u || '')) ? String(u) : ''; }
  function digits(s) { return String(s || '').replace(/\D/g, ''); }

  /* ---------- text (bn / en) ---------- */
  var TX = {
    shop: { bn: 'দোকান', en: 'Shop' }, menu: { bn: 'পণ্য', en: 'Products' }, cart: { bn: 'কার্ট', en: 'Cart' }, track: { bn: 'অর্ডার ট্র্যাক', en: 'Track order' },
    custom: { bn: 'কাস্টম কেক', en: 'Custom cake' }, contact: { bn: 'যোগাযোগ', en: 'Contact' }, policy: { bn: 'নীতি', en: 'Policies' },
    add: { bn: 'কার্টে দিন', en: 'Add to cart' }, soldOut: { bn: 'শেষ', en: 'Sold out' }, limited: { bn: 'সীমিত', en: 'Limited' }, inStock: { bn: 'আছে', en: 'In stock' },
    preorder: { bn: 'প্রি-অর্ডার', en: 'Pre-order' }, total: { bn: 'মোট', en: 'Total' }, subtotal: { bn: 'পণ্য', en: 'Items' }, charge: { bn: 'ডেলিভারি', en: 'Delivery' },
    empty: { bn: 'কার্ট খালি', en: 'Your cart is empty' }, checkout: { bn: 'অর্ডার করুন', en: 'Place order' }, whatsapp: { bn: 'হোয়াটসঅ্যাপে অর্ডার', en: 'Order on WhatsApp' },
    messenger: { bn: 'মেসেঞ্জারে লিখুন', en: 'Message on Messenger' }, name: { bn: 'আপনার নাম', en: 'Your name' }, mobile: { bn: 'মোবাইল নম্বর', en: 'Mobile number' },
    pickup: { bn: 'দোকান থেকে নেব', en: 'Pick up' }, home: { bn: 'বাসায় পৌঁছে দিন', en: 'Home delivery' }, zone: { bn: 'এলাকা', en: 'Area' }, address: { bn: 'ঠিকানা', en: 'Address' },
    date: { bn: 'কবে লাগবে', en: 'When needed' }, note: { bn: 'নোট (ঐচ্ছিক)', en: 'Note (optional)' }, coupon: { bn: 'কুপন কোড (ঐচ্ছিক)', en: 'Coupon code (optional)' },
    couponHelp: { bn: 'কুপন দোকান যাচাই করে যোগ করবে।', en: 'The shop checks and applies the coupon.' },
    cod: { bn: 'ডেলিভারিতে নগদ', en: 'Cash on delivery' }, manual: { bn: 'bKash / Nagad (Trx ID লিখুন)', en: 'bKash / Nagad (enter Trx ID)' },
    trx: { bn: 'Trx ID', en: 'Trx ID' }, sendTo: { bn: 'এই নম্বরে টাকা পাঠান', en: 'Send the money to this number' },
    sent: { bn: 'অর্ডার পেয়েছি', en: 'Order received' }, keepCode: { bn: 'এই কোডটি রাখুন:', en: 'Keep this code:' },
    track2: { bn: 'অর্ডার কোড', en: 'Order code' }, find: { bn: 'খুঁজুন', en: 'Find' }, cancelAsk: { bn: 'বাতিলের অনুরোধ', en: 'Request cancellation' },
    reason: { bn: 'কারণ লিখুন', en: 'Write the reason' }, cancelSent: { bn: 'অনুরোধ পাঠানো হয়েছে। দোকান নিশ্চিত করবে।', en: 'Request sent. The shop will confirm.' },
    chooseDate: { bn: 'তারিখ বেছে নিন', en: 'Pick a date' }, flavour: { bn: 'স্বাদ', en: 'Flavour' }, weight: { bn: 'ওজন (কেজি)', en: 'Weight (kg)' },
    message: { bn: 'কেকের লেখা', en: 'Message on the cake' }, slot: { bn: 'সময়', en: 'Time slot' }, photo: { bn: 'নমুনা ছবি (ঐচ্ছিক, সর্বোচ্চ ৩ MB)', en: 'Reference photo (optional, max 3 MB)' },
    send: { bn: 'অনুরোধ পাঠান', en: 'Send request' }, uploading: { bn: 'ছবি পাঠানো হচ্ছে…', en: 'Uploading photo…' },
    closed: { bn: 'এই মুহূর্তে অর্ডার নেওয়া হচ্ছে না।', en: 'Orders are not being taken right now.' },
    offline: { bn: 'ইন্টারনেট সংযোগ নেই। আবার চেষ্টা করুন — অর্ডার নষ্ট হবে না।', en: 'No internet. Try again — the order is not lost.' },
    loading: { bn: 'লোড হচ্ছে…', en: 'Loading…' }, failed: { bn: 'হয়নি, আবার চেষ্টা করুন।', en: 'Did not work, please try again.' },
    comingSoon: { bn: 'শীঘ্রই আসছে।', en: 'Coming soon.' }, consentText: { bn: 'এই সাইট কুকি ব্যবহার করতে পারে (বিশ্লেষণের জন্য)। সম্মতি দেবেন?', en: 'This site may use cookies for analytics. Do you agree?' },
    yes: { bn: 'মেনে নিলাম', en: 'Accept' }, no: { bn: 'না', en: 'Decline' }, offNote: { bn: 'ওয়েবসাইট এখন বন্ধ।', en: 'The website is closed for now.' },
    toggle: { bn: 'English', en: 'বাংলা' }, cats: { bn: 'সব', en: 'All' }, featured: { bn: 'আজকের পছন্দ', en: 'Featured' },
    weightHint: { bn: 'যেমন ১.৫', en: 'e.g. 1.5' }, hours: { bn: 'খোলার সময়', en: 'Opening hours' }, closures: { bn: 'ছুটির দিন', en: 'Closure days' },
    orderNo: { bn: 'অর্ডার নং', en: 'Order no.' }, status: { bn: 'অবস্থা', en: 'Status' }, sendMsg: { bn: 'সাথে যোগাযোগ', en: 'Contact the shop' },
    diet: { halal: { bn: 'হালাল', en: 'Halal' }, eggless: { bn: 'ডিম ছাড়া', en: 'Eggless' }, sugar_free: { bn: 'চিনি ছাড়া', en: 'Sugar free' }, vegan: { bn: 'ভেগান', en: 'Vegan' } },
    allergen: { bn: 'উপাদান/অ্যালার্জেন', en: 'Ingredients / allergens' }, freeText: { bn: 'আপনার কাছে কিছু জানার থাকলে লিখুন।', en: 'Write to us if you have a question.' },
    notFound: { bn: 'এই কোড ও মোবাইল মেলেনি।', en: 'No order matches this code and mobile.' },
  };
  var ERR = {
    off: 'offNote', orders_closed: 'closed', closed_today: 'closed', customer_name_required: 'name', bad_mobile: 'mobile', address_required: 'address',
    zone_required: 'zone', below_zone_min: 'minorder', below_min_order: 'minorder', trx_required: 'trx', pay_off: 'failed', bad_date: 'date', too_soon: 'toosoon',
    cutoff_passed: 'cutoff', sold_out: 'soldout', rate_limited: 'ratelimit', captcha_required: 'failed', item_unavailable: 'soldout', bad_qty: 'failed',
    pickup_point_unavailable: 'failed', date_required: 'date', bad_mode: 'failed', too_long: 'failed', no_lines: 'empty', bad_pay: 'failed',
  };
  var ERRTX = {
    name: { bn: 'আপনার নাম লিখুন।', en: 'Enter your name.' }, mobile: { bn: 'সঠিক মোবাইল নম্বর লিখুন।', en: 'Enter a valid mobile number.' },
    address: { bn: 'ডেলিভারির ঠিকানা লিখুন।', en: 'Enter the delivery address.' }, date: { bn: 'তারিখ ঠিক নেই; আবার বেছে নিন।', en: 'The date is not valid; pick it again.' },
    closed: { bn: 'এই মুহূর্তে অর্ডার নেওয়া হচ্ছে না।', en: 'Orders are not being taken right now.' }, offNote: { bn: 'ওয়েবসাইট এখন বন্ধ।', en: 'The website is closed for now.' },
    minorder: { bn: 'সর্বনিম্ন অর্ডার পূরণ হয়নি।', en: 'Below the minimum order.' }, trx: { bn: 'bKash/Nagad Trx ID লিখুন।', en: 'Enter the bKash/Nagad Trx ID.' },
    toosoon: { bn: 'এত তাড়াতাড়ি দেওয়া যাবে না — একটু পরের তারিখ বেছে নিন।', en: 'Too soon — pick a later date.' }, cutoff: { bn: 'আজকের জন্য সময় শেষ হয়ে গেছে।', en: 'Today\'s cut-off has passed.' },
    soldout: { bn: 'কিছু পণ্য শেষ হয়ে গেছে। কার্ট দেখুন।', en: 'Some items are sold out. Check your cart.' }, ratelimit: { bn: 'অনেকবার চেষ্টা হয়েছে; কিছুক্ষণ পরে আবার।', en: 'Too many tries; wait a while.' },
    zone: { bn: 'আপনার এলাকা বেছে নিন।', en: 'Choose your area.' }, empty: { bn: 'কার্ট খালি।', en: 'The cart is empty.' }, failed: { bn: 'হয়নি, আবার চেষ্টা করুন।', en: 'Did not work, try again.' },
  };
  function tx(k) { var v = TX[k]; return v ? pickLang(v) : k; }
  function errTx(code) { var k = ERR[code]; if (!k) { return tx('failed'); } return ERRTX[k] ? pickLang(ERRTX[k]) : tx(k); }

  /* ---------- API (public RPCs only) ---------- */
  function rpc(name, args) {
    if (!CFG.url || !CFG.key) { return Promise.reject(new Error('config')); }
    return fetch(CFG.url.replace(/\/$/, '') + '/rest/v1/rpc/' + name, {
      method: 'POST', headers: { 'apikey': CFG.key, 'Authorization': 'Bearer ' + CFG.key, 'Content-Type': 'application/json' },
      body: JSON.stringify(args || {}), credentials: 'omit', cache: 'no-store',
    }).then(function (r) { if (!r.ok) { throw new Error('http ' + r.status); } return r.json(); });
  }
  function publicUrl(path) { return CFG.url.replace(/\/$/, '') + '/storage/v1/object/public/' + path; }

  /* ---------- cart (this device only; the server re-prices every time) ---------- */
  function cartGet() { try { var v = JSON.parse(store(CART_KEY) || '[]'); return Array.isArray(v) ? v.filter(function (x) { return x && x.id && x.qty > 0; }) : []; } catch (e) { return []; } }
  function cartSet(list) { store(CART_KEY, JSON.stringify(list.slice(0, 100))); updateCartBadge(); }
  function cartAdd(id, qty) { var c = cartGet(); var f = c.filter(function (x) { return x.id === id; })[0]; if (f) { f.qty = Math.min(1000, f.qty + qty); } else { c.push({ id: id, qty: qty }); } cartSet(c); }
  function cartQty(id, qty) { var c = cartGet().filter(function (x) { return x.id !== id; }); if (qty > 0) { c.push({ id: id, qty: Math.min(1000, qty) }); } cartSet(c); }
  function cartCount() { return cartGet().reduce(function (n, x) { return n + (Number(x.qty) || 0); }, 0); }
  function updateCartBadge() { $$('[data-cartcount]').forEach(function (el) { el.textContent = String(cartCount()); }); }

  /* ---------- shared chrome ---------- */
  var NAV = [['index.html', 'shop'], ['catalogue.html', 'menu'], ['cart.html', 'cart'], ['track.html', 'track'], ['custom-cake.html', 'custom'], ['contact.html', 'contact'], ['policies.html', 'policy']];
  function header(cfg) {
    var brand = pickLang(cfg && cfg.brand) || (CFG.brand || 'Shop');
    var links = NAV.filter(function (n) { return n[0] !== 'custom-cake.html' || !(cfg && cfg.custom_cake === false); }).map(function (n) {
      return '<a href="' + n[0] + '"' + (PAGE === n[1] ? ' aria-current="page"' : '') + '>' + esc(tx(n[1])) + (n[1] === 'cart' ? ' (<span data-cartcount>0</span>)' : '') + '</a>';
    }).join('');
    $('#hdr').innerHTML = '<header class="top"><a class="brand" href="index.html">' + esc(brand) + '</a>' +
      '<button type="button" class="linkbtn" id="langbtn">' + esc(tx('toggle')) + '</button>' +
      '<nav aria-label="menu" class="nav">' + links + '</nav></header>';
    var lb = $('#langbtn'); if (lb) { lb.addEventListener('click', function () { store(LANG_KEY, lang() === 'en' ? 'bn' : 'en'); window.location.reload(); }); }
    updateCartBadge();
  }
  function footer(cfg) {
    var wa = cfg && cfg.whatsapp ? '<a href="' + waLink(cfg, '') + '" rel="noopener">' + esc(tx('whatsapp')) + '</a> · ' : '';
    var fb = cfg && safeUrl(cfg.messenger) ? '<a href="' + esc(safeUrl(cfg.messenger)) + '" rel="noopener">' + esc(tx('messenger')) + '</a> · ' : '';
    $('#ftr').innerHTML = '<footer class="foot"><p>' + wa + fb + '<a href="policies.html">' + esc(tx('policy')) + '</a></p><p class="muted">© ' + new Date().getFullYear() + ' ' + esc(pickLang(cfg && cfg.brand) || '') + '</p></footer>';
  }
  function waLink(cfg, text) { var n = digits(cfg && cfg.whatsapp); return n ? 'https://wa.me/' + n + (text ? '?text=' + encodeURIComponent(text) : '') : ''; }
  function banner(cfg) {
    var parts = [];
    if (cfg && cfg.closed_today) { parts.push(tx('closed')); }
    var h = cfg && cfg.holiday ? pickLang(cfg.holiday) : ''; if (h) { parts.push(h); }
    if (!parts.length) { return ''; }
    return '<div class="notice" role="status">' + parts.map(esc).join(' · ') + '</div>';
  }
  function consentBanner() {
    if (store(CONSENT_KEY) !== null) { return; }
    var d = document.createElement('div'); d.className = 'consent'; d.setAttribute('role', 'dialog'); d.setAttribute('aria-label', 'cookies');
    d.innerHTML = '<p>' + esc(tx('consentText')) + '</p><div class="row"><button type="button" class="primary" data-c="yes">' + esc(tx('yes')) + '</button> <button type="button" data-c="no">' + esc(tx('no')) + '</button></div>';
    document.body.appendChild(d);
    d.addEventListener('click', function (e) { var c = e.target.getAttribute && e.target.getAttribute('data-c'); if (!c) { return; } store(CONSENT_KEY, c); d.remove(); if (c === 'yes') { loadAnalytics(); } });
  }
  function loadAnalytics() {   // only when the owner set an id AND the visitor accepted
    if (store(CONSENT_KEY) !== 'yes' || !window.SITE_CONFIG_LIVE) { return; }
    var a = window.SITE_CONFIG_LIVE.analytics || {};
    var pid = /^[0-9]{6,20}$/.test(String(a.pixel_id || '')) ? String(a.pixel_id) : '';
    var gid = /^G-[A-Z0-9]{4,20}$/.test(String(a.ga_id || '')) ? String(a.ga_id) : '';
    if (pid && !window.fbq) {
      var s = document.createElement('script');
      s.textContent = '!function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?n.callMethod.apply(n,arguments):n.queue.push(arguments)};if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version="2.0";n.queue=[];t=b.createElement(e);t.async=!0;t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,document,"script","https://connect.facebook.net/en_US/fbevents.js");fbq("init","' + pid + '");fbq("track","PageView");';
      document.head.appendChild(s);
    }
    if (gid && !window.gtag) {
      var g = document.createElement('script'); g.async = true; g.src = 'https://www.googletagmanager.com/gtag/js?id=' + gid; document.head.appendChild(g);
      var c = document.createElement('script'); c.textContent = 'window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments);}gtag("js",new Date());gtag("config","' + gid + '");'; document.head.appendChild(c);
    }
  }
  function captureUtm() {   // campaign links (?utm_source=...) are kept for this visit and sent with the order
    var q = new URLSearchParams(window.location.search); var u = {};
    ['source', 'medium', 'campaign'].forEach(function (k) { var v = q.get('utm_' + k); if (v) { u[k] = String(v).replace(/[^A-Za-z0-9_\-. ]/g, '').slice(0, 40); } });
    if (Object.keys(u).length) { ss(UTM_KEY, JSON.stringify(u)); }
    var raw = ss(UTM_KEY); try { return raw ? JSON.parse(raw) : {}; } catch (e) { return {}; }
  }
  function setSchema(obj) { var s = document.getElementById('jsonld'); if (!s) { s = document.createElement('script'); s.type = 'application/ld+json'; s.id = 'jsonld'; document.head.appendChild(s); } s.textContent = JSON.stringify(obj); }

  /* ---------- catalogue rendering ---------- */
  function availTx(a) { return { in_stock: tx('inStock'), limited: tx('limited'), sold_out: tx('soldOut'), preorder: tx('preorder') }[a] || ''; }
  function itemName(i) { return pickLang({ bn: i.name_bn, en: i.name_en }); }
  function imgUrl(path) { return path ? publicUrl('web-public/' + path) : ''; }
  function card(i) {
    var out = i.availability === 'sold_out';
    var img = i.images && i.images[0] ? '<img src="' + esc(imgUrl(i.images[0])) + '" alt="' + esc(itemName(i)) + '" loading="lazy" width="320" height="240">' : '<div class="ph" aria-hidden="true"></div>';
    var tags = (i.diet || []).map(function (d) { return '<span class="tag">' + esc(pickLang((TX.diet[d]) || d)) + '</span>'; }).join('');
    return '<article class="card item"><a href="product.html?id=' + esc(i.id) + '">' + img + '<h3>' + esc(itemName(i)) + '</h3></a>' +
      '<p class="price">' + money(i.price) + (i.unit ? ' / ' + esc(i.unit) : '') + ' <span class="av av-' + esc(i.availability) + '">' + esc(availTx(i.availability)) + '</span></p>' +
      '<div class="tags">' + tags + '</div>' +
      (out ? '<button type="button" disabled>' + esc(tx('soldOut')) + '</button>' :
        '<button type="button" class="primary" data-add="' + esc(i.id) + '">' + esc(tx('add')) + '</button>') + '</article>';
  }
  function bindAdd(root) {
    $$('[data-add]', root).forEach(function (b) {
      b.addEventListener('click', function () { cartAdd(b.getAttribute('data-add'), 1); b.textContent = '✓'; setTimeout(function () { b.textContent = tx('add'); }, 900); });
    });
  }
  function loadCatalogue(cat) { return rpc('web_catalog_v2', { p_category: cat || null }).then(function (d) { return d || { items: [] }; }); }

  /* ---------- pages ---------- */
  var cfgLive = null;
  function boot() {
    document.documentElement.lang = lang();
    captureUtm();
    rpc('web_site_config', {}).then(function (cfg) {
      cfgLive = cfg; window.SITE_CONFIG_LIVE = cfg;
      header(cfg); footer(cfg);
      var main = $('#main');
      if (!cfg || !cfg.on) { main.innerHTML = '<div class="notice">' + esc(tx('offNote')) + '</div>'; consentBanner(); return; }
      var page = pages[PAGE] || pages.home; page(cfg, main);
      consentBanner(); loadAnalytics();
    }).catch(function () {
      header(null); footer(null);
      $('#main').innerHTML = '<div class="notice bad" role="alert">' + esc(tx(navigator.onLine ? 'failed' : 'offline')) + '</div>';
    });
    if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1')) {
      navigator.serviceWorker.register('sw.js').catch(function () {});
    }
  }
  var pages = {};
  pages.home = function (cfg, main) {
    main.innerHTML = banner(cfg) + '<section class="hero"><h1>' + esc(pickLang(cfg.brand) || '') + '</h1><p>' + esc(tx('freeText')) + '</p>' +
      '<p><a class="btn primary" href="catalogue.html">' + esc(tx('menu')) + '</a> ' + (cfg.custom_cake ? '<a class="btn" href="custom-cake.html">' + esc(tx('custom')) + '</a>' : '') + '</p></section>' +
      '<h2>' + esc(tx('featured')) + '</h2><div class="grid" id="feat"><p class="muted">' + esc(tx('loading')) + '</p></div>';
    loadCatalogue().then(function (d) {
      var items = (d.items || []).slice(0, 6);
      $('#feat').innerHTML = items.length ? items.map(card).join('') : '<p class="muted">' + esc(tx('comingSoon')) + '</p>';
      bindAdd($('#feat'));
    }).catch(function () { $('#feat').innerHTML = '<p class="muted">' + esc(tx('failed')) + '</p>'; });
  };
  pages.catalogue = function (cfg, main) {
    main.innerHTML = banner(cfg) + '<h1>' + esc(tx('menu')) + '</h1><div id="cats" class="chips"></div><div class="grid" id="list"><p class="muted">' + esc(tx('loading')) + '</p></div>';
    var cur = '';
    function show(d) {
      var items = d.items || [];
      var cats = []; items.forEach(function (i) { if (cats.indexOf(i.category) < 0) { cats.push(i.category); } });
      $('#cats').innerHTML = [''].concat(cats).map(function (c) { return '<button type="button" class="chip' + (c === cur ? ' on' : '') + '" data-cat="' + esc(c) + '">' + esc(c ? c.replace(/_/g, ' ') : tx('cats')) + '</button>'; }).join('');
      $$('[data-cat]', $('#cats')).forEach(function (b) { b.addEventListener('click', function () { cur = b.getAttribute('data-cat'); load(); }); });
      var shown = cur ? items.filter(function (i) { return i.category === cur; }) : items;
      $('#list').innerHTML = shown.length ? shown.map(card).join('') : '<p class="muted">' + esc(tx('comingSoon')) + '</p>';
      bindAdd($('#list'));
    }
    function load() { loadCatalogue().then(show).catch(function () { $('#list').innerHTML = '<p class="muted">' + esc(tx('failed')) + '</p>'; }); }
    load();
  };
  pages.product = function (cfg, main) {
    var id = new URLSearchParams(location.search).get('id') || '';
    if (!/^[0-9a-f-]{36}$/i.test(id)) { main.innerHTML = '<p class="muted">' + esc(tx('comingSoon')) + '</p>'; return; }
    main.innerHTML = '<p class="muted">' + esc(tx('loading')) + '</p>';
    loadCatalogue().then(function (d) {
      var i = (d.items || []).filter(function (x) { return x.id === id; })[0];
      if (!i) { main.innerHTML = '<p class="muted">' + esc(tx('comingSoon')) + '</p>'; return; }
      var name = itemName(i), desc = pickLang({ bn: i.description_bn, en: i.description_en });
      var img = i.images && i.images[0] ? '<img class="big" src="' + esc(imgUrl(i.images[0])) + '" alt="' + esc(name) + '" width="640" height="480">' : '';
      var tags = (i.diet || []).map(function (x) { return '<span class="tag">' + esc(pickLang(TX.diet[x] || x)) + '</span>'; }).join('');
      document.title = name + ' · ' + (pickLang(cfg.brand) || '');
      var meta = document.querySelector('meta[name="description"]'); if (meta) { meta.setAttribute('content', (desc || name).slice(0, 160)); }
      setSchema({ '@context': 'https://schema.org', '@type': 'Product', name: name, description: desc || name, image: i.images && i.images[0] ? [imgUrl(i.images[0])] : undefined,
        offers: { '@type': 'Offer', priceCurrency: 'BDT', price: Number(i.price) || 0, availability: i.availability === 'sold_out' ? 'https://schema.org/SoldOut' : i.availability === 'preorder' ? 'https://schema.org/PreOrder' : 'https://schema.org/InStock' } });
      main.innerHTML = img + '<h1>' + esc(name) + '</h1><p class="price">' + money(i.price) + (i.unit ? ' / ' + esc(i.unit) : '') + ' <span class="av av-' + esc(i.availability) + '">' + esc(availTx(i.availability)) + '</span></p>' +
        (desc ? '<p>' + esc(desc) + '</p>' : '') + (i.allergens ? '<p class="muted">' + esc(tx('allergen')) + ': ' + esc(i.allergens) + '</p>' : '') + '<div class="tags">' + tags + '</div>' +
        (i.availability === 'sold_out' ? '' : '<div class="row"><label class="qty">Qty <input id="pq" type="number" min="1" max="1000" value="1"></label><button type="button" class="primary" id="padd">' + esc(tx('add')) + '</button> ' +
          '<button type="button" id="pshare">' + esc(lang() === 'en' ? 'Share' : 'শেয়ার') + '</button></div>');
      var add = $('#padd'); if (add) { add.addEventListener('click', function () { cartAdd(i.id, Math.max(1, Math.min(1000, Math.floor(Number($('#pq').value) || 1)))); add.textContent = '✓ ' + tx('cart'); }); }
      var sh = $('#pshare'); if (sh) { sh.addEventListener('click', function () { var u = location.href; if (navigator.share) { navigator.share({ title: name, url: u }).catch(function () {}); } else if (navigator.clipboard) { navigator.clipboard.writeText(u); } }); }
    }).catch(function () { main.innerHTML = '<p class="muted">' + esc(tx('failed')) + '</p>'; });
  };
  pages.cart = function (cfg, main) {
    main.innerHTML = '<h1>' + esc(tx('cart')) + '</h1><div id="cart"><p class="muted">' + esc(tx('loading')) + '</p></div>';
    var lines = cartGet();
    if (!lines.length) { $('#cart').innerHTML = '<p class="muted">' + esc(tx('empty')) + '</p><p><a class="btn" href="catalogue.html">' + esc(tx('menu')) + '</a></p>'; return; }
    loadCatalogue().then(function (d) {
      var byId = {}; (d.items || []).forEach(function (i) { byId[i.id] = i; });
      var known = lines.filter(function (l) { return byId[l.id]; });
      if (known.length !== lines.length) { cartSet(known); lines = known; }
      if (!lines.length) { $('#cart').innerHTML = '<p class="muted">' + esc(tx('empty')) + '</p>'; return; }
      $('#cart').innerHTML = lines.map(function (l) { var i = byId[l.id]; return '<div class="row between line" data-id="' + esc(l.id) + '"><span>' + esc(itemName(i)) + '</span>' +
        '<span><input class="qin" type="number" min="1" max="1000" value="' + esc(l.qty) + '" aria-label="Qty"> × ' + money(i.price) + '</span><button type="button" data-rm="' + esc(l.id) + '">✕</button></div>'; }).join('') +
        '<div class="card stack" id="quote"></div>' +
        '<p><a class="btn primary" href="checkout.html">' + esc(tx('checkout')) + '</a> ' + (waLink(cfg, '') ? '<a class="btn" id="waorder" href="#">' + esc(tx('whatsapp')) + '</a>' : '') + '</p>';
      $$('.qin', $('#cart')).forEach(function (inp) { inp.addEventListener('change', function () { cartQty(inp.closest('.line').getAttribute('data-id'), Math.floor(Number(inp.value) || 0)); window.location.reload(); }); });
      $$('[data-rm]', $('#cart')).forEach(function (b) { b.addEventListener('click', function () { cartQty(b.getAttribute('data-rm'), 0); window.location.reload(); }); });
      var wa = $('#waorder'); if (wa) { wa.addEventListener('click', function (e) { e.preventDefault(); var txt = lines.map(function (l) { return itemName(byId[l.id]) + ' x ' + l.qty; }).join('\n'); window.open(waLink(cfg, txt), '_blank', 'noopener'); }); }
      return rpc('web_quote', { p_lines: lines.map(function (l) { return { item_id: l.id, qty: l.qty }; }), p_zone: null, p_mode: 'pickup' }).then(function (q) {
        var box = $('#quote');
        if (!q || !q.ok) { box.innerHTML = '<p class="notice bad">' + esc(errTx(q && q.error)) + '</p>'; return; }
        box.innerHTML = '<div class="row between"><span>' + esc(tx('subtotal')) + '</span><span>' + money(q.subtotal) + '</span></div>' +
          '<p class="muted">' + esc(tx('charge')) + ': ' + esc(tx('home')) + ' · ' + esc(tx('zone')) + '</p>';
      });
    }).catch(function () { $('#cart').innerHTML = '<p class="muted">' + esc(tx('failed')) + '</p>'; });
  };
  pages.checkout = function (cfg, main) {
    if (!cartGet().length) { main.innerHTML = '<p class="muted">' + esc(tx('empty')) + '</p><p><a class="btn" href="catalogue.html">' + esc(tx('menu')) + '</a></p>'; return; }
    var today = new Date(Date.now() + 6 * 3600 * 1000).toISOString().slice(0, 10);
    var zones = cfg.zones || [], pick = cfg.pickup || [], pay = cfg.payments || {};
    var sub = ss('site_sub') || uuid(); ss('site_sub', sub);
    var zoneOpts = zones.map(function (z) { return '<option value="' + esc(z.id) + '">' + esc(pickLang({ bn: z.name_bn, en: z.name_en })) + ' (+' + money(z.charge) + ')</option>'; }).join('');
    var pickOpts = pick.map(function (p) { return '<option value="' + esc(p.id) + '">' + esc(pickLang({ bn: p.name_bn, en: p.name_en })) + '</option>'; }).join('');
    var payRows = (pay.cod ? '<label class="row"><input type="radio" name="pay" value="cod" checked> ' + esc(tx('cod')) + '</label>' : '') +
      (pay.manual ? '<label class="row"><input type="radio" name="pay" value="manual"' + (pay.cod ? '' : ' checked') + '> ' + esc(tx('manual')) + '</label>' +
        '<p class="muted">' + esc(tx('sendTo')) + ': <b>' + esc(pay.manual_number || '') + '</b></p><label>' + esc(tx('trx')) + '<input name="trx" autocomplete="off"></label>' : '');
    main.innerHTML = '<h1>' + esc(tx('checkout')) + '</h1><div id="sum" class="card stack"><p class="muted">' + esc(tx('loading')) + '</p></div>' +
      '<form id="ck" class="stack" novalidate>' +
      '<label>' + esc(tx('name')) + '<input name="name" required maxlength="80" autocomplete="name"></label>' +
      '<label>' + esc(tx('mobile')) + '<input name="mobile" required inputmode="tel" maxlength="20" autocomplete="tel"></label>' +
      '<fieldset><legend>' + esc(tx('date')) + '</legend><input name="date" type="date" min="' + today + '" value="' + today + '" required></fieldset>' +
      '<fieldset><legend>' + esc(tx('pickup')) + ' / ' + esc(tx('home')) + '</legend>' +
      '<label class="row"><input type="radio" name="mode" value="pickup" checked> ' + esc(tx('pickup')) + '</label>' +
      (pick.length > 1 ? '<label>' + esc(tx('pickup')) + '<select name="pickup">' + pickOpts + '</select></label>' : '') +
      (zones.length ? '<label class="row"><input type="radio" name="mode" value="home"> ' + esc(tx('home')) + '</label>' +
        '<label>' + esc(tx('zone')) + '<select name="zone"><option value="">—</option>' + zoneOpts + '</select></label>' +
        '<label>' + esc(tx('address')) + '<textarea name="address" rows="2" maxlength="300"></textarea></label>' : '') + '</fieldset>' +
      '<fieldset><legend>Payment</legend>' + (payRows || '<p class="muted">—</p>') + '</fieldset>' +
      '<label>' + esc(tx('note')) + '<textarea name="note" rows="2" maxlength="300"></textarea></label>' +
      '<label>' + esc(tx('coupon')) + '<input name="coupon" maxlength="30" autocomplete="off"></label><p class="muted">' + esc(tx('couponHelp')) + '</p>' +
      '<p id="ckmsg" role="status"></p><button type="submit" class="primary" id="cksend">' + esc(tx('checkout')) + '</button></form>';
    loadCatalogue().then(function (d) {
      var byId = {}; (d.items || []).forEach(function (i) { byId[i.id] = i; });
      var lines = cartGet().filter(function (l) { return byId[l.id]; });
      $('#sum').innerHTML = lines.map(function (l) { return '<div class="row between"><span>' + esc(itemName(byId[l.id])) + ' × ' + l.qty + '</span><span>' + money(byId[l.id].price * l.qty) + '</span></div>'; }).join('') || '<p class="muted">' + esc(tx('empty')) + '</p>';
      var f = $('#ck'); var msgEl = $('#ckmsg');
      f.addEventListener('submit', function (e) {
        e.preventDefault(); msgEl.textContent = '';
        var fd = new FormData(f); var mode = fd.get('mode') || 'pickup';
        var lines2 = cartGet().map(function (l) { return { item_id: l.id, qty: l.qty }; });
        var pay2 = fd.get('pay') || (pay.cod ? 'cod' : 'manual');
        var args = { p_submission: sub, p_name: String(fd.get('name') || ''), p_mobile: String(fd.get('mobile') || ''), p_mode: mode,
          p_zone: mode === 'home' && fd.get('zone') ? Number(fd.get('zone')) : null, p_address: mode === 'home' ? String(fd.get('address') || '') : null,
          p_lines: lines2, p_note: [String(fd.get('note') || ''), fd.get('coupon') ? 'coupon: ' + String(fd.get('coupon')) : ''].filter(Boolean).join(' | ') || null,
          p_pay: pay2, p_trx: pay2 === 'manual' ? String(fd.get('trx') || '') : null, p_delivery_date: String(fd.get('date') || ''),
          p_pickup_loc: mode === 'pickup' && fd.get('pickup') ? Number(fd.get('pickup')) : null, p_utm: captureUtm(), p_key_hash: deviceKey() };
        if (!lines2.length) { msgEl.textContent = errTx('empty'); return; }
        var btn = $('#cksend'); btn.disabled = true;
        rpc('web_checkout_submit', args).then(function (r) {
          if (r && r.ok) {
            cartSet([]); ss('site_sub', null);
            ss('site_last', JSON.stringify({ code: r.web_code, no: r.order_no, total: r.total }));
            window.location.href = 'confirm.html?code=' + encodeURIComponent(r.web_code || '');
            return;
          }
          msgEl.className = 'notice bad'; msgEl.textContent = errTx(r && r.error);
          btn.disabled = false;
        }).catch(function () { msgEl.className = 'notice bad'; msgEl.textContent = tx(navigator.onLine ? 'failed' : 'offline'); btn.disabled = false; });
      });
    }).catch(function () { $('#sum').innerHTML = '<p class="muted">' + esc(tx('failed')) + '</p>'; });
  };
  pages.confirm = function (cfg, main) {
    var code = new URLSearchParams(location.search).get('code') || '';
    var last = {}; try { last = JSON.parse(ss('site_last') || '{}'); } catch (e) { last = {}; }
    main.innerHTML = '<h1>' + esc(tx('sent')) + '</h1><div class="card stack"><p>' + esc(tx('keepCode')) + ' <b>' + esc(code || last.code || '') + '</b></p>' +
      (last.no ? '<p>' + esc(tx('orderNo')) + ': ' + esc(String(last.no)) + '</p>' : '') + '<p><a class="btn" href="track.html?code=' + encodeURIComponent(code || last.code || '') + '">' + esc(tx('track')) + '</a></p></div>';
  };
  pages.track = function (cfg, main) {
    var q = new URLSearchParams(location.search);
    main.innerHTML = '<h1>' + esc(tx('track')) + '</h1><form id="tf" class="stack"><label>' + esc(tx('track2')) + '<input name="code" value="' + esc(q.get('code') || '') + '" autocomplete="off" required maxlength="12"></label>' +
      '<label>' + esc(tx('mobile')) + '<input name="mobile" inputmode="tel" autocomplete="tel" required maxlength="20"></label><button class="primary" type="submit">' + esc(tx('find')) + '</button></form><div id="tr" class="stack"></div>';
    function show(code, mobile) {
      $('#tr').innerHTML = '<p class="muted">' + esc(tx('loading')) + '</p>';
      rpc('web_order_track', { p_code: code, p_mobile: mobile }).then(function (r) {
        if (!r || !r.ok) { $('#tr').innerHTML = '<p class="notice bad">' + esc(r && r.error === 'off' ? tx('offNote') : tx('notFound')) + '</p>'; return; }
        var lbl = { new: { bn: 'নতুন', en: 'Received' }, confirmed: { bn: 'নিশ্চিত', en: 'Confirmed' }, packed: { bn: 'প্যাক হয়েছে', en: 'Packed' }, delivered: { bn: 'দেওয়া হয়েছে', en: 'Delivered' }, cancelled: { bn: 'বাতিল', en: 'Cancelled' } };
        $('#tr').innerHTML = '<div class="card stack"><p><b>' + esc(tx('status')) + ':</b> ' + esc(pickLang(lbl[r.status] || { bn: r.status, en: r.status })) + '</p>' +
          '<p>' + esc(tx('orderNo')) + ' ' + esc(String(r.order_no)) + ' · ' + esc(tx('total')) + ' ' + money(r.total) + '</p>' +
          (r.delivery_date ? '<p class="muted">' + esc(String(r.delivery_date)) + '</p>' : '') +
          (r.cancel_requested ? '<p class="notice">' + esc(tx('cancelSent')) + '</p>' : '') +
          (r.can_request_cancel ? '<form id="cf" class="stack"><label>' + esc(tx('reason')) + '<input name="reason" required maxlength="300"></label><button type="submit">' + esc(tx('cancelAsk')) + '</button></form>' : '') +
          '</div>';
        var cf = $('#cf'); if (cf) { cf.addEventListener('submit', function (e) { e.preventDefault(); rpc('web_order_cancel_request', { p_code: code, p_mobile: mobile, p_reason: String(new FormData(cf).get('reason') || ''), p_key_hash: deviceKey() }).then(function () { show(code, mobile); }).catch(function () {}); }); }
      }).catch(function () { $('#tr').innerHTML = '<p class="notice bad">' + esc(tx(navigator.onLine ? 'failed' : 'offline')) + '</p>'; });
    }
    $('#tf').addEventListener('submit', function (e) { e.preventDefault(); var fd = new FormData(e.target); show(String(fd.get('code') || '').trim().toUpperCase(), String(fd.get('mobile') || '')); });
  };
  pages['custom-cake'] = function (cfg, main) {
    if (!cfg.custom_cake) { main.innerHTML = '<div class="notice">' + esc(tx('comingSoon')) + '</div>'; return; }
    var tomorrow = new Date(Date.now() + 6 * 3600 * 1000 + 86400000).toISOString().slice(0, 10);
    main.innerHTML = '<h1>' + esc(tx('custom')) + '</h1><form id="cc" class="stack" novalidate>' +
      '<label>' + esc(tx('name')) + '<input name="name" required maxlength="80"></label><label>' + esc(tx('mobile')) + '<input name="mobile" inputmode="tel" required maxlength="20"></label>' +
      '<label>' + esc(tx('flavour')) + '<input name="flavour" maxlength="80"></label><label>' + esc(tx('weight')) + '<input name="weight" inputmode="decimal" placeholder="' + esc(tx('weightHint')) + '"></label>' +
      '<label>' + esc(tx('message')) + '<input name="message" maxlength="200"></label>' +
      '<label>' + esc(tx('date')) + '<input name="wanted" type="date" min="' + tomorrow + '" required></label><label>' + esc(tx('slot')) + '<input name="slot" maxlength="40"></label>' +
      '<label>' + esc(tx('photo')) + '<input name="photo" type="file" accept="image/jpeg,image/png,image/webp"></label><p id="ccmsg" role="status"></p><button class="primary" type="submit">' + esc(tx('send')) + '</button></form>';
    var submission = uuid();
    $('#cc').addEventListener('submit', function (e) {
      e.preventDefault(); var f = e.target, msgEl = $('#ccmsg'); msgEl.className = ''; msgEl.textContent = '';
      var fd = new FormData(f), file = f.photo.files[0] || null;
      if (file && (file.size > 3 * 1024 * 1024 || ['image/jpeg', 'image/png', 'image/webp'].indexOf(file.type) < 0)) { msgEl.className = 'notice bad'; msgEl.textContent = tx('photo'); return; }
      var ext = file ? ({ 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' })[file.type] : '';
      var path = file ? submission + '/' + Date.now() + '.' + ext : null;
      function send(refPath) {
        return rpc('web_custom_request', { p_submission: submission, p_name: String(fd.get('name') || ''), p_mobile: String(fd.get('mobile') || ''), p_flavour: String(fd.get('flavour') || ''),
          p_weight: Number(String(fd.get('weight') || '').replace(',', '.')) || null, p_message: String(fd.get('message') || ''), p_wanted: String(fd.get('wanted') || ''),
          p_slot: String(fd.get('slot') || ''), p_ref_path: refPath, p_key_hash: deviceKey() });
      }
      function upload(attempt) {   // the photo goes to the PRIVATE bucket; up to 3 tries with a short pause
        msgEl.textContent = tx('uploading');
        return fetch(CFG.url.replace(/\/$/, '') + '/storage/v1/object/web-refs/' + path, { method: 'POST', body: file,
          headers: { 'apikey': CFG.key, 'Authorization': 'Bearer ' + CFG.key, 'Content-Type': file.type, 'x-upsert': 'false' } })
          .then(function (r) { if (!r.ok) { throw new Error('upload ' + r.status); } return path; })
          .catch(function (err) { if (attempt >= 3) { throw err; } return new Promise(function (res) { setTimeout(res, 800 * attempt); }).then(function () { return upload(attempt + 1); }); });
      }
      (file ? upload(1) : Promise.resolve(null)).then(send).then(function (r) {
        if (r && r.ok) { msgEl.className = 'notice'; msgEl.textContent = tx('sent') + ' · ' + (r.code || ''); f.reset(); submission = uuid(); return; }
        msgEl.className = 'notice bad'; msgEl.textContent = errTx(r && r.error);
      }).catch(function () { msgEl.className = 'notice bad'; msgEl.textContent = tx(navigator.onLine ? 'failed' : 'offline'); });
    });
  };
  pages.contact = function (cfg, main) {
    var hrs = (cfg.pickup || []).map(function (p) { return '<div class="card"><b>' + esc(pickLang({ bn: p.name_bn, en: p.name_en })) + '</b><p class="muted">' + esc(pickLang({ bn: p.hours_bn, en: p.hours_en })) + '</p>' + (p.address ? '<p>' + esc(p.address) + '</p>' : '') + '</div>'; }).join('');
    var cl = (cfg.closures || []).map(function (c) { return '<li>' + esc(String(c.day)) + ' ' + esc(pickLang({ bn: c.bn, en: c.en })) + '</li>'; }).join('');
    main.innerHTML = banner(cfg) + '<h1>' + esc(tx('contact')) + '</h1><p>' + esc(tx('freeText')) + '</p>' +
      (cfg.whatsapp ? '<p><a class="btn primary" href="' + esc(waLink(cfg, '')) + '" rel="noopener">' + esc(tx('whatsapp')) + '</a></p>' : '') +
      (safeUrl(cfg.messenger) ? '<p><a class="btn" href="' + esc(safeUrl(cfg.messenger)) + '" rel="noopener">' + esc(tx('messenger')) + '</a></p>' : '') +
      '<h2>' + esc(tx('hours')) + '</h2>' + (hrs || '<p class="muted">—</p>') + (cl ? '<h2>' + esc(tx('closures')) + '</h2><ul>' + cl + '</ul>' : '');
  };
  pages.policies = function (cfg, main) {
    var p = cfg.policies || {};
    function sec(key, title) {
      var t = pickLang(p[key] || {});
      return '<section><h2>' + esc(title) + '</h2><p>' + (t ? esc(t).replace(/\n/g, '<br>') : esc(tx('comingSoon'))) + '</p></section>';
    }
    main.innerHTML = '<h1>' + esc(tx('policy')) + '</h1>' + sec('privacy', lang() === 'en' ? 'Privacy' : 'গোপনীয়তা') + sec('terms', lang() === 'en' ? 'Terms' : 'শর্তাবলি') + sec('refund', lang() === 'en' ? 'Refund and cancellation' : 'ফেরত ও বাতিল');
  };

  window.SITE = { cartGet: cartGet, cartAdd: cartAdd, cartQty: cartQty, cartSet: cartSet, cartCount: cartCount, money: money, esc: esc, digits: digits, safeUrl: safeUrl,
    waLink: waLink, errTx: errTx, pickLang: pickLang, lang: lang, TX: TX, ERR: ERR, imgUrl: imgUrl, publicUrl: publicUrl, itemName: itemName, availTx: availTx };
  if (!window.SITE_TEST) { boot(); }
})();
