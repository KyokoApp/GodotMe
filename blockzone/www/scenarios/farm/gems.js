/**
 * FarmGems — gemas y tienda de gemas (sombreros, gafas, gallos, cursores, ambientes…).
 *
 * Fase 1: SOLO CrazyGames (window.GAME_MARKET === 'crazygames'). En el resto de
 * builds (itch.io, Playgama…) enabled() es false y nada de esto se ve ni se
 * guarda. Google Play llegará en la Fase 3 (Play Billing); el pago real en
 * CrazyGames (Xsolla) en la Fase 2 — hasta entonces los paquetes muestran
 * "Próximamente".
 *
 * ── Datos (GLOBALES, no por modo — `state` se recarga en cada loadState) ─────
 *   chickenIdleGems  → saldo (entero)
 *   chickenIdleHats  → { owned: [id…], off: [id…] }  (comprados / desactivados)
 *   Ambas claves están en _SAVE_KEYS (script.js) para que se carguen de la nube.
 *
 * ── Sombreros ──────────────────────────────────────────────────────────────
 *   pixelart_design/hats.png: 15 celdas de 16×12, sombrero centrado abajo.
 *   HAT_ANCHORS[fila][fotograma] = [x, y] del píxel más alto de la cresta en
 *   cada fotograma 24×24 de chicken_*.png (detectado automáticamente; idéntico
 *   en las 9 hojas). El sombrero se apoya ahí, bajando HAT_OVERLAP px.
 *   Cada gallina lleva uno de los sombreros ACTIVOS, elegido de forma estable
 *   (por chickenId, o al azar fijo por objeto si no tiene id).
 *
 * ── Regalo de bienvenida ───────────────────────────────────────────────────
 *   25 gemas UNA vez a quien vuelve (ya tenía partida guardada al cargar: 2ª sesión
 *   o una versión anterior del juego), con una ventana que le presenta la tienda.
 *   Los jugadores nuevos no lo reciben en su primera sesión, sí al volver.
 */
