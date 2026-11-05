// shared/audio.js — Audio infrastructure
// Exposes window.GameAudio. Loaded before script.js.

// Restaura la preferencia de mute guardada YA, en vez de arrancar siempre en
// false — shared/shell.js (_setupMuteBtn) también la restaura, pero lo hace
// más tarde (GameShell.init() se llama después del primer updateBGM() en
// script.js), así que sin esto la música arrancaba igual un instante en cada
// carga, ignorando que el jugador la había silenciado en una sesión anterior.
window.isMusicMuted  = (function () {
    try { return localStorage.getItem('chickenIdleMuted') === 'true'; } catch (e) { return false; }
})();
// Ajuste independiente del de arriba — separa "Música" (bgmTheme/bgmMenu,
// gestionado por _syncBGM() en scenarios/farm/script.js) de "Efectos"
// (todo lo que pasa por playSound()/playRestartSound() aquí abajo: cok,
// huevo, dinero, gallinas, etc.). Restaurado ya por el mismo motivo que
// isMusicMuted arriba (ver comentario): shared/shell.js también lo
// restaura, pero más tarde.
window.isSfxMuted = (function () {
    try { return localStorage.getItem('chickenIdleSfxMuted') === 'true'; } catch (e) { return false; }
})();
window.isBgmMuted    = false;
window.isAdPaused    = false;
window._cgMuteAudio  = false; // set by CrazyGames SDK muteAudio setting; takes priority over in-game toggle
window.androidAudioUnlocked = false;

