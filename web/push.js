// Phone notifications for the DentPass web app. Called from the Flutter code.
(function () {
  function keyBytes(base64) {
    const padding = '='.repeat((4 - (base64.length % 4)) % 4);
    const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'));
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  async function registration() {
    const existing = await navigator.serviceWorker.getRegistration();
    if (existing) return existing;
    await navigator.serviceWorker.register('push-sw.js');
    return navigator.serviceWorker.ready;
  }

  window.dentpassPush = {
    // 'unsupported' | 'install' (iPhone: add to home screen first) | 'default' | 'granted' | 'denied'
    status: function () {
      if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
        const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
        return ios ? 'install' : 'unsupported';
      }
      return Notification.permission;
    },

    // Asks for permission (must run straight after a tap) and returns the device as JSON.
    subscribe: async function (publicKey) {
      try {
        const permission = await Notification.requestPermission();
        if (permission !== 'granted') return JSON.stringify({ error: permission });
        const reg = await registration();
        let sub = await reg.pushManager.getSubscription();
        if (!sub) {
          sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(publicKey) });
        }
        return JSON.stringify(sub.toJSON());
      } catch (e) {
        return JSON.stringify({ error: String(e && e.message ? e.message : e) });
      }
    },

    // The device already subscribed on this phone, or ''.
    current: async function () {
      try {
        const reg = await navigator.serviceWorker.getRegistration();
        if (!reg) return '';
        const sub = await reg.pushManager.getSubscription();
        return sub ? JSON.stringify(sub.toJSON()) : '';
      } catch (_) {
        return '';
      }
    },

    // Stops notifications on this phone; returns the endpoint that was removed, or ''.
    unsubscribe: async function () {
      try {
        const reg = await navigator.serviceWorker.getRegistration();
        const sub = reg ? await reg.pushManager.getSubscription() : null;
        if (!sub) return '';
        const endpoint = sub.endpoint;
        await sub.unsubscribe();
        return endpoint;
      } catch (_) {
        return '';
      }
    },
  };
})();
