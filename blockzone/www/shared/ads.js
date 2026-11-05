// shared/ads.js — Ad & SDK lifecycle hub for all platforms.
// To add a new platform (AdMob, etc.), only edit this file.
// Exposes window.GameAds. Loaded before scenario scripts.
//
// Setup (call once after BGM is ready):
//   GameAds.init({ onAdStart, onAdEnd })
//
// Platform detection priority:
//   1. CrazyGames SDK v3   (window.CrazyGames.SDK present)
//   2. Playgama Bridge     (GAME_MARKET === 'playgama', window.bridge present)
//   3. AdMob / Capacitor   (window.Capacitor.Plugins.AdMob present — googleplay build)
//   4. Local / web stub    (reward fires immediately, lifecycle is no-op)

window.GameAds = (() => {
    let _freeAdsLeft     = 1; // 1 free token; restored after a paid purchase (CrazyGames policy: ad → pay → ad → …)
    let _onAdStart       = null;
    let _onAdEnd         = null;
    let _currentBannerId = null; // tracks which banner is active so ad-breaks can clear/restore it
    // Pick up the SDK promise set in index.html immediately at load time,
    // so _sdkRun defers correctly even before GameAds.init() is called.
    let _sdkReady        = window._cgSdkReady || null;
    // Playgama Bridge — mismo rol que _sdkReady pero para window._pgBridgeReady
    // (ver index.html). Solo se usa cuando GAME_MARKET === 'playgama'.
    let _pgReady          = window._pgBridgeReady || null;

    // ── AdMob (Android/Google Play + iOS/App Store) ──────────────────────────
    // Unidades de anuncio reales, confirmadas en la consola de AdMob. Android
    // usa la app ca-app-pub-5090386339666109~3930024802 (la ya usada en el
    // build viejo); iOS usa una app separada dentro del mismo publisher,
    // ca-app-pub-5090386339666109~4150013439 (ver GADApplicationIdentifier en
    // ios/App/App/Info.plist) — AdMob exige un App ID distinto por plataforma.
    const _ADMOB_IS_IOS = !!(window.Capacitor && window.Capacitor.getPlatform && window.Capacitor.getPlatform() === 'ios');
    const _ADMOB_BANNER_ID       = _ADMOB_IS_IOS ? 'ca-app-pub-5090386339666109/3978623040' : 'ca-app-pub-5090386339666109/8062105220';
    const _ADMOB_INTERSTITIAL_ID = _ADMOB_IS_IOS ? 'ca-app-pub-5090386339666109/6125706018' : 'ca-app-pub-5090386339666109/4842211831';
    const _ADMOB_REWARDED_ID     = _ADMOB_IS_IOS ? 'ca-app-pub-5090386339666109/6975753250' : 'ca-app-pub-5090386339666109/6066497274';
    // Ocultado temporalmente a petición explícita (Android + iOS) — solo afecta
    // al banner de AdMob (ver guard en el bloque AdMob de _requestBannerNow),
    // no al banner de CrazyGames. El resto de la lógica (init, listeners,
    // reserva de hueco, etc.) sigue intacta para poder reactivarlo con solo
    // volver esto a `true`.
    const _ADMOB_BANNER_ENABLED = false;
    // Decisión de producto explícita (Android + iOS, por el momento) — quitado
    // junto con el banner. Sin él, "Quitar anuncios" deja de tener sentido
    // (ver guard del botón en scenarios/farm/script.js); puede sustituirse más
    // adelante por un "Pase exprés" (ofertas limitadas sin ver rewarded). No
    // afecta al intersticial de CrazyGames, solo al bloque AdMob de
    // _admPreloadInterstitial()/requestMidgame().
    const _ADMOB_INTERSTITIAL_ENABLED = false;
    // Pon esto a `true` SOLO en tu propio dispositivo mientras pruebas antes de
    // publicar — sirve anuncios de test reales en vez de producción (evita que
    // tus propios clics/impresiones de prueba cuenten como tráfico inválido).
    const _ADMOB_TEST_MODE = false;

    let _admListenersReady = false;
    let _admInterstitialLoaded = false;
    let _admInterstitialLoading = false;
    let _admRewardedLoaded = false;
    let _admRewardedLoading = false;
    let _admPendingReward = null;
    let _admPendingFail   = null;

    // Llama al callback de fallo pendiente (si lo hay) y limpia ambos — mismo
    // punto único usado tanto por el listener nativo de fallo como por los
    // .catch() de las promesas de prepare/show, para no duplicar la lógica.
    function _admRewardedFail() {
        const fail = _admPendingFail;
        _admPendingReward = null;
        _admPendingFail   = null;
        fail?.();
    }

    // ── UMP (Google User Messaging Platform) — consentimiento EEE/RU ─────────
    // _consentCanRequestAds empieza en `true` (fail-open): si el propio SDK de
    // consentimiento falla al arrancar (sin red, error del propio Google...),
    // preferimos no bloquear anuncios a los jugadores fuera de zona regulada
    // por un fallo ajeno, en vez de dejar la app sin anuncios para todo el
    // mundo. Se corrige a `false` en cuanto requestConsentInfo() responda de
    // verdad con canRequestAds:false.
    let _consentCanRequestAds = true;
    let _consentPrivacyOptionsRequired = false;
    let _onPrivacyOptionsChange = null;

    // Pide el estado de consentimiento y, si Google dice que hace falta,
    // muestra el formulario — antes de inicializar el SDK de anuncios (orden
    // recomendado por Google: https://developers.google.com/admob/android/privacy).
    async function _admHandleConsent(adm) {
        try {
            let info = await adm.requestConsentInfo({});
            if (info.status === 'REQUIRED' && info.isConsentFormAvailable) {
                info = await adm.showConsentForm();
            }
            _consentCanRequestAds = !!info.canRequestAds;
            _consentPrivacyOptionsRequired = info.privacyOptionsRequirementStatus === 'REQUIRED';
        } catch (e) {
            console.warn('[Ads] UMP consent flow failed, defaulting to canRequestAds=true:', e);
        }
        _onPrivacyOptionsChange?.(_consentPrivacyOptionsRequired);
        console.log('[Ads] consent resolved — canRequestAds:', _consentCanRequestAds, '| privacyOptionsRequired:', _consentPrivacyOptionsRequired);
    }

    // Botón de "opciones de privacidad" en Ajustes: Google exige un punto de
    // acceso permanente (no solo el aviso inicial) para que el jugador pueda
    // cambiar su elección más adelante. Solo debe mostrarse si Google indica
    // que hace falta (privacyOptionsRequirementStatus === 'REQUIRED' — p.ej.
    // jugadores en el EEE/Reino Unido), por eso el callback en vez de un
    // botón siempre visible.
    function showPrivacyOptions() {
        const adm = _adm();
        if (!adm) return;
        adm.showPrivacyOptionsForm().catch((e) => console.warn('[Ads] showPrivacyOptionsForm failed:', e));
    }
    function privacyOptionsRequired() { return _consentPrivacyOptionsRequired; }
    function canRequestAds() { return _consentCanRequestAds; }
    function onPrivacyOptionsChange(cb) { _onPrivacyOptionsChange = cb || null; }

    // ── ¿Hay un anuncio de recompensa listo AHORA MISMO? ─────────────────────
    // Para que las ofertas del juego (boost de Endless/Normal/Adam/Manual, oferta
    // aleatoria de Normal) no se muestren si sabemos de antemano que van a
    // fallar al pulsarlas — mejor no ofrecer nada que ofrecer algo roto.
    // CrazyGames no expone una API de "precarga" como AdMob (sus anuncios se
    // piden bajo demanda) — se asume listo si el módulo existe, igual que el
    // resto del código de este archivo. Sin ningún SDK real (escritorio/dev)
    // también se considera "listo": ese caso siempre resuelve con el stub
    // (recompensa inmediata sin anuncio real), no tiene sentido ocultar la oferta.
    function isRewardedReady() {
        // Playgama Bridge no expone una API de precarga consultable (igual que
        // CrazyGames) — se asume listo, la propia SDK cae al stub si no lo está.
        if (window.GAME_MARKET === 'playgama') return true;
        if (_cgAd()) return true;
        const adm = _adm();
        if (adm) return _consentCanRequestAds && _admRewardedLoaded;
        return true;
    }

    // window.Capacitor solo existe dentro de la app nativa empaquetada (Capacitor
    // lo inyecta en el WebView antes de que cargue esta página) — nunca en el
    // navegador de escritorio ni en el build web/CrazyGames.
    function _adm() {
        try {
            if (!window.Capacitor?.isNativePlatform?.()) return null;
            return window.Capacitor.Plugins?.AdMob || null;
        } catch (e) { return null; }
    }

    // Precarga en segundo plano, SIN pausar el juego — así cuando el jugador
    // pide ver un anuncio, ya está listo y se muestra al instante en vez de
    // dejar el juego en pausa mientras AdMob lo descarga. Se llama al iniciar
    // y se vuelve a llamar tras cada anuncio (dismissed/failed) para rellenar
    // la "reserva" de cara a la siguiente vez.
    function _admPreloadInterstitial() {
        if (!_ADMOB_INTERSTITIAL_ENABLED) return;
        const adm = _adm();
        if (!adm || !_consentCanRequestAds || _admInterstitialLoaded || _admInterstitialLoading) return;
        _admInterstitialLoading = true;
        adm.prepareInterstitial({ adId: _ADMOB_INTERSTITIAL_ID, isTesting: _ADMOB_TEST_MODE })
            .catch((e) => console.warn('[Ads] AdMob interstitial preload failed:', e))
            .finally(() => { _admInterstitialLoading = false; });
    }
    function _admPreloadRewarded() {
        const adm = _adm();
        if (!adm || !_consentCanRequestAds || _admRewardedLoaded || _admRewardedLoading) return;
        _admRewardedLoading = true;
        adm.prepareRewardVideoAd({ adId: _ADMOB_REWARDED_ID, isTesting: _ADMOB_TEST_MODE })
            .catch((e) => console.warn('[Ads] AdMob rewarded preload failed:', e))
            .finally(() => { _admRewardedLoading = false; });
    }

    // Listeners registrados UNA sola vez (no en cada request) — cada evento
    // ajusta el estado interno y, si aplica, cierra el "ad-break" (reanuda
    // juego/audio) igual que hace el flujo de CrazyGames.
    function _admInitListeners(adm) {
        if (_admListenersReady) return;
        _admListenersReady = true;

        adm.addListener('interstitialAdLoaded', () => { _admInterstitialLoaded = true; });
        adm.addListener('interstitialAdFailedToLoad', (e) => {
            console.warn('[Ads] AdMob interstitial failed to load:', e);
            _admInterstitialLoaded = false;
        });
        adm.addListener('interstitialAdFailedToShow', (e) => {
            console.warn('[Ads] AdMob interstitial failed to show:', e);
            _admInterstitialLoaded = false;
            _adBreakEnd('interstitial');
            _admPreloadInterstitial();
        });
        adm.addListener('interstitialAdDismissed', () => {
            _admInterstitialLoaded = false;
            _adBreakEnd('interstitial');
            _admPreloadInterstitial();
        });

        adm.addListener('onRewardedVideoAdLoaded', () => { _admRewardedLoaded = true; });
        adm.addListener('onRewardedVideoAdFailedToLoad', (e) => {
            console.warn('[Ads] AdMob rewarded failed to load:', e);
            _admRewardedLoaded = false;
        });
        adm.addListener('onRewardedVideoAdFailedToShow', (e) => {
            console.warn('[Ads] AdMob rewarded failed to show:', e);
            _admRewardedLoaded = false;
            _admRewardedFail();
            _adBreakEnd('rewarded');
            _admPreloadRewarded();
        });
        adm.addListener('onRewardedVideoAdReward', (reward) => {
            console.log('[Ads] AdMob rewarded → reward granted', reward);
            const cb = _admPendingReward;
            _admPendingReward = null;
            cb?.();
        });
        adm.addListener('onRewardedVideoAdDismissed', () => {
            _admRewardedLoaded = false;
            _adBreakEnd('rewarded');
            _admPreloadRewarded();
        });

        // ADAPTIVE_BANNER pide a Google un alto real que depende del ancho del
        // dispositivo (más alto en tablet) — el banner nativo se pinta como
        // overlay FUERA del DOM, así que si el hueco reservado en CSS
        // (--admob-banner-h, ver portrait.css) no coincide con este alto real,
        // el overlay tapa/recorta lo que haya justo debajo (típicamente el
        // canvas). Este evento avisa del alto real en cuanto Google lo calcula.
        adm.addListener('bannerAdSizeChanged', (info) => {
            const h = info?.height;
            if (!h) return;
            console.log('[Ads] AdMob banner alto real:', h);
            document.documentElement.style.setProperty('--admob-banner-h', h + 'px');
        });
    }

    // ── AdMob: sincroniza el mute del jugador con el SDK ────────────────────
    // Google recomienda explícitamente llamar a esto (setAppMuted) cuando la
    // app tiene su propio control de silencio — si no, un intersticial/vídeo
    // de recompensa puede sonar aunque el jugador tenga el juego en mute.
    // Best-effort: no todos los creativos de anuncio respetan el flag (lo
    // documenta el propio Google), pero reduce el caso la mayoría de veces.
    //
    // CRASH real encontrado: AdMob solo se inicializa de forma diferida (ver
    // _admLazyInit(), se dispara al empezar a jugar) — pero esta función se
    // llama también desde el botón de sonido, alcanzable desde Ajustes en el
    // MENÚ PRINCIPAL, antes de que el jugador haya jugado ni una vez. En una
    // instalación nueva eso significa llamar a setApplicationMuted() sobre el
    // SDK nativo de Google Mobile Ads ANTES de initialize() — comportamiento
    // no soportado por el propio SDK de Google (puede lanzar una excepción
    // nativa que ningún .catch() de JS intercepta). _admInitialized se pone a
    // true justo cuando initialize() resuelve de verdad; hasta entonces esta
    // función no hace nada — no hace falta "guardar" el mute pendiente:
    // _admLazyInit() ya llama a setMuted(window.isMusicMuted) nada más
    // inicializar, leyendo el valor VIVO de window.isMusicMuted.
    let _admInitialized = false;
    function setMuted(muted) {
        if (!_admInitialized) return;
        const adm = _adm();
        if (!adm) return;
        adm.setApplicationMuted({ muted: !!muted })
            ?.catch?.((e) => console.warn('[Ads] setApplicationMuted failed:', e));
    }

    // ── Banner position ──────────────────────────────────────────────────────
    // Change ONLY this line to move the banner top ↔ bottom.
    const _BANNER_POSITION = 'top'; // 'top' | 'bottom'

    // ── CrazyGames muteAudio support ─────────────────────────────────────────
    function _applyCgMuteSettings(settings) {
        const s = settings || _cgGame()?.settings || {};
        const shouldMute = !!s.muteAudio;
        window._cgMuteAudio = shouldMute;
        if (shouldMute) {
            window.isMusicMuted = true;
            window.isSfxMuted = true;
            try { window.GameAudio?.bgmTheme?.pause?.(); } catch (e) {}
        } else {
            // Restore player's saved preferences (música y efectos, cada uno
            // con su propia clave — ver shared/audio.js)
            window.isMusicMuted = localStorage.getItem('chickenIdleMuted') === 'true';
            window.isSfxMuted = localStorage.getItem('chickenIdleSfxMuted') === 'true';
        }
        console.log('[Ads] muteAudio:', shouldMute, '| isMusicMuted:', window.isMusicMuted, '| isSfxMuted:', window.isSfxMuted);
    }

    // ── Playgama Bridge muteAudio support ─────────────────────────────────────
    // Mismo rol que _applyCgMuteSettings pero para bridge.platform.isAudioEnabled
    // (getter) + bridge.EVENT_NAME.AUDIO_STATE_CHANGED (evento).
    function _applyPgMuteSettings(isEnabled) {
        const shouldMute = isEnabled === false;
        window._pgMuteAudio = shouldMute;
        if (shouldMute) {
            window.isMusicMuted = true;
            // Mismo tratamiento que _applyCgMuteSettings (isSfxMuted se añadió
            // ahí en un cambio en paralelo) — sin esto, forzar mute desde
            // Playgama silenciaba la música pero no los efectos de sonido.
            window.isSfxMuted = true;
            try { window.GameAudio?.bgmTheme?.pause?.(); } catch (e) {}
        } else {
            // Restore player's saved preferences (música y efectos, cada uno
            // con su propia clave — ver shared/audio.js)
            window.isMusicMuted = localStorage.getItem('chickenIdleMuted') === 'true';
            window.isSfxMuted = localStorage.getItem('chickenIdleSfxMuted') === 'true';
        }
        console.log('[Ads] Playgama audio enabled:', isEnabled, '| isMusicMuted:', window.isMusicMuted, '| isSfxMuted:', window.isSfxMuted);
    }

    // ── Playgama Bridge ad listeners — registrados UNA sola vez ──────────────
    // Mismo patrón que _admInitListeners: el SDK de Playgama es basado en
    // eventos (bridge.advertisement.on(...)), no en un callback por llamada
    // como CrazyGames, así que los listeners se registran una vez y las
    // peticiones en curso se rastrean con _pgPendingReward/_pgPendingFail
    // (mismo mecanismo que _admPendingReward/_admPendingFail para AdMob).
    let _pgListenersReady = false;
    let _pgPendingReward  = null;
    let _pgPendingFail    = null;

    function _pgInitListeners(bridge) {
        if (_pgListenersReady) return;
        _pgListenersReady = true;

        bridge.advertisement.on(bridge.EVENT_NAME.INTERSTITIAL_STATE_CHANGED, (state) => {
            console.log('[Ads] Playgama interstitial state:', state);
            if (state === 'closed' || state === 'failed') _adBreakEnd('interstitial');
        });

        bridge.advertisement.on(bridge.EVENT_NAME.REWARDED_STATE_CHANGED, (state) => {
            console.log('[Ads] Playgama rewarded state:', state);
            // Solo se premia en 'rewarded' — nunca en 'closed' (permitiría
            // reclamar la recompensa sin terminar de ver el anuncio, pedido
            // explícito de la doc de Playgama).
            if (state === 'rewarded') {
                const cb = _pgPendingReward;
                _pgPendingReward = null;
                cb?.();
            } else if (state === 'closed' || state === 'failed') {
                if (state === 'failed') {
                    const fail = _pgPendingFail;
                    _pgPendingFail = null;
                    fail?.();
                }
                _pgPendingReward = null;
                _pgPendingFail   = null;
                _adBreakEnd('rewarded');
            }
        });

        // Solo diagnóstico — el banner no tiene lifecycle de pausa/recompensa,
        // pero saber si el SDK llega a 'shown' o se queda en 'failed' es la
        // única forma de distinguir "nuestro código no lo pide bien" de "esta
        // plataforma/entorno no tiene demanda de banner ahora mismo".
        bridge.advertisement.on(bridge.EVENT_NAME.BANNER_STATE_CHANGED, (state) => {
            console.log('[Ads] Playgama banner state:', state);
        });
    }

    // ── One-time setup — register audio hooks + reuse SDK init promise ───────
    function init({ onAdStart, onAdEnd } = {}) {
        _onAdStart = onAdStart || null;
        _onAdEnd   = onAdEnd   || null;

        if (window.GAME_MARKET === 'playgama') {
            // Reuse the promise started in index.html so bridge.initialize() is only called once.
            if (window._pgBridgeReady) {
                _pgReady = window._pgBridgeReady;
                console.log('[Ads] init — reusing window._pgBridgeReady');
            } else if (window.bridge) {
                _pgReady = window.bridge.initialize().catch(() => {});
                console.log('[Ads] init — called bridge.initialize() (fallback)');
            } else {
                console.warn('[Ads] init — no Playgama bridge found, ads will be stubs');
            }

            (_pgReady || Promise.resolve()).then(() => {
                const bridge = window.bridge;
                if (!bridge) return;
                _applyPgMuteSettings(bridge.platform.isAudioEnabled);
                try {
                    bridge.platform.on(bridge.EVENT_NAME.AUDIO_STATE_CHANGED, _applyPgMuteSettings);
                    // Pausa/reanuda impuesta por el host (p.ej. el jugador cambia de
                    // pestaña dentro del portal) — reutiliza el mismo lifecycle que ya
                    // frena/reanuda el loop principal (window.isAdPaused) en vez de
                    // inventar un mecanismo nuevo. No es un anuncio real, pero
                    // _onAdStart/_onAdEnd ya solo tocan música/UI genérica (el chequeo
                    // de adType==='interstitial'/'rewarded' en el caller ignora
                    // cualquier otro valor sin efecto).
                    bridge.platform.on(bridge.EVENT_NAME.PAUSE_STATE_CHANGED, (isPaused) => {
                        console.log('[Ads] Playgama pause state:', isPaused);
                        if (isPaused) {
                            window.isAdPaused = true;
                            gameplayStop();
                            _onAdStart?.();
                        } else {
                            window.isAdPaused = false;
                            gameplayStart();
                            _onAdEnd?.('platformPause');
                        }
                    });
                } catch (e) {}
            });
            return;
        }

        // Reuse the promise started in index.html so SDK.init() is only called once.
        if (window._cgSdkReady) {
            _sdkReady = window._cgSdkReady;
            console.log('[Ads] init — reusing window._cgSdkReady');
        } else if (window.CrazyGames?.SDK) {
            _sdkReady = window.CrazyGames.SDK.init().catch(() => {});
            console.log('[Ads] init — called SDK.init() (fallback)');
        } else {
            console.warn('[Ads] init — no CrazyGames SDK found, ads will be stubs');
        }

        // Apply muteAudio once SDK is ready, then listen for changes.
        _sdkRun(() => {
            _applyCgMuteSettings();
            try {
                _cgGame()?.addSettingsChangeListener?.(_applyCgMuteSettings);
            } catch (e) {}
        });

        // AdMob: el registro de listeners + consentimiento UMP + MobileAds.initialize()
        // NO va aquí — ver _admLazyInit()/gameplayStart() más abajo para el motivo
        // (se difiere hasta que el jugador entra de verdad a un modo, para no competir
        // con la animación de la intro del menú).
    }

    // ── AdMob: init diferido hasta gameplayStart() ──────────────────────────
    // Antes vivía en init() (arranque de la página) — pero eso significaba
    // pedir el consentimiento UMP, y mostrar su formulario si hacía falta,
    // justo cuando empezaba la animación de la intro. El formulario es un
    // overlay NATIVO a pantalla completa, así que aparecía literalmente
    // encima de la intro (visto en dispositivo real). Se difiere hasta que
    // el jugador entra de verdad a un modo — mismo motivo y mismo punto ya
    // usado para la precarga de intersticial/recompensa, ver más abajo.
    // _admInitPromise cachea la promesa para que solo se ejecute una vez
    // (llamadas posteriores a gameplayStart() la reutilizan ya resuelta).
    let _admInitPromise = null;
    function _admLazyInit() {
        const adm = _adm();
        if (!adm) return Promise.resolve();
        if (_admInitPromise) return _admInitPromise;
        console.log('[Ads] gameplayStart → AdMob plugin found, initializing (diferido)');
        _admInitListeners(adm);
        // Orden pedido por Google: resolver el consentimiento (y mostrar el
        // formulario si hace falta) ANTES de inicializar el SDK de anuncios.
        _admInitPromise = _admHandleConsent(adm).then(() => {
            return adm.initialize({ initializeForTesting: _ADMOB_TEST_MODE }).then(() => {
                _admInitialized = true;
                // Estado inicial de mute, tal y como pide Google (afecta a qué
                // creativos de vídeo son elegibles para la petición).
                setMuted(window.isMusicMuted);
            }).catch((e) => {
                console.warn('[Ads] AdMob initialize failed:', e);
            });
        });
        return _admInitPromise;
    }

    // ── Platform accessors ───────────────────────────────────────────────────
    // SDK.game / SDK.ad / SDK.banner are getters that THROW if SDK isn't initialized.
    // Optional chaining (?.) doesn't catch throws, only null/undefined — so we wrap them.
    function _cgGame()   { try { return window.CrazyGames?.SDK?.game;   } catch (e) { return null; } }
    function _cgAd()     { try { return window.CrazyGames?.SDK?.ad;     } catch (e) { return null; } }
    function _cgBanner() { try { return window.CrazyGames?.SDK?.banner; } catch (e) { return null; } }

    // Runs fn after SDK init if on CrazyGames, otherwise runs it immediately.
    // Checks window._cgSdkReady as fallback in case GameAds.init() wasn't called yet.
    function _sdkRun(fn) {
        const p = _sdkReady || window._cgSdkReady || null;
        if (p) { p.then(fn); } else { fn(); }
    }

    function _logAdState(label) {
        console.log('[Ads]', label, '| _sdkReady:', !!(_sdkReady || window._cgSdkReady), '| _cgGame():', !!_cgGame(), '| _cgAd():', !!_cgAd());
    }

    // ── Internal ad-break helpers ────────────────────────────────────────────
    // Timeout de seguridad: si un anuncio nunca dispara ningún evento de cierre
    // (dismissed/failedToShow) — SDK atascado, doble-petición nativa confundida,
    // proceso muerto en segundo plano... — window.isAdPaused se quedaba a true
    // para siempre, y con eso update() (script.js) no volvía a correr nunca:
    // el juego se veía "congelado hasta reiniciar la app". Este timeout fuerza
    // la recuperación aunque el SDK nunca responda. 60s da margen de sobra
    // (un recompensado normal dura 15-30s vistos + carga — pero se ha visto en
    // dispositivo real un caso legítimo de 65s+ entre "showing now" y el evento
    // de recompensa, así que 60s se quedaba corto y cortaba anuncios que SÍ
    // iban a completarse. 120s da mucho más margen sin dejar de ser una red de
    // seguridad real).
    const _AD_BREAK_TIMEOUT_MS = 120000;
    let _adBreakTimeoutId = null;

    // Pauses the game loop and audio before any ad.
    function _adBreakStart() {
        window.isAdPaused = true;
        _onAdStart?.();
        gameplayStop();
        // Clear banner during ads (required by CrazyGames — no banner on top of ad)
        if (_currentBannerId) {
            try { _cgBanner()?.clearBanner?.(_currentBannerId); } catch (e) {}
        }
        clearTimeout(_adBreakTimeoutId);
        _adBreakTimeoutId = setTimeout(() => {
            // OJO: NO limpiar _admPendingReward/_admPendingFail aquí. Este
            // timeout es solo para no dejar el JUEGO bloqueado si el anuncio
            // nativo nunca avisa de que ha terminado — pero el anuncio puede
            // seguir en curso de verdad (visto en dispositivo real: el evento
            // de recompensa llegó bien, solo que más tarde de lo esperado).
            // Si se limpia aquí, esa recompensa legítima se pierde en cuanto
            // llega, porque ya no hay callback al que avisar. request() ya
            // rechaza peticiones nuevas mientras _admPendingReward siga
            // ocupado, así que no hay riesgo de que un segundo anuncio la pise.
            console.warn('[Ads] ad break superó el timeout sin evento de cierre — reanudando el juego (si el anuncio termina más tarde, la recompensa se sigue concediendo)');
            _adBreakEnd('timeout');
        }, _AD_BREAK_TIMEOUT_MS);
    }

    // Resumes the game loop and audio after any ad.
    // adType: 'interstitial' | 'rewarded' | 'timeout' — pasado a onAdEnd() para
    // que el llamador pueda distinguir (p.ej. mostrar el aviso de "quitar
    // anuncios" solo tras un intersticial, nunca tras un anuncio de recompensa
    // elegido voluntariamente por el jugador, ni tras una recuperación forzada).
    function _adBreakEnd(adType) {
        clearTimeout(_adBreakTimeoutId);
        _adBreakTimeoutId = null;
        window.isAdPaused = false;
        _onAdEnd?.(adType);
        gameplayStart();
        // Re-request banner after ad ends. Pequeño respiro antes de repedirlo:
        // justo al cerrarse el anuncio, el overlay del SDK puede seguir un
        // instante en el DOM/mid-transición, y el propio SDK comprobaba la
        // visibilidad del contenedor EN ESE momento → "notVisible" en un
        // contenedor que en realidad está bien (confirmado con log real de
        // CrazyGames: BannerError notVisible justo tras un midgame).
        if (_currentBannerId) setTimeout(() => _requestBannerNow(_currentBannerId), 500);
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────
    // Call when actual gameplay starts (player is in control).
    function gameplayStart() {
        // Pedido explícito de CrazyGames en review: "don't call any gameplay
        // events while an ad is playing". _adBreakEnd() (más abajo) SIEMPRE
        // pone isAdPaused=false ANTES de llamar aquí, así que su propio
        // resume nunca lo bloquea este guard — solo frena a cualquier OTRO
        // caller (ranking, ajustes, cambio de modo...) que intente marcar
        // "el jugador está jugando" mientras el anuncio sigue en pantalla de
        // verdad.
        if (window.isAdPaused) { console.warn('[Ads] gameplayStart ignorado — hay un anuncio en curso'); return; }
        console.log('[Ads] gameplayStart called');
        _sdkRun(() => {
            console.log('[Ads] gameplayStart → SDK ready, calling SDK.game.gameplayStart()');
            _cgGame()?.gameplayStart?.();
        });
        // AdMob hook: window.AdMob?.resume?.();
        // Init (consentimiento UMP + MobileAds.initialize) y precarga de
        // intersticial/recompensa AQUÍ, no en init() — así nunca compiten por
        // hilo principal ni por pantalla con la animación de la intro del menú
        // (cámara + logo cayendo). Evidencia real por logcat: las llamadas
        // nativas de precarga coincidían, milisegundo a milisegundo, con una
        // ráfaga de huecos de hasta 130ms entre frames de la intro — y el
        // formulario de consentimiento, al ser un overlay nativo a pantalla
        // completa, se veía literalmente encima de la intro. Hay tiempo de
        // sobra: el primer intersticial no se pide hasta los 8 min de partida,
        // y estas funciones son idempotentes (no repiten trabajo si ya está
        // cargado, cargando, o ya inicializado).
        _admLazyInit().then(() => {
            _admPreloadInterstitial();
            _admPreloadRewarded();
        });
    }

    // Celebración nativa de CrazyGames (confetti, etc. — lo dibuja el propio
    // sitio, no el juego). Pedido explícito por la doc del SDK: "sparingly,
    // the celebration should remain a special moment" — solo en hitos reales
    // (logro, retiro), nunca en cada acción menor. No-op fuera de CrazyGames
    // (_cgGame() da null, el optional chaining se queda ahí sin más).
    function happyTime() {
        _sdkRun(() => {
            console.log('[Ads] happyTime → SDK.game.happytime()');
            _cgGame()?.happytime?.();
        });
    }

    // Call when gameplay pauses (menus, overlays, ads, cutscenes).
    function gameplayStop() {
        console.log('[Ads] gameplayStop called');
        _sdkRun(() => {
            console.log('[Ads] gameplayStop → SDK ready, calling SDK.game.gameplayStop()');
            _cgGame()?.gameplayStop?.();
        });
        // AdMob hook: window.AdMob?.pause?.();
    }

    // ── Midgame (interstitial) ads ───────────────────────────────────────────
    // Called automatically on a timer. Pauses the game for the ad duration.
    function requestMidgame() {
        // Evita pedir un segundo anuncio nativo mientras el primero sigue en
        // curso (posible doble-tap, o el timer del midgame disparando otra vez
        // antes de que llegue el evento de cierre) — dos peticiones simultáneas
        // pueden confundir al SDK y hacer que ninguna dispare su evento final,
        // dejando isAdPaused a true para siempre (ver _adBreakStart).
        if (window.isAdPaused) { console.warn('[Ads] requestMidgame — ya hay un anuncio en curso, ignorado'); return; }
        _logAdState('requestMidgame');

        if (window.GAME_MARKET === 'playgama') {
            const bridge = window.bridge;
            if (!bridge?.advertisement) { console.warn('[Ads] requestMidgame — Playgama bridge no listo, se omite'); return; }
            _pgInitListeners(bridge);
            console.log('[Ads] requestMidgame → Playgama showInterstitial() | isInterstitialSupported:', bridge.advertisement.isInterstitialSupported);
            _adBreakStart();
            // 'midgame' coincide con el id declarado en playgama-bridge-config.json.
            bridge.advertisement.showInterstitial('midgame');
            return;
        }

        _sdkRun(() => {
            if (!_cgAd()) { console.warn('[Ads] requestMidgame — no _cgAd(), skipping'); return; }
            console.log('[Ads] requestMidgame → requesting midgame ad');
            _adBreakStart();
            _cgAd().requestAd('midgame', {
                adStarted:  () => { console.log('[Ads] midgame adStarted'); },
                adFinished: () => { console.log('[Ads] midgame adFinished'); _adBreakEnd('interstitial'); },
                adError:    (e) => { console.warn('[Ads] midgame adError:', e); _adBreakEnd('interstitial'); },
            });
        });

        // _sdkRun() above runs synchronously when there's no CrazyGames SDK promise
        // (see _sdkRun), so by this point _cgAd() already reflects reality.
        const adm = _adm();
        if (_ADMOB_INTERSTITIAL_ENABLED && !_cgAd() && adm) {
            if (!_consentCanRequestAds) { console.warn('[Ads] requestMidgame — sin consentimiento válido (UMP), se omite'); return; }
            if (_admInterstitialLoaded) {
                // Ya estaba precargado — se muestra al instante, sin pausa de carga.
                console.log('[Ads] requestMidgame → AdMob interstitial preloaded, showing now');
                _adBreakStart();
                adm.showInterstitial().catch((e) => {
                    console.warn('[Ads] AdMob interstitial error:', e);
                    _adBreakEnd('interstitial');
                });
            } else if (_admInterstitialLoading) {
                // Ya hay una precarga en curso — no lanzar una segunda petición
                // nativa para el mismo bloque (dispara "Too many recently failed
                // requests" en Google, ver el mismo caso en request() más abajo).
                // Es automático (no lo pidió el jugador), así que simplemente se
                // omite este ciclo sin pausar el juego para nada.
                console.warn('[Ads] requestMidgame → AdMob interstitial ya se está precargando, se omite');
            } else {
                // Fallback poco común (aún no había terminado de precargar): se pide y
                // se muestra en cuanto llegue, como antes.
                console.log('[Ads] requestMidgame → AdMob interstitial not preloaded, prepare+show');
                _adBreakStart();
                adm.prepareInterstitial({ adId: _ADMOB_INTERSTITIAL_ID, isTesting: _ADMOB_TEST_MODE })
                    .then(() => adm.showInterstitial())
                    .catch((e) => {
                        console.warn('[Ads] AdMob interstitial error:', e);
                        _adBreakEnd('interstitial');
                    });
            }
        }
    }

    // ── Rewarded ads ─────────────────────────────────────────────────────────
    // Pauses + mutes the game, shows the ad, then rewards and resumes.
    // IMPORTANT: must be called synchronously from a user gesture (click).
    // _sdkRun() uses .then() which breaks the browser's user-gesture chain
    // and causes requestFullscreen to fail inside the CG SDK.
    // So we check _cgAd() synchronously first — if SDK is ready, call directly.
    // onFail (opcional): se llama cuando el anuncio falla de verdad (no fill,
    // error de red, límite de peticiones...) — para que quien llame pueda
    // avisar al jugador en vez de dejar el botón sin ninguna respuesta visible.
    function request(onReward, onFail) {
        // Mismo motivo que en requestMidgame — sin esto, pulsar dos veces
        // seguidas "ver anuncio" (fácil: hay unos cientos de ms entre pedirlo
        // y que la pantalla nativa lo tape de verdad) podía lanzar una segunda
        // petición nativa mientras la primera seguía en curso, dejando el
        // juego congelado para siempre si el SDK nunca respondía a ninguna.
        // _admPendingReward además cubre el caso "el timeout de seguridad ya
        // reanudó el juego, pero el anuncio anterior todavía puede conceder su
        // recompensa más tarde" — sin este chequeo, una segunda petición aquí
        // pisaría ese callback pendiente y la recompensa se concedería mal
        // (o a la petición equivocada).
        if (window.isAdPaused || _admPendingReward || _pgPendingReward) { console.warn('[Ads] request (rewarded) — ya hay un anuncio en curso (o una recompensa aún pendiente), ignorado'); onFail?.(); return; }
        _logAdState('request (rewarded)');
        // Tienda de gemas (scenarios/farm/gems.js, solo CrazyGames — fuera de ahí FarmGems
        // no está activo y esto no hace nada):
        //  · VIP: la recompensa se da sin anuncio. Mismo orden que un anuncio real
        //    (onReward y luego onAdEnd('rewarded')) para que script.js revele el boost.
        //  · Resto: gemas por cada anuncio de recompensa terminado (FarmGems.rewardForAd:
        //    cuántas, tope diario y quién no las recibe).
        const _fg = window.FarmGems;
        if (_fg && _fg.isVip && _fg.isVip()) {
            console.log('[Ads] request → VIP, recompensa sin anuncio');
            onReward();
            _onAdEnd?.('rewarded');
            return;
        }
        if (_fg && _fg.rewardForAd) {
            const _origReward = onReward;
            onReward = function () { _origReward.apply(this, arguments); try { _fg.rewardForAd(); } catch (e) {} };
        }

        if (window.GAME_MARKET === 'playgama') {
            const bridge = window.bridge;
            if (!bridge?.advertisement) {
                // SDK aún no listo — igual que el resto de plataformas sin SDK,
                // se premia al instante en vez de dejar al jugador sin respuesta.
                console.log('[Ads] request → Playgama bridge no listo, rewarding immediately (stub)');
                onReward();
                return;
            }
            _pgInitListeners(bridge);
            _pgPendingReward = onReward;
            _pgPendingFail   = onFail;
            // isRewardedSupported: getter real del SDK — si viene false aquí, el
            // problema no es este código, es que la plataforma/entorno de prueba
            // no tiene demanda de anuncios de recompensa (fuera de nuestro control).
            console.log('[Ads] request → Playgama showRewarded() | isRewardedSupported:', bridge.advertisement.isRewardedSupported);
            _adBreakStart();
            // 'shop_bonus' coincide con el id declarado en playgama-bridge-config.json.
            bridge.advertisement.showRewarded('shop_bonus');
            return;
        }

        const adModule = _cgAd();
        if (adModule) {
            // SDK already ready — call directly in the user gesture context.
            console.log('[Ads] request → requesting rewarded ad (sync, gesture preserved)');
            _adBreakStart();
            adModule.requestAd('rewarded', {
                adStarted:  () => { console.log('[Ads] rewarded adStarted'); },
                // onReward() ANTES que _adBreakEnd('rewarded'): onReward() es donde
                // script.js empuja el boost nuevo a state._boostActive con
                // _pendingReveal:true (ver el listener de #eb-accept), y
                // _adBreakEnd() es lo que dispara onAdEnd('rewarded') → limpia ese
                // flag para revelar el testigo/pill del boost. En el orden anterior
                // (_adBreakEnd primero) la limpieza corría cuando el boost nuevo
                // TODAVÍA no existía en el array — se quedaba _pendingReveal:true
                // para siempre: el bonus se aplicaba pero el contador nunca se veía
                // (reportado en CrazyGames, donde este es el único camino usado).
                adFinished: () => { console.log('[Ads] rewarded adFinished → reward granted'); onReward(); _adBreakEnd('rewarded'); },
                adError:    (e) => { console.warn('[Ads] rewarded adError:', e); _adBreakEnd('rewarded'); onFail?.(); },
            });
            return;
        }

        // AdMob path (Android/Google Play). Unlike CrazyGames, showing a native
        // rewarded ad doesn't need the browser Fullscreen-API user-gesture chain,
        // so it's fine to prepare+show asynchronously here.
        // Sin consentimiento válido (UMP) no se pide el anuncio — cae al stub de
        // debajo (recompensa inmediata) en vez de dejar al jugador sin respuesta.
        const adm = _adm();
        if (adm && _consentCanRequestAds) {
            if (_admRewardedLoaded) {
                // Ya estaba precargado — se muestra al instante, sin pausa de carga.
                _admPendingReward = onReward;
                _admPendingFail   = onFail;
                console.log('[Ads] request → AdMob rewarded preloaded, showing now');
                _adBreakStart();
                adm.showRewardVideoAd().catch((e) => {
                    console.warn('[Ads] AdMob rewarded error:', e);
                    _admRewardedFail();
                    _adBreakEnd('rewarded');
                });
            } else if (_admRewardedLoading) {
                // Ya hay una precarga en curso (p.ej. lanzada por gameplayStart())
                // — NO lanzar una segunda petición nativa para el mismo bloque de
                // anuncio. Justo eso ("dos prepareRewardVideoAd casi a la vez")
                // es lo que dispara en Google el error "Too many recently failed
                // requests" (visto en logcat real) y deja al jugador sin ninguna
                // respuesta visible al pulsar "ver anuncio".
                console.warn('[Ads] request → AdMob rewarded ya se está precargando, se evita petición duplicada');
                onFail?.();
            } else {
                // No preloaded and nothing in flight: kick off a fresh prepare+show.
                _admPendingReward = onReward;
                _admPendingFail   = onFail;
                console.log('[Ads] request → AdMob rewarded not preloaded, prepare+show');
                _adBreakStart();
                adm.prepareRewardVideoAd({ adId: _ADMOB_REWARDED_ID, isTesting: _ADMOB_TEST_MODE })
                    .then(() => adm.showRewardVideoAd())
                    .catch((e) => {
                        console.warn('[Ads] AdMob rewarded error:', e);
                        _admRewardedFail();
                        _adBreakEnd('rewarded');
                    });
            }
            return;
        }

        // SDK not yet ready — fall back to stub (reward immediately).
        // Deferring via .then() here would lose the user gesture anyway.
        console.log('[Ads] request → SDK not ready, rewarding immediately (stub)');
        onReward();
    }

    // ── Leaderboards ─────────────────────────────────────────────────────────
    // Submit a numeric score. No-op on non-CG platforms.
    function saveScore(leaderboardName, score) {
        console.log('[Ads] saveScore:', leaderboardName, score);
        if (window.GAME_MARKET === 'playgama') {
            (_pgReady || Promise.resolve()).then(() => {
                try {
                    window.bridge?.leaderboards?.setScore?.(leaderboardName, score)
                        ?.catch?.((e) => console.warn('[Ads] Playgama setScore failed:', e));
                } catch (e) { console.warn('[Ads] Playgama setScore exception:', e); }
            });
            return;
        }
        _sdkRun(() => {
            try {
                window.CrazyGames?.SDK?.leaderboard?.save(leaderboardName, score)
                    ?.catch?.((e) => { console.warn('[Ads] saveScore failed:', e); });
            } catch (e) { console.warn('[Ads] saveScore exception:', e); }
        });
        // AdMob: no leaderboard equivalent
    }

    // Show the leaderboard overlay.
    // SDK v3 does not expose a built-in showLeaderboard overlay — calls fallback() on all platforms.
    function showLeaderboard(leaderboardName, fallback) {
        fallback?.();
    }

    // ── Banner ads ───────────────────────────────────────────────────────────
    // containerId: id del div reservado en el HTML para el banner (e.g. 'game-banner').
    // Platform routing:
    //   CrazyGames → SDK.banner.requestBanner() inyecta el banner en el div.
    //   AdMob      → descomenta el hook AdMob; el div actúa como placeholder de espacio.
    //
    // Solo se muestra en pantallas con ratio > 1.78 (más altas que 16:9 — a 16:9
    // o menos no cabe). En esas pantallas el hueco no se reserva — el canvas
    // recibe el 100% del espacio.

    let _bannerInterval = null;

    // CrazyGames rechaza requestBanner() con "bannerCooldown" si se pide dos
    // veces para el mismo contenedor en menos de 30s (confirmado con log real:
    // "A banner has already been requested for container ... less than 30
    // seconds ago"). _syncBannerToGameState puede disparar una petición nueva
    // sin que haga falta — p.ej. al cambiar de reto, CinematicCore.reset()
    // toca la clase body.in-game (aunque nunca se sale realmente de partida),
    // y eso reengancha showBanner() sobre un banner que ya estaba bien puesto.
    // Guardamos cuándo se pidió cada contenedor por última vez para no volver
    // a pedirlo antes de que el propio SDK vaya a aceptarlo — así se evita el
    // rechazo en vez de intentar sortearlo a reintentos cortos (30s no se
    // arregla reintentando cada 400ms).
    const _lastBannerRequestTs = {};
    const _BANNER_COOLDOWN_MS = 30000;

    // "bannersDisabledMobileApp" (confirmado en la documentación oficial:
    // docs.crazygames.com/sdk/banners/ → Errors) — cuando el juego corre
    // DENTRO de la app móvil de CrazyGames (no en su web/navegador), los
    // banners están deshabilitados por diseño de la plataforma, sin
    // excepción; no es un error transitorio ni algo que un reintento vaya a
    // arreglar. rewarded/midgame sí funcionan ahí con normalidad. Una vez se
    // confirma este error para un contenedor, se deja de pedir banner para
    // él el resto de la sesión y se oculta — sin esto se quedaba reintentando
    // cada 35s para siempre y, si se llegaba a mostrar el contenedor vacío,
    // dejaba una franja negra sin usar ocupando espacio en la app.
    const _bannerDisabledPermanently = {};

    // CrazyGames exige width/height explícitos en requestBanner() — sin ellos
    // el SDK falla con "undefinedxundefined is not a valid size" (visto en
    // producción: el hueco del banner se quedaba vacío sin ningún error en
    // nuestra consola, solo en la de CrazyGames). game-banner (portrait, tira
    // horizontal arriba) y desktop-banner (franja de 50px de alto en el
    // topbar) usan el tamaño IAB estándar más cercano a su alto real.
    const _BANNER_SIZES = {
        'game-banner':    { width: 320, height: 50 },
        'desktop-banner': { width: 320, height: 50 },
    };

    // _retriesLeft: SDK.banner es un getter que ya no throwea una vez _sdkRun
    // esperó a _cgSdkReady — pero (igual que SDK.data, ver _waitForSDK en
    // shared/save.js) puede seguir rechazando con "not initialized" durante un
    // instante justo después de que SDK.init() resuelva, antes de estar
    // REALMENTE listo. Antes esto se perdía en silencio hasta el siguiente
    // refresco de 35s (o para siempre, si esos 35s nunca llegaban a probarse) —
    // probable causa de "container not available" al revisar el banner recién
    // entrado en partida. Reintenta unas pocas veces con una espera corta,
    // mismo patrón ya probado para SDK.data.
    function _requestBannerNow(containerId, _retriesLeft) {
        const _isFreshCall = _retriesLeft === undefined;
        if (_retriesLeft === undefined) _retriesLeft = 15;

        if (_bannerDisabledPermanently[containerId]) return;

        // Solo se aplica en la llamada "fresca" (no en los propios reintentos
        // de esta función, que ya manejan su error específico aparte) — evita
        // pedir un banner que el SDK va a rechazar de todos modos por
        // "bannerCooldown" (ver _lastBannerRequestTs arriba). El banner que ya
        // está puesto se deja tal cual en vez de tocarlo sin necesidad.
        if (_isFreshCall) {
            const _elapsed = Date.now() - (_lastBannerRequestTs[containerId] || 0);
            if (_elapsed < _BANNER_COOLDOWN_MS) {
                console.log('[Ads] requestBanner: en cooldown (' + Math.ceil((_BANNER_COOLDOWN_MS - _elapsed) / 1000) + 's), se omite —', containerId);
                return;
            }
        }

        _sdkRun(() => {
            const b = _cgBanner();
            if (b) {
                const size = _BANNER_SIZES[containerId] || { width: 320, height: 50 };
                console.log('[Ads] requestBanner:', containerId, size);
                _lastBannerRequestTs[containerId] = Date.now();
                // El SDK v3 espera la clave "id" (confirmado en la documentación
                // oficial: requestBanner({ id, width, height })) — el intento
                // anterior con "containerId" (creyendo que era la clave correcta
                // tras cambiarla desde "bannerId") seguía siendo el nombre
                // equivocado: el SDK no lo reconoce, lee su propio "id" interno
                // como undefined, y construye el contenedor que busca como
                // "undefined-crazygames-inner" — que nunca existe. Confirmado con
                // el log real de CrazyGames: id: 'undefined-crazygames-inner' y
                // "ContainerId: undefined" pese a que SÍ mandábamos el div correcto.
                const req = b.requestBanner({ id: containerId, width: size.width, height: size.height });
                req?.catch?.(e => {
                    const _msg = String(e?.message || e);
                    if (e?.code === 'bannersDisabledMobileApp' || _msg.includes('bannersDisabledMobileApp')) {
                        console.log('[Ads] banner deshabilitado por la plataforma (app móvil de CrazyGames) — no se reintenta más esta sesión:', containerId);
                        _bannerDisabledPermanently[containerId] = true;
                        clearInterval(_bannerInterval);
                        _bannerInterval = null;
                        const _elDisabled = document.getElementById(containerId);
                        if (_elDisabled) _elDisabled.style.display = 'none';
                        return;
                    }
                    // "bannerCooldown": el SDK rechaza por su propio límite de 30s —
                    // reintentar a los 400ms es inútil (va a fallar igual toda la
                    // ventana de reintentos). Se deja pasar: el guard de arriba evita
                    // que vuelva a pasar por nuestra propia culpa, y si aun así llega
                    // aquí (otro disparador fuera de nuestro control), el refresco
                    // periódico de 35s ya lo recogerá cuando el cooldown expire.
                    if (_msg.includes('bannerCooldown') || _msg.includes('already been requested')) {
                        console.warn('[Ads] banner error (cooldown del SDK, no se reintenta a corto plazo):', e);
                        return;
                    }
                    // "not initialized" (SDK.banner aún no listo) y "notVisible" (el
                    // contenedor no se ve como "entero" en el instante exacto del
                    // chequeo — típico justo tras cerrarse un midgame, o durante una
                    // transición) son ambos transitorios: mismo reintento para los
                    // dos. Antes solo cubría "not initialized" y un "notVisible" se
                    // abandonaba sin más, dejando el banner caído hasta el próximo
                    // refresco de 35s — y si ESE también caía en mal momento, se
                    // quedaba caído indefinidamente.
                    if (_retriesLeft > 0 && (_msg.includes('not initialized') || _msg.includes('notVisible') || _msg.includes('not entirely visible'))) {
                        console.log('[Ads] requestBanner: retry (' + _msg + ')', 15 - _retriesLeft + 1);
                        // Limpiar antes de reintentar: un requestBanner repetido sobre
                        // el mismo id sin clearBanner de por medio puede quedarse
                        // pegado al primer intento fallido en vez de crear uno nuevo.
                        try { b.clearBanner?.(containerId); } catch (_) {}
                        setTimeout(() => _requestBannerNow(containerId, _retriesLeft - 1), 400);
                    } else {
                        console.warn('[Ads] banner error:', e);
                    }
                });
                return;
            }
            // _cgBanner() devolvió null pese a que _sdkRun ya esperó _cgSdkReady —
            // el módulo banner puede tardar un pelín más en poblarse tras init().
            if (_retriesLeft > 0 && window.CrazyGames?.SDK) {
                setTimeout(() => _requestBannerNow(containerId, _retriesLeft - 1), 150);
            }
        });

        // AdMob: el banner es un overlay NATIVO por encima del WebView — no se
        // dibuja dentro del <div>, así que el contenedor solo sirve para reservar
        // el hueco de layout (ver showBanner()/CSS) mientras el SDK pinta encima.
        //
        // CRÍTICO: hay que esperar a _admInitPromise antes de llamar a
        // adm.showBanner() — confirmado con logcat real (NullPointerException en
        // BannerExecutor.createNewAdView, mViewGroup.addView sobre null) que en
        // según qué dispositivo (visto en Samsung gama media-alta, Android 12+)
        // esta llamada nativa llega ANTES de que adm.initialize() haya terminado
        // de ejecutarse en el lado nativo. mViewGroup solo se asigna dentro de
        // AdMob.initialize() (bannerExecutor.initialize(), ver plugin nativo) —
        // si el banner se pide antes de que eso corra, se queda null para
        // siempre y CADA intento de mostrar banner revienta la app. La causa:
        // gameplayStart() (que dispara _admLazyInit(), con un requestConsentInfo
        // real de por medio antes de llegar a adm.initialize()) y showBanner()
        // (disparado por el MutationObserver de body.in-game, que reacciona casi
        // al instante siguiente) se llaman prácticamente a la vez al entrar en
        // partida — sin este .then(), showBanner() no tiene ninguna garantía de
        // ir DESPUÉS de que initialize() haya terminado de verdad en nativo.
        const adm = _adm();
        if (_ADMOB_BANNER_ENABLED && !_cgBanner() && adm && _consentCanRequestAds) {
            (_admInitPromise || Promise.resolve()).then(() => {
                adm.showBanner({
                    adId: _ADMOB_BANNER_ID,
                    adSize: 'ADAPTIVE_BANNER',
                    position: _BANNER_POSITION === 'top' ? 'TOP_CENTER' : 'BOTTOM_CENTER',
                    isTesting: _ADMOB_TEST_MODE,
                }).catch((e) => console.warn('[Ads] AdMob banner error:', e));
            });
        }

        // Playgama Bridge: igual que AdMob, es un overlay del propio SDK — no
        // recibe un id de contenedor, solo la posición. El <div> del containerId
        // solo reserva el hueco de layout (CSS), el SDK pinta encima.
        if (window.GAME_MARKET === 'playgama') {
            (_pgReady || Promise.resolve()).then(() => {
                const bridge = window.bridge;
                if (!bridge?.advertisement) { console.warn('[Ads] requestBanner (Playgama) — bridge.advertisement no disponible'); return; }
                _pgInitListeners(bridge);
                // isBannerSupported: getter real del SDK — si viene false aquí, el
                // problema no es este código, es que la plataforma/entorno de
                // prueba no tiene demanda de banners (fuera de nuestro control).
                console.log('[Ads] requestBanner (Playgama):', _BANNER_POSITION, '| isBannerSupported:', bridge.advertisement.isBannerSupported);
                // 'topbar' coincide con el id declarado en playgama-bridge-config.json.
                bridge.advertisement.showBanner(_BANNER_POSITION, 'topbar');
            });
        }
    }

    function showBanner(containerId) {
        // Pedido explícito: en CrazyGames, SIN banner en portrait (ni el de la
        // app móvil — ya vetado por la propia plataforma, ver bannersDisabledMobileApp
        // más abajo — ni el de un navegador/ventana móvil-estrecha). Solo afecta
        // a CrazyGames: en Google Play (que siempre es portrait) se deja tal
        // cual, sigue mostrando banner con normalidad.
        // playgama añadido por el mismo motivo, pedido explícito: su SDK no
        // soporta banner en absoluto (isBannerSupported siempre false,
        // confirmado contra su código fuente — ver comentario en style.css),
        // así que en portrait el <div> #game-banner (fondo negro sólido, sin
        // ningún texto de relleno como sí tiene el de escritorio) se quedaba
        // como una barra negra vacía arriba de la pantalla sin motivo.
        if ((window.GAME_MARKET === 'crazygames' || window.GAME_MARKET === 'playgama') && window.GAME_MODE === 'portrait') return;
        // Banner de AdMob deshabilitado a petición explícita (_ADMOB_BANNER_ENABLED):
        // sin este guard, el div se ponía en display:flex y reservaba
        // --admob-banner-h igualmente aunque el overlay nativo nunca llegara a
        // pintarse encima (showBanner solo evitaba la llamada nativa, no la
        // reserva de espacio) — dejaba un hueco vacío en vez de ocupar 0px.
        // Solo aplica cuando AdMob es el backend real (no toca CrazyGames).
        if (!_ADMOB_BANNER_ENABLED && !_cgBanner() && _adm()) return;
        // Ratio <= 1.78 (16:9 o menos alto): no cabe hueco para el banner sin
        // apretar el resto del layout. Esta gate SÍ existía (ver git history,
        // commit b940d1c) pero se quitó por completo al depurar un problema de
        // CrazyGames — la causa real ahí resultó ser el veto de la propia
        // plataforma a banners en su app móvil (ver bannersDisabledMobileApp más
        // abajo), nada que ver con el ratio, así que aquella vez sobraba. Pero al
        // quitarla entera también se perdió la protección para Google Play/AdMob,
        // que si la necesita — aquí no hay ningún veto de plataforma, así que sin
        // esto un móvil de ratio bajo (~16:9) sí intenta mostrar el banner y el
        // canvas queda apretado contra la tienda. _safeInnerH/_safeInnerW (no
        // existían cuando se escribió la gate original) evitan el valor
        // transitorio incorrecto de window.innerHeight/innerWidth en el arranque
        // en frío del WebView de Android (ver shared/responsive.js).
        //
        // Las tablets quedan EXCLUIDAS de esta gate — tienen, por forma física,
        // un ratio más bajo que cualquier móvil (más "cuadradas": una tablet de
        // 10" en portrait ronda 1.3-1.6, por debajo incluso del 1.78 del corte),
        // así que sin esta exclusión el check las trataba igual que a un móvil
        // estrecho y les ocultaba el banner también a ellas — cuando son
        // justamente las que SÍ tienen sitio de sobra (y ya cuentan con su propio
        // tope de ancho, ver portrait.css @media (min-width:600px), que reserva
        // el hueco real del banner adaptativo). Mismo umbral de 600px/dp que usa
        // ese @media — es la propia definición de "tablet" que usa Android
        // (sw600dp).
        const _isTabletWidth = window._safeInnerW() >= 600;
        if (containerId === 'game-banner' && !_isTabletWidth && window._safeInnerH() / window._safeInnerW() <= 1.78) return;
        _currentBannerId = containerId;
        const el = document.getElementById(containerId);
        if (!el) return;
        el.classList.toggle('banner-bottom', _BANNER_POSITION === 'bottom');
        el.style.display = 'flex';
        // Alto de reserva por defecto (mismo valor que antes de existir el
        // ajuste dinámico) hasta que llegue el alto real por bannerAdSizeChanged
        // (AdMob) — CrazyGames/no-SDK nunca disparan ese evento, así que se
        // quedan siempre en este valor, igual que antes.
        //
        // ?debugBannerH=NN — SOLO para probar en localhost/navegador (donde no
        // hay SDK real y por tanto bannerAdSizeChanged nunca llega): fuerza el
        // alto reservado a NN px para poder ver, en devtools con un viewport de
        // tablet, cómo quedaría el layout con un banner adaptativo real de ese
        // alto. No tiene ningún efecto en la app empaquetada — ahí siempre llega
        // el evento real y lo sobreescribe. Mismo patrón que ?mode= en
        // shared/responsive.js.
        const _debugBannerH = new URLSearchParams(window.location.search).get('debugBannerH');
        document.documentElement.style.setProperty('--admob-banner-h', (_debugBannerH || '50') + 'px');
        _requestBannerNow(containerId);
        // Refrescar cada 35 s (requisito CrazyGames)
        clearInterval(_bannerInterval);
        _bannerInterval = setInterval(() => _requestBannerNow(containerId), 35000);
    }

    function hideBanner(containerId) {
        clearInterval(_bannerInterval);
        _bannerInterval = null;
        const el = document.getElementById(containerId);
        if (el) el.style.display = 'none';
        document.documentElement.style.setProperty('--admob-banner-h', '0px');
        if (window.GAME_MARKET === 'playgama') {
            try { window.bridge?.advertisement?.hideBanner?.(); } catch (e) {}
            return;
        }
        const b = _cgBanner();
        if (b) { b.clearBanner?.(containerId)?.catch?.(() => {}); return; }
        const adm = _adm();
        if (adm) adm.removeBanner().catch(() => {});
    }

    // ── Free-ad token pool (used for "ad-gated" shop items) ──────────────────
    // Persistido vía GameSave (no solo en memoria) — si no, recargar la página
    // restauraba _freeAdsLeft a 1 sin haber completado la compra de pago
    // requerida, permitiendo ver anuncios gratis en bucle (política de
    // CrazyGames: anuncio → pago → anuncio → …). La carga es perezosa (a la
    // primera llamada a cualquiera de estas 4 funciones) en vez de en init(),
    // porque shared/ads.js se carga ANTES que shared/save.js en index.html —
    // window.GameSave todavía no existiría si se leyera al analizar el módulo.
    let _freeAdsLoaded = false;
    function _loadFreeAdsState() {
        if (_freeAdsLoaded) return;
        _freeAdsLoaded = true;
        try {
            const raw = window.GameSave && window.GameSave.loadRaw('adsFreeUpgradeLeft');
            if (raw != null) _freeAdsLeft = Math.max(0, Math.min(1, Number(raw)));
        } catch (e) {}
    }
    function _saveFreeAdsState() {
        try { window.GameSave && window.GameSave.saveRaw('adsFreeUpgradeLeft', String(_freeAdsLeft)); } catch (e) {}
    }
    function hasFree()       { _loadFreeAdsState(); return _freeAdsLeft > 0; }
    function consume()       { _loadFreeAdsState(); _freeAdsLeft = Math.max(0, _freeAdsLeft - 1); _saveFreeAdsState(); }
    function replenishFree() { _loadFreeAdsState(); _freeAdsLeft = Math.min(1, _freeAdsLeft + 1); _saveFreeAdsState(); }
    function freeLeft()      { _loadFreeAdsState(); return _freeAdsLeft; }

    return { init, gameplayStart, gameplayStop, happyTime, request, requestMidgame, showBanner, hideBanner, saveScore, showLeaderboard, hasFree, consume, replenishFree, freeLeft, setMuted, showPrivacyOptions, privacyOptionsRequired, canRequestAds, onPrivacyOptionsChange, isRewardedReady };
})();