window.GameAudio = (() => {
    // Los Audio() con src por defecto arrancan la descarga YA (preload="auto"),
    // aunque nadie los haya reproducido todavía. Con 34 sonidos (~20MB, uno de
    // 5.5MB) eso significaba descargar TODO el audio del juego antes de que el
    // jugador viera nada — 7s+ de pantalla negra en una conexión fría, mucho
    // más que el JS/CSS (que ya comprime con gzip). preload="none" difiere la
    // descarga de cada sonido hasta la primera vez que se llama a .play().
    function _mkAudio(src) {
        const a = new Audio(src);
        a.preload = 'none';
        return a;
    }
    const sfxCok        = _mkAudio('audio/cok.wav');
    const sfxEgg        = _mkAudio('audio/egg.wav');
    const sfxMoney      = _mkAudio('audio/money.mp3');
    const sfxDeathBirth = _mkAudio('audio/muerte-nacimiento.wav');
    const sfxDeath      = _mkAudio('audio/death.wav');
    const sfxLayEgg     = _mkAudio('audio/ponerhuevo.wav');
    // catpurring y theme eran WAV sin comprimir (5.3MB y 14MB) — pasados a .ogg
    // (60KB y 1.55MB, ~99% y ~89% más ligeros) sin pérdida audible perceptible.
    // Los .wav originales se dejan en audio/ sin usar por si hiciera falta volver atrás.
    //
    // .ogg -> .m4a (AAC): WebKit/Safari (y por tanto el WKWebView de la app de
    // iOS) nunca ha soportado Ogg Vorbis, ni en <audio> ni en decodeAudioData()
    // — así que estos 23 sonidos no sonaban en absoluto en iOS, sin ningún
    // error visible (el catch(e){return null} de _loadAudioBuffer() y el
    // .catch(()=>{}) del fallback <audio> se comen el fallo en silencio).
    // AAC sí está soportado de forma nativa en iOS y Android. Los .ogg
    // originales se dejan en audio/ sin usar, mismo criterio que arriba.
    const sfxCatPurr    = _mkAudio('audio/catpurring.m4a');
    sfxCatPurr.loop   = true;
    sfxCatPurr.volume = 1.0;
    const sfxPopBuy  = _mkAudio('audio/pop-buy.wav');
    const bgmTheme   = _mkAudio('audio/theme.m4a');
    bgmTheme.loop    = true;
    bgmTheme.volume  = 0.1;
    // Pista de "menú" — main menu, menú de pausa dentro de partida, y también
    // durante partida activa una vez comprada la mejora de radio (musicLevel
    // > 0). theme.ogg queda reservado a partida activa SIN la radio comprada.
    // Ver _syncBGM() en scenarios/farm/script.js, que decide cuál de las dos
    // suena en cada momento.
    const bgmMenu    = _mkAudio('audio/music_menu.m4a');
    bgmMenu.loop     = true;
    bgmMenu.volume   = 0.1;

    const sfxCok1 = _mkAudio('audio/cok1.wav');
    const sfxCok2 = _mkAudio('audio/cok2.wav');
    const sfxCok3 = _mkAudio('audio/cok3.wav');

    const sfxPio1 = _mkAudio('audio/pio1.wav');
    const sfxPio2 = _mkAudio('audio/pio2.wav');
    const sfxPio3 = _mkAudio('audio/pio3.wav');
    const sfxPio4 = _mkAudio('audio/pio4.wav');
    const sfxPio5 = _mkAudio('audio/pio5.wav');

    // V2 sounds — .ogg -> .m4a, ver comentario junto a sfxCatPurr más arriba.
    const sfxRefillWater   = _mkAudio('audio/v2/bebedero_rellenar.m4a');
    const sfxRefillFood    = _mkAudio('audio/v2/comedero_rellenar.m4a');
    const sfxChickenAngry  = _mkAudio('audio/v2/gallina_alterada.m4a');
    const sfxChickenWake   = _mkAudio('audio/v2/gallina_despierta.m4a');
    const sfxRoosterMate   = _mkAudio('audio/v2/gallo_aparear.m4a');
    const sfxRoosterMatePrev = _mkAudio('audio/v2/gallo_aparear_prev.m4a');
    const sfxRoosterCreate = _mkAudio('audio/v2/gallo_crear.m4a');
    const sfxRoosterWake   = _mkAudio('audio/v2/gallo_despierta.m4a');
    const sfxRoosterFight  = _mkAudio('audio/v2/gallo_fight.m4a');
    const sfxMachineCreate = _mkAudio('audio/v2/maquina_crear.m4a');
    const sfxStamp1        = _mkAudio('audio/v2/maquina_selladora_sello_1.m4a');
    const sfxStamp2        = _mkAudio('audio/v2/maquina_selladora_sello_2.m4a');
    const sfxChickAngry    = _mkAudio('audio/v2/pollito_alterado.m4a');
    const sfxChickWake     = _mkAudio('audio/v2/pollito_despierta.m4a');
    const sfxChickBorn     = _mkAudio('audio/v2/pollito_nacer.m4a');
    const sfxPress         = _mkAudio('audio/v2/press.m4a');
    const sfxRelease       = _mkAudio('audio/v2/release.m4a');
    const sfxLogoFall      = _mkAudio('audio/v2/logo_fall.m4a');
    const sfxLogoDown      = _mkAudio('audio/v2/logo_down.m4a');
    const sfxLogoHit       = _mkAudio('audio/v2/logo_hit.m4a');

    let _lastSoundTimes = {};
    let _activeVoices   = {};
    let _chickenCount   = 0;

    let _audioCtx = null;
    let _gestureReceived = false;
    const _audioBufferCache = {};

    function _getAudioCtx() {
        if (!_gestureReceived) return null;
        if (!_audioCtx) _audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        else if (_audioCtx.state === 'suspended') _audioCtx.resume().catch(() => {});
        return _audioCtx;
    }

    async function _loadAudioBuffer(src) {
        if (_audioBufferCache[src]) return _audioBufferCache[src];
        if (window.location.protocol === 'file:') return null;
        try {
            const ctx = _getAudioCtx();
            if (!ctx) return null;
            const response  = await fetch(src);
            const arrayBuffer = await response.arrayBuffer();
            const buffer    = await ctx.decodeAudioData(arrayBuffer);
            _audioBufferCache[src] = buffer;
            return buffer;
        } catch(e) {
            return null;
        }
    }

    const _allAudioSrcs = [
        'audio/cok.wav','audio/cok1.wav','audio/cok2.wav','audio/cok3.wav',
        'audio/pio1.wav','audio/pio2.wav','audio/pio3.wav','audio/pio4.wav','audio/pio5.wav',
        'audio/egg.wav','audio/money.mp3','audio/muerte-nacimiento.wav',
        'audio/death.wav','audio/ponerhuevo.wav','audio/catpurring.m4a',
        'audio/pop-buy.wav',
        'audio/v2/bebedero_rellenar.m4a','audio/v2/comedero_rellenar.m4a',
        'audio/v2/gallina_alterada.m4a','audio/v2/gallina_despierta.m4a',
        'audio/v2/gallo_aparear.m4a','audio/v2/gallo_aparear_prev.m4a',
        'audio/v2/gallo_crear.m4a','audio/v2/gallo_despierta.m4a',
        'audio/v2/gallo_fight.m4a','audio/v2/maquina_crear.m4a',
        'audio/v2/maquina_selladora_sello_1.m4a','audio/v2/maquina_selladora_sello_2.m4a',
        'audio/v2/pollito_alterado.m4a','audio/v2/pollito_despierta.m4a',
        'audio/v2/pollito_nacer.m4a','audio/v2/press.m4a','audio/v2/release.m4a',
        'audio/v2/logo_fall.m4a','audio/v2/logo_down.m4a','audio/v2/logo_hit.m4a',
    ];

    // Desbloquear AudioContext en el primer gesto del usuario y precargar buffers
    function _unlockAndPreload() {
        _gestureReceived = true;
        if (_audioCtx) {
            if (_audioCtx.state === 'suspended') _audioCtx.resume().catch(() => {});
        } else {
            _audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
        // Reproducir un buffer SILENCIOSO (1 muestra) por el contexto.
        //
        // En iOS no basta con resume(): mientras no sale audio de verdad por el
        // grafo, la sesión de audio del sistema no llega a activarse y Web Audio
        // queda mudo aunque el contexto diga "running". Cuando la música suena,
        // el elemento <audio> activa esa sesión por su cuenta y no se nota — por
        // eso el síntoma era "silencio la música desde Ajustes, reinicio, y los
        // EFECTOS tampoco se oyen" (solo en iOS; no hay ninguna ruta en JS que
        // ligue isMusicMuted con los efectos, playSound() solo mira isSfxMuted).
        //
        // Este truco ya existía en scenarios/farm/script.js (el listener de
        // touchstart), pero está desactivado en Capacitor nativo por un problema
        // de ANDROID: aquel bloque llamaba además a .load() sobre TODOS los
        // <audio>, lo que abortaba la música que ya estuviera sonando. Aquí se
        // recupera solo la parte útil, sin ese .load().
        try {
            const _s = _audioCtx.createBufferSource();
            _s.buffer = _audioCtx.createBuffer(1, 1, 22050);
            _s.connect(_audioCtx.destination);
            _s.start(0);
        } catch (e) { }
        _allAudioSrcs.forEach(src => _loadAudioBuffer(src));
    }
    ['click', 'keydown', 'touchstart', 'pointerdown'].forEach(evt =>
        document.addEventListener(evt, function _unlock() {
            _unlockAndPreload();
            ['click', 'keydown', 'touchstart', 'pointerdown'].forEach(e =>
                document.removeEventListener(e, _unlock));
        }, { once: false })
    );

    // Intento inmediato al arrancar — mismo motivo que el arranque directo de
    // la música (ver GameSave.initAndLoad en script.js): Capacitor desactiva
    // la restricción nativa de "requiere gesto" en Android
    // (setMediaPlaybackRequiresUserGesture(false), Bridge.java), así que
    // AudioContext puede arrancar ya resuelto sin esperar a los listeners de
    // arriba. En plataformas donde el navegador SÍ lo bloquea, esto no
    // rompe nada: el contexto se queda "suspended" (como ya pasaba) y
    // playSound() lo detecta y no reproduce hasta el primer gesto real, que
    // sigue funcionando exactamente igual que antes gracias a los listeners.
    _unlockAndPreload();

    function playSound(audioObj, vol = 1.0, baseThrottleMs = 50, rndPitch = false) {
        if (!audioObj) return;
        if (document.hidden) return;
        if (window.isSfxMuted || window._cgMuteAudio) return;

        let key = audioObj.src || (audioObj instanceof HTMLAudioElement ? audioObj.src : '');
        let now = Date.now();

        let isPassive = key.includes('cok') || key.includes('egg') || key.includes('huevo') || key.includes('nacimiento') || key.includes('death') || key.includes('money');

        if (isPassive) {
            if (!_activeVoices[key]) _activeVoices[key] = 0;
            if (_activeVoices[key] >= 4) return;
        }

        let chickenCount = _chickenCount || 1;
        let throttleMs   = baseThrottleMs;
        if (isPassive && chickenCount > 10) {
            throttleMs = baseThrottleMs * (1 + (chickenCount / 30));
        }
        if (_lastSoundTimes[key] && now - _lastSoundTimes[key] < throttleMs) return;
        _lastSoundTimes[key] = now;

        let finalVol = vol;
        if (isPassive && chickenCount > 20) {
            finalVol = vol / Math.pow(1 + (chickenCount / 100), 1.5);
        }
        finalVol = Math.max(0.01, Math.min(1.0, finalVol));

        let relSrc = key;
        try { relSrc = new URL(key).pathname.replace(/^\//, ''); } catch(e) {}
        relSrc = relSrc.replace(/^.*\/audio\//, 'audio/');

        if (isPassive) _activeVoices[key] = (_activeVoices[key] || 0) + 1;

        const _ctx = _getAudioCtx();
        if (!_ctx) return;
        if (_ctx.state === 'suspended') { _ctx.resume().catch(() => {}); return; }

        _loadAudioBuffer(relSrc).then(buffer => {
            if (!buffer) {
                if (isPassive) _activeVoices[key] = Math.max(0, (_activeVoices[key] || 1) - 1);
                let clone = audioObj.cloneNode();
                clone.volume = finalVol;
                clone.play().catch(() => {});
                return;
            }
            const source = _ctx.createBufferSource();
            source.buffer = buffer;
            if (rndPitch) source.playbackRate.value = 0.8 + Math.random() * 0.6;

            const gainNode = _ctx.createGain();
            gainNode.gain.value = finalVol;
            source.connect(gainNode);
            gainNode.connect(_ctx.destination);
            source.start(0);

            if (isPassive) {
                source.onended = () => {
                    _activeVoices[key] = Math.max(0, (_activeVoices[key] || 1) - 1);
                };
            }
        }).catch(() => {
            if (isPassive) _activeVoices[key] = Math.max(0, (_activeVoices[key] || 1) - 1);
        });
    }

    // Play a sound restarting from the beginning if already playing (no overlap)
    const _restartNodes = {};
    const _cancelledSrcs = {};
    function _relSrcOf(audioObj) {
        let key = audioObj.src || '';
        let relSrc = key;
        try { relSrc = new URL(key).pathname.replace(/^\//, ''); } catch(e) {}
        return relSrc.replace(/^.*\/audio\//, 'audio/');
    }
    function playRestartSound(audioObj, vol) {
        if (!audioObj || document.hidden || window.isSfxMuted || window._cgMuteAudio) return;
        const ctx = _getAudioCtx();
        if (!ctx || ctx.state === 'suspended') { ctx && ctx.resume().catch(() => {}); return; }
        const relSrc = _relSrcOf(audioObj);
        _cancelledSrcs[relSrc] = false;
        if (_restartNodes[relSrc]) {
            try { _restartNodes[relSrc].stop(); } catch(e) {}
            _restartNodes[relSrc] = null;
        }
        const finalVol = Math.max(0.01, Math.min(1, vol || 1));
        _loadAudioBuffer(relSrc).then(buffer => {
            // Puede haberse pedido stopSound() mientras el buffer aún cargaba
            // (async) — sin esto, el sonido arrancaba igual justo después de
            // cortarlo (p.ej. al pulsar SKIP muy pronto en la intro).
            if (_cancelledSrcs[relSrc]) return;
            if (!buffer) {
                audioObj.pause(); audioObj.currentTime = 0; audioObj.volume = finalVol;
                audioObj.play().catch(() => {}); return;
            }
            const ctx2 = _getAudioCtx();
            if (!ctx2) return;
            const source = ctx2.createBufferSource();
            source.buffer = buffer;
            const gain = ctx2.createGain();
            gain.gain.value = finalVol;
            source.connect(gain);
            gain.connect(ctx2.destination);
            source.start(0);
            source.onended = () => { if (_restartNodes[relSrc] === source) _restartNodes[relSrc] = null; };
            _restartNodes[relSrc] = source;
        }).catch(() => {});
    }

    // Corta un sonido lanzado con playRestartSound (o su fallback <audio>),
    // esté ya sonando o todavía cargando el buffer (async).
    function stopSound(audioObj) {
        if (!audioObj) return;
        const relSrc = _relSrcOf(audioObj);
        _cancelledSrcs[relSrc] = true;
        if (_restartNodes[relSrc]) {
            try { _restartNodes[relSrc].stop(); } catch(e) {}
            _restartNodes[relSrc] = null;
        }
        try { audioObj.pause(); audioObj.currentTime = 0; } catch(e) {}
    }

    // ── Ronroneo del gato ───────────────────────────────────────────────────
    // Caso especial: es el único sonido en bucle CONTINUO cuyo volumen varía en
    // tiempo real (sube al acariciar, decae solo — ver scenarios/farm/script.js).
    //
    // Antes era un <audio loop> al que se le escribía .volume directamente. Eso
    // funciona en escritorio y Android, pero en iOS/WebKit la propiedad .volume
    // de un HTMLAudioElement es de SOLO LECTURA (Apple reserva el volumen al
    // usuario y a los botones físicos): la asignación se ignora en silencio. Como
    // el elemento tiene loop=true y no se pausa nunca, el resultado en iOS era el
    // ronroneo sonando eternamente a volumen 1.0 tras acariciar al gato una vez.
    //
    // Con Web Audio el volumen vive en un GainNode del grafo, que sí es
    // controlable en iOS. Se arranca de forma perezosa (la primera vez que se
    // pide volumen > 0) y no hace falta pre-arrancarlo mudo: el buffer ya está
    // en caché por _unlockAndPreload(), así que no hay latencia audible.
    let _purrSource = null, _purrGain = null, _purrStarting = false, _purrFallback = false;
    let _purrVol = 0;

    function setCatPurrVolume(vol) {
        _purrVol = Math.max(0, Math.min(1, vol || 0));
        if (_purrGain) { _purrGain.gain.value = _purrVol; return; }
        // Sin Web Audio disponible (p.ej. file://): se degrada al <audio> de
        // siempre. En iOS esto no funcionaría, pero ahí el buffer sí carga, así
        // que este camino no se toma.
        if (_purrFallback) { sfxCatPurr.volume = _purrVol; return; }
        if (_purrVol <= 0 || _purrStarting) return;
        const ctx = _getAudioCtx();
        if (!ctx || ctx.state === 'suspended') return;
        _purrStarting = true;
        _loadAudioBuffer(_relSrcOf(sfxCatPurr)).then(buffer => {
            _purrStarting = false;
            if (!buffer) {
                _purrFallback = true;
                sfxCatPurr.volume = _purrVol;
                sfxCatPurr.play().catch(() => {});
                return;
            }
            const c = _getAudioCtx();
            if (!c) return;
            const src = c.createBufferSource();
            src.buffer = buffer;
            src.loop = true;
            const gain = c.createGain();
            gain.gain.value = _purrVol;
            src.connect(gain);
            gain.connect(c.destination);
            src.start(0);
            _purrSource = src;
            _purrGain = gain;
        }).catch(() => { _purrStarting = false; });
    }

    const _randomCokSounds = [sfxCok1, sfxCok2, sfxCok3];
    function playRandomCok() {
        playSound(_randomCokSounds[Math.floor(Math.random() * _randomCokSounds.length)], 0.15, 100);
    }

    const _pioSounds = [sfxPio1, sfxPio2, sfxPio3, sfxPio4, sfxPio5];
    let _pioPerSecCount = 0;
    let _pioSecTimer = 0;
    function playChickSound() {
        if (_pioPerSecCount >= 5) return;
        _pioPerSecCount++;
        playSound(_pioSounds[Math.floor(Math.random() * _pioSounds.length)], 0.12, 80, true);
    }
    function tickPioRateLimit(dt) {
        _pioSecTimer += dt;
        if (_pioSecTimer >= 1) { _pioSecTimer -= 1; _pioPerSecCount = 0; }
    }

    const _allAudioObjects = [
        sfxCok, sfxEgg, sfxMoney, sfxDeathBirth, sfxDeath, sfxLayEgg,
        sfxCatPurr, sfxPopBuy, sfxCok1, sfxCok2, sfxCok3, bgmTheme, bgmMenu,
        sfxPio1, sfxPio2, sfxPio3, sfxPio4, sfxPio5,
        sfxRefillWater, sfxRefillFood,
        sfxChickenAngry, sfxChickenWake,
        sfxRoosterMate, sfxRoosterMatePrev, sfxRoosterCreate, sfxRoosterWake, sfxRoosterFight,
        sfxMachineCreate, sfxStamp1, sfxStamp2,
        sfxChickAngry, sfxChickWake, sfxChickBorn,
        sfxPress, sfxRelease, sfxLogoFall, sfxLogoDown, sfxLogoHit,
    ];

    // La mejora de tienda "Farm Music" (state.musicLevel) SOLO sube el volumen
    // de la música que ya suena — pedido explícito, antes (antes de esta
    // función) el nivel decidía si sonaba o no, lo cual dejaba la música muda
    // sin comprar la mejora pese a sonar ya libremente en el main menu.
    // Base 0.1 (nivel 0) hasta 0.3 (nivel 10+) — se cubre con Math.min porque
    // en el reto Endless musicLevel no tiene tope de 10 (puede seguir subiendo).
    function bgmVolumeFor(musicLevel) {
        return 0.1 + Math.min(musicLevel || 0, 10) * 0.02;
    }

    // Solo lleva la cuenta de gallinas para otros usos de audio (pitch/volumen
    // de sonidos) — YA NO decide qué pista de fondo suena. Eso lo centraliza
    // _syncBGM() en scenarios/farm/script.js (bgmTheme vs bgmMenu según
    // contexto), que se llama en paralelo desde los mismos sitios que llaman
    // a este updateBGM(). Mantenerlo así evita que dos funciones distintas
    // manden a la vez sobre play()/pause() de los <audio>.
    function updateBGM(_musicLevel, chickenCount) {
        _chickenCount = (chickenCount || 0);
    }

    // Silenciar todo cuando la app va al background (minimizar, bloquear pantalla)
    function _onHide() {
        bgmTheme.pause();
        bgmMenu.pause();
        if (_audioCtx && _audioCtx.state === 'running') _audioCtx.suspend().catch(() => {});
    }
    function _onShow() {
        if (_audioCtx && _audioCtx.state === 'suspended') _audioCtx.resume().catch(() => {});
        // El estado del BGM lo restaura _syncBGM() desde el game loop
    }
    document.addEventListener('visibilitychange', () => {
        document.hidden ? _onHide() : _onShow();
    });
    // Capacitor también dispara estos eventos en Android
    document.addEventListener('pause', _onHide);
    document.addEventListener('resume', _onShow);

    return {
        sfxCok, sfxEgg, sfxMoney, sfxDeathBirth, sfxDeath, sfxLayEgg,
        sfxCatPurr, sfxPopBuy, sfxCok1, sfxCok2, sfxCok3, bgmTheme, bgmMenu,
        sfxRefillWater, sfxRefillFood,
        sfxChickenAngry, sfxChickenWake,
        sfxRoosterMate, sfxRoosterMatePrev, sfxRoosterCreate, sfxRoosterWake, sfxRoosterFight,
        sfxMachineCreate, sfxStamp1, sfxStamp2,
        sfxChickAngry, sfxChickWake, sfxChickBorn,
        sfxPress, sfxRelease, sfxLogoFall, sfxLogoDown, sfxLogoHit,
        _allAudioObjects,
        setChickenCount(n) { _chickenCount = n || 0; },
        updateBGM,
        bgmVolumeFor,
        playSound,
        playRestartSound,
        stopSound,
        setCatPurrVolume,
        playRandomCok,
        playChickSound,
        tickPioRateLimit,
    };
})();
