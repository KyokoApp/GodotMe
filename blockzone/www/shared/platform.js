// shared/platform.js — Platform/distribution configuration
// Set window.GAME_MARKET before this file loads to override (e.g. from a build script).
// Valid markets: "itchio" | "newgrounds" | "galaxy" | "googleplay" | "crazygames" | "viverse" | "playgama"

window.GAME_MARKET = window.GAME_MARKET || "newgrounds";

window.PLATFORM = (() => {
    const market = window.GAME_MARKET;

    // scripts/copy-to-www.js fija GAME_MARKET = "googleplay" en el bundle www/
    // COMPARTIDO por "npx cap sync android" Y "npx cap sync ios" — no hay rama
    // iOS ahí, a diferencia de shared/ads.js o shared/iap.js. Por eso, para
    // todo lo que se GUARDA en el ranking (que si no queda indistinguible
    // Android/iOS para siempre en la base de datos), se usa este valor
    // derivado en vez de "market" a secas. El resto de usos de GAME_MARKET en
    // el proyecto (anuncios, IAP, el guard de resize, etc.) siguen igual: ahí
    // "googleplay" sí significa correctamente "app nativa empaquetada", da
    // igual el SO, y no hace falta tocarlos.
    const _isIosApp   = !!(window.Capacitor && window.Capacitor.getPlatform && window.Capacitor.getPlatform() === 'ios');
    const rankingMarket = _isIosApp ? 'ios' : market;

    // ── Badge colours for leaderboard rows ──────────────────────────────────
    const _colors = {
        itchio:        '#fa5c5c',
        newgrounds:    '#fda238',
        galaxy:        '#0099cc',
        incrementaldb: '#00bcd4',
        googleplay:    '#34a853',
        ios:           '#007aff',
        crazygames:    '#9b3de8',
        viverse:       '#00e5a0',
        playgama:      '#e64980',
    };

    // ── Display names for market badges ─────────────────────────────────────
    const _labels = {
        itchio:        'ITCH.IO',
        newgrounds:    'NEWGROUNDS',
        galaxy:        'GALAXY',
        incrementaldb: 'INCREMENTAL DB',
        googleplay:    'GOOGLE PLAY',
        ios:           'IOS',
        crazygames:    'CRAZYGAMES',
        viverse:       'VIVERSE',
        playgama:      'PLAYGAMA',
    };

    // ── Speedrun leaderboard API ─────────────────────────────────────────────
    const rankingApiUrl = 'https://themachinegg.com/server';

    // ── Steam wishlist — shown on non-Steam storefronts ──────────────────────
    // crazygames incluido a propósito: el botón del menú principal (#mm-steam-btn)
    // ya enlazaba a Steam allí con la URL hardcodeada, así que excluirlo aquí solo
    // conseguía que el botón del cartel final se ocultara mientras el del menú sí
    // salía. Ahora los dos son coherentes. playgama incluido por el mismo motivo.
    const _steamMarkets = ['itchio', 'galaxy', 'newgrounds', 'googleplay', 'crazygames', 'viverse', 'playgama'];
    const steamUrl = _steamMarkets.includes(market)
        ? `https://store.steampowered.com/app/4563810/The_MachinEGG/?utm_source=G1_${market.toUpperCase()}`
        : null;

    // ── "Rate us" link after speedrun ending (itch.io only) ──────────────────
    const showRateLink = market === 'itchio';

    // ── Community dropdown options for speedrun submission ───────────────────
    // itch.io players can also submit to IncrementalDB
    const communityOptions = market === 'itchio'
        ? [{ value: 'itchio', label: 'itch.io' }, { value: 'incrementaldb', label: 'IncrementalDB' }]
        : [{ value: rankingMarket, label: _labels[rankingMarket] || rankingMarket }];

    // ── SDK hooks (override per platform in dist builds) ─────────────────────
    // e.g. CrazyGames SDK, AdMob, etc.
    function initSdk() { /* no-op in local/web build */ }
    function requestAd(onReward) { onReward(); } // override in dist if needed

    return {
        market,
        rankingMarket,
        rankingApiUrl,
        steamUrl,
        showRateLink,
        communityOptions,
        initSdk,
        requestAd,
        marketColor: (m) => _colors[m] || '#888',
        marketLabel: (m) => _labels[m] || m,
    };
})();
