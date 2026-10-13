/* Registers sw.js (offline start). Off switch: the rule offline_cache_on (Switchboard) or this phone's localStorage bos_sw = 'off'. Never blocks the app; any failure is silent. */
(() => {
'use strict';
if (!('serviceWorker' in navigator)) return;
const secure = location.protocol === 'https:' || location.hostname === 'localhost' || location.hostname === '127.0.0.1';
let off = false; try { off = localStorage.getItem('bos_sw') === 'off'; } catch (e) { /* storage blocked */ }
const kill = async () => { try { const rs = await navigator.serviceWorker.getRegistrations(); await Promise.all(rs.map((r) => r.unregister())); const ks = await caches.keys(); await Promise.all(ks.filter((k) => k.startsWith('bos-sw-')).map((k) => caches.delete(k))); } catch (e) { /* ignore */ } };
if (!secure || off) { if (off) kill(); return; }
window.addEventListener('load', () => {
  navigator.serviceWorker.register('sw.js').catch(() => {});
  setTimeout(() => { try { const B = window.BOS; if (B && B.rule && B.rule('offline_cache_on', true) === false) { try { localStorage.setItem('bos_sw', 'off'); } catch (e) { /* ignore */ } kill(); } else { try { if (localStorage.getItem('bos_sw') === 'off') localStorage.removeItem('bos_sw'); } catch (e) { /* ignore */ } } } catch (e) { /* ignore */ } }, 5000);
});
})();
