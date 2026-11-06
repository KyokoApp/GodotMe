// shared/shell.js — Common UI shell wired up before any scenario runs.
// Exposes window.GameShell. Each scenario calls GameShell.init(hooks) once.
//
// Hooks (all optional):
//   onPause()        — called when the user clicks the pause button
//   onResume()       — called when the user clicks the resume button
//   onMute()         — called after muting (window.isMusicMuted is already true)
//   onUnmute()       — called after unmuting (window.isMusicMuted is already false)
//   onInfoToggle()   — called after toggling info mode (window.infoMode updated)

window.GameShell = (() => {
    let _hooks = {};

    // ── Public ───────────────────────────────────────────────────────────────
    function init(hooks) {
        _hooks = hooks || {};
        _hideLoadingScreen();
        _setupMuteBtn();
        _setupPauseBtn();
        _setupInfoBtn();
        _setupBtnSounds();
    }

    // ── Loading screen ───────────────────────────────────────────────────────
    // Tope de espera del SDK de CrazyGames antes de continuar igualmente.
    const SDK_TIMEOUT_MS = 6000;
    // Tope de espera de imágenes — nunca debe colgar la pantalla de carga para
    // siempre por una imagen suelta que no cargue (o una conexión muy lenta).
    const IMG_TIMEOUT_MS = 1200; // Fast timeout for mobile Discord Activity
    // Suelo mínimo antes de poder ocultar la pantalla de carga. Con las imágenes
    // ya en caché (típico al cerrar/reabrir la app en pruebas) _preloadImages()
    // puede resolver casi al instante, ocultando la pantalla negra ANTES de que
    // el escalado inicial del menú (_applyScaling()/_fixScaleRoot(), en
    // index.html/portrait.js) llegue a aplicarse ni una vez — se ve entonces un
    // frame sin escalar, gigante, "saliéndose de la pantalla" durante unos
    // milisegundos. En vez de perseguir esa carrera exacta, se cubre la clase
    // entera del problema: la pantalla de carga nunca se oculta antes de este
    // tiempo mínimo, dando margen de sobra a que el layout se asiente.
    const MIN_VISIBLE_MS = 400;

    // Reporte real: en producción (conexión fría, sin caché) la pantalla de
    // carga se ocultaba en cuanto GameShell.init() se ejecutaba en JS — sin
    // esperar a que ninguna imagen hubiera terminado de descargar. Resultado:
    // el juego arrancaba visualmente incompleto (iconos de botones en blanco,
    // gallinas del intro invisibles hasta que su sprite individual terminaba
    // de llegar, a veces varios segundos después, coincidiendo por pura
    // casualidad con el aterrizaje del logo).
    //
    // Primer intento: escanear TODO el documento (querySelectorAll('*') +
    // background-image computado) — descartado. La página tiene cientos de
    // elementos ocultos (tienda, logros, paneles de pausa...) cuyo CSS ya
    // referencia spritesheets grandes que no hacen falta para la primera
    // pantalla; esperar a todo eso alargaba la carga varios segundos y
    // encima desincronizaba la animación de caída del logo (que arranca en
    // cuanto corre GameIntro.start(), sin esperar a la pantalla de carga) de
    // lo que el jugador veía: la pantalla se quedaba en negro y, al quitarse,
    // el logo aparecía ya aterrizado. Ahora se limita a lo que de verdad hace
    // falta para pintar la intro: los <img> ya presentes en el HTML inicial
    // (fondo, nubes, logo, cofre de JUGAR — solo 21 en toda la página) más
    // los sprites que faltan por listarse a mano porque se crean más tarde:
    // los animales del intro (shared/intro.js — GameIntro.start() no corre
    // hasta un <script> inline al final de index.html, después de que este
    // código ya se ejecutó) y el spritesheet de los iconos de la barra del
    // menú (ajustes/clasificación/logros), que es un background-image CSS,
    // no un <img>.
    const _CRITICAL_EXTRA_SRCS = [
        'pixelart_design/chicken_white.png',
        'pixelart_design/chicken_beige.png',
        'pixelart_design/chicken_brown.png',
        'pixelart_design/chicken_black.png',
        'pixelart_design/chick.png',
        'pixelart_design/rooster.png',
        'pixelart_design/button_icons.png',
    ];

    function _collectCriticalImageUrls() {
        const urls = new Set(_CRITICAL_EXTRA_SRCS);
        document.querySelectorAll('img[src]').forEach(img => {
            if (img.src) urls.add(img.src);
        });
        return Array.from(urls);
    }

    function _preloadImages(urls) {
        const loaders = urls.map(url => new Promise(resolve => {
            const img = new Image();
            img.onload = img.onerror = resolve; // nunca rechaza: una imagen rota no debe colgar el arranque
            img.src = url;
        }));
        return Promise.race([
            Promise.all(loaders),
            new Promise(r => setTimeout(r, IMG_TIMEOUT_MS))
        ]);
    }

    function _hideLoadingScreen() {
        const el = document.getElementById('loading-screen');
        if (!el) return;
        const hide = () => {
            if (window._flashDiag) window._flashDiag('loading-screen-HIDE', null);
            el.style.display = 'none';
            // Señal obligatoria de Playgama: "el primer frame jugable está listo".
            // Este es el punto exacto en que eso es cierto — justo cuando se oculta
            // la pantalla de carga (no antes, no en otro sitio).
            if (window.GAME_MARKET === 'playgama') {
                try { window.bridge?.platform?.sendMessage?.('game_ready'); } catch (e) {}
            }
        };

        // window._cgSdkReady/_pgBridgeReady SOLO existen en la build de CrazyGames/Playgama
        // respectivamente (son las únicas que cargan su SDK). En el resto de
        // plataformas ambas quedan undefined y esa espera se salta.
        const _sdkReadyPromise = window._cgSdkReady || window._pgBridgeReady;
        const sdkWait = _sdkReadyPromise
            // Antes: `_cgSdkReady.finally(hide)` a secas. Si SDK.init() no resolvía NUNCA
            // —red lenta, adblock, el ITP de Safari bloqueando el iframe de terceros, o una
            // caída del servidor de anuncios— el .finally() no se disparaba y el jugador se
            // quedaba en la pantalla de carga PARA SIEMPRE. Reporte real: iPad/Safari con
            // "Vast error 301: ad request timed out".
            // El juego funciona perfectamente sin el SDK (pierde la nube, nada más), así que
            // pasado el tope se continúa igual.
            ? Promise.race([_sdkReadyPromise, new Promise(r => setTimeout(r, SDK_TIMEOUT_MS))])
            : Promise.resolve();

        const minVisible = new Promise(r => setTimeout(r, MIN_VISIBLE_MS));
        const safetyTimer = new Promise(r => setTimeout(r, 1200));
        Promise.race([
            Promise.all([sdkWait, _preloadImages(_collectCriticalImageUrls()), minVisible]),
            safetyTimer
        ]).finally(hide);
    }

    function _waitFrames(n, cb) {
        if (n <= 0) return cb();
        requestAnimationFrame(() => _waitFrames(n - 1, cb));
    }

    // ── Mute button ──────────────────────────────────────────────────────────
    function _syncMuteStyle(btn) {
        if (window.isMusicMuted) {
            btn.style.background   = '#e74c3c';
            btn.style.borderColor  = '#fff #c0392b #c0392b #fff';
        } else {
            btn.style.background  = '';
            btn.style.borderColor = '';
        }
    }

    function _setupMuteBtn() {
        // Restore persisted state
        const saved = localStorage.getItem('chickenIdleMuted');
        window.isMusicMuted = saved === null ? false : saved === 'true';

        const btn = document.getElementById('mute-btn');
        if (!btn) return;
        _syncMuteStyle(btn);

        btn.addEventListener('click', () => {
            // CrazyGames/Playgama muteAudio takes priority — block unmuting if SDK forces mute
            if ((window._cgMuteAudio || window._pgMuteAudio) && window.isMusicMuted) return;
            window.isMusicMuted = !window.isMusicMuted;
            localStorage.setItem('chickenIdleMuted', window.isMusicMuted);
            _syncMuteStyle(btn);
            if (window.isMusicMuted) _hooks.onMute?.();
            else                     _hooks.onUnmute?.();
        });
    }

    // ── Pause / resume ───────────────────────────────────────────────────────
    function _setupPauseBtn() {
        const pauseBtn   = document.getElementById('pause-btn');
        const resumeBtn  = document.getElementById('resume-btn');
        const overlay    = document.getElementById('pause-overlay');

        if (pauseBtn) {
            pauseBtn.addEventListener('click', () => {
                window.gamePaused = true;
                const panel = document.getElementById('pause-panel');
                if (overlay) {
                    // Reset any leftover slide-out class from the intro menu flow,
                    // then trigger slide-up so the panel enters from below.
                    if (panel) { panel.classList.remove('mm-slide-out', 'mm-slide-in'); }
                    overlay.style.display = 'flex';
                    if (panel) { void panel.offsetWidth; panel.classList.add('mm-slide-in'); }
                }
                _hooks.onPause?.();
            });
        }

        if (resumeBtn) {
            resumeBtn.addEventListener('click', () => {
                window.gamePaused = false;
                if (overlay && document.body.classList.contains('in-game')) {
                    overlay.classList.add('overlay-closing');
                    overlay.addEventListener('animationend', function() {
                        overlay.style.display = 'none';
                        overlay.classList.remove('overlay-closing');
                    }, { once: true });
                } else if (overlay) {
                    overlay.style.display = 'none';
                }
                _hooks.onResume?.();
            });
        }
    }

    // ── Info button + shop-desc injection ────────────────────────────────────
    function _setupInfoBtn() {
        window.infoMode = window.infoMode || false;

        // Inject a collapsible description div into every .shop-btn that has data-title
        document.querySelectorAll('.shop-btn').forEach(btn => {
            if (btn.querySelector('.shop-desc-text')) return; // already injected
            const title = btn.getAttribute('data-title') || btn.getAttribute('title');
            if (!title) return;
            const d = document.createElement('div');
            d.className = 'shop-desc-text';
            d.innerHTML = title;
            Object.assign(d.style, {
                display:       'none',
                flexBasis:     '100%',
                fontSize:      '7px',
                color:         '#795548',
                lineHeight:    '1.4',
                marginTop:     '6px',
                paddingTop:    '6px',
                borderTop:     '1px dashed rgba(121, 85, 72, 0.4)',
                textAlign:     'left',
                whiteSpace:    'normal',
                pointerEvents: 'none',
            });
            btn.appendChild(d);
        });

        const infoBtn = document.getElementById('toggle-info-btn');
        if (!infoBtn) return;

        infoBtn.addEventListener('click', () => {
            window.infoMode = !window.infoMode;
            if (window.infoMode) {
                infoBtn.style.background   = '#e74c3c';
                infoBtn.style.color        = 'white';
                infoBtn.style.borderColor  = '#fff #d35400 #d35400 #fff';
            } else {
                infoBtn.style.background  = '';
                infoBtn.style.color       = '';
                infoBtn.style.borderColor = '';
            }
            const tooltip = document.getElementById('game-tooltip');
            if (tooltip) tooltip.style.display = 'none';
            _hooks.onInfoToggle?.();
        });
    }

    // ── Button press / release sounds ────────────────────────────────────────
    function _setupBtnSounds() {
        function _sfxPress()   { const ga = window.GameAudio; if (ga) ga.playSound(ga.sfxPress,   0.2, 50); }
        function _sfxRelease() { const ga = window.GameAudio; if (ga) ga.playSound(ga.sfxRelease, 0.2, 50); }
        const _isBtn = e => e.target.closest('button, .pixel-btn, .shop-btn, .mm-btn, .tab-btn, [role="button"]');
        document.addEventListener('mousedown',  e => { if (_isBtn(e)) _sfxPress(); });
        document.addEventListener('mouseup',    e => { if (_isBtn(e)) _sfxRelease(); });
        document.addEventListener('touchstart', e => { if (_isBtn(e)) _sfxPress(); },   { passive: true });
        document.addEventListener('touchend',   e => { if (_isBtn(e)) _sfxRelease(); }, { passive: true });
    }

    return { init };
})();

