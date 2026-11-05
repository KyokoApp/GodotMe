// shared/cursors.js — Cursores del juego, generados desde pixelart_design/cursors.png
//
// El sprite es 48×16: TRES tiles de 16×16, que se escalan a 32×32 al generarlos.
//   tile 0 → MANO   · cursor por defecto en TODO el juego
//   tile 1 → IMÁN   · en el canvas, al arrastrar/atraer huevos
//   tile 2 → DEDO   · al pasar por encima de un botón o elemento clicable
//
// Se publican como variables CSS en :root (--cur-hand / --cur-magnet / --cur-finger),
// así el CSS puede usarlos en cualquier selector sin tocar JS:
//     body   { cursor: var(--cur-hand); }
//     button { cursor: var(--cur-finger); }
//
// Cada cursor lleva un fallback nativo (default / grabbing / pointer) que actúa hasta
// que carga la imagen, y también si no llegara a cargar.
//
// Antes esta lógica estaba DUPLICADA en scenarios/farm/script.js y shared/intro.js, cada
// uno cargando el PNG por su cuenta y con hotspots distintos. Ahora es la única fuente.
window.GameCursors = (function () {
    'use strict';

    const SRC = 'pixelart_design/cursors.png';
    const TILE = 16;   // tamaño del tile en el sprite
    const OUT  = 32;   // tamaño del cursor generado (x2, pixelado)

    // Hotspot = punto exacto que "hace clic", en coordenadas del cursor ya escalado (32×32).
    // Sacados de la punta real de cada dibujo, no a ojo.
    const TILES = {
        hand:   { x: 0,           hot: [16, 4],  fallback: 'default'  },
        magnet: { x: TILE,        hot: [16, 16], fallback: 'grabbing' }, // centro: es el punto de atracción
        finger: { x: TILE * 2,    hot: [10, 6],  fallback: 'pointer'  }, // la yema del dedo
    };

    const _built = {};

    // Diseños alternativos (tienda de gemas, scenarios/farm/gems.js), un PNG por diseño en
    // pixelart_design/cursor_skins/<tipo>_<diseño>.png, tiles de 16×16 como cursors.png:
    //   hand_*.png   32×16 → mano | dedo (el dedo es la misma mano señalando)
    //   magnet_*.png 16×16 → imán
    // Los hotspots son los de TILES: la punta tiene que quedar en el mismo píxel.
    const SKIN_DIR = 'pixelart_design/cursor_skins/';
    const SKINS = { hand: ['nails', 'jewels'], magnet: ['blackhole', 'battery'] };
    // Posición de cada cursor dentro del PNG de su diseño.
    const SKIN_X = { hand: 0, finger: TILE, magnet: 0 };
    let _img = null;
    const _skinImg = {};   // 'hand_gold' → Promise<Image|null> (se cargan al pedirlos)

    function _make(img, t, x) {
        const cvs = document.createElement('canvas');
        cvs.width = OUT; cvs.height = OUT;
        const c = cvs.getContext('2d');
        c.imageSmoothingEnabled = false;   // pixel art: nada de suavizado
        c.drawImage(img, x === undefined ? t.x : x, 0, TILE, TILE, 0, 0, OUT, OUT);
        return 'url(' + cvs.toDataURL('image/png') + ') ' + t.hot[0] + ' ' + t.hot[1] + ', ' + t.fallback;
    }
    function _loadSkin(kind, skin) {
        const id = kind + '_' + skin;
        if (!(SKINS[kind] && SKINS[kind].indexOf(skin) >= 0)) return Promise.resolve(null);
        if (!_skinImg[id]) _skinImg[id] = new Promise(function (resolve) {
            const im = new Image();
            im.onload = function () { resolve(im); };
            im.onerror = function () { resolve(null); };
            im.src = SKIN_DIR + id + '.png';
        });
        return _skinImg[id];
    }

    // kind: 'hand' (también cambia el dedo) o 'magnet'; skin: id de SKINS o 'default'.
    const _skinReq = {};   // último setSkin por tipo: si llegan dos seguidos, gana el último
    function setSkin(kind, skin) {
        const names = kind === 'hand' ? ['hand', 'finger'] : kind === 'magnet' ? ['magnet'] : [];
        const req = _skinReq[kind] = (_skinReq[kind] || 0) + 1;
        Promise.all([_ready, _loadSkin(kind, skin)]).then(function (r) {
            if (req !== _skinReq[kind]) return;
            const sk = r[1];
            const root = document.documentElement;
            names.forEach(function (k) {
                if (sk) _built[k] = _make(sk, TILES[k], SKIN_X[k]);
                else if (_img) _built[k] = _make(_img, TILES[k]);   // 'default' (o PNG que falta)
                else return;
                root.style.setProperty('--cur-' + k, _built[k]);
            });
        });
    }
    // Vista previa (promesa → dataURL 32×32) de un diseño, para la tienda.
    function preview(kind, skin) {
        const k = kind === 'magnet' ? 'magnet' : 'hand';
        return Promise.all([_ready, _loadSkin(kind, skin)]).then(function (r) {
            const v = r[1] ? _make(r[1], TILES[k], SKIN_X[k]) : _img ? _make(_img, TILES[k]) : null;
            return v ? v.slice(4, v.indexOf(')')) : null;
        });
    }

    const _ready = new Promise(function (resolve) {
        const img = new Image();
        img.onload = function () {
            _img = img;
            const root = document.documentElement;
            for (const k in TILES) {
                _built[k] = _make(img, TILES[k]);
                root.style.setProperty('--cur-' + k, _built[k]);
            }
            resolve(_built);
        };
        // Si no carga, no pasa nada: las variables CSS conservan sus fallbacks nativos.
        img.onerror = function () { resolve(_built); };
        img.src = SRC;
    });

    return {
        ready: _ready,                              // promesa: resuelve cuando están listos
        get: function (name) { return _built[name] || null; },
        setSkin: setSkin,                           // diseños de la tienda de gemas
        preview: preview,
        SKINS: SKINS,
    };
}());