window.FarmGems = (function () {
    'use strict';

    const KEY_GEMS = 'chickenIdleGems';
    const KEY_HATS = 'chickenIdleHats';
    const WELCOME_GEMS = 25;   // regalo único a jugadores que vuelven
    // Códigos regalo (mercados sin pagos): los valida el servidor (Servidor Codigos/redeem_code.php).
    // El código da N gemas; con CODE_UNLOCK_ALL desbloquea todo, como el VIP de CrazyGames.
    const REDEEM_URL = 'https://themachinegg.com/server/redeem_code.php';
    const CODE_UNLOCK_ALL = 999;
    // Gemas por logro según su nivel ('platinum' es el que se muestra como Rubí). Cada logro se
    // paga una sola vez (ids en _achPaid): los ya conseguidos, de golpe en la bienvenida.
    const ACH_GEMS = { bronze: 1, silver: 2, gold: 3, platinum: 5, diamond: 10 };
    // Sin anuncios ni pagos (itch.io) las gemas solo salen de jugar: los logros dan bastante más.
    const ACH_GEMS_FREE = { bronze: 5, silver: 10, gold: 25, platinum: 50, diamond: 100 };
    function _achTable() { return _freeSources() ? ACH_GEMS_FREE : ACH_GEMS; }
    // Gemas por cada anuncio de recompensa visto (pedido del usuario). Tope diario solo de
    // seguridad (bots/scripts de anuncios: ese tráfico no paga y puede dar problemas con
    // CrazyGames); un jugador normal no llega. El día cambia a las 9:00 UTC.
    const AD_GEMS = 1, AD_GEMS_DAILY_CAP = 25, DAY_RESET_HOUR_UTC = 9;   // tope = 25 anuncios al día

    // Mismo orden que las celdas de hats.png.
    const HATS = [
        { id: 'top_hat',  key: 'hatTopHat',   price: 25 },
        { id: 'cowboy',   key: 'hatCowboy',   price: 25, dy: 1 }, // dy: px extra hacia abajo (pedido del usuario)
        { id: 'crown',    key: 'hatCrown',    price: 30 },
        { id: 'party',    key: 'hatParty',    price: 20 },
        { id: 'witch',    key: 'hatWitch',    price: 30 },
        { id: 'santa',    key: 'hatSanta',    price: 25 },
        { id: 'beanie',   key: 'hatBeanie',   price: 20 },
        { id: 'sombrero', key: 'hatSombrero', price: 25 },
        { id: 'pirate',   key: 'hatPirate',   price: 30, dy: 1 },
        { id: 'chef',     key: 'hatChef',     price: 20 },
        { id: 'unicorn',  key: 'hatUnicorn',  price: 30 },
        { id: 'viking',   key: 'hatViking',   price: 30 },
        { id: 'propeller',key: 'hatPropeller',price: 25 },
        { id: 'halo',     key: 'hatHalo',     price: 25 },
        { id: 'flowers',  key: 'hatFlowers',  price: 20 },
    ];
    // Paquetes con dinero real — Fase 2 (Xsolla). Hasta entonces, "Próximamente".
    const PACKS = [
        { id: 'gems_100', gems: 100, price: '1 €', desc: 'gemsPack100Desc' },
        { id: 'gems_300', gems: 300, price: '2 €', bonus: '+50%', desc: 'gemsPack300Desc' },
    ];
    // Compras únicas (no consumibles). "Todo" incluye también lo que se añada en el futuro
    // (se completa en cada carga, ver _applyUnlockAll). VIP = todo + sin banner + recompensas
    // de anuncio sin anuncio (shared/ads.js) — lo de los anuncios, pedido explícito del usuario
    // (CrazyGames lo permite dentro de un pack con más cosas, según el usuario).
    const OFFERS = [
        { id: 'unlock_all', key: 'gemsUnlockAll', desc: 'gemsUnlockAllDesc', price: '4,99 €' },
        { id: 'vip',        key: 'gemsVip',       desc: 'gemsVipDesc',       price: '5,99 €' },
    ];
    const PURCHASES_LIVE = false; // Fase 2: true cuando Xsolla esté conectado
    // Compras de PRUEBA (pedido explícito): los paquetes dan las gemas al momento,
    // sin pagar — SOLO en localhost (o con window.GEMS_DEBUG = true en la consola).
    // En CrazyGames de verdad sigue saliendo "Próximamente" hasta la Fase 2.
    function _debugPurchases() {
        return !PURCHASES_LIVE && (window.GEMS_DEBUG === true || /^(localhost|127\.0\.0\.1)$/.test(location.hostname));
    }

    // Cursores (diseños en shared/cursors.js → GameCursors.SKINS). 'default' es gratis.
    // La mano cambia también el dedo (cursor de botones).
    const CURSORS = [
        { id: 'hand_default',   kind: 'hand',   skin: 'default', key: 'curHandDefault',   price: 0 },
        { id: 'hand_nails', kind: 'hand', skin: 'nails', key: 'curHandNails', price: 20 },
        { id: 'hand_jewels', kind: 'hand', skin: 'jewels', key: 'curHandJewels', price: 30 },
        { id: 'magnet_default', kind: 'magnet', skin: 'default', key: 'curMagnetDefault', price: 0 },
        { id: 'magnet_blackhole', kind: 'magnet', skin: 'blackhole', key: 'curMagnetBlackHole', price: 30 },
        { id: 'magnet_battery', kind: 'magnet', skin: 'battery', key: 'curMagnetBattery', price: 20 },
    ];

    // Skins de gallo: recoloreado de rooster.png. Solo cambian el naranja del cuello/cola y el
    // gris del cuerpo; cresta, pico, patas y contorno se quedan igual. 'default' es gratis.
    const ROOSTER_SKINS = [
        { id: 'default', key: 'rsDefault', price: 0 },
        { id: 'gold',    key: 'rsGold',    price: 40, map: { '#e6904e': '#f9c22b', '#625565': '#c48a1e', '#3e3546': '#8a5a12' } },
        { id: 'snow',    key: 'rsSnow',    price: 40, map: { '#e6904e': '#ffffff', '#625565': '#c7dcd0', '#3e3546': '#9babb2' } },
        { id: 'raven',   key: 'rsRaven',   price: 40, map: { '#e6904e': '#4d65b4', '#625565': '#33303f', '#3e3546': '#24212e' } },
    ];
    // Pollitos de colores (como los de los mercados): un solo artículo; cada pollito tintado
    // sale de uno de estos colores. Solo cambia el amarillo del cuerpo (pico y patas igual).
    const CHICK_BODY = '#ffd560';
    const CHICK_TINTS = ['#ff7eb6', '#5fc4ff', '#7fdc5a', '#b88bff', '#ff6b5e'];
    const CHICK_TINT_PRICE = 50;
    // Ambientes: capa de color con modo de fusión sobre TODO el canvas del juego (pradera y
    // sótano), por encima de las gallinas y por debajo de la interfaz. 'normal' es gratis.
    const AMBIENCES = [
        { id: 'normal', key: 'ambNormal', price: 0 },
        { id: 'sunny',  key: 'ambSunny',  price: 20, color: '#ffc86b', blend: 'soft-light', alpha: 0.55 },
        { id: 'cloudy', key: 'ambCloudy', price: 20, color: '#7d8aa0', blend: 'multiply',   alpha: 0.40 },
        { id: 'sunset', key: 'ambSunset', price: 25, color: '#ff8a5c', blend: 'multiply',   alpha: 0.45 },
        { id: 'night',  key: 'ambNight',  price: 30, color: '#26346e', blend: 'multiply',   alpha: 0.62 },
    ];
    // Efectos de partículas sobre la granja. 'none' es gratis.
    const EFFECTS = [
        { id: 'none',     key: 'fxNone',     price: 0 },
        { id: 'snow',     key: 'fxSnow',     price: 25 },
        { id: 'rain',     key: 'fxRain',     price: 20 },
        { id: 'confetti', key: 'fxConfetti', price: 25 },
        { id: 'leaves',   key: 'fxLeaves',   price: 20 },
    ];

    // Gafas: pixelart_design/glasses.png, celdas de 16x8 (fila 0 de perfil, fila 1 de frente).
    // El píxel (8,4) de la celda va sobre el píxel superior izquierdo del ojo, que está
    // siempre 3 px por debajo del ancla del sombrero (medido en todas las animaciones).
    const GLASSES = [
        { id: 'sun',     key: 'glSun',     price: 20 },
        { id: 'nerd',    key: 'glNerd',    price: 20 },
        { id: 'heart',   key: 'glHeart',   price: 25 },
        { id: 'monocle', key: 'glMonocle', price: 30 },
        { id: 'star',    key: 'glStar',    price: 25 },
    ];
    const GL_W = 16, GL_H = 8, GL_EYE_X = 8, GL_EYE_Y = 4;
    // Vista de cada fila de la hoja de la gallina: 'S' perfil, 'M' perfil mirando a la
    // izquierda dentro de la hoja (dormida), 'F' de frente, null de espaldas (sin gafas).
    const GL_VIEW = ['S', 'S', 'F', null, 'S', 'S', 'S', 'F', null, 'S', 'S', 'S', 'S', 'S', 'M', 'S', 'F'];

    const HAT_W = 16, HAT_H = 12, HAT_OVERLAP = 2;
    const HAT_ANCHORS = [
        // Idle: en el 3er fotograma la cabeza baja 1 px pero la cresta no (se mueve
        // sola) → anclado al ojo (ojo − 3 px, distancia constante en las vistas de lado).
        [[15,9], [15,9], [15,10], [15,10], null, null, null, null],
        [[16,9], [15,10], [17,9], [17,8], [16,9], [15,10], [17,9], [18,7]],
        [[13,9], [13,10], [13,8], [13,6], [13,9], [13,10], [13,8], [13,6]],
        [[13,9], [13,10], [13,8], [13,6], [13,9], [13,10], [13,8], [13,6]],
        [[17,11], [18,11], [17,11], [18,11], [18,10], [17,9], [17,9], [16,9]],
        [[15,8], [15,9], [15,8], [15,9], null, null, null, null],
        [[16,10], [15,10], [17,10], [17,9], [16,10], [15,11], [17,10], [18,9]],
        [[13,10], [13,12], [13,9], [13,8], [13,10], [13,11], [13,9], [13,8]],
        [[13,10], [13,10], [13,8], [13,7], [13,10], [13,11], [13,9], [13,8]],
        [[14,13], [14,13], [14,13], [14,13], [14,12], [14,12], [14,12], [14,13]],
        [[15,2], [15,3], [15,3], [15,4], [15,4], [15,6], [15,7], [15,9]],
        [[15,8], [15,9], [15,8], [15,9], null, null, null, null],
        [null, null, null, null, [15,4], [16,5], [16,8], [16,10]],
        [[16,9], [16,8], [16,8], [16,7], [16,7], [16,8], [16,8], [16,9]],
        [[9,13], [9,13], [9,13], [9,13], [9,12], [9,12], [9,12], [9,13]],
        [[15,5], [15,4], null, null, null, null, null, null],
        [[11,5], [11,4], null, null, null, null, null, null],
    ];

    const hatImage = new Image();
    hatImage.src = 'pixelart_design/hats.png';
    const glassesImage = new Image();
    glassesImage.src = 'pixelart_design/glasses.png';
    const _henPreview = new Image();
    _henPreview.src = 'pixelart_design/chicken_white.png';

    const T = (k, fb) => (window.t ? window.t(k) : (fb || k));
    // Tienda de gemas: CrazyGames e itch.io. Pagos con dinero real y gemas por anuncios, solo
    // CrazyGames; en itch.io (sin anuncios ni pagos) las gemas salen de jugar (_freeSources).
    function enabled() { return window.GAME_MARKET === 'crazygames' || window.GAME_MARKET === 'itchio'; }
    function _paidMarket() { return window.GAME_MARKET === 'crazygames'; }
    function _freeSources() { return window.GAME_MARKET === 'itchio'; }
    // Donde no hay pagos ni anuncios no es una "tienda de gemas" sino de cosméticos (pedido del usuario).
    function _shopTitle() { return _freeSources() ? T('gemsTitleFree', 'COSMETICS') : T('gemsTitle', 'GEM SHOP'); }
    function _menuKey() { return _freeSources() ? 'gemsMenuBtnFree' : 'gemsMenuBtn'; }
    // Huevo de gema más o menos cada 2 min de partida activa (entre 100 y 140 s, al azar). Si no
    // lo coge el jugador en GEM_EGG_LIFE s de juego, la gema se pierde (dejarlo abierto no da nada).
    const GEM_EGG_MIN_S = 100, GEM_EGG_MAX_S = 140, GEM_EGG_LIFE = 60;

    // ── Monedero y sombreros ────────────────────────────────────────────────
    let _gems = 0, _owned = [], _off = [], _active = [];
    // % de gallinas que llevan sombrero (barra de la tienda; 0 = nadie, 100 = todas).
    const HAT_SHARE_DEFAULT = 20;
    let _share = HAT_SHARE_DEFAULT;
    // Gafas compradas / quitadas / activas y su propio % (independiente del de sombreros).
    let _glOwned = [], _glOff = [], _glActive = [], _glShare = HAT_SHARE_DEFAULT;
    // Cursores comprados y puestos (van en el mismo guardado que los sombreros).
    let _curOwned = [], _curOn = { hand: 'default', magnet: 'default' };
    // Efectos comprados y el que está puesto.
    let _fxOwned = [], _fxOn = 'none';
    // Ambientes comprados y el puesto.
    let _ambOwned = [], _ambOn = 'normal';
    // Skins de gallo compradas / puesta; pollitos de colores comprados / activos / %.
    let _rsOwned = [], _rsOff = [];
    // Compras únicas y contador de gemas por anuncios de hoy ({ d: día, n: gemas }).
    let _unlockAll = false, _vip = false, _adGems = { d: -1, n: 0 }, _welcomeGiven = false, _achPaid = [];
    let _ctOwned = false, _ctOff = false, _ctShare = 50;
    // Densidad (barra de la tienda, 10..100). 25 = la cantidad sutil de serie (x1); 100 = x4.
    const FX_DENS_DEFAULT = 25;
    let _fxDens = FX_DENS_DEFAULT;
    const _listeners = [];

    function _load() {
        const gs = window.GameSave;
        let g = 0;
        try { g = parseInt(gs && gs.loadRaw(KEY_GEMS), 10); } catch (e) { g = 0; }
        _gems = Number.isFinite(g) && g > 0 ? g : 0;
        let h = null;
        try { h = JSON.parse((gs && gs.loadRaw(KEY_HATS)) || 'null'); } catch (e) { h = null; }
        const valid = id => HATS.some(x => x.id === id);
        _owned = (h && Array.isArray(h.owned)) ? h.owned.filter(valid) : [];
        _off = (h && Array.isArray(h.off)) ? h.off.filter(valid) : [];
        _share = (h && Number.isFinite(h.share)) ? Math.max(0, Math.min(100, Math.round(h.share))) : HAT_SHARE_DEFAULT;
        _curOwned = (h && Array.isArray(h.curOwned)) ? h.curOwned.filter(id => CURSORS.some(x => x.id === id && x.price > 0)) : [];
        _curOn = { hand: 'default', magnet: 'default' };
        ['hand', 'magnet'].forEach(k => {
            const sk = h && h.cur && h.cur[k];
            if (sk && _curOwned.includes(k + '_' + sk)) _curOn[k] = sk;
        });
        const validG = id => GLASSES.some(x => x.id === id);
        _glOwned = (h && Array.isArray(h.glOwned)) ? h.glOwned.filter(validG) : [];
        _glOff = (h && Array.isArray(h.glOff)) ? h.glOff.filter(validG) : [];
        _glShare = (h && Number.isFinite(h.glShare)) ? Math.max(0, Math.min(100, Math.round(h.glShare))) : HAT_SHARE_DEFAULT;
        _fxOwned = (h && Array.isArray(h.fxOwned)) ? h.fxOwned.filter(id => EFFECTS.some(x => x.id === id && x.price > 0)) : [];
        _fxOn = (h && _fxOwned.includes(h.fx)) ? h.fx : 'none';
        _fxDens = (h && Number.isFinite(h.fxDens)) ? Math.max(10, Math.min(100, Math.round(h.fxDens))) : FX_DENS_DEFAULT;
        _rebuildActive();
        _applyCursors();
        _ambOwned = (h && Array.isArray(h.ambOwned)) ? h.ambOwned.filter(id => AMBIENCES.some(x => x.id === id && x.price > 0)) : [];
        _ambOn = (h && _ambOwned.includes(h.amb)) ? h.amb : 'normal';
        _rsOwned = (h && Array.isArray(h.rsOwned)) ? h.rsOwned.filter(id => ROOSTER_SKINS.some(x => x.id === id && x.price > 0)) : [];
        _rsOff = (h && Array.isArray(h.rsOff)) ? h.rsOff.filter(id => id === 'default' || _rsOwned.includes(id)) : [];
        if (!_rsOnList().length) _rsOff = [];   // nunca todas quitadas
        _ctOwned = !!(h && h.ctOwned);
        _ctOff = !!(h && h.ctOff);
        _ctShare = (h && Number.isFinite(h.ctShare)) ? Math.max(0, Math.min(100, Math.round(h.ctShare))) : 50;
        _unlockAll = !!(h && h.ua);
        _vip = !!(h && h.vip);
        _welcomeGiven = !!(h && h.wg);
        _achPaid = (h && Array.isArray(h.ap)) ? h.ap.filter(x => typeof x === 'string') : [];
        _adGems = (h && h.adg && Number.isFinite(h.adg.d) && Number.isFinite(h.adg.n)) ? { d: h.adg.d, n: h.adg.n } : { d: -1, n: 0 };
        _applyUnlockAll();
        _fxRestart();
        _ambApply();
    }
    // "Desbloquear todo" / VIP: marca como comprado todo lo que haya en los catálogos. Se
    // llama en cada carga → lo que se añada en futuras versiones queda incluido solo.
    function _applyUnlockAll() {
        if (!(_unlockAll || _vip)) return;
        const addAll = (arr, list) => list.forEach(x => { if (x.price > 0 && !arr.includes(x.id)) arr.push(x.id); });
        addAll(_owned, HATS);
        addAll(_glOwned, GLASSES);
        addAll(_curOwned, CURSORS);
        addAll(_fxOwned, EFFECTS);
        addAll(_ambOwned, AMBIENCES);
        addAll(_rsOwned, ROOSTER_SKINS);
        _ctOwned = true;
        _rebuildActive();
    }
    function hasAll() { return enabled() && (_unlockAll || _vip); }
    function isVip() { return enabled() && _vip; }
    // +AD_GEMS por anuncio de recompensa visto (lo llama shared/ads.js). No a quien tiene
    // "Desbloquear todo" o VIP: ya no tiene en qué gastarlas (pedido del usuario).
    function rewardForAd() {
        if (!enabled() || !_paidMarket() || _vip || _unlockAll) return;
        const day = Math.floor((Date.now() - DAY_RESET_HOUR_UTC * 3600000) / 86400000);
        if (_adGems.d !== day) _adGems = { d: day, n: 0 };
        if (_adGems.n >= AD_GEMS_DAILY_CAP) return;
        const g = Math.min(AD_GEMS, AD_GEMS_DAILY_CAP - _adGems.n);
        _adGems.n += g;
        _saveHats();
        add(g);
        _adGemPopup(g);
    }
    // Mismo marco, sitio y animación que #achievement-popup (style.css); si hay un logro en
    // pantalla a la vez, se apila encima en vez de taparlo.
    let _agpTimer = null;
    // Aviso morado genérico: badge (rosa), título (blanco, texto o HTML) y descripción opcional.
    function _purplePopup(badge, title, desc, titleIsHtml) {
        let el = document.getElementById('gems-reward-popup');
        if (!el) {
            el = document.createElement('div');
            el.id = 'gems-reward-popup';
            const ic = document.createElement('canvas'); ic.width = 11; ic.height = 10; ic.className = 'gm-rp-ico';
            _drawGem(ic.getContext('2d'), 0, 0);
            el.appendChild(ic);
            el.insertAdjacentHTML('beforeend', '<div><div class="gm-rp-badge"></div><div class="gm-rp-title"></div><div class="gm-rp-desc"></div></div>');
            document.body.appendChild(el);
        }
        el.querySelector('.gm-rp-badge').textContent = badge;
        const tt = el.querySelector('.gm-rp-title');
        if (titleIsHtml) tt.innerHTML = title; else tt.textContent = title;
        const dd = el.querySelector('.gm-rp-desc');
        dd.textContent = desc || '';
        dd.style.display = desc ? '' : 'none';
        const ach = document.getElementById('achievement-popup');
        const below = (ach && ach.classList.contains('show')) ? ach.offsetHeight + 12 : 0;
        el.style.setProperty('--gm-rp-bottom', (20 + below) + 'px');
        el.classList.remove('show'); void el.offsetWidth; el.classList.add('show');
        clearTimeout(_agpTimer);
        _agpTimer = setTimeout(() => el.classList.remove('show'), 3500);
    }
    function _adGemPopup(n, descKey, descFb) {
        _purplePopup(T('gemsAdBadge', 'Gems!'), '+' + n + ' <img src="pixelart_design/gem.png" alt="">',
            descKey ? T(descKey, descFb) : T('gemsAdDesc', 'For watching the ad'), true);
    }
    function _applyCursors() {
        const gc = window.GameCursors;
        if (!gc || !gc.setSkin) return;
        gc.setSkin('hand', _curOn.hand);
        gc.setSkin('magnet', _curOn.magnet);
    }
    function _saveGems() { if (window.GameSave) window.GameSave.saveRaw(KEY_GEMS, String(_gems)); }
    function _saveHats() { if (window.GameSave) window.GameSave.saveRaw(KEY_HATS, JSON.stringify({ owned: _owned, off: _off, share: _share, curOwned: _curOwned, cur: _curOn, fxOwned: _fxOwned, fx: _fxOn, fxDens: _fxDens, glOwned: _glOwned, glOff: _glOff, glShare: _glShare, ambOwned: _ambOwned, amb: _ambOn, rsOwned: _rsOwned, rsOff: _rsOff, ctOwned: _ctOwned, ctOff: _ctOff, ctShare: _ctShare, ua: _unlockAll, vip: _vip, adg: _adGems, wg: _welcomeGiven, ap: _achPaid })); }
    function _rebuildActive() {
        _active = [];
        HATS.forEach((h, i) => { if (_owned.includes(h.id) && !_off.includes(h.id)) _active.push(i); });
        _glActive = [];
        GLASSES.forEach((g, i) => { if (_glOwned.includes(g.id) && !_glOff.includes(g.id)) _glActive.push(i); });
    }
    function _changed() { _listeners.forEach(fn => { try { fn(); } catch (e) {} }); _refreshHud(); _refreshStore(); }

    function balance() { return _gems; }
    function add(n) { if (!(n > 0)) return; _gems += Math.floor(n); _saveGems(); _changed(); }
    function trySpend(n) {
        if (!enabled() || !(n > 0) || _gems < n) return false;
        _gems -= n; _saveGems(); _changed(); return true;
    }

    // Sombrero que lleva una gallina: índice de celda en hats.png o -1.
    const _seedOf = new WeakMap();
    function _seed(c) {
        if (typeof c.chickenId === 'number') return c.chickenId;
        let seed = _seedOf.get(c);
        if (seed === undefined) { seed = Math.floor(Math.random() * 1e9); _seedOf.set(c, seed); }
        return seed;
    }
    function hatIndexFor(c) {
        if (!enabled() || !_active.length || !c) return -1;
        const seed = _seed(c);
        // Segundo hash, independiente del de elegir sombrero: decide si esta gallina
        // entra en el % elegido. Fijo por gallina → al mover la barra no hay parpadeos.
        const pick = Math.imul((seed ^ 0x27d4eb2d) >>> 0, 0x165667b1) >>> 0;
        if ((pick % 100) >= _share) return -1;
        const hsh = Math.imul((seed ^ 0x5bd1e995) >>> 0, 2654435761) >>> 0;
        return _active[hsh % _active.length];
    }
    // Ajuste vertical propio de cada sombrero (px del fotograma), p.ej. el vaquero baja 1.
    function hatDy(i) { return (HATS[i] && HATS[i].dy) || 0; }
    // Vistas de frente y de espaldas (filas 2, 3, 7, 8 y 16 de la hoja): cabeza simétrica de ancho
    // impar y sombrero de 16 px → centrado en la cresta quedaba 1 px a la izquierda (aviso del
    // usuario). Solo el sombrero: las gafas usan la misma ancla y ya estaban bien.
    // Dormida mirando a la izquierda (fila 14 de la hoja, pico a la izquierda; el código la llama
    // "derecha" por la dirección de la gallina): el sombrero quedaba 2 px a la izquierda (aviso del usuario).
    const HAT_ROW_DX = { 2: 1, 3: 1, 7: 1, 8: 1, 14: 2, 16: 1 };
    function hatDx(row) { return HAT_ROW_DX[row] || 0; }
    function anchor(row, frame) {
        const r = HAT_ANCHORS[row];
        return r ? (r[frame] || null) : null;
    }
    // Canvas 2D (respaldo sin Pixi y cinemática): ctx ya trasladado/escalado como
    // en renderChicken (origen en el punto de anclaje del fotograma: x 12, y 21).
    function drawHat(ctx, c, row, frame) {
        const hi = hatIndexFor(c);
        if (hi < 0 || !hatImage.complete || !hatImage.naturalWidth) return;
        const a = anchor(row, frame);
        if (!a) return;
        ctx.drawImage(hatImage, hi * HAT_W, 0, HAT_W, HAT_H, -12 + a[0] + hatDx(row) - HAT_W / 2, -21 + a[1] + HAT_OVERLAP + hatDy(hi) - HAT_H, HAT_W, HAT_H);
    }

    // Gafas de una gallina: índice en glasses.png o -1. Hashes distintos a los del
    // sombrero → reparto independiente (una gallina puede llevar las dos cosas).
    function glassesIndexFor(c) {
        if (!enabled() || !_glActive.length || !c) return -1;
        const seed = _seed(c);
        const pick = Math.imul((seed ^ 0x3c6ef372) >>> 0, 0x2c1b3c6d) >>> 0;
        if ((pick % 100) >= _glShare) return -1;
        const hsh = Math.imul((seed ^ 0x6a09e667) >>> 0, 2246822519) >>> 0;
        return _glActive[hsh % _glActive.length];
    }
    // Dónde y cómo van las gafas en un fotograma: { ex, ey, view } o null.
    //   ex, ey = píxel del ojo donde cae el (GL_EYE_X, GL_EYE_Y) de la celda (fotograma de 24x24):
    //   el superior izquierdo; en 'M' (celda volteada) el superior DERECHO, que es el ancla.
    function glassesSpot(row, frame) {
        const v = GL_VIEW[row], a = v ? anchor(row, frame) : null;
        if (!a) return null;
        return { ex: a[0], ey: a[1] + 3, view: v };
    }
    // Canvas 2D: mismo convenio que drawHat (origen en el píxel 12,21 del fotograma).
    function drawGlasses(ctx, c, row, frame) {
        const gi = glassesIndexFor(c);
        if (gi < 0 || !glassesImage.complete || !glassesImage.naturalWidth) return;
        const sp = glassesSpot(row, frame);
        if (!sp) return;
        const sy = sp.view === 'F' ? GL_H : 0;
        if (sp.view === 'M') {
            // Espejo: el píxel GL_EYE_X de la celda cae en sp.ex (borde derecho del ojo)
            ctx.save();
            ctx.translate(-12 + sp.ex + 1 + GL_EYE_X, 0);
            ctx.scale(-1, 1);
            ctx.drawImage(glassesImage, gi * GL_W, sy, GL_W, GL_H, 0, -21 + sp.ey - GL_EYE_Y, GL_W, GL_H);
            ctx.restore();
        } else {
            ctx.drawImage(glassesImage, gi * GL_W, sy, GL_W, GL_H, -12 + sp.ex - GL_EYE_X, -21 + sp.ey - GL_EYE_Y, GL_W, GL_H);
        }
    }
    function _buyGlasses(i) {
        const g = GLASSES[i];
        if (!g || _glOwned.includes(g.id)) return;
        if (!trySpend(g.price)) { _toast(T('gemsNotEnough', 'Not enough gems')); _flashPacks(); return; }
        _glOwned.push(g.id);
        _glOff = _glOff.filter(id => id !== g.id);
        _rebuildActive(); _saveHats(); _changed();
        _toast(T('gemsGlassesBought', 'New glasses!'));
    }
    function _toggleGlasses(i) {
        const g = GLASSES[i];
        if (!g || !_glOwned.includes(g.id)) return;
        if (_glOff.includes(g.id)) _glOff = _glOff.filter(id => id !== g.id); else _glOff.push(g.id);
        _rebuildActive(); _saveHats(); _changed();
    }

    function _buyHat(i) {
        const h = HATS[i];
        if (!h || _owned.includes(h.id)) return;
        if (!trySpend(h.price)) { _toast(T('gemsNotEnough', 'Not enough gems')); _flashPacks(); return; }
        _owned.push(h.id);
        _off = _off.filter(id => id !== h.id);
        _rebuildActive(); _saveHats(); _changed();
        _toast(T('gemsHatBought', 'New hat! Your chickens love it.'));
    }
    function _toggleHat(i) {
        const h = HATS[i];
        if (!h || !_owned.includes(h.id)) return;
        if (_off.includes(h.id)) _off = _off.filter(id => id !== h.id); else _off.push(h.id);
        _rebuildActive(); _saveHats(); _changed();
    }

    function _useCursor(i) {
        const c = CURSORS[i];
        if (!c) return;
        if (c.price > 0 && !_curOwned.includes(c.id)) {
            if (!trySpend(c.price)) { _toast(T('gemsNotEnough', 'Not enough gems')); _flashPacks(); return; }
            _curOwned.push(c.id);
            _toast(T('gemsCurBought', 'New cursor!'));
        }
        _curOn[c.kind] = c.skin;
        _applyCursors(); _saveHats(); _changed();
    }

    // ── Recoloreado (gallo y pollitos) ──────────────────────────────────────
    // Devuelve un canvas con los colores cambiados; se guarda en caché por clave para no
    // repetirlo en cada fotograma. script.js lo usa como hoja en lugar del PNG original.
    const _recolorCache = {};
    function _recolor(img, map, key) {
        if (_recolorCache[key]) return _recolorCache[key];
        if (!img || !img.complete || !img.naturalWidth) return null;
        const cv = document.createElement('canvas'); cv.width = img.naturalWidth; cv.height = img.naturalHeight;
        const c = cv.getContext('2d'); c.drawImage(img, 0, 0);
        const id = c.getImageData(0, 0, cv.width, cv.height), d = id.data;
        const m = {};
        for (const k in map) m[parseInt(k.slice(1), 16)] = parseInt(map[k].slice(1), 16);
        for (let i = 0; i < d.length; i += 4) {
            if (!d[i + 3]) continue;
            const to = m[(d[i] << 16) | (d[i + 1] << 8) | d[i + 2]];
            if (to === undefined) continue;
            d[i] = to >> 16; d[i + 1] = (to >> 8) & 255; d[i + 2] = to & 255;
        }
        c.putImageData(id, 0, 0);
        return (_recolorCache[key] = cv);
    }
    // Reparto de skins entre los gallos (pedido del usuario): las PUESTAS (de 1 a las 4,
    // incluido el clásico; mínimo 1) se reparten por igual entre los gallos de la granja,
    // por turnos: compradas en orden de compra y el clásico al final.
    // idx = posición del gallo en roostersArr. Devuelve el id de la skin o null (clásico).
    function _rsOnList() {
        return _rsOwned.concat('default').filter(id => !_rsOff.includes(id));
    }
    function roosterSkinFor(idx) {
        if (!enabled() || !(idx >= 0)) return null;
        const on = _rsOnList();
        const sk = on.length ? on[idx % on.length] : 'default';
        return sk === 'default' ? null : sk;
    }
    // Hoja recoloreada de una skin (canvas en caché) o null.
    function roosterSheet(img, skinId) {
        const sk = skinId && ROOSTER_SKINS.find(x => x.id === skinId);
        return sk && sk.map ? _recolor(img, sk.map, 'rooster_' + sk.id) : null;
    }
    // Color de un pollito: índice en CHICK_TINTS o -1 (sin tintar). Fijo por pollito.
    function chickTintFor(ch) {
        if (!enabled() || !_ctOwned || _ctOff || !ch) return -1;
        const seed = _seed(ch);
        const pick = Math.imul((seed ^ 0x1b873593) >>> 0, 0x7feb352d) >>> 0;
        if ((pick % 100) >= _ctShare) return -1;
        const hsh = Math.imul((seed ^ 0x85ebca6b) >>> 0, 0x846ca68b) >>> 0;
        return hsh % CHICK_TINTS.length;
    }
    function chickSheet(img, ti) {
        if (ti < 0 || ti >= CHICK_TINTS.length) return null;
        return _recolor(img, { [CHICK_BODY]: CHICK_TINTS[ti] }, 'chick_' + ti);
    }
    const _roosterImg = new Image(); _roosterImg.src = 'pixelart_design/rooster.png';
    const _chickImg = new Image(); _chickImg.src = 'pixelart_design/chick.png';
    // Comprar una skin, o si ya es tuya (el clásico siempre lo es), PUESTA/QUITADA. No se puede
    // quitar la última que queda puesta: siempre hay al menos una.
    function _useRoosterSkin(i) {
        const r = ROOSTER_SKINS[i];
        if (!r) return;
        if (r.price > 0 && !_rsOwned.includes(r.id)) {
            if (!trySpend(r.price)) { _toast(T('gemsNotEnough', 'Not enough gems')); _flashPacks(); return; }
            _rsOwned.push(r.id);
            _rsOff = _rsOff.filter(id => id !== r.id);
            _toast(T('gemsRsBought', 'New rooster look!'));
        } else if (_rsOff.includes(r.id)) _rsOff = _rsOff.filter(id => id !== r.id);
        else if (_rsOnList().length <= 1) { _toast(T('rsMinOne', 'At least one look must stay on')); return; }
        else _rsOff.push(r.id);
        _saveHats(); _changed();
    }
    function _buyOrToggleChicks() {
        if (!_ctOwned) {
            if (!trySpend(CHICK_TINT_PRICE)) { _toast(T('gemsNotEnough', 'Not enough gems')); _flashPacks(); return; }
            _ctOwned = true; _ctOff = false;
            _toast(T('gemsCtBought', 'Colorful chicks!'));
        } else _ctOff = !_ctOff;
        _saveHats(); _changed();
    }
    // Vistas previas (dataURL): gallo (fotograma 0, 32x32) y 3 pollitos de colores.
    function _roosterPreview(r, im) {
        const draw = () => {
            const src = r.map ? _recolor(_roosterImg, r.map, 'rooster_' + r.id) : (_roosterImg.complete && _roosterImg.naturalWidth ? _roosterImg : null);
            if (!src) return;
            const cv = document.createElement('canvas'); cv.width = 32; cv.height = 32;
            cv.getContext('2d').drawImage(src, 0, 0, 32, 32, 0, 0, 32, 32);
            im.src = cv.toDataURL();
        };
        if (_roosterImg.complete) draw(); else _roosterImg.addEventListener('load', draw, { once: true });
    }
    function _chicksPreview(im) {
        const draw = () => {
            const cv = document.createElement('canvas'); cv.width = 36; cv.height = 24;
            const c = cv.getContext('2d');
            [0, 1, 3].forEach((ti, k) => { const sh = chickSheet(_chickImg, ti); if (sh) c.drawImage(sh, 0, 0, 24, 24, k * 8 - 6, 2 - (k % 2) * 4, 24, 24); });
            im.src = cv.toDataURL();
        };
        if (_chickImg.complete) draw(); else _chickImg.addEventListener('load', draw, { once: true });
    }

    function _useAmbience(i) {
        const a = AMBIENCES[i];
        if (!a) return;
        if (a.price > 0 && !_ambOwned.includes(a.id)) {
            if (!trySpend(a.price)) { _toast(T('gemsNotEnough', 'Not enough gems')); _flashPacks(); return; }
            _ambOwned.push(a.id);
            _toast(T('gemsAmbBought', 'New ambience!'));
        }
        _ambOn = a.id;
        _ambApply(); _saveHats(); _changed();
    }
    // Capa del ambiente: <div> hermano de #gameCanvas (z 6, sobre Pixi z 5; partículas z 7),
    // sin eventos de ratón, alineado con el canvas igual que el de partículas (sirve en PC y
    // en móvil sin usar window.innerWidth). Solo hay bucle mientras el ambiente no es 'normal'.
    let _ambEl = null, _ambIEl = null, _ambRaf = 0;
    function _ambApply() {
        if (_ambRaf) { cancelAnimationFrame(_ambRaf); _ambRaf = 0; }
        const a = AMBIENCES.find(x => x.id === _ambOn);
        if (!enabled() || !a || !a.color) { if (_ambEl) _ambEl.style.display = 'none'; if (_ambIEl) _ambIEl.style.display = 'none'; return; }
        const game = document.getElementById('gameCanvas');
        if (!game || !game.parentNode) return;
        if (!_ambEl) {
            _ambEl = document.createElement('div');
            _ambEl.id = 'gm-amb-layer';
            _ambEl.style.cssText = 'position:absolute;top:0;left:0;pointer-events:none;z-index:6;display:none';
            game.parentNode.appendChild(_ambEl);
        }
        _ambEl.style.background = a.color;
        _ambEl.style.mixBlendMode = a.blend;
        _ambEl.style.opacity = String(a.alpha);
        if (!_ambIEl) {
            _ambIEl = document.createElement('div');
            _ambIEl.id = 'gm-amb-intro';
            _ambIEl.style.cssText = 'position:absolute;inset:0;pointer-events:none;z-index:4;display:none';
        }
        _ambIEl.style.background = a.color;
        _ambIEl.style.mixBlendMode = a.blend;
        _ambIEl.style.opacity = String(a.alpha);
        const tick = () => {
            _ambRaf = requestAnimationFrame(tick);
            // Intro del menú (la capa va dentro de #intro-pan-wrapper, debajo de los botones)
            const wrap = document.getElementById('intro-pan-wrapper');
            if (wrap && _introVisible() && !document.hidden) {
                if (_ambIEl.parentNode !== wrap) wrap.appendChild(_ambIEl);
                _ambIEl.style.display = 'block';
            } else _ambIEl.style.display = 'none';
            const cr = game.getBoundingClientRect();
            if (cr.width <= 0 || cr.height <= 0 || !document.body.classList.contains('in-game') || document.hidden) { _ambEl.style.display = 'none'; return; }
            const pr = game.offsetParent ? game.offsetParent.getBoundingClientRect() : { left: 0, top: 0 };
            // En portrait el cielo (.sky-extension) y la tierra (.earth-extension) son piezas
            // aparte encima y debajo del canvas: el ambiente las cubre también. En PC miden 0.
            let top = cr.top, bottom = cr.bottom;
            ['sky-extension', 'earth-extension'].forEach(cls => {
                const el = game.parentNode.querySelector(':scope > .' + cls);
                const r = el && el.getBoundingClientRect();
                if (r && r.height > 0 && r.width > 0) { top = Math.min(top, r.top); bottom = Math.max(bottom, r.bottom); }
            });
            const st = _ambEl.style;
            st.display = 'block';
            st.left = (cr.left - pr.left) + 'px'; st.top = (top - pr.top) + 'px';
            st.width = cr.width + 'px'; st.height = (bottom - top) + 'px';
        };
        tick();
    }
    // Vista previa: trozo de pradera y sótano con el ambiente aplicado (mismo color/fusión).
    function _ambPreview(a) {
        const cv = document.createElement('canvas'); cv.width = 16; cv.height = 16;
        const c = cv.getContext('2d');
        c.fillStyle = '#8fd3ff'; c.fillRect(0, 0, 16, 4);
        c.fillStyle = '#7ec850'; c.fillRect(0, 4, 16, 6);
        c.fillStyle = '#f9c22b'; c.fillRect(3, 6, 2, 2);
        c.fillStyle = '#ffffff'; c.fillRect(9, 6, 3, 2); c.fillStyle = '#ea4f36'; c.fillRect(10, 5, 1, 1);
        c.fillStyle = '#6e3f2a'; c.fillRect(0, 10, 16, 6);
        c.fillStyle = '#f57d4a'; c.fillRect(0, 10, 16, 1);
        if (a.color) { c.globalAlpha = a.alpha; c.globalCompositeOperation = a.blend; c.fillStyle = a.color; c.fillRect(0, 0, 16, 16); }
        return cv.toDataURL();
    }

    function _useEffect(i) {
        const fx = EFFECTS[i];
        if (!fx) return;
        if (fx.price > 0 && !_fxOwned.includes(fx.id)) {
            if (!trySpend(fx.price)) { _toast(T('gemsNotEnough', 'Not enough gems')); _flashPacks(); return; }
            _fxOwned.push(fx.id);
            _toast(T('gemsFxBought', 'New effect!'));
        }
        _fxOn = fx.id;
        _fxRestart(); _saveHats(); _changed();
    }

    // ── Partículas sobre la granja ──────────────────────────────────────────
    // Canvas propio encima del de Pixi (z 5) y por debajo de la UI (bocadillo z 20),
    // sin eventos de ratón. Copia el rectángulo de #gameCanvas igual que shared/pixi.js
    // (sync), así sirve tal cual en PC y en móvil (portrait): no usa window.innerWidth.
    // Resolución interna = la del juego / FX_PX → partículas pixeladas, como el arte.
    const FX_PX = 3;
    const FX_COLORS = {
        confetti: ['#f1c40f', '#ea4f36', '#4d9be6', '#1ebc73', '#ff6fae', '#ffffff'],
        leaves: ['#e07438', '#c64524', '#f2a93b', '#a8502c'],
    };
    // Partículas por cada 100 px (internos) de ancho: sutil.
    const FX_DENSITY = { snow: 7, rain: 9, confetti: 4, leaves: 2 };
    let _fxCvs = null, _fxCtx = null, _fxParts = [], _fxRaf = 0, _fxLast = 0;
    // Intro del menú: mismo efecto sobre la escena (dentro de #intro-pan-wrapper, por debajo
    // de los botones del menú, que van en #mm-home con z-index superior).
    let _fxICvs = null, _fxICtx = null, _fxIParts = [];

    function _fxNew(type, w, h, anyY) {
        const r = Math.random;
        const pt = { x: r() * w, y: anyY ? r() * h : -4 - r() * 10, ph: r() * 6.28 };
        if (type === 'snow') { pt.vy = 6 + r() * 8; pt.sz = r() < 0.25 ? 2 : 1; pt.a = 0.55 + r() * 0.4; }
        else if (type === 'rain') { pt.vy = 90 + r() * 40; pt.len = 3 + Math.floor(r() * 3); pt.a = 0.25 + r() * 0.25; }
        else if (type === 'confetti') { pt.vy = 10 + r() * 8; pt.c = FX_COLORS.confetti[Math.floor(r() * 6)]; pt.sp = 4 + r() * 5; }
        else { pt.vy = 7 + r() * 5; pt.c = FX_COLORS.leaves[Math.floor(r() * 4)]; pt.sp = 1 + r() * 1.5; }
        return pt;
    }
    function _fxStop() {
        if (_fxRaf) cancelAnimationFrame(_fxRaf);
        _fxRaf = 0; _fxParts = []; _fxIParts = [];
        if (_fxCvs) _fxCvs.style.display = 'none';
        if (_fxICvs) _fxICvs.style.display = 'none';
    }
    // ¿Se ve el menú principal (la intro con sus gallinas) y no la partida?
    function _introVisible() {
        if (document.body.classList.contains('in-game')) return false;
        const ov = document.getElementById('main-menu-overlay');
        return !!(ov && getComputedStyle(ov).display !== 'none' && document.getElementById('intro-pan-wrapper'));
    }
    // Mueve y pinta las partículas de un lienzo de w×h (px internos).
    function _fxDraw(c, parts, type, w, h, dt, t) {
        const want = Math.max(1, Math.round(w / 100 * FX_DENSITY[type] * _fxDens / FX_DENS_DEFAULT));
        while (parts.length < want) parts.push(_fxNew(type, w, h, true));
        if (parts.length > want) parts.length = want;
        c.clearRect(0, 0, w, h);
        for (let i = 0; i < parts.length; i++) {
            let pt = parts[i];
            pt.y += pt.vy * dt;
            if (type === 'rain') pt.x -= pt.vy * 0.25 * dt;
            if (pt.y > h + 6 || pt.x < -6) { pt = parts[i] = _fxNew(type, w, h, false); }
            if (type === 'snow') {
                c.globalAlpha = pt.a; c.fillStyle = '#ffffff';
                c.fillRect(Math.round(pt.x + Math.sin(t * 0.8 + pt.ph) * 3), Math.round(pt.y), pt.sz, pt.sz);
            } else if (type === 'rain') {
                c.globalAlpha = pt.a; c.fillStyle = '#c7dcf5';
                const x = Math.round(pt.x), y = Math.round(pt.y);
                for (let k = 0; k < pt.len; k++) c.fillRect(x + Math.floor(k / 4), y - k, 1, 1);
            } else if (type === 'confetti') {
                // Papelito que gira: alterna tumbado / de pie.
                c.globalAlpha = 0.9; c.fillStyle = pt.c;
                const flat = Math.sin(t * pt.sp + pt.ph) > 0;
                c.fillRect(Math.round(pt.x + Math.sin(t * 1.3 + pt.ph) * 4), Math.round(pt.y), flat ? 2 : 1, flat ? 1 : 2);
            } else {
                // Hoja: vaivén amplio, de 2×1 a 2×2 según se balancea.
                c.globalAlpha = 0.85; c.fillStyle = pt.c;
                const sw = Math.sin(t * pt.sp + pt.ph);
                c.fillRect(Math.round(pt.x + sw * 8), Math.round(pt.y), 2, Math.abs(sw) > 0.5 ? 1 : 2);
            }
        }
        c.globalAlpha = 1;
    }
    function _fxRestart() {
        _fxStop();
        if (!enabled() || _fxOn === 'none') return;
        const game = document.getElementById('gameCanvas');
        if (!game || !game.parentNode) return;
        if (!_fxCvs) {
            _fxCvs = document.createElement('canvas');
            _fxCvs.id = 'gm-fx-canvas';
            _fxCvs.style.cssText = 'position:absolute;top:0;left:0;pointer-events:none;image-rendering:pixelated;z-index:7;display:none';
            game.parentNode.appendChild(_fxCvs);
            _fxCtx = _fxCvs.getContext('2d');
        }
        _fxLast = 0;
        _fxRaf = requestAnimationFrame(_fxFrame);
    }
    function _fxFrame(now) {
        _fxRaf = requestAnimationFrame(_fxFrame);
        const dt = _fxLast ? Math.min(0.1, (now - _fxLast) / 1000) : 0;
        _fxLast = now;
        const t = now / 1000, type = _fxOn;
        if (document.hidden) { _fxCvs.style.display = 'none'; if (_fxICvs) _fxICvs.style.display = 'none'; _fxLast = 0; return; }
        // ── Granja ──
        const game = document.getElementById('gameCanvas');
        const cr = game && game.getBoundingClientRect();
        // Solo en partida y con el canvas visible (no en el menú ni en cinemáticas que lo oculten).
        if (!cr || cr.width <= 0 || cr.height <= 0 || !document.body.classList.contains('in-game')) {
            _fxCvs.style.display = 'none';
        } else {
            const pr = game.offsetParent ? game.offsetParent.getBoundingClientRect() : { left: 0, top: 0 };
            // Solo la pradera (pedido del usuario: el sótano no). LAYOUT.MEADOW_BOTTOM está en
            // coordenadas del canvas del juego y ya cambia según el modo (PC / portrait).
            const L = window.LAYOUT;
            const top = Math.min(game.height, (L && L.MEADOW_BOTTOM > 0) ? L.MEADOW_BOTTOM : game.height);
            const st = _fxCvs.style;
            st.display = 'block';
            st.left = (cr.left - pr.left) + 'px'; st.top = (cr.top - pr.top) + 'px';
            st.width = cr.width + 'px'; st.height = (cr.height * top / game.height) + 'px';
            const w = Math.max(1, Math.round(game.width / FX_PX)), h = Math.max(1, Math.round(top / FX_PX));
            if (_fxCvs.width !== w || _fxCvs.height !== h) { _fxCvs.width = w; _fxCvs.height = h; _fxParts = []; }
            _fxDraw(_fxCtx, _fxParts, type, w, h, dt, t);
        }
        // ── Intro del menú: toda la escena visible (cielo y pradera) ──
        const wrap = document.getElementById('intro-pan-wrapper');
        if (!wrap || !_introVisible()) { if (_fxICvs) _fxICvs.style.display = 'none'; return; }
        if (!_fxICvs) {
            _fxICvs = document.createElement('canvas');
            _fxICvs.id = 'gm-fx-intro';
            _fxICvs.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none;image-rendering:pixelated;z-index:5';
            _fxICtx = _fxICvs.getContext('2d');
        }
        if (_fxICvs.parentNode !== wrap) wrap.appendChild(_fxICvs);
        _fxICvs.style.display = 'block';
        const iw = Math.max(1, Math.round(wrap.clientWidth / FX_PX)), ih = Math.max(1, Math.round(wrap.clientHeight / FX_PX));
        if (_fxICvs.width !== iw || _fxICvs.height !== ih) { _fxICvs.width = iw; _fxICvs.height = ih; _fxIParts = []; }
        _fxDraw(_fxICtx, _fxIParts, type, iw, ih, dt, t);
    }
    // Vista previa estática (dataURL) para la tienda.
    function _fxPreview(id) {
        const cv = document.createElement('canvas'); cv.width = 16; cv.height = 16;
        const c = cv.getContext('2d');
        c.fillStyle = '#5a9e48'; c.fillRect(0, 0, 16, 16);
        c.fillStyle = '#7ec850'; c.fillRect(0, 11, 16, 5);
        if (id === 'none') return cv.toDataURL();
        let seed = id.length * 97;
        const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
        for (let i = 0; i < 9; i++) {
            const x = Math.floor(rnd() * 15), y = Math.floor(rnd() * 15);
            if (id === 'snow') { c.fillStyle = '#ffffff'; c.fillRect(x, y, 1, 1); }
            else if (id === 'rain') { c.fillStyle = '#c7dcf5'; c.fillRect(x, y, 1, 1); c.fillRect(x, y - 1, 1, 1); c.fillRect(x + 1, y - 3, 1, 1); c.fillRect(x + 1, y - 2, 1, 1); }
            else if (id === 'confetti') { c.fillStyle = FX_COLORS.confetti[i % 6]; c.fillRect(x, y, i % 2 ? 2 : 1, i % 2 ? 1 : 2); }
            else if (i < 5) { c.fillStyle = FX_COLORS.leaves[i % 4]; c.fillRect(x, y, 2, i % 2 ? 1 : 2); }
        }
        return cv.toDataURL();
    }

    function _toast(msg) {
        _purplePopup(_shopTitle(), msg, '');
    }
    function _inCrazyGamesApp() {
        try {
            const t = window.CrazyGames.SDK.user.systemInfo.applicationType;
            return t === 'google_play_store' || t === 'apple_store';
        } catch (e) { return false; }
    }

    // ── Estilos (inyectados: no tocan style.css / portrait.css) ─────────────
    function _injectCss() {
        if (document.getElementById('gems-css')) return;
        const st = document.createElement('style');
        st.id = 'gems-css';
        st.textContent = `
#gems-hud-btn{width:44px;height:44px;flex:0 0 auto;padding:0;margin:0;border:none;box-shadow:none;background:transparent url('pixelart_design/button_gems.png') no-repeat center/contain;image-rendering:pixelated;cursor:var(--cur-finger)}
#gems-hud-btn:hover{transform:translateY(-2px)}
#gems-reward-popup{position:fixed;bottom:-200px;right:20px;border:10px solid transparent;border-image:url('pixelart_design/panel_purple_small.png') 5 fill / 10px / 0 stretch;background-color:#45293f;background-clip:padding-box;image-rendering:pixelated;padding:14px 18px;display:flex;align-items:center;gap:12px;z-index:100030;transition:bottom .4s cubic-bezier(.175,.885,.32,1.275);min-width:200px;max-width:340px;box-shadow:0 4px 20px rgba(0,0,0,.6);pointer-events:none;font-family:'Press Start 2P',monospace}
#gems-reward-popup.show{bottom:var(--gm-rp-bottom,20px)}
#gems-reward-popup .gm-rp-ico{width:33px;height:30px;image-rendering:pixelated;flex-shrink:0}
#gems-reward-popup .gm-rp-badge{color:#ed8099;font-size:9px;margin-bottom:6px}
#gems-reward-popup .gm-rp-title{color:#fff;font-size:12px;margin-bottom:5px;line-height:1.4;display:flex;align-items:center;gap:6px}
#gems-reward-popup .gm-rp-title img{width:14px;height:14px;image-rendering:pixelated;position:relative;top:-1px}
#gems-reward-popup .gm-rp-desc{color:#d8c2d4;font-size:8px;line-height:1.4}
body.capture-mode-hide-menu #gems-reward-popup{display:none!important}
#gems-hud-btn:active{transform:translate(2px,2px)}
#gems-shop-bal{position:absolute;left:6px;top:50%;transform:translateY(-50%);z-index:2;display:flex;align-items:center;gap:5px;padding:3px 8px 3px 5px;background:#45293f;border:2px solid #2e222f;border-radius:6px;box-shadow:inset 0 -3px 0 rgba(0,0,0,.25);font-family:'Press Start 2P',monospace;font-size:12px;line-height:1;color:#fff;text-shadow:0 2px #000;cursor:var(--cur-finger)}
#gems-shop-bal:hover{background:#5a3552}
#gems-shop-bal img{width:16px;height:16px;image-rendering:pixelated;flex-shrink:0;position:relative;top:-1px}
#gems-shop-bal-val{position:relative;top:1px}
body.mode-portrait #gems-shop-bal{left:4px;gap:4px;padding:2px 7px 2px 4px;border-width:2px;border-radius:5px;font-size:9px}
body.mode-portrait #gems-shop-bal img{width:16px;height:16px}
#mm-gems-btn,#mm-gems-btn .mm-bar-label{font-family:'Press Start 2P',monospace!important;text-shadow:1px 1px 0 #00000050,2px 2px 0 #00000050}
.mm-icon-gems{background-image:url('pixelart_design/gem.png')!important;background-size:contain!important;background-position:center!important;background-repeat:no-repeat!important;image-rendering:pixelated}
.gm-overlay{position:fixed;inset:0;z-index:100020;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.3);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px);animation:overlay-blur-in .15s ease forwards;font-family:'Press Start 2P',monospace}
.gm-panel{position:relative;width:min(640px,96vw);max-height:92vh;box-sizing:border-box;display:flex;flex-direction:column;color:#fff;border-style:solid;border-width:18px 35px 32px 35px;border-image:url('pixelart_design/themachinegg_panel.png') 17 35 32 35 fill / 56px 86px 77px 86px stretch round;background-clip:padding-box;image-rendering:pixelated}
.gm-title{position:absolute;top:2px;left:0;right:0;margin:0;text-align:center;pointer-events:none;color:#f1c40f;font-size:20px;text-shadow:2px 2px #000;white-space:nowrap}
.gm-body{margin:38px 0 0;padding:10px 2px 8px;overflow-y:auto;flex:1;min-height:0;scrollbar-width:thin}
.gm-bal{position:absolute;top:5px;left:4px;z-index:1;display:flex;align-items:center;gap:6px;font-size:14px;margin:0;text-shadow:2px 2px #000;pointer-events:none}
.gm-bal + .gm-body{scrollbar-width:none}
.gm-bal + .gm-body::-webkit-scrollbar{display:none}
.gm-sbar{position:absolute;right:-25px;width:18px;touch-action:none;cursor:var(--cur-finger)}
.gm-sbar::before{content:'';position:absolute;top:0;bottom:0;left:6px;width:6px;border-radius:3px;background:rgba(0,0,0,.28)}
.gm-sbar-thumb{position:absolute;left:6px;width:6px;border-radius:3px;background:#f1c40f}
.gm-sbar.drag .gm-sbar-thumb,.gm-sbar:hover .gm-sbar-thumb{background:#ffe08a}
body.mode-portrait .gm-sbar{right:-19px;width:16px}
body.mode-portrait .gm-sbar::before,body.mode-portrait .gm-sbar-thumb{left:5px}
.gm-bal img{width:18px;height:18px;image-rendering:pixelated}
.gm-sec{font-size:12px;color:#fff;text-align:center;margin:14px 0 8px;text-shadow:2px 2px #000}
.gm-packs{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}
.gm-panel .gm-pack{position:relative;background:#a8553f;border:3px solid #6e2f25;border-radius:0;box-shadow:inset 0 3px 0 #c06a50,inset 0 -3px 0 #8e4434;justify-content:flex-start;gap:4px;padding:8px 4px 8px}
.gm-pk-ico{width:108px;height:72px;max-width:100%;object-fit:contain;image-rendering:pixelated;flex:0 0 auto}
.gm-pack .gm-btn{margin-top:auto}
.gm-pack .gm-n{font-size:14px;color:#f1c40f;line-height:1.2}
.gm-pack .gm-bonus{position:absolute;top:4px;right:4px;min-height:0;font-size:8px;color:#fff;background:#1ebc73;border-radius:3px;padding:3px 4px;line-height:1}
.gm-pack .gm-bonus:empty{display:none}
body.mode-desktop.gm-vip #shop{max-height:none}
#eb-offer.eb-vip #eb-accept::before{display:none!important}
body.mode-desktop #eb-offer.eb-vip #eb-accept #eb-accept-label,body.mode-portrait #eb-offer.eb-vip #eb-accept #eb-accept-label{display:block;font-family:'Press Start 2P',monospace;font-size:9px;color:#fff;text-shadow:1px 1px 0 rgba(0,0,0,.6);padding:0 4px;white-space:nowrap}
.gm-packs.gm-earn{grid-template-columns:repeat(3,minmax(0,1fr))}
body.mode-portrait .gm-packs.gm-earn{grid-template-columns:repeat(2,minmax(0,1fr));gap:6px}
body.mode-portrait .gm-code-card{grid-column:1 / -1}
body.mode-portrait .gm-earn-card .gm-offer-t{font-size:9px}
.gm-code-card input{width:92%;max-width:240px;box-sizing:border-box;font-family:'Press Start 2P',monospace;font-size:12px;letter-spacing:2px;text-transform:uppercase;text-align:center;color:#fff;background:#45293f;border:2px solid #2e222f;border-radius:4px;padding:6px 8px;outline:none;cursor:text}
.gm-code-card input:focus{border-color:#f1c40f}
.gm-code-card input::placeholder{color:#9b7a93}
.gm-panel .gm-code-card .gm-btn{margin-top:2px}
.gm-packs.gm-packs-2{grid-template-columns:repeat(2,minmax(0,1fr));max-width:340px;margin:0 auto}
.gm-offer .gm-offer-t{font-size:10px;color:#f1c40f;line-height:1.4}
.gm-pack .gm-offer-d{font-size:7px;line-height:1.5;color:#fff;text-shadow:1px 1px #000}
.gm-pack,.gm-hat,.gm-share{min-width:0;box-sizing:border-box;background:rgba(0,0,0,.14);border:2px dashed #c9a27a;border-radius:4px}
.gm-pack,.gm-hat{padding:5px 4px;text-align:center;display:flex;flex-direction:column;align-items:center;gap:3px}
.gm-pack .gm-n{font-size:12px;text-shadow:2px 2px #000}.gm-pack .gm-bonus{font-size:7px;color:#2dff9d;min-height:9px}
.gm-hats{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:6px}
.gm-hat{background:none;border:none}
.gm-hat canvas{width:60px;height:60px;image-rendering:pixelated;margin:-6px 0 -4px}
.gm-gl canvas{width:48px;height:48px;margin:2px 0 4px}
.gm-hat .gm-name{font-size:8px;line-height:1.3;min-height:21px;color:#ffe08a;text-shadow:1px 1px #000;display:flex;align-items:center;justify-content:center}
.gm-panel .gm-btn{border-width:6px!important;width:auto;min-width:72%;max-width:100%;align-self:center;display:flex;align-items:center;justify-content:center;gap:4px;font-family:'Press Start 2P',monospace;font-size:9px;padding:2px 4px;line-height:1.1;white-space:nowrap;cursor:var(--cur-finger)}
.gm-panel .gm-back{border-width:12px!important;width:100%;font-size:13px;padding:10px;margin-top:12px}
.gm-panel .gm-btn img{position:relative;top:-1px}
.gm-panel .gm-hback{position:absolute;top:2px;right:2px;z-index:1;width:auto;min-width:0;max-width:none;margin:0;font-size:9px;padding:3px 6px}
body.mode-portrait .gm-panel .gm-hback{top:4px;right:0;font-size:7px;padding:2px 4px}
.gm-curs{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:6px}
.gm-cur{min-width:0;padding:5px 2px;text-align:center;display:flex;flex-direction:column;align-items:center;gap:3px}
.gm-cur>img{width:48px;height:48px;image-rendering:pixelated}
.gm-rs>img{width:56px;height:56px;margin:-4px 0 -4px}
.gm-ct-wrap{display:flex;justify-content:center}
.gm-ct{width:min(220px,60%)}
.gm-ct>img{width:72px;height:48px}
.gm-fxs{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:6px}
.gm-fx>img{width:40px;height:40px;margin:4px 0;border:2px solid #2e222f;border-radius:3px}
.gm-cur .gm-name{font-size:8px;line-height:1.3;min-height:21px;color:#ffe08a;text-shadow:1px 1px #000;display:flex;align-items:center;justify-content:center}
.gm-share{margin-top:12px;padding:8px 10px;background:none;border:none}
.gm-share-lbl{font-size:8px;text-align:center;margin-bottom:8px;color:#f1c40f;text-shadow:1px 1px #000}
.gm-share input{width:100%;accent-color:#f1c40f;cursor:var(--cur-finger)}
.gm-share-ends{display:flex;justify-content:space-between;font-size:6px;color:#bdc3c7;margin-top:4px}
.gm-note{font-size:7px;color:#bdc3c7;text-align:center;margin-top:10px;line-height:1.5}
.gm-flash{animation:gmflash .5s 2}@keyframes gmflash{50%{border-color:#f1c40f}}
.gm-wel-gift{display:flex;align-items:center;justify-content:center;gap:10px;margin:6px 0 4px;font-size:22px;color:#f1c40f;text-shadow:2px 2px #000}
.gm-wel-gift canvas{width:44px;height:40px;image-rendering:pixelated}
.gm-wel-btns{display:flex;gap:10px;margin-top:12px}
.gm-wel-lines{width:min(320px,100%);margin:2px auto 8px}
.gm-wel-mode{display:flex;align-items:center;justify-content:center;gap:10px;margin:10px 0 2px;font-size:10px;color:#2dff9d;text-shadow:1px 1px #000;line-height:1.4}
.gm-wel-mode img{width:72px;height:28px;image-rendering:pixelated;flex-shrink:0}
.ach-tier-header{flex-wrap:wrap;row-gap:4px}
.ach-tier-gems{flex-basis:100%;order:5;display:flex;align-items:center;justify-content:center;gap:6px;font-size:10px;color:#ffe08a;text-shadow:1px 1px #000;line-height:1}
.ach-tier-gems img{width:16px;height:16px;image-rendering:pixelated;position:relative;top:-1px}
body.mode-portrait .ach-tier-gems{font-size:9px}
body.mode-portrait .ach-tier-gems img{width:16px;height:16px}
.gm-wel-line{display:flex;justify-content:space-between;gap:10px;font-size:9px;line-height:1.9;color:#fff;text-shadow:1px 1px #000}
.gm-wel-line b{color:#f1c40f;font-weight:normal}
.gm-panel .gm-wel-btns .gm-back{margin-top:0;flex:1 1 0;width:auto;min-width:0;font-size:12px;padding:8px 4px}
body.mode-portrait .gm-wel-gift{font-size:16px}
.gm-big{text-align:center;font-size:clamp(10px,2.4vw,13px);margin:8px 0 6px;line-height:1.5;color:#f1c40f;text-shadow:2px 2px #000}
body.mode-portrait .gm-hats{grid-template-columns:repeat(4,minmax(0,1fr))}
body.mode-portrait .gm-hat .gm-name{font-size:7px;min-height:19px}
body.mode-portrait .gm-hat canvas{width:54px;height:54px}
body.mode-portrait .gm-gl canvas{width:44px;height:44px}
body.mode-portrait .gm-curs{grid-template-columns:repeat(3,minmax(0,1fr))}
body.mode-portrait .gm-fxs{grid-template-columns:repeat(3,minmax(0,1fr))}
body.mode-portrait .gm-cur .gm-name{font-size:7px;min-height:19px}
body.mode-portrait .gm-panel .gm-cur .gm-btn{font-size:8px;padding:2px 2px;min-width:85%}
body.mode-portrait .gm-panel .gm-pack .gm-btn{font-size:7px;padding:2px 2px}
body.mode-portrait .gm-packs{grid-template-columns:repeat(2,minmax(0,1fr))}
body.mode-portrait .gm-offer .gm-offer-t{font-size:11px}
body.mode-portrait .gm-panel .gm-hat .gm-btn{font-size:8px;padding:2px 2px;min-width:85%}
body.mode-portrait .gm-title{font-size:clamp(9px,3.8vw,20px)}
body.mode-portrait .gm-bal{top:6px;left:0;font-size:11px;gap:4px}
body.mode-portrait #gems-store-overlay .gm-title{box-sizing:border-box}
body.mode-portrait .gm-bal img{width:14px;height:14px}
body.mode-portrait .gm-panel{border-width:18px 20px 32px 20px}
`;
        document.head.appendChild(st);
    }

    // ── Contador en partida + botón en el menú ──────────────────────────────
    function _mountHud() {
        if (document.getElementById('gems-hud-btn')) return;
        const pause = document.getElementById('pause-btn');
        if (!pause || !pause.parentNode) return;
        const b = document.createElement('button');
        b.id = 'gems-hud-btn';
        b.type = 'button';
        // Solo el icono (button_gems.png, mismo formato que button_options.png); el
        // saldo se ve dentro de la tienda.
        b.title = _shopTitle();
        b.setAttribute('aria-label', _shopTitle());
        b.addEventListener('click', e => { e.stopPropagation(); openStore(); });
        pause.parentNode.insertBefore(b, pause);
        // Mismo tamaño que el botón de opciones, que cambia según la pantalla
        // (30/44/64 px…) — se copia en vez de duplicar todas sus reglas de CSS.
        const sync = () => {
            const r = pause.getBoundingClientRect();
            if (r.width > 0 && r.height > 0) { b.style.width = r.width + 'px'; b.style.height = r.height + 'px'; }
        };
        sync();
        setTimeout(sync, 500);
        window.addEventListener('resize', () => setTimeout(sync, 200));
    }
    function _mountMenuBtn() {
        if (document.getElementById('mm-gems-btn')) return;
        const bar = document.getElementById('mm-bottom-bar');
        if (!bar) return;
        const b = document.createElement('button');
        b.id = 'mm-gems-btn';
        b.className = 'mm-bar-btn';
        b.type = 'button';
        b.innerHTML = '<span class="mm-bar-icon mm-icon-gems"></span><span class="mm-bar-label" data-i18n="' + _menuKey() + '"></span>';
        b.querySelector('.mm-bar-label').textContent = T(_menuKey(), 'SHOP');
        b.addEventListener('click', e => { e.stopPropagation(); openStore(); });
        const steam = document.getElementById('mm-steam-btn');
        bar.insertBefore(b, steam || null);
    }
    // Saldo en la barra de la tienda de la partida (pedido del usuario): a la izquierda de
    // #shop-header, siempre visible mientras se juega; pulsarlo abre la tienda de gemas.
    // Es un <div> (no <span>): style.css/portrait.css ya dan estilo a los span de esa barra.
    function _mountShopBal() {
        if (document.getElementById('gems-shop-bal')) return;
        const hdr = document.getElementById('shop-header');
        if (!hdr) return;
        const d = document.createElement('div');
        d.id = 'gems-shop-bal';
        // Icono blanco de la interfaz (pixelart_design/gem.png), pedido del usuario
        d.innerHTML = '<img src="pixelart_design/gem.png" alt=""><div id="gems-shop-bal-val">0</div>';
        d.title = _shopTitle();
        // En móvil la barra despliega la tienda al tocarla: que este toque no llegue a ella.
        ['pointerdown', 'mousedown', 'touchstart'].forEach(ev => d.addEventListener(ev, e => e.stopPropagation(), { passive: true }));
        d.addEventListener('click', e => { e.stopPropagation(); openStore(); });
        hdr.appendChild(d);
        // Centrado con el título de la barra, no con la caja: en PC la barra lleva 10 px de
        // padding-bottom (index.html) y el 50% quedaba 5 px por debajo de la franja rosa.
        const align = () => {
            const h2 = hdr.querySelector('h2');
            if (h2 && h2.offsetHeight) d.style.top = (h2.offsetTop + h2.offsetHeight / 2) + 'px';
        };
        align();
        setTimeout(align, 500);
        window.addEventListener('resize', () => setTimeout(align, 150));
        _refreshHud();
    }
    function _refreshHud() {
        const v = document.getElementById('gems-shop-bal-val');
        if (v) v.textContent = String(_gems);
        // Con todo desbloqueado las gemas ya no sirven para nada (pedido del usuario): fuera el contador
        const b = document.getElementById('gems-shop-bal');
        if (b) b.style.display = hasAll() ? 'none' : '';
        // VIP sin banner: en PC la tienda tenía un tope de alto (style.css, 100vh - 130px) pensado para
        // la barra de arriba CON banner; sin él quedaba una franja negra abajo. Ver CSS .gm-vip.
        document.body.classList.toggle('gm-vip', isVip());
    }

    // ── Tienda ──────────────────────────────────────────────────────────────
    let _store = null, _pausedBefore = null;
    function _glassesPreview(i) {
        const cv = document.createElement('canvas'); cv.width = 24; cv.height = 24;
        const x = cv.getContext('2d'); x.imageSmoothingEnabled = false;
        const draw = () => {
            x.clearRect(0, 0, 24, 24);
            // Solo la cabeza (recorte de 12x12 alrededor del ojo) a x2: las gafas son pequeñas
            const sp = glassesSpot(0, 0), ox = sp.ex - 7, oy = sp.ey - 5;
            if (_henPreview.complete && _henPreview.naturalWidth) x.drawImage(_henPreview, ox, oy, 12, 12, 0, 0, 24, 24);
            if (glassesImage.complete && glassesImage.naturalWidth) x.drawImage(glassesImage, i * GL_W, 0, GL_W, GL_H, (sp.ex - GL_EYE_X - ox) * 2, (sp.ey - GL_EYE_Y - oy) * 2, GL_W * 2, GL_H * 2);
        };
        draw();
        if (!glassesImage.complete) glassesImage.addEventListener('load', draw, { once: true });
        if (!_henPreview.complete) _henPreview.addEventListener('load', draw, { once: true });
        return cv;
    }
    function _hatPreview(i) {
        const cv = document.createElement('canvas'); cv.width = 24; cv.height = 24;
        const x = cv.getContext('2d'); x.imageSmoothingEnabled = false;
        const draw = () => {
            x.clearRect(0, 0, 24, 24);
            if (_henPreview.complete && _henPreview.naturalWidth) x.drawImage(_henPreview, 0, 0, 24, 24, 0, 4, 24, 24);
            const a = HAT_ANCHORS[0][0];
            if (hatImage.complete && hatImage.naturalWidth) x.drawImage(hatImage, i * HAT_W, 0, HAT_W, HAT_H, a[0] - HAT_W / 2, a[1] + HAT_OVERLAP + hatDy(i) - HAT_H + 4, HAT_W, HAT_H);
        };
        draw();
        if (!hatImage.complete) hatImage.addEventListener('load', draw, { once: true });
        if (!_henPreview.complete) _henPreview.addEventListener('load', draw, { once: true });
        return cv;
    }
    // Gema de color (pixel art, 11x10) para los paquetes. gem.png es el icono blanco de la
    // interfaz; aquí se quiere algo más vistoso. O contorno, L luz, M medio, D sombra.
    const _GEM_PX = [
        '...OOOOO...',
        '..OLLMMDO..',
        '.OLLLMMDDO.',
        'OOOOOOOOOOO',
        'OLLMMMMMDDO',
        '.OLMMMMMDO.',
        '..OLMMMDO..',
        '...OLMDO...',
        '....OMO....',
        '.....O.....',
    ];
    const _GEM_COL = { O: '#323353', L: '#c7f2ff', M: '#4d9be6', D: '#3b5dc9' };
    function _drawGem(c, x0, y0) {
        _GEM_PX.forEach((row, y) => { for (let x = 0; x < row.length; x++) { const k = row[x]; if (k !== '.') { c.fillStyle = _GEM_COL[k]; c.fillRect(x0 + x, y0 + y, 1, 1); } } });
    }
    // Cofre del tesoro abierto ("Desbloquear todo") y corona enjoyada (VIP), mismo estilo.
    // O contorno, W/M/D madera, G/g/L oro, Y perla, R rubí, B zafiro.
    const _OFFER_COL = { O: '#2e222f', W: '#cd683d', M: '#9e4539', D: '#6e2727', G: '#f9c22b', g: '#c99418', L: '#fff3a0', Y: '#ffffff', R: '#ea4f36', B: '#4d9be6' };
    const _CHEST_LID = ['.OOOOOOOOOOOOOOOOOOOO.', 'OWWWWWWWWWWWWWWWWWWWWO', 'OMMMMMMMMMMMMMMMMMMMMO', 'OGGGGGGGGGGGGGGGGGGGGO', '.OOOOOOOOOOOOOOOOOOOO.'];
    const _CHEST_BODY = ['OOOOOOOOOOOOOOOOOOOOOO', 'OGGGGGGGGGGGGGGGGGGGGO', 'OMMMMMMMMGGGGMMMMMMMMO', 'OWWWWWWWWGOOGWWWWWWWWO', 'OMMMMMMMMGGGGMMMMMMMMO', 'OMMMMMMMMMMMMMMMMMMMMO', 'ODDDDDDDDDDDDDDDDDDDDO', 'OggggggggggggggggggggO', '.OOOOOOOOOOOOOOOOOOOO.'];
    const _CROWN = ['..O.......O.......O..', '.OYO.....OYO.....OYO.', '..O.......O.......O..', '.OGO.....OGO.....OGO.', '.OGGO...OGGGO...OGGO.', '.OGGGO.OGGGGGO.OGGGO.', '.OGGGGOGGGGGGGOGGGGO.', '.OGGGGGGGGGGGGGGGGGO.', 'OLLLLLLLLLLLLLLLLLLLO', 'OGGRRGGGGBBBGGGGRRGGO', 'OGGRRGGGGBBBGGGGRRGGO', 'OgggggggggggggggggggO', '.OOOOOOOOOOOOOOOOOOO.'];
    function _putPx(c, rows, x0, y0) {
        rows.forEach((r, y) => { for (let x = 0; x < r.length; x++) { const k = r[x]; if (_OFFER_COL[k]) { c.fillStyle = _OFFER_COL[k]; c.fillRect(x0 + x, y0 + y, 1, 1); } } });
    }
    function _spark(c, x, y) { c.fillStyle = '#ffffff'; c.fillRect(x, y - 1, 1, 3); c.fillRect(x - 1, y, 3, 1); }
    // Iconos de "Cómo conseguir gemas": trofeo de logros y huevo de gema.
    const _EARN_COL = { O: '#2e222f', W: '#ffffff', S: '#c7dcd0', D: '#3e3546', R: '#ea4f36', Y: '#f9c22b', y: '#c99418' };
    // Caja de regalo (código regalo): R lazo rojo, Y caja dorada, y sombra
    const _GIFT = ['...RR.RR...', '..R..R..R..', '...RRRRR...', 'OOOOORROOOO', 'OYYYYRRYYYO', 'OYYYYRRYYyO', 'OOOOORROOOO', '.OYYYRRYYO.', '.OYYYRRYyO.', '.OYYYRRYyO.', '.OyyyRRyyO.', '.OOOORROOO.'];
    const _EGG = ['...OOO...', '..OWWWO..', '.OWWWWWO.', '.OWWWWWO.', 'OWWWWWWSO', 'OWWWWWWSO', 'OWWWWWWSO', 'OWWWWWSSO', '.OWWWSSO.', '..OOOOO..'];
    function _earnIcon(k) {
        const cv = document.createElement('canvas'); cv.width = 36; cv.height = 24; cv.className = 'gm-pk-ico';
        const c = cv.getContext('2d'); c.imageSmoothingEnabled = false;
        const px = (rows, x0, y0) => rows.forEach((r, y) => { for (let x = 0; x < r.length; x++) { const col = _EARN_COL[r[x]]; if (col) { c.fillStyle = col; c.fillRect(x0 + x, y0 + y, 1, 1); } } });
        if (k === 'egg') { px(_EGG, 13, 13); _drawGem(c, 12, 1); }
        else if (k === 'code') { px(_GIFT, 10, 6); _drawGem(c, 23, 1); }
        else {
            const im = new Image();
            im.onload = () => { c.drawImage(im, 0, 0, 20, 20, 8, 4, 20, 20); _drawGem(c, 24, 0); };
            im.src = 'pixelart_design/ach_tier_gold.png';
        }
        return cv;
    }
    // 100: una gema · 300: montón de tres · todo: cofre con tesoro · VIP: corona
    function _packIcon(id) {
        const cv = document.createElement('canvas'); cv.width = 36; cv.height = 24; cv.className = 'gm-pk-ico';
        const c = cv.getContext('2d'); c.imageSmoothingEnabled = false;
        if (id === 'gems_100') _drawGem(c, 12, 8);
        else if (id === 'gems_300') { _drawGem(c, 6, 12); _drawGem(c, 19, 12); _drawGem(c, 12, 4); }
        else if (id === 'vip') { _putPx(c, _CROWN, 7, 6); _spark(c, 4, 4); _spark(c, 31, 6); _spark(c, 18, 2); }
        else { _putPx(c, _CHEST_LID, 7, 0); _drawGem(c, 8, 4); _drawGem(c, 17, 3); _putPx(c, _CHEST_BODY, 7, 13); _spark(c, 5, 5); _spark(c, 31, 3); _spark(c, 30, 12); }
        return cv;
    }
    function _buildStore() {
        const ov = document.createElement('div');
        ov.id = 'gems-store-overlay';
        ov.className = 'gm-overlay';
        ov.innerHTML = `<div class="gm-panel">
            <h2 class="gm-title" id="gm-title"></h2>
            <div class="gm-bal"><img src="pixelart_design/gem.png" alt=""><span id="gm-bal-val">0</span></div>
            <button class="pixel-btn btn-sprite btn-5 gm-btn gm-hback" type="button" id="gm-back"></button>
            <div class="gm-body">
            <div id="gm-packs-wrap"><div class="gm-sec" id="gm-sec-packs"></div><div class="gm-packs" id="gm-packs"></div></div>
            <div id="gm-earn-wrap"><div class="gm-sec" id="gm-sec-earn"></div><div class="gm-packs gm-earn" id="gm-earn"></div></div>
            <div class="gm-sec" id="gm-sec-hats"></div><div class="gm-hats" id="gm-hats"></div>
            <div class="gm-share"><div class="gm-share-lbl" id="gm-share-lbl"></div><input type="range" id="gm-share" min="0" max="100" step="5"><div class="gm-share-ends"><span id="gm-share-none"></span><span id="gm-share-all"></span></div></div>
            <div class="gm-sec" id="gm-sec-gl"></div><div class="gm-hats" id="gm-gls"></div>
            <div class="gm-share"><div class="gm-share-lbl" id="gm-gls-lbl"></div><input type="range" id="gm-gls-share" min="0" max="100" step="5"><div class="gm-share-ends"><span id="gm-gls-none"></span><span id="gm-gls-all"></span></div></div>
            <div class="gm-sec" id="gm-sec-rs"></div><div class="gm-curs" id="gm-rss" style="grid-template-columns:repeat(4,minmax(0,1fr))"></div>
            <div class="gm-sec" id="gm-sec-ct"></div><div class="gm-ct-wrap"><div class="gm-cur gm-ct" id="gm-ct"><img alt=""><div class="gm-name" id="gm-ct-name"></div><button class="pixel-btn btn-sprite btn-orange gm-btn" type="button" id="gm-ct-btn"></button></div></div>
            <div class="gm-share" id="gm-ct-box"><div class="gm-share-lbl" id="gm-ct-lbl"></div><input type="range" id="gm-ct-share" min="0" max="100" step="5"><div class="gm-share-ends"><span id="gm-ct-none"></span><span id="gm-ct-all"></span></div></div>
            <div class="gm-sec" id="gm-sec-curs"></div><div class="gm-curs" id="gm-curs"></div>
            <div class="gm-sec" id="gm-sec-amb"></div><div class="gm-fxs" id="gm-ambs"></div>
            <div class="gm-sec" id="gm-sec-fx"></div><div class="gm-fxs" id="gm-fxs"></div>
            <div class="gm-share" id="gm-fxd-box"><div class="gm-share-lbl" id="gm-fxd-lbl"></div><input type="range" id="gm-fxd" min="10" max="100" step="5"><div class="gm-share-ends"><span id="gm-fxd-less"></span><span id="gm-fxd-more"></span></div></div>
            <div class="gm-note" id="gm-note"></div>
            </div>
        </div>`;
        ov.addEventListener('click', e => { if (e.target === ov) closeStore(); });
        ov.querySelector('#gm-back').addEventListener('click', closeStore);
        // Barra "% de gallinas con sombrero": en vivo al arrastrar, se guarda al soltar.
        const sl = ov.querySelector('#gm-share');
        sl.addEventListener('input', () => { _share = Math.max(0, Math.min(100, +sl.value || 0)); _refreshStore(); });
        sl.addEventListener('change', () => { _share = Math.max(0, Math.min(100, +sl.value || 0)); _saveHats(); _refreshStore(); });
        // Barra "% de gallinas con gafas": igual que la de sombreros.
        const gsl = ov.querySelector('#gm-gls-share');
        gsl.addEventListener('input', () => { _glShare = Math.max(0, Math.min(100, +gsl.value || 0)); _refreshStore(); });
        gsl.addEventListener('change', () => { _glShare = Math.max(0, Math.min(100, +gsl.value || 0)); _saveHats(); _refreshStore(); });
        // Pollitos de colores: botón y barra de %.
        ov.querySelector('#gm-ct-btn').addEventListener('click', _buyOrToggleChicks);
        _chicksPreview(ov.querySelector('#gm-ct > img'));
        const csl = ov.querySelector('#gm-ct-share');
        csl.addEventListener('input', () => { _ctShare = Math.max(0, Math.min(100, +csl.value || 0)); _refreshStore(); });
        csl.addEventListener('change', () => { _ctShare = Math.max(0, Math.min(100, +csl.value || 0)); _saveHats(); _refreshStore(); });
        // Barra de densidad de los efectos: en vivo al arrastrar, se guarda al soltar.
        const fd = ov.querySelector('#gm-fxd');
        fd.addEventListener('input', () => { _fxDens = Math.max(10, Math.min(100, +fd.value || FX_DENS_DEFAULT)); });
        fd.addEventListener('change', () => { _fxDens = Math.max(10, Math.min(100, +fd.value || FX_DENS_DEFAULT)); _saveHats(); });
        document.body.appendChild(ov);
        // Barra de scroll propia en el borde derecho del panel: los navegadores de móvil
        // esconden la nativa y así se ve siempre que hay más opciones (pedido del usuario).
        const sb = document.createElement('div'); sb.className = 'gm-sbar';
        sb.innerHTML = '<div class="gm-sbar-thumb"></div>';
        ov.querySelector('.gm-panel').appendChild(sb);
        ov.querySelector('.gm-body').addEventListener('scroll', _syncSbar, { passive: true });
        // Arrastrar el pulgar; pulsar en la pista lo centra ahí y sigue arrastrando.
        sb.addEventListener('pointerdown', e => {
            const body = ov.querySelector('.gm-body'), thumb = sb.firstChild;
            const r = sb.getBoundingClientRect(), th = thumb.offsetHeight, range = sb.clientHeight - th;
            if (range <= 0) return;
            e.preventDefault();
            let grab = e.clientY - r.top - thumb.offsetTop;
            if (grab < 0 || grab > th) grab = th / 2;   // fuera del pulgar: se centra en el dedo
            const move = ev => {
                const y = Math.max(0, Math.min(range, ev.clientY - r.top - grab));
                body.scrollTop = y / range * (body.scrollHeight - body.clientHeight);
            };
            const up = () => {
                sb.classList.remove('drag');
                window.removeEventListener('pointermove', move);
                window.removeEventListener('pointerup', up);
                window.removeEventListener('pointercancel', up);
            };
            sb.classList.add('drag');
            move(e);
            window.addEventListener('pointermove', move);
            window.addEventListener('pointerup', up);
            window.addEventListener('pointercancel', up);
        });
        window.addEventListener('resize', () => setTimeout(() => { _fitTitle(); _syncSbar(); }, 100));
        // Paquetes
        const pk = ov.querySelector('#gm-packs');
        PACKS.forEach(p => {
            const d = document.createElement('div'); d.className = 'gm-pack';
            d.innerHTML = `<div class="gm-n">${p.gems}</div><div class="gm-offer-d"></div><div class="gm-bonus">${p.bonus || ''}</div><button class="pixel-btn btn-sprite btn-blue gm-btn" type="button"></button>`;
            d.insertBefore(_packIcon(p.id), d.firstChild);
            d.querySelector('button').addEventListener('click', () => _buyPack(p));
            pk.appendChild(d);
        });
        OFFERS.forEach(o => {
            const d = document.createElement('div'); d.className = 'gm-pack gm-offer'; d.dataset.offer = o.id;
            d.innerHTML = '<div class="gm-n gm-offer-t"></div><div class="gm-offer-d"></div><button class="pixel-btn btn-sprite btn-blue gm-btn" type="button"></button>';
            d.insertBefore(_packIcon(o.id), d.firstChild);
            d.querySelector('button').addEventListener('click', () => _buyOffer(o));
            pk.appendChild(d);
        });
        // Cómo conseguir gemas (mercados sin pagos): logros, tiempo jugado y huevos de gema
        const eg = ov.querySelector('#gm-earn');
        ['ach', 'egg'].forEach(k => {
            const d = document.createElement('div'); d.className = 'gm-pack gm-earn-card'; d.dataset.earn = k;
            d.appendChild(_earnIcon(k));
            d.insertAdjacentHTML('beforeend', '<div class="gm-n gm-offer-t"></div><div class="gm-offer-d"></div>');
            eg.appendChild(d);
        });
        // Tarjeta del código regalo (misma celda que las otras)
        const cc = document.createElement('div'); cc.className = 'gm-pack gm-code-card';
        cc.appendChild(_earnIcon('code'));
        cc.insertAdjacentHTML('beforeend', '<div class="gm-n gm-offer-t" id="gm-code-lbl"></div><input id="gm-code-in" type="text" maxlength="32" autocomplete="off" spellcheck="false"><button class="pixel-btn btn-sprite btn-blue gm-btn" type="button" id="gm-code-btn"></button>');
        eg.appendChild(cc);
        // Código regalo: las teclas no deben llegar al juego mientras se escribe
        const cin = cc.querySelector('#gm-code-in');
        ['keydown', 'keyup', 'keypress'].forEach(ev => cin.addEventListener(ev, e => { e.stopPropagation(); if (ev === 'keydown' && e.key === 'Enter') _redeemCode(); }));
        cin.addEventListener('input', () => { const v = cin.value.toUpperCase().replace(/[^A-Z0-9]/g, ''); if (v !== cin.value) cin.value = v; });
        cc.querySelector('#gm-code-btn').addEventListener('click', _redeemCode);
        // Sombreros
        const hg = ov.querySelector('#gm-hats');
        HATS.forEach((h, i) => {
            const d = document.createElement('div'); d.className = 'gm-hat'; d.dataset.i = String(i);
            d.appendChild(_hatPreview(i));
            const n = document.createElement('div'); n.className = 'gm-name'; d.appendChild(n);
            const b = document.createElement('button'); b.className = 'pixel-btn btn-sprite btn-orange gm-btn'; b.type = 'button';
            b.addEventListener('click', () => { if (_owned.includes(h.id)) _toggleHat(i); else _buyHat(i); });
            d.appendChild(b);
            hg.appendChild(d);
        });
        // Gafas (mismas tarjetas que los sombreros)
        const glg = ov.querySelector('#gm-gls');
        GLASSES.forEach((g, i) => {
            const d = document.createElement('div'); d.className = 'gm-hat gm-gl'; d.dataset.g = String(i);
            d.appendChild(_glassesPreview(i));
            const n = document.createElement('div'); n.className = 'gm-name'; d.appendChild(n);
            const b = document.createElement('button'); b.className = 'pixel-btn btn-sprite btn-orange gm-btn'; b.type = 'button';
            b.addEventListener('click', () => { if (_glOwned.includes(g.id)) _toggleGlasses(i); else _buyGlasses(i); });
            d.appendChild(b);
            glg.appendChild(d);
        });
        // Skins de gallo
        const rg = ov.querySelector('#gm-rss');
        ROOSTER_SKINS.forEach((r, i) => {
            const d = document.createElement('div'); d.className = 'gm-cur gm-rs'; d.dataset.rs = String(i);
            const im = document.createElement('img'); im.alt = ''; d.appendChild(im); _roosterPreview(r, im);
            const n = document.createElement('div'); n.className = 'gm-name'; d.appendChild(n);
            const b = document.createElement('button'); b.className = 'pixel-btn btn-sprite btn-orange gm-btn'; b.type = 'button';
            b.addEventListener('click', () => _useRoosterSkin(i));
            d.appendChild(b);
            rg.appendChild(d);
        });
        // Cursores
        const cg = ov.querySelector('#gm-curs');
        CURSORS.forEach((c, i) => {
            const d = document.createElement('div'); d.className = 'gm-cur'; d.dataset.i = String(i);
            const im = document.createElement('img'); im.alt = ''; d.appendChild(im);
            const n = document.createElement('div'); n.className = 'gm-name'; d.appendChild(n);
            const b = document.createElement('button'); b.className = 'pixel-btn btn-sprite btn-orange gm-btn'; b.type = 'button';
            b.addEventListener('click', () => _useCursor(i));
            d.appendChild(b);
            cg.appendChild(d);
        });
        // Efectos de partículas
        // Ambientes
        const ag = ov.querySelector('#gm-ambs');
        AMBIENCES.forEach((a, i) => {
            const d = document.createElement('div'); d.className = 'gm-cur gm-fx gm-amb'; d.dataset.amb = String(i);
            const im = document.createElement('img'); im.alt = ''; im.src = _ambPreview(a); d.appendChild(im);
            const n = document.createElement('div'); n.className = 'gm-name'; d.appendChild(n);
            const b = document.createElement('button'); b.className = 'pixel-btn btn-sprite btn-orange gm-btn'; b.type = 'button';
            b.addEventListener('click', () => _useAmbience(i));
            d.appendChild(b);
            ag.appendChild(d);
        });
        const fg = ov.querySelector('#gm-fxs');
        EFFECTS.forEach((fx, i) => {
            const d = document.createElement('div'); d.className = 'gm-cur gm-fx'; d.dataset.fx = String(i);
            const im = document.createElement('img'); im.alt = ''; im.src = _fxPreview(fx.id); d.appendChild(im);
            const n = document.createElement('div'); n.className = 'gm-name'; d.appendChild(n);
            const b = document.createElement('button'); b.className = 'pixel-btn btn-sprite btn-orange gm-btn'; b.type = 'button';
            b.addEventListener('click', () => _useEffect(i));
            d.appendChild(b);
            fg.appendChild(d);
        });
        return ov;
    }
    function _refreshStore() {
        if (!_store) return;
        _store.querySelector('#gm-title').textContent = _shopTitle();
        _store.querySelector('#gm-back').textContent = T('back', 'BACK');
        _store.querySelector('#gm-bal-val').textContent = String(_gems);
        // Con todo desbloqueado: sin saldo ni paquetes de gemas (no tendría en qué gastarlas);
        // quedan las dos compras únicas (la de VIP, por si quiere pasar a VIP).
        const _all = hasAll();
        _store.querySelector('.gm-bal').style.display = _all ? 'none' : '';
        _store.querySelectorAll('.gm-pack:not(.gm-offer):not(.gm-earn-card):not(.gm-code-card)').forEach(d => { d.style.display = _all ? 'none' : ''; });
        _store.querySelector('#gm-packs').classList.toggle('gm-packs-2', _all);
        _store.querySelector('#gm-sec-packs').textContent = T('gemsPacks', 'Gem packs');
        _store.querySelector('#gm-sec-hats').textContent = T('gemsHats', 'Hats');
        const sl = _store.querySelector('#gm-share');
        if (document.activeElement !== sl) sl.value = String(_share);
        _store.querySelector('#gm-share-lbl').textContent = T('gemsHatShare', 'Chickens with hats: {n}%').replace('{n}', _share);
        _store.querySelector('#gm-share-none').textContent = T('gemsHatShareNone', 'Nobody');
        _store.querySelector('#gm-share-all').textContent = T('gemsHatShareAll', 'Everyone');
        // Cómo conseguir gemas: solo donde las gemas salen de jugar
        _store.querySelector('#gm-earn-wrap').style.display = (_freeSources() && !hasAll()) ? '' : 'none';
        _store.querySelector('#gm-code-lbl').textContent = T('gemsCodeLbl', 'Do you have a code?');
        _store.querySelector('#gm-code-in').placeholder = T('gemsCodePh', 'CODE');
        if (!_codeBusy) _store.querySelector('#gm-code-btn').textContent = T('gemsCodeBtn', 'REDEEM');
        _store.querySelector('#gm-sec-earn').textContent = T('gemsEarnTitle', 'How to get gems');
        const _earnTxt = {
            ach:  [T('gemsEarnAch', 'Achievements'), T('gemsEarnAchDesc', '+{min} to +{max} gems per achievement').replace('{min}', _achTable().bronze).replace('{max}', _achTable().diamond)],
            egg:  [T('gemsEarnEgg', 'Gem eggs'), T('gemsEarnEggDesc', 'Now and then hens lay gem eggs: grab them before the gem is gone!')],
        };
        _store.querySelectorAll('.gm-earn-card').forEach(d => {
            const tx = _earnTxt[d.dataset.earn];
            d.querySelector('.gm-offer-t').textContent = tx[0];
            d.querySelector('.gm-offer-d').textContent = tx[1];
        });
        // En la app de CrazyGames no se puede mostrar compra con dinero real (requisito).
        _store.querySelector('#gm-packs-wrap').style.display = (!_paidMarket() || _inCrazyGamesApp()) ? 'none' : '';
        const _priceTxt = pr => PURCHASES_LIVE ? pr : _debugPurchases() ? pr + ' (TEST)' : T('gemsComingSoon', 'Coming soon');
        _store.querySelectorAll('.gm-pack:not(.gm-offer):not(.gm-earn-card):not(.gm-code-card)').forEach((d, i) => {
            d.querySelector('.gm-offer-d').textContent = T(PACKS[i].desc, '');
            d.querySelector('button').textContent = _priceTxt(PACKS[i].price);
        });
        _store.querySelectorAll('.gm-offer').forEach(d => {
            const o = OFFERS.find(x => x.id === d.dataset.offer);
            d.querySelector('.gm-offer-t').textContent = T(o.key, o.id);
            d.querySelector('.gm-offer-d').textContent = T(o.desc, '');
            const own = o.id === 'vip' ? _vip : (_unlockAll || _vip);
            const b = d.querySelector('button');
            b.className = 'pixel-btn btn-sprite gm-btn ' + (own ? 'btn-green' : 'btn-blue');
            b.textContent = own ? T('gemsOwned', 'OWNED') : _priceTxt(o.price);
        });
        _store.querySelectorAll('.gm-hat:not(.gm-gl)').forEach(d => {
            const i = +d.dataset.i, h = HATS[i];
            d.querySelector('.gm-name').textContent = T(h.key, h.id);
            const b = d.querySelector('button');
            if (_owned.includes(h.id)) {
                const on = !_off.includes(h.id);
                b.className = 'pixel-btn btn-sprite gm-btn ' + (on ? 'btn-green' : 'btn-5');
                b.textContent = on ? T('gemsHatOn', 'ON') : T('gemsHatOff', 'OFF');
            } else {
                b.className = 'pixel-btn btn-sprite btn-orange gm-btn';
                b.innerHTML = '<img src="pixelart_design/gem.png" alt="" style="width:11px;height:11px;image-rendering:pixelated"> ' + h.price;
            }
        });
        _store.querySelector('#gm-sec-gl').textContent = T('gemsGlasses', 'Glasses');
        const gsl = _store.querySelector('#gm-gls-share');
        if (document.activeElement !== gsl) gsl.value = String(_glShare);
        _store.querySelector('#gm-gls-lbl').textContent = T('gemsGlassesShare', 'Chickens with glasses: {n}%').replace('{n}', _glShare);
        _store.querySelector('#gm-gls-none').textContent = T('gemsHatShareNone', 'Nobody');
        _store.querySelector('#gm-gls-all').textContent = T('gemsHatShareAll', 'Everyone');
        _store.querySelectorAll('.gm-gl').forEach(d => {
            const g = GLASSES[+d.dataset.g];
            d.querySelector('.gm-name').textContent = T(g.key, g.id);
            const b = d.querySelector('button');
            if (_glOwned.includes(g.id)) {
                const on = !_glOff.includes(g.id);
                b.className = 'pixel-btn btn-sprite gm-btn ' + (on ? 'btn-green' : 'btn-5');
                b.textContent = on ? T('gemsHatOn', 'ON') : T('gemsHatOff', 'OFF');
            } else {
                b.className = 'pixel-btn btn-sprite btn-orange gm-btn';
                b.innerHTML = '<img src="pixelart_design/gem.png" alt="" style="width:11px;height:11px;image-rendering:pixelated"> ' + g.price;
            }
        });
        _store.querySelector('#gm-sec-rs').textContent = T('gemsRoosters', 'Roosters');
        _store.querySelectorAll('.gm-rs').forEach(d => {
            const r = ROOSTER_SKINS[+d.dataset.rs];
            d.querySelector('.gm-name').textContent = T(r.key, r.id);
            const b = d.querySelector('button');
            if (r.price === 0 || _rsOwned.includes(r.id)) {
                const on = !_rsOff.includes(r.id);
                b.className = 'pixel-btn btn-sprite gm-btn ' + (on ? 'btn-green' : 'btn-5');
                b.textContent = on ? T('gemsHatOn', 'ON') : T('gemsHatOff', 'OFF');
            } else {
                b.className = 'pixel-btn btn-sprite btn-orange gm-btn';
                b.innerHTML = '<img src="pixelart_design/gem.png" alt="" style="width:11px;height:11px;image-rendering:pixelated"> ' + r.price;
            }
        });
        _store.querySelector('#gm-sec-ct').textContent = T('gemsChicks', 'Chicks');
        _store.querySelector('#gm-ct-name').textContent = T('ctName', 'Colorful chicks');
        const cb = _store.querySelector('#gm-ct-btn');
        if (_ctOwned) {
            cb.className = 'pixel-btn btn-sprite gm-btn ' + (_ctOff ? 'btn-5' : 'btn-green');
            cb.textContent = _ctOff ? T('gemsHatOff', 'OFF') : T('gemsHatOn', 'ON');
        } else {
            cb.className = 'pixel-btn btn-sprite btn-orange gm-btn';
            cb.innerHTML = '<img src="pixelart_design/gem.png" alt="" style="width:11px;height:11px;image-rendering:pixelated"> ' + CHICK_TINT_PRICE;
        }
        // La barra solo con el artículo comprado
        _store.querySelector('#gm-ct-box').style.display = _ctOwned ? '' : 'none';
        const csl = _store.querySelector('#gm-ct-share');
        if (document.activeElement !== csl) csl.value = String(_ctShare);
        _store.querySelector('#gm-ct-lbl').textContent = T('ctShare', 'Colorful chicks: {n}%').replace('{n}', _ctShare);
        _store.querySelector('#gm-ct-none').textContent = T('gemsHatShareNone', 'Nobody');
        _store.querySelector('#gm-ct-all').textContent = T('gemsHatShareAll', 'Everyone');
        _store.querySelector('#gm-sec-curs').textContent = T('gemsCursors', 'Cursors');
        const gc = window.GameCursors;
        _store.querySelectorAll('.gm-cur:not(.gm-fx):not(.gm-rs):not(.gm-ct)').forEach(d => {
            const c = CURSORS[+d.dataset.i];
            const im = d.querySelector(':scope>img');
            if (!im.dataset.req && gc && gc.preview) { im.dataset.req = '1'; gc.preview(c.kind, c.skin).then(u => { if (u) im.src = u; }); }
            d.querySelector('.gm-name').textContent = T(c.key, c.id);
            const b = d.querySelector('button');
            if (_curOn[c.kind] === c.skin) {
                b.className = 'pixel-btn btn-sprite btn-green gm-btn';
                b.textContent = T('gemsHatOn', 'ON');
            } else if (c.price === 0 || _curOwned.includes(c.id)) {
                b.className = 'pixel-btn btn-sprite btn-blue gm-btn';
                b.textContent = T('gemsCurUse', 'USE');
            } else {
                b.className = 'pixel-btn btn-sprite btn-orange gm-btn';
                b.innerHTML = '<img src="pixelart_design/gem.png" alt="" style="width:11px;height:11px;image-rendering:pixelated"> ' + c.price;
            }
        });
        _store.querySelector('#gm-sec-amb').textContent = T('gemsAmbience', 'Ambience');
        _store.querySelectorAll('.gm-amb').forEach(d => {
            const a = AMBIENCES[+d.dataset.amb];
            d.querySelector('.gm-name').textContent = T(a.key, a.id);
            const b = d.querySelector('button');
            if (_ambOn === a.id) {
                b.className = 'pixel-btn btn-sprite btn-green gm-btn';
                b.textContent = T('gemsHatOn', 'ON');
            } else if (a.price === 0 || _ambOwned.includes(a.id)) {
                b.className = 'pixel-btn btn-sprite btn-blue gm-btn';
                b.textContent = T('gemsCurUse', 'USE');
            } else {
                b.className = 'pixel-btn btn-sprite btn-orange gm-btn';
                b.innerHTML = '<img src="pixelart_design/gem.png" alt="" style="width:11px;height:11px;image-rendering:pixelated"> ' + a.price;
            }
        });
        _store.querySelector('#gm-sec-fx').textContent = T('gemsEffects', 'Farm effects');
        const fd = _store.querySelector('#gm-fxd');
        if (document.activeElement !== fd) fd.value = String(_fxDens);
        _store.querySelector('#gm-fxd-lbl').textContent = T('gemsFxDensity', 'Effect density');
        _store.querySelector('#gm-fxd-less').textContent = T('gemsFxLess', 'Less');
        _store.querySelector('#gm-fxd-more').textContent = T('gemsFxMore', 'More');
        // Solo tiene sentido con un efecto puesto.
        _store.querySelector('#gm-fxd-box').style.display = _fxOn === 'none' ? 'none' : '';
        _store.querySelectorAll('.gm-fx:not(.gm-amb)').forEach(d => {
            const fx = EFFECTS[+d.dataset.fx];
            d.querySelector('.gm-name').textContent = T(fx.key, fx.id);
            const b = d.querySelector('button');
            if (_fxOn === fx.id) {
                b.className = 'pixel-btn btn-sprite btn-green gm-btn';
                b.textContent = T('gemsHatOn', 'ON');
            } else if (fx.price === 0 || _fxOwned.includes(fx.id)) {
                b.className = 'pixel-btn btn-sprite btn-blue gm-btn';
                b.textContent = T('gemsCurUse', 'USE');
            } else {
                b.className = 'pixel-btn btn-sprite btn-orange gm-btn';
                b.innerHTML = '<img src="pixelart_design/gem.png" alt="" style="width:11px;height:11px;image-rendering:pixelated"> ' + fx.price;
            }
        });
        const loggedIn = !!(window.GameSave && window.GameSave.isLoggedIn);
        _store.querySelector('#gm-note').textContent = _freeSources()
            ? T('gemsNote', '')
            : (loggedIn ? T('gemsNote', '') : T('gemsLoginNeeded', 'Log in to CrazyGames to get gems.'));
        _syncSbar();   // el alto del contenido puede haber cambiado (p.ej. aparece una barra)
        _fitTitle();   // el saldo puede haber cambiado de ancho
    }
    function _buyPack(p) {
        if (_debugPurchases()) { add(p.gems); _toast('[TEST] +' + p.gems + ' 💎'); return; }
        if (!PURCHASES_LIVE) { _toast(T('gemsComingSoon', 'Coming soon')); return; }
        if (!(window.GameSave && window.GameSave.isLoggedIn)) { _toast(T('gemsLoginNeeded', 'Log in to CrazyGames to get gems.')); return; }
        // Fase 2: abrir PayStation de Xsolla con getXsollaUserToken() y validar con el Inventory.
    }
    function _buyOffer(o) {
        if (o.id === 'vip' ? _vip : (_unlockAll || _vip)) return;   // ya lo tiene
        if (_debugPurchases()) { _grantOffer(o.id); _toast('[TEST] ' + T(o.key, o.id)); return; }
        if (!PURCHASES_LIVE) { _toast(T('gemsComingSoon', 'Coming soon')); return; }
        if (!(window.GameSave && window.GameSave.isLoggedIn)) { _toast(T('gemsLoginNeeded', 'Log in to CrazyGames to get gems.')); return; }
        // Fase 2: PayStation de Xsolla (artículo no consumible) y comprobar con el Inventory.
    }
    // Concede una compra única (Fase 2: solo tras confirmarla Xsolla).
    function _grantOffer(id) {
        if (id === 'vip') _vip = true; else _unlockAll = true;
        _applyUnlockAll();
        _saveHats(); _changed();
        _fxRestart(); _ambApply();
        // VIP: quitar el banner ya (script.js decide con FarmGems.isVip()) y refrescar la oferta de boost.
        if (_vip) { try { window._syncAdBannerToGameState && window._syncAdBannerToGameState(); } catch (e) {} }
    }
    function _fitTitle() {
        if (!_store || _store.style.display === 'none') return;
        const t = _store.querySelector('#gm-title'), bal = _store.querySelector('.gm-bal'), bk = _store.querySelector('#gm-back');
        if (!t || !bal || !bk) return;
        const side = Math.ceil(Math.max(bal.offsetWidth, bk.offsetWidth)) + 6;
        t.style.boxSizing = 'border-box';
        t.style.paddingLeft = t.style.paddingRight = side + 'px';
        t.style.fontSize = '';
        // Ancho real del texto (con texto centrado, scrollWidth no detecta el desborde)
        const room = t.clientWidth - 2 * side, rg = document.createRange();
        rg.selectNodeContents(t);
        let f = parseFloat(getComputedStyle(t).fontSize) || 20;
        while (rg.getBoundingClientRect().width > room && f > 7) { f -= 0.5; t.style.fontSize = f + 'px'; }
    }
    function _syncSbar() {
        if (!_store || _store.style.display === 'none') return;
        const body = _store.querySelector('.gm-body'), sb = _store.querySelector('.gm-sbar');
        if (!body || !sb) return;
        const ch = body.clientHeight, sh = body.scrollHeight;
        if (sh <= ch + 2) { sb.style.display = 'none'; return; }
        sb.style.display = '';
        sb.style.top = body.offsetTop + 'px';
        sb.style.height = ch + 'px';
        const th = Math.max(24, Math.round(ch * ch / sh));
        const thumb = sb.firstChild;
        thumb.style.height = th + 'px';
        thumb.style.top = Math.round((ch - th) * body.scrollTop / (sh - ch)) + 'px';
    }
    let _codeBusy = false;
    async function _redeemCode() {
        if (_codeBusy || !_store || !enabled()) return;
        const inp = _store.querySelector('#gm-code-in'), btn = _store.querySelector('#gm-code-btn');
        const code = inp.value.trim().toUpperCase();
        if (code.length < 3) { _toast(T('gemsCodeInvalid', 'Invalid code')); return; }
        _codeBusy = true; btn.textContent = '…'; btn.disabled = true;
        let d = null;
        try {
            const r = await fetch(REDEEM_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code }) });
            d = await r.json();
        } catch (e) { d = null; }
        _codeBusy = false; btn.disabled = false; btn.textContent = T('gemsCodeBtn', 'REDEEM');
        if (!d) { _toast(T('gemsCodeNet', 'Could not connect. Try again later.')); return; }
        if (!d.ok) {
            _toast(d.error === 'used' ? T('gemsCodeUsed', 'This code has already been used')
                : d.error === 'too_many' ? T('gemsCodeMany', 'Too many attempts. Try again later.')
                : d.error === 'invalid' ? T('gemsCodeInvalid', 'Invalid code')
                : T('gemsCodeNet', 'Could not connect. Try again later.'));
            return;
        }
        inp.value = '';
        const n = d.reward | 0;
        if (n === CODE_UNLOCK_ALL) {
            _unlockAll = true;
            _applyUnlockAll();
            _saveHats(); _changed();
            _purplePopup(_shopTitle(), T('gemsCodeAll', 'Everything unlocked!'), T('gemsCodeOk', 'Code redeemed'));
        } else if (n > 0) {
            add(n);
            _purplePopup(T('gemsAdBadge', 'Gems!'), '+' + n + ' <img src="pixelart_design/gem.png" alt="">', T('gemsCodeOk', 'Code redeemed'), true);
        }
    }
    function _flashPacks() {
        if (!_store) return;
        const w = _store.querySelector('#gm-packs');
        if (!w) return;
        w.classList.remove('gm-flash'); void w.offsetWidth; w.classList.add('gm-flash');
    }
    function openStore() {
        if (!enabled()) return;
        if (!_store) _store = _buildStore();
        _refreshStore();
        _store.style.display = 'flex';
        _fitTitle();
        _syncSbar();
        setTimeout(_syncSbar, 200);   // tras cargar imágenes / previas
        // Si se abre en partida, la partida se pausa mientras está abierta.
        if (document.body.classList.contains('in-game')) { _pausedBefore = !!window.gamePaused; window.gamePaused = true; }
        else _pausedBefore = null;
    }
    function closeStore() {
        if (!_store) return;
        _store.style.display = 'none';
        if (_pausedBefore !== null) window.gamePaused = _pausedBefore;
        _pausedBefore = null;
    }

    // ── Gemas gratis (itch.io): huevos de gema ──────────────────────────────
    // script.js pregunta al poner cada huevo si sale de gema, y llama a claimGemEgg cuando el
    // JUGADOR lo coge (clic o imán). Si se vende, lo recoge una máquina o caduca, se pierde.
    let _gemEggSec = 0, _gemEggNext = GEM_EGG_MIN_S + Math.random() * (GEM_EGG_MAX_S - GEM_EGG_MIN_S), _gemEggPending = false;
    function rollGemEgg() {
        if (!_gemEggPending || !enabled() || !_freeSources() || hasAll()) return false;
        _gemEggPending = false;
        return true;
    }
    function claimGemEgg() {
        if (!enabled()) return;
        add(1);
        _adGemPopup(1, 'gemsEggDesc', 'Gem egg!');
    }
    // Gema pequeña de color (11x10) para pintarla sobre los huevos de gema (Pixi en script.js).
    let _gemCv = null;
    function gemCanvas() {
        if (!_gemCv) { _gemCv = document.createElement('canvas'); _gemCv.width = 11; _gemCv.height = 10; _drawGem(_gemCv.getContext('2d'), 0, 0); }
        return _gemCv;
    }
    // Cuenta el tiempo de partida activa (en partida, sin pausa, pestaña visible); al llegar al
    // siguiente plazo, el próximo huevo que se ponga será de gema.
    function _watchGemEggs() {
        setInterval(() => {
            if (!_freeSources() || hasAll() || _gemEggPending) return;
            if (!document.body.classList.contains('in-game') || window.gamePaused || window.isAdPaused || document.hidden) return;
            if (++_gemEggSec >= _gemEggNext) {
                _gemEggSec = 0;
                _gemEggNext = GEM_EGG_MIN_S + Math.random() * (GEM_EGG_MAX_S - GEM_EGG_MIN_S);
                _gemEggPending = true;
            }
        }, 1000);
    }

    // ── Gemas por logros ────────────────────────────────────────────────────
    function _achValue(a) { return _achTable()[(a && a.tier) || 'bronze'] || 0; }
    // Gemas que da un logro de ese nivel (para el panel de logros); 0 fuera de CrazyGames.
    function achGems(tier) { return enabled() ? (_achTable()[tier || 'bronze'] || 0) : 0; }
    // Paga los logros conseguidos que aún no se habían pagado. Devuelve { gems, count }.
    function _payUnpaidAchievements() {
        const GA = window.GameAchievements;
        if (!enabled() || !GA || !GA.getUnlocked) return { gems: 0, count: 0 };
        const list = GA.getUnlocked().filter(a => a && a.id && !_achPaid.includes(a.id));
        if (!list.length) return { gems: 0, count: 0 };
        let g = 0;
        list.forEach(a => { g += hasAll() ? 0 : _achValue(a); _achPaid.push(a.id); });
        _saveHats();
        if (g > 0) add(g);
        return { gems: g, count: list.length };
    }
    // Logro nuevo (lo llama shared/achievements.js al desbloquearlo): se paga al momento.
    // Si aún está pendiente la bienvenida, se deja para ella (sale todo junto).
    function onAchievement(ach) {
        if (!enabled() || !_inited || _welcomePending || !ach || _achPaid.includes(ach.id)) return;
        const v = hasAll() ? 0 : _achValue(ach);
        _achPaid.push(ach.id);
        _saveHats();
        if (v > 0) { add(v); _adGemPopup(v, 'gemsAchDesc', 'Achievement reward'); }
    }

    // ── Intro del menú (shared/intro.js llama a introDecorate en cada fotograma) ──
    // Los animales de la intro son <div> con la hoja de sprites de fondo (mismas hojas y
    // filas que en la granja, a otro tamaño), así que se usan las mismas anclas.
    const _sheetUrlCache = {};
    function _sheetUrl(key, make) {
        if (_sheetUrlCache[key]) return _sheetUrlCache[key];
        const cv = make();
        return cv ? (_sheetUrlCache[key] = cv.toDataURL()) : null;
    }
    const _introRoosterIdx = new WeakMap();
    let _introRoosterN = 0;
    function _introChild(s, key, cls) {
        let ch = s.el[key];
        if (!ch) {
            ch = document.createElement('div');
            ch.className = cls;
            ch.style.cssText = 'position:absolute;pointer-events:none;background-repeat:no-repeat;image-rendering:pixelated;display:none';
            s.el.appendChild(ch);
            s.el.style.overflow = 'visible';   // el sombrero asoma por encima del fotograma
            s.el[key] = ch;
        }
        return ch;
    }
    function _introBg(s, url) {
        if (s._gmBg === url) return;
        s._gmBg = url;
        s.el.style.backgroundImage = 'url(' + url + ')';
    }
    // s: animal de la intro ({ el, isChick, isRooster }); row/frame: celda de la hoja; fs: px por celda.
    function introDecorate(s, row, frame, fs) {
        if (!s || !s.el) return;
        const on = enabled() && _inited;
        if (s.isChick) {
            const ti = on ? chickTintFor(s) : -1;
            _introBg(s, ti >= 0 ? (_sheetUrl('chick' + ti, () => chickSheet(_chickImg, ti)) || 'pixelart_design/chick.png') : 'pixelart_design/chick.png');
            return;
        }
        if (s.isRooster) {
            if (!_introRoosterIdx.has(s)) _introRoosterIdx.set(s, _introRoosterN++);
            const sk = on ? roosterSkinFor(_introRoosterIdx.get(s)) : null;
            _introBg(s, sk ? (_sheetUrl('rooster_' + sk, () => roosterSheet(_roosterImg, sk)) || 'pixelart_design/rooster.png') : 'pixelart_design/rooster.png');
            return;
        }
        const k = fs / 24;   // escala: celdas de 24 px de la hoja de gallina
        // Sombrero
        const hi = on ? hatIndexFor(s) : -1, a = hi >= 0 ? anchor(row, frame) : null;
        if (hi >= 0 || s.el._gmHat) {
            const h = _introChild(s, '_gmHat', 'gm-intro-hat');
            if (hi < 0 || !a) h.style.display = 'none';
            else {
                const st = h.style;
                st.display = 'block';
                st.backgroundImage = 'url(' + hatImage.src + ')';
                st.backgroundSize = (HAT_W * HATS.length * k) + 'px ' + (HAT_H * k) + 'px';
                st.backgroundPosition = (-hi * HAT_W * k) + 'px 0';
                st.width = (HAT_W * k) + 'px'; st.height = (HAT_H * k) + 'px';
                st.left = ((a[0] + hatDx(row) - HAT_W / 2) * k) + 'px';
                st.top = ((a[1] + HAT_OVERLAP + hatDy(hi) - HAT_H) * k) + 'px';
                st.zIndex = '2';
            }
        }
        // Gafas
        const gi = on ? glassesIndexFor(s) : -1, sp = gi >= 0 ? glassesSpot(row, frame) : null;
        if (gi >= 0 || s.el._gmGl) {
            const g = _introChild(s, '_gmGl', 'gm-intro-gl');
            if (gi < 0 || !sp) g.style.display = 'none';
            else {
                const st = g.style, mirror = sp.view === 'M';
                st.display = 'block';
                st.backgroundImage = 'url(' + glassesImage.src + ')';
                st.backgroundSize = (GL_W * GLASSES.length * k) + 'px ' + (GL_H * 2 * k) + 'px';
                st.backgroundPosition = (-gi * GL_W * k) + 'px ' + (sp.view === 'F' ? -GL_H * k : 0) + 'px';
                st.width = (GL_W * k) + 'px'; st.height = (GL_H * k) + 'px';
                // Igual que drawGlasses: en 'M' la celda va volteada y su píxel GL_EYE_X cae en sp.ex
                st.left = ((mirror ? sp.ex + 1 + GL_EYE_X - GL_W : sp.ex - GL_EYE_X) * k) + 'px';
                st.top = ((sp.ey - GL_EYE_Y) * k) + 'px';
                st.transform = mirror ? 'scaleX(-1)' : 'none';
                st.zIndex = '1';
            }
        }
    }

    // ── Regalo de bienvenida ────────────────────────────────────────────────
    let _welcomePending = false, _welOv = null, _welPausedBefore = null;
    // returning = ya había partida guardada al cargar (lo decide script.js ANTES de
    // loadState, que podría crear la de un jugador nuevo). Se da una sola vez.
    // Un jugador nuevo nunca la recibe: se marca ya como dada para que no salte en su 2ª visita.
    function _grantWelcome(returning) {
        if (_welcomeGiven) return;
        if (!returning) { _welcomeGiven = true; _saveHats(); return; }
        _welcomeGiven = true;
        _saveHats();
        add(WELCOME_GEMS);
        _welcomePending = true;
    }
    function _closeWelcome() {
        if (!_welOv) return;
        _welOv.style.display = 'none';
        if (_welPausedBefore !== null) window.gamePaused = _welPausedBefore;
        _welPausedBefore = null;
    }
    function _showWelcome(ach) {
        ach = ach || { gems: 0, count: 0 };
        if (!_welOv) {
            _welOv = document.createElement('div');
            _welOv.id = 'gems-welcome-overlay';
            _welOv.className = 'gm-overlay';
            _welOv.innerHTML = `<div class="gm-panel" style="width:min(520px,96vw)">
                <h2 class="gm-title" id="gm-w-title"></h2>
                <div class="gm-body">
                <div class="gm-wel-gift"><span id="gm-w-total"></span></div>
                <div class="gm-big" id="gm-w-msg"></div>
                <div class="gm-wel-lines" id="gm-w-lines"></div>
                <div class="gm-note" id="gm-w-desc"></div>
                <div class="gm-wel-mode"><img src="pixelart_design/mode_icon_mimosas.png" alt=""><span id="gm-w-mode"></span></div>
                <div class="gm-wel-btns">
                    <button class="pixel-btn btn-sprite btn-5 gm-btn gm-back" type="button" id="gm-w-later"></button>
                    <button class="pixel-btn btn-sprite btn-green gm-btn gm-back" type="button" id="gm-w-shop"></button>
                </div>
                </div>
            </div>`;
            const ic = document.createElement('canvas'); ic.width = 11; ic.height = 10;
            _drawGem(ic.getContext('2d'), 0, 0);
            _welOv.querySelector('.gm-wel-gift').appendChild(ic);
            document.body.appendChild(_welOv);
            _welOv.querySelector('#gm-w-later').addEventListener('click', _closeWelcome);
            _welOv.querySelector('#gm-w-shop').addEventListener('click', () => { _closeWelcome(); openStore(); });
        }
        _welOv.querySelector('#gm-w-title').textContent = T('welcomeTitle', 'WELCOME BACK!');
        const total = WELCOME_GEMS + ach.gems;
        _welOv.querySelector('#gm-w-total').textContent = '+' + total;
        _welOv.querySelector('#gm-w-msg').textContent = T('welcomeGot', '{n} free gems for you!').replace('{n}', total);
        const lines = _welOv.querySelector('#gm-w-lines');
        lines.innerHTML = '';
        const line = (txt, n) => { const r = document.createElement('div'); r.className = 'gm-wel-line'; r.innerHTML = '<span></span><b>+' + n + '</b>'; r.firstChild.textContent = txt; lines.appendChild(r); };
        line(T('welcomeGift', 'Welcome gift'), WELCOME_GEMS);
        if (ach.gems > 0) line(T('welcomeAch', 'Achievements completed ({n})').replace('{n}', ach.count), ach.gems);
        _welOv.querySelector('#gm-w-desc').textContent = T('welcomeDesc', 'New gem shop: hats, glasses, roosters, cursors, effects and more.');
        // Novedad de esta versión para quien vuelve (pedido del usuario): el modo Gallinas Mimosas
        _welOv.querySelector('#gm-w-mode').textContent = T('welcomeNewMode', 'New mode: {m}!').replace('{m}', T('chal7Title', 'CUDDLY HENS'));
        _welOv.querySelector('#gm-w-later').textContent = T('welcomeLater', 'LATER');
        _welOv.querySelector('#gm-w-shop').textContent = T('welcomeShop', 'SEE SHOP');
        _welOv.style.display = 'flex';
        if (document.body.classList.contains('in-game')) { _welPausedBefore = !!window.gamePaused; window.gamePaused = true; }
    }
    // Se enseña en cuanto se ve el menú principal o la partida, sin cinemática ni otro cartel delante.
    function _watchWelcome() {
        const t = setInterval(() => {
            if (!_welcomePending) { clearInterval(t); return; }
            const bar = document.getElementById('mm-bottom-bar');
            const inMenu = !!(bar && getComputedStyle(bar).display !== 'none' && getComputedStyle(bar).opacity !== '0');
            if (!(inMenu || document.body.classList.contains('in-game')) || document.body.classList.contains('is-cinematic')) return;
            const busy = ['weekly-reset-overlay', 'wipe-confirm-overlay', 'stuck-rescue-overlay', 'gems-store-overlay']
                .some(id => { const el = document.getElementById(id); return el && el.style.display === 'flex'; });
            if (busy) return;
            _welcomePending = false;
            clearInterval(t);
            _showWelcome(_payUnpaidAchievements());
        }, 500);
    }
    // Sin bienvenida: logros conseguidos y aún sin pagar (p.ej. de antes de esta versión
    // si la bienvenida ya se dio) → se pagan al entrar al menú o a la partida.
    function _watchUnpaidAchievements() {
        const t = setInterval(() => {
            if (_welcomePending) return;   // los paga la bienvenida
            const bar = document.getElementById('mm-bottom-bar');
            const inMenu = !!(bar && getComputedStyle(bar).display !== 'none');
            if (!(inMenu || document.body.classList.contains('in-game'))) return;
            clearInterval(t);
            const r = _payUnpaidAchievements();
            if (r.gems > 0) _adGemPopup(r.gems, 'gemsAchDesc', 'Achievement reward');
        }, 700);
    }

    // ── Arranque ────────────────────────────────────────────────────────────
    let _inited = false;
    // opts.returning: script.js indica si ya había partida guardada al cargar (jugador que vuelve).
    function init(opts) {
        if (_inited || !enabled()) return;
        _inited = true;
        _load();
        if (window.GameCursors) window.GameCursors.ready.then(() => { _applyCursors(); _refreshStore(); });
        _injectCss();
        _mountHud();
        _mountMenuBtn();
        _mountShopBal();
        _grantWelcome(!!(opts && opts.returning));
        _watchWelcome();
        _watchUnpaidAchievements();
        _watchGemEggs();
    }
    // Recarga desde el guardado (p.ej. si GameSave cargó más tarde)
    function reload() { if (!enabled()) return; _load(); _changed(); }

    return {
        enabled, init, reload, balance, add, trySpend, openStore, closeStore,
        hatIndexFor, anchor, hatDy, hatDx, drawHat, hatImage,
        glassesIndexFor, glassesSpot, drawGlasses, glassesImage,
        roosterSkinFor, roosterSheet, chickTintFor, chickSheet, GLASSES, GL_W, GL_H, GL_EYE_X, GL_EYE_Y,
        onChange: fn => _listeners.push(fn),
        HAT_W, HAT_H, HAT_OVERLAP, HATS, CURSORS, EFFECTS, AMBIENCES, hasAll, isVip, rewardForAd, onAchievement, achGems, introDecorate, rollGemEgg, claimGemEgg, gemCanvas, GEM_EGG_LIFE,
        // solo para pruebas
        _debugShowWelcome: () => _showWelcome(),
        _isOverlayOpen: () => !!((_store && _store.style.display === 'flex') || (_welOv && _welOv.style.display === 'flex')),
    };
})();