// ── iOS: menú nativo de Copiar/Traducir al hacer doble toque ─────────────────
// En la app de iOS, un doble toque sobre la zona de juego sacaba el menú de
// edición nativo (Copiar / Traducir / Look Up / Compartir) junto con la lupa.
// Medido en dispositivo: al hacer ese doble toque, WebKit crea un rango de
// selección ANCLADO EN EL CONTENEDOR (#cine-frame) pero VACÍO — sin un solo
// carácter dentro. Eso es lo que dispara el menú, que luego se queda sin nada
// que ofrecer (el log de Xcode lo dice literalmente: "did not have performable
// commands and/or actions").
//
// Por qué user-select:none no bastaba: impide seleccionar TEXTO, pero no impide
// que WebKit cree un rango a nivel de NODO sobre un elemento reemplazado como
// un <canvas>. Por eso el menú salía sobre la zona de juego y no sobre la
// tienda ni el menú principal, que sí son texto real — y por eso no había
// ninguna diferencia de CSS entre ambas zonas que lo explicara (comprobado
// comparando los estilos computados de #shop contra #farm-area: 15 diferencias,
// todas cosméticas).
//
// Se descartaron antes, con pruebas en el propio dispositivo: -webkit-user-select,
// -webkit-touch-callout, touch-action (none/manipulation/pan-x), el meta viewport,
// ios.allowsLinkPreview, y cualquier causa nativa (el otro proyecto Capacitor de
// referencia no toca nada en Swift y no tiene el problema).
//
// Solo se eliminan rangos VACÍOS, así que la selección real de texto (campos de
// nombre del ranking) no se ve afectada; aun así se excluyen INPUT/TEXTAREA de
// forma explícita. Fuera de desktop a propósito: ahí no existe este menú y no
// hay motivo para tocar su comportamiento.
// IMPORTANTE — esto MITIGA pero no elimina el problema, y no se debe presentar
// como la solución: es REACTIVO (borra el rango una vez WebKit ya lo ha creado),
// así que siempre queda una ventana de carrera. Se comprobó que esa ventana es
// real: con solo esta capa, el menú seguía saliendo en un iPhone físico (a
// menudo) y en el simulador de iPhone (de forma esporádica). La supresión de
// verdad se hace en nativo — ver scripts/patch-ios-webview.js.
//
// Se intentó cerrar la carrera cancelando 'selectstart' (que es preventivo en
// lugar de reactivo), pero se DESCARTÓ con medición en dispositivo: en ~150
// eventos 'selectionchange' consecutivos no se disparó 'selectstart' ni una sola
// vez. WebKit no pasa por ese evento aquí, así que esa vía es inerte. No volver
// a intentarlo.
(function () {
    if (window.GAME_MODE === 'desktop') return;
    document.addEventListener('selectionchange', function () {
        const s = window.getSelection();
        if (!s || !s.rangeCount) return;
        if (s.toString()) return;                       // selección real: no tocar
        const ae = document.activeElement;
        if (ae && /^(INPUT|TEXTAREA)$/.test(ae.tagName)) return;
        s.removeAllRanges();
    });
})();
