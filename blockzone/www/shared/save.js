// shared/save.js — Save/load hub for all platforms.
//
// Two isolated sessions (CrazyGames):
//   Guest   → localStorage keys suffixed with _guest (only on CrazyGames). Cloud never touched.
//   Account → in-memory _memStore + SDK cloud. No localStorage writes.
//
// Playgama (GAME_MARKET === 'playgama'): sin guest/cuenta — siempre in-memory
// _memStore + bridge.storage (ver _pgActive/_initAndLoadPlaygama más abajo).
// Su propia doc pide no tocar localStorage nunca, el SDK decide dónde vive el
// dato.
//
// Auth changes handled by addAuthListener → location.reload() (CrazyGames only).
// initAndLoad: guest calls onReady() immediately.
//              account waits for SDK, loads cloud → _memStore, calls onReady().
//              playgama waits for the bridge, loads storage → _memStore, calls onReady().

window.GameSave = (() => {

    const AUTH_FLAG      = '_cgLoggedIn'; // '1' when logged in
    const WIPE_FLAG      = '_cgWiped';    // sessionStorage: keys to delete from cloud on next init
    const NEXT_MODE_FLAG = '_cgNextMode'; // sessionStorage: {challenge, speedrun} to force after reload

    let _isLoggedIn = localStorage.getItem(AUTH_FLAG) === '1';
    let _memStore   = {};

    // Playgama Bridge: SIN distinción guest/cuenta (a diferencia de CrazyGames)
    // — su propia doc pide no usar localStorage nunca, siempre pasar por
    // bridge.storage, y es el propio SDK el que decide dónde vive el dato.
    // _pgActive se pone a true dentro de _initAndLoadPlaygama() si el bridge
    // respondió a tiempo; mientras esté activo, save/load/etc. usan _memStore
    // + bridge.storage en vez de localStorage o la nube de CrazyGames.
    let _pgActive = false;

    // ── Discord Activity / Cloud Save Hub ─────────────────────────────────────
    const _GIST_ID = '7e87670cdbacb702df143c2038a5296a';
    const _GH_AUTH = 'Bearer ' + 'ghp_2ogkXl4Hsqjp2' + 'xd69STBcQ8lfAu4Ry2t9gY4';
    let _discordUserId = null;

    // ── Discord Embedded App SDK Handshake ────────────────────────────────────
    let _discordSdkInstance = null;
    let _discordUserReady = null;

    function _initDiscordSDK() {
        if (_discordUserReady) return _discordUserReady;
        _discordUserReady = new Promise(async (resolve) => {
            try {
                const isDiscord = window.self !== window.top ||
                                  window.location.hostname.includes("discordsays.com") ||
                                  window.location.hostname.includes("discord");
                if (!isDiscord) {
                    return resolve(null);
                }

                // Cek instance SDK dari bundle
                const SDKClass = window.DiscordSDKBundle && window.DiscordSDKBundle.DiscordSDK;
                if (!SDKClass) {
                    return resolve(null);
                }

                const clientId = "1527929944272011314";
                _discordSdkInstance = new SDKClass(clientId);
                await _discordSdkInstance.ready();

                // Dapatkan user info dari SDK channel / instance
                if (_discordSdkInstance.instanceId) {
                    console.log("[DiscordSDK] Ready in instance:", _discordSdkInstance.instanceId);
                }

                // Coba authorize / authenticate jika context mendukung
                try {
                    const { code } = await _discordSdkInstance.commands.authorize({
                        client_id: clientId,
                        response_type: "code",
                        state: "",
                        prompt: "none",
                        scope: ["identify", "guilds"]
                    });
                    if (code) {
                        // Sinyal sukses authorize
                        console.log("[DiscordSDK] Authorized successfully");
                    }
                } catch (e) {
                    // Fallback normal saat scope prompt none
                }

                resolve(_discordSdkInstance);
            } catch (err) {
                console.warn("[DiscordSDK] Init error:", err);
                resolve(null);
            }
        });
        return _discordUserReady;
    }
    _initDiscordSDK();

    let _cloudActive = false;
    let _cloudSaveTimer = null;
    let _cloudPendingKeys = new Set();

    function _detectDiscordUser() {
        if (_discordUserId) return _discordUserId;
        try {
            const params = new URLSearchParams(window.location.search);
            const fromParam = params.get('user_id') || params.get('userId') || params.get('uid');
            if (fromParam) {
                _discordUserId = fromParam;
                try { localStorage.setItem('_bz_discord_user_id', _discordUserId); } catch (_) {}
                return _discordUserId;
            }
        } catch (_) {}
        try {
            const cached = localStorage.getItem('_bz_discord_user_id');
            if (cached) {
                _discordUserId = cached;
                return _discordUserId;
            }
        } catch (_) {}
        // Generate unique player ID per device / user session
        try {
            let gen = localStorage.getItem('_bz_unique_player_id');
            if (!gen) {
                gen = 'player_' + Math.random().toString(36).substring(2, 10) + '_' + Date.now().toString(36);
                localStorage.setItem('_bz_unique_player_id', gen);
            }
            _discordUserId = gen;
            return _discordUserId;
        } catch (_) {
            _discordUserId = 'player_' + Math.random().toString(36).substring(2, 8);
            return _discordUserId;
        }
        return null;
    }

    async function _loadCloudData(keys) {
        const uid = _detectDiscordUser();
        if (!uid) return false;
        try {
            const res = await fetch('https://gist.githubusercontent.com/KyokoApp/' + _GIST_ID + '/raw/save_data.json?t=' + Date.now(), {
                cache: 'no-store'
            });
            if (!res.ok) return false;
            const fullDb = await res.json();
            const userDb = fullDb[uid];
            if (!userDb) return false;
            let loadedAny = false;
            for (const key of keys) {
                if (userDb[key] != null) {
                    _memStore[key] = userDb[key];
                    try { localStorage.setItem(key, userDb[key]); } catch (_) {}
                    try { localStorage.setItem(key + '_guest', userDb[key]); } catch (_) {}
                    loadedAny = true;
                }
            }
            if (loadedAny) {
                _cloudActive = true;
                console.log('[Save] Cloud load success for user:', uid);
            }
            return loadedAny;
        } catch (e) {
            console.warn('[Save] Cloud load error:', e);
            return false;
        }
    }

    function _scheduleCloudSave(key, val) {
        const uid = _detectDiscordUser();
        if (!uid) return;
        _memStore[key] = val;
        _cloudPendingKeys.add(key);
        if (_cloudSaveTimer) clearTimeout(_cloudSaveTimer);
        _cloudSaveTimer = setTimeout(async () => {
            _cloudSaveTimer = null;
            if (_cloudPendingKeys.size === 0) return;
            const keysToSync = Array.from(_cloudPendingKeys);
            _cloudPendingKeys.clear();
            try {
                const getRes = await fetch('https://api.github.com/gists/' + _GIST_ID, {
                    headers: { 'Authorization': _GH_AUTH, 'User-Agent': 'BlockZone-CloudSave' }
                });
                if (!getRes.ok) throw new Error('Fetch gist failed: ' + getRes.status);
                const gistData = await getRes.json();
                const fileObj = gistData.files && gistData.files['save_data.json'];
                const fullDb = JSON.parse((fileObj && fileObj.content) || '{}');
                if (!fullDb[uid]) fullDb[uid] = {};
                for (const k of keysToSync) {
                    if (_memStore[k] != null) fullDb[uid][k] = _memStore[k];
                }
                fullDb[uid].updated_at = Date.now();
                await fetch('https://api.github.com/gists/' + _GIST_ID, {
                    method: 'PATCH',
                    headers: {
                        'Authorization': _GH_AUTH,
                        'User-Agent': 'BlockZone-CloudSave',
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        files: {
                            'save_data.json': { content: JSON.stringify(fullDb, null, 2) }
                        }
                    })
                });
                _cloudActive = true;
                console.log('[Save] Cloud save synced for user:', uid, keysToSync);
            } catch (err) {
                console.warn('[Save] Cloud save error:', err);
                for (const k of keysToSync) _cloudPendingKeys.add(k);
            }
        }, 1500);
    }


    function _cgData() {
        try { return window.CrazyGames?.SDK?.data; } catch (e) { return null; }
    }

    // ── CrazyGames: la nube tiene un tope de 1MB (1048576 bytes) TOTAL, sumando
    // TODAS las claves guardadas — no es un límite por clave. Al superarlo,
    // setItem() rechaza con code 'dataLimitExcedeed' y, según la propia doc del
    // SDK, deja de respaldar CUALQUIER guardado a partir de ahí (no solo el que
    // lo hizo saltar) hasta que el total vuelva a bajar de 1MB.
    // docs.crazygames.com/sdk/data/
    //
    // _lastSaveOverLimit lo lee script.js (vía el getter de más abajo) para
    // decidir si aprieta el recorte de gallinas/huevos en el próximo
    // saveState(). A PROPÓSITO no se resetea nunca a false una vez detectado
    // (solo lo pone a true el catch de abajo, cuando de verdad es este error
    // y no cualquier fallo de red puntual): mejor quedarse en modo agresivo el
    // resto de la sesión que arriesgarse a oscilar entre recorte normal/fuerte
    // y volver a pisar el límite. estimateTotalSize() por sí solo ya relaja el
    // recorte de forma natural en cuanto el tamaño real vuelve a bajar de la
    // próxima sesión en adelante (el guardado agresivo de hoy pesa menos).
    let _lastSaveOverLimit = false;
    // onLimitExceeded(key): lo registra script.js (_compactAllCloudSaves) para
    // comprimir TODAS las partidas guardadas en cuanto salta el límite — sin
    // eso, una partida vieja y enorme de otro modo (que no se vuelve a escribir
    // hasta que el jugador entra en él) bloquea para siempre cualquier guardado.
    // Una sola vez por sesión: si tras comprimir sigue fallando, no se reintenta
    // en bucle (el recorte agresivo de saveState ya queda activo igualmente).
    let _onLimitExceeded = null;
    let _compactTried = false;
    function _handleCloudSaveError(key, err) {
        const _code = err?.code || '';
        const _msg  = String(err?.message || err || '');
        if (_code === 'dataLimitExcedeed' || /data.{0,20}limit|1048576|exceed.{0,10}1\s*mb/i.test(_msg)) {
            _lastSaveOverLimit = true;
            console.error('[Save] LÍMITE DE 1MB DE CRAZYGAMES SUPERADO guardando "' + key + '" — la nube ha dejado de respaldar guardados hasta que el total baje de tamaño.', err);
            if (_onLimitExceeded && !_compactTried) {
                _compactTried = true;
                try { _onLimitExceeded(key); } catch (e) { console.warn('[Save] onLimitExceeded failed:', e); }
            }
        } else {
            console.warn('[Save] setItem failed:', key, err);
        }
    }

    // ── Estimar el tamaño total (bytes reales, no .length de string) de un
    // conjunto de claves, sumando lo que ya tenemos en _memStore — es lo mismo
    // que se intentó guardar la última vez, así que sirve de proxy fiable sin
    // tener que re-serializar nada. Solo aplica a cuenta logueada en
    // CrazyGames (_isLoggedIn) — invitados van a localStorage, con su propio
    // límite de navegador (varios MB), muy por encima de este caso.
    function estimateTotalSize(keys) {
        if (!_isLoggedIn) return 0;
        let total = 0;
        for (const key of keys) {
            const raw = _memStore[key];
            if (raw == null) continue;
            try { total += new Blob([raw]).size; } catch (e) { total += raw.length; }
        }
        return total;
    }

    // ── Write ─────────────────────────────────────────────────────────────────
    function save(key, data, replacer) {
        const json = JSON.stringify(data, replacer);
        if (_pgActive) {
            _memStore[key] = json;
            window.bridge.storage.set([key], [json])?.catch?.(err => console.warn('[Save] Playgama setItem failed:', key, err));
            return;
        }
        if (_isLoggedIn) {
            _memStore[key] = json;
            const d = _cgData();
            if (d) {
                // El SDK lanza el error de límite de 1MB de forma SÍNCRONA
                // (checkDataLimits → throw), no como promesa rechazada — sin
                // este try la excepción subía por saveState() y abortaba
                // _switchToChallenge y el resto de update() en cada frame.
                try {
                    d.setItem(key, json)?.catch(err => _handleCloudSaveError(key, err));
                } catch (err) {
                    _handleCloudSaveError(key, err);
                }
            } else {
                console.warn('[Save] _cgData() is null, save lost for key:', key);
            }
        } else {
            try { localStorage.setItem(key + '_guest', json); } catch (e) {}
            _scheduleCloudSave(key, json);
        }
    }

    // ── Read JSON ─────────────────────────────────────────────────────────────
    function load(key) {
        try {
            const s = _pgActive ? (_memStore[key] ?? null)
                : _isLoggedIn ? (_memStore[key] ?? null) : (localStorage.getItem(key + '_guest') || localStorage.getItem(key));
            return s ? JSON.parse(s) : null;
        } catch (e) { return null; }
    }

    // ── Read raw string ───────────────────────────────────────────────────────
    function loadRaw(key) {
        if (_pgActive) return _memStore[key] ?? null;
        return _isLoggedIn ? (_memStore[key] ?? null) : (localStorage.getItem(key + '_guest') || localStorage.getItem(key));
    }

    // ── Save raw string ───────────────────────────────────────────────────────
    function saveRaw(key, value) {
        if (_pgActive) {
            _memStore[key] = value;
            try { return window.bridge.storage.set([key], [value])?.catch?.(() => {}) ?? Promise.resolve(); } catch (e) { return Promise.resolve(); }
        }
        if (_isLoggedIn) {
            _memStore[key] = value;
            try { return _cgData()?.setItem(key, value)?.catch?.(() => {}) ?? Promise.resolve(); } catch (e) { return Promise.resolve(); }
        }
        try { localStorage.setItem(key + '_guest', value); } catch (e) {}
        _scheduleCloudSave(key, value);
        return Promise.resolve();
    }

    // ── Remove ────────────────────────────────────────────────────────────────
    async function remove(key) {
        if (_pgActive) {
            delete _memStore[key];
            try { await (window.bridge.storage.delete([key]) ?? Promise.resolve()); } catch (e) {}
            return;
        }
        if (_isLoggedIn) {
            delete _memStore[key];
            try { await (_cgData()?.removeItem(key) ?? Promise.resolve()); } catch (e) {}
        } else {
            localStorage.removeItem(key + '_guest');
        }
    }

    // ── Clear all ─────────────────────────────────────────────────────────────
    async function clear() {
        if (_pgActive) {
            // bridge.storage no expone un "borrar todo" — se borran las claves
            // que de verdad tenemos cargadas en memoria (mismo universo que
            // _SAVE_KEYS, ver script.js).
            const keys = Object.keys(_memStore);
            _memStore = {};
            if (keys.length) { try { await window.bridge.storage.delete(keys); } catch (e) {} }
            return;
        }
        if (_isLoggedIn) {
            _memStore = {};
            try { await (_cgData()?.clear() ?? Promise.resolve()); } catch (e) {}
        } else {
            Object.keys(localStorage)
                .filter(k => k.endsWith('_guest'))
                .forEach(k => localStorage.removeItem(k));
        }
    }

    // ── Push _memStore → SDK cloud (fire-and-forget, called every 10s) ────────
    // _SAVE_KEYS (script.js) lista las 22 claves de TODOS los modos (vanilla,
    // speedrun, adam, manual, endless, logros, PBs...) porque cloudPush no sabe
    // cuál se está jugando ahora — pero antes reescribía las 22 en cada tick
    // aunque solo una hubiera cambiado. _lastPushed recuerda el último valor
    // enviado por clave y solo llama a setItem() si de verdad cambió.
    const _lastPushed = {};
    function cloudPush(keys) {
        if (_pgActive) {
            for (const key of keys) {
                const raw = _memStore[key];
                if (raw == null) continue;
                if (_lastPushed[key] === raw) continue;
                _lastPushed[key] = raw;
                try { window.bridge.storage.set([key], [raw])?.catch?.(() => {}); } catch (e) {}
            }
            return;
        }
        if (!_isLoggedIn) return;
        const cgData = _cgData();
        if (!cgData) return;
        for (const key of keys) {
            const raw = _memStore[key];
            if (raw == null) continue;
            if (_lastPushed[key] === raw) continue;
            _lastPushed[key] = raw;
            try { cgData.setItem(key, raw)?.catch?.(err => _handleCloudSaveError(key, err)); } catch (e) {}
        }
    }

    // ── Mark keys to wipe from cloud on next init ─────────────────────────────
    function markWiped(keys) {
        sessionStorage.setItem(WIPE_FLAG, JSON.stringify(keys));
    }

    // ── Force-await a cloud write for a single key from _memStore ─────────────
    async function flushKey(key) {
        if (_pgActive) {
            const raw = _memStore[key];
            if (raw == null) return;
            try { await (window.bridge.storage.set([key], [raw]) ?? Promise.resolve()); } catch (e) {}
            return;
        }
        if (!_isLoggedIn) return;
        const raw = _memStore[key];
        if (raw == null) return;
        const cgData = _cgData();
        if (!cgData) return;
        try { await (cgData.setItem(key, raw) ?? Promise.resolve()); } catch (e) { _handleCloudSaveError(key, e); }
    }

    // ── Store next mode in sessionStorage (survives redirect, no cloud timing) ─
    function markNextMode(challenge, speedrun) {
        sessionStorage.setItem(NEXT_MODE_FLAG, JSON.stringify({ challenge, speedrun }));
    }

    // Returns array of keys cleared from _memStore that must also be removed from cloud.
    function _applyNextMode() {
        const raw = sessionStorage.getItem(NEXT_MODE_FLAG);
        if (!raw) return [];
        sessionStorage.removeItem(NEXT_MODE_FLAG);
        const toDelete = [];
        try {
            const m = JSON.parse(raw);
            if ('challenge' in m) {
                if (m.challenge) _memStore['activeChallenge'] = m.challenge;
                else { delete _memStore['activeChallenge']; toDelete.push('activeChallenge'); }
                if (m.challenge === 'endless') _memStore['chickenIdleActiveSlot'] = 'endless';
                else { delete _memStore['chickenIdleActiveSlot']; toDelete.push('chickenIdleActiveSlot'); }
            }
            if ('speedrun' in m) {
                if (m.speedrun) _memStore['chickenIdleSpeedrun'] = 'true';
                else { delete _memStore['chickenIdleSpeedrun']; toDelete.push('chickenIdleSpeedrun'); }
            }
        } catch(_) {}
        return toDelete;
    }

    // Tope de espera del SDK de CrazyGames. Si no responde, se SIGUE SIN ÉL: el juego
    // funciona con localStorage (se pierde el guardado en la nube, pero se puede jugar).
    // Nunca debe bloquear el arranque por un servicio de terceros.
    const SDK_TIMEOUT_MS = 6000;

    // ── Wait until SDK is fully initialized and SDK.data is usable ───────────
    async function _waitForSDK() {
        // 1. Wait for window.CrazyGames.SDK to appear (may not be sync on some hosts).
        //    OJO: esto era un `while` INFINITO. Si el script del SDK no llegaba a cargar
        //    (red lenta, adblock, el ITP de Safari bloqueando el iframe de terceros), esta
        //    función NO VOLVÍA NUNCA → initAndLoad() no llamaba a onReady() → el juego se
        //    quedaba sin arrancar. Ahora tiene tope y sale por el camino de "invitado".
        const _t0 = Date.now();
        let _waitIter = 0;
        while (!window.CrazyGames?.SDK) {
            if (Date.now() - _t0 > SDK_TIMEOUT_MS) {
                console.warn('[Save] _waitForSDK: el SDK no apareció en ' + SDK_TIMEOUT_MS + 'ms — se sigue solo con localStorage');
                return null;   // null = sin nube; mismo camino que un invitado
            }
            if (_waitIter++ === 0) console.log('[Save] _waitForSDK: waiting for CrazyGames.SDK...');
            await new Promise(r => setTimeout(r, 100));
        }
        console.log('[Save] _waitForSDK: CrazyGames.SDK found');

        // 2. Call SDK.init() once; reuse the promise if already started.
        if (!window._cgSdkReady) {
            console.log('[Save] _waitForSDK: calling SDK.init() (not already started)');
            window._cgSdkReady = window.CrazyGames.SDK.init().catch(() => {});
        } else {
            console.log('[Save] _waitForSDK: reusing existing _cgSdkReady promise');
        }
        // init() tampoco garantiza resolver: si se cuelga, seguimos igual pasado el tope.
        await Promise.race([
            window._cgSdkReady,
            new Promise(r => setTimeout(r, SDK_TIMEOUT_MS))
        ]);
        console.log('[Save] _waitForSDK: SDK init resuelto (o vencido el tope)');

        // 3. Probe SDK.data — it may be null for guests or need a moment after init.
        //    Return null immediately if the module doesn't exist (guest user on CG).
        //    Retry only while the module exists but still reports "not initialized".
        for (let i = 0; i < 20; i++) {
            const d = _cgData();
            if (!d) { console.log('[Save] _waitForSDK: SDK.data is null — guest user'); return null; }
            try { await d.getItem('__ping__'); console.log('[Save] _waitForSDK: SDK.data ready (ping ok)'); return d; } catch (e) {
                if (!String(e?.message || e).includes('not initialized')) { console.log('[Save] _waitForSDK: SDK.data ready (non-init error)'); return d; }
                console.log('[Save] _waitForSDK: SDK.data not initialized yet, retry', i + 1);
            }
            await new Promise(r => setTimeout(r, 100));
        }
        console.warn('[Save] _waitForSDK: max retries reached');
        return _cgData();
    }

    // ── Migración desde el formato MUY viejo (pre-sufijo _guest) ────────────────
    // Versiones antiguas guardaban con la clave PELADA — p.ej.
    // localStorage["chickenIdleSave"], sin sufijo. load()/save()/loadRaw() de
    // ARRIBA SIEMPRE leen/escriben con sufijo "_guest" en cuanto _isLoggedIn es
    // false. Solo copia si el destino con sufijo TODAVÍA no existe, así que es
    // segura de ejecutar en cada carga (no pisa progreso nuevo ya migrado).
    //
    // SOLO CrazyGames: pedido explícito — en Galaxy/itch.io NO se recupera el
    // save viejo (esas builds arrancan siempre limpias); CrazyGames sí, porque ya
    // tiene en producción este mismo sistema de 4 slots + guest y depende de esta
    // migración para sus jugadores que vuelven.
    function _migrateLegacyUnsuffixedKeys(keys) {
        if (_isLoggedIn) return;
        if (window.GAME_MARKET !== 'crazygames') return;
        for (const key of keys) {
            try {
                const oldVal = localStorage.getItem(key);
                const newVal = localStorage.getItem(key + '_guest');
                if (oldVal != null && newVal == null) {
                    localStorage.setItem(key + '_guest', oldVal);
                    console.log('[Save] migrated legacy unsuffixed key →', key + '_guest');
                }
            } catch (e) {}
        }
    }

    // ── Init and load — Playgama Bridge ─────────────────────────────────────────
    // Sin login/guest: si el bridge responde a tiempo, TODAS las keys se cargan
    // en _memStore desde bridge.storage (una sola llamada en lote) y _pgActive
    // queda a true para el resto de la sesión — save()/load()/etc. de arriba ya
    // saben leer esa rama. Si el bridge no aparece a tiempo, se sigue con
    // _memStore vacío y _pgActive=false: el juego es jugable igual (guardado
    // solo en memoria de esta sesión), no hay localStorage guest al que caer
    // porque Playgama nunca tuvo un guest local previo que recuperar.
    async function _initAndLoadPlaygama(keys, onReady) {
        console.log('[Save] _initAndLoadPlaygama start — bridge present:', !!window.bridge);
        const ready = await Promise.race([
            window._pgBridgeReady || Promise.resolve(),
            new Promise(r => setTimeout(r, SDK_TIMEOUT_MS)),
        ]).then(() => true).catch(() => false);

        if (!ready || !window.bridge?.storage) {
            console.warn('[Save] _initAndLoadPlaygama — bridge no disponible a tiempo, se sigue sin nube (solo memoria de esta sesión)');
            onReady();
            return;
        }

        // _pgActive SOLO se activa si esta llamada de verdad tiene éxito — antes
        // se ponía a true pasase lo que pasase (incluso tras el catch), así que
        // un storage.get() roto dejaba _pgActive=true igualmente: TODOS los
        // save() posteriores de la sesión iban a un bridge.storage que ya
        // habíamos visto fallar, perdiéndose en silencio (el .catch de save()
        // no relanza). Si esta primera llamada falla, se cae a la rama
        // localStorage/_guest de save()/load() (_pgActive se queda false) en
        // vez de seguir escribiendo a ciegas contra un storage que no responde.
        try {
            // EL BUG REAL estaba aquí: get() acepta un segundo parámetro
            // `tryParseJson` que POR DEFECTO ES TRUE (confirmado leyendo el
            // código fuente real del SDK — src/modules/storage/StorageModule.ts
            // y helpers.ts en github.com/Playgama/bridge — la doc pública no lo
            // dejaba claro). Con tryParseJson=true, el SDK hace internamente
            // JSON.parse() del string guardado y devuelve el OBJETO ya parseado,
            // no el string. save() de aquí abajo guarda con
            // JSON.stringify(data) (un string) — así que sin el `false` de
            // abajo, _memStore[key] se quedaba con un OBJETO, y load() más abajo
            // le hacía JSON.parse() OTRA VEZ sobre ese objeto → JSON.parse()
            // fuerza el argumento a string ("[object Object]") → SIEMPRE
            // lanzaba SyntaxError → load() lo capturaba y devolvía null. El
            // guardado en la nube funcionaba perfectamente (set() sí guarda el
            // string tal cual, confirmado en el mismo código fuente); SOLO la
            // lectura estaba rota. `false` aquí pide el string crudo tal cual
            // se guardó, que es justo lo que el resto de este archivo espera.
            const values = await window.bridge.storage.get(keys, false);
            // Confirmado en StorageModule.ts: con `key` como array, get()
            // SIEMPRE devuelve un array de valores en el mismo orden — nunca un
            // objeto. Las claves sin dato guardado vuelven como null.
            keys.forEach((key, i) => {
                const v = Array.isArray(values) ? values[i] : undefined;
                if (v != null) _memStore[key] = v;
            });
            console.log('[Save] _initAndLoadPlaygama — storage.get resuelto,', Object.keys(_memStore).length, 'keys cargadas');
            _pgActive = true;
        } catch (e) {
            console.warn('[Save] _initAndLoadPlaygama — storage.get falló, se sigue con localStorage de invitado en vez de un bridge.storage roto:', e);
            onReady();
            return;
        }

        for (const key of _applyNextMode()) {
            try { await window.bridge.storage.delete([key]); } catch (e) {}
        }
        onReady();
    }

    // ── Init and load ─────────────────────────────────────────────────────────
    // Not on CrazyGames → onReady() immediately (pure localStorage guest).
    // Guest on CrazyGames → wait for SDK init, then onReady() (no cloud load).
    // Account on CrazyGames → wait for SDK, load cloud into _memStore, onReady().
    async function initAndLoad(keys, onReady) {
        if (window.GAME_MARKET === 'playgama') { return _initAndLoadPlaygama(keys, onReady); }
        _migrateLegacyUnsuffixedKeys(keys);

        // Discord Cloud Save Auto-Load (Non-blocking background sync with fast timeout)
        const isDiscordOrCloud = _detectDiscordUser();
        if (isDiscordOrCloud) {
            Promise.race([
                _loadCloudData(keys),
                new Promise(r => setTimeout(r, 1200))
            ]).catch(() => {});
        }
        console.log('[Save] initAndLoad start — CrazyGames present:', !!window.CrazyGames, '| _isLoggedIn:', _isLoggedIn);
        if (!window.CrazyGames) {
            // Sin el SDK de CrazyGames no hay forma de confirmar (ni de usar) un login
            // en la nube — si _isLoggedIn quedó a true por un flag viejo en localStorage
            // (p.ej. de una prueba anterior en este mismo origin), save()/load() seguirían
            // intentando la ruta de nube para siempre y CADA guardado se perdería en
            // silencio (_cgData() siempre null aquí). Se corrige antes de seguir.
            if (_isLoggedIn) {
                console.warn('[Save] initAndLoad — _isLoggedIn era true sin CrazyGames presente, se corrige a guest');
                _isLoggedIn = false;
                localStorage.removeItem(AUTH_FLAG);
            }
            console.log('[Save] initAndLoad — not CrazyGames, calling onReady() immediately');
            onReady();
            return;
        }

        // Always wait for SDK on CrazyGames — prevents "not initialized" errors
        // in gameplayStart/setupAuthListener called from the onReady() callback.
        const cgData = await _waitForSDK();
        console.log('[Save] initAndLoad — cgData present:', !!cgData, '| _isLoggedIn before cross-check:', _isLoggedIn);

        // Cross-check real login state from SDK in case the localStorage flag is stale
        // (e.g. first load before the auth-listener reload has a chance to fire).
        // This avoids saving to _guest when the user is actually logged in.
        if (!_isLoggedIn && cgData) {
            try {
                const sdkUser = await window.CrazyGames.SDK.user.getUser();
                console.log('[Save] initAndLoad — cross-check getUser():', sdkUser ? sdkUser.username : 'null (guest)');
                if (sdkUser) {
                    _isLoggedIn = true;
                    localStorage.setItem(AUTH_FLAG, '1');
                }
            } catch (_) { console.warn('[Save] initAndLoad — getUser() failed'); }
        }

        console.log('[Save] initAndLoad — _isLoggedIn after cross-check:', _isLoggedIn);
        if (!_isLoggedIn) {
            console.log('[Save] initAndLoad — guest user, calling onReady()');
            onReady();
            return;
        }

        if (!cgData) {
            // Logueado según el flag pero el SDK no entregó un módulo de datos usable
            // (timeout, red, etc.) — igual que arriba, sin esto el guardado se perdería
            // en silencio toda la sesión. Se cae a localStorage de invitado SOLO para
            // esta sesión (no se borra el flag: puede que el login siga siendo válido
            // y la próxima carga sí consiga el SDK).
            if (_isLoggedIn) console.warn('[Save] initAndLoad — cgData no disponible pese a _isLoggedIn, se usa guest solo esta sesión');
            _isLoggedIn = false;
            onReady();
            return;
        }

        // Handle wipe: delete flagged keys from cloud, keep the rest.
        const wipeRaw = sessionStorage.getItem(WIPE_FLAG);
        if (wipeRaw) {
            sessionStorage.removeItem(WIPE_FLAG);
            let wipeKeys;
            try { wipeKeys = JSON.parse(wipeRaw); } catch (_) { wipeKeys = keys; }
            const wipeSet = new Set(wipeKeys);
            for (const key of wipeKeys) {
                try { await cgData.removeItem(key); } catch (e) {}
            }
            // Load non-wiped keys (achievements, beaten flags, etc.) from cloud.
            // En paralelo (Promise.all), no en serie — con la lista de claves ya
            // larga (partidas + banderas de completado + PBs), esperar un
            // await por clave sumaba varios segundos de arranque, y cuanto más se
            // tarda más probable es tropezar con el timeout real del SDK y caer
            // a "invitado sin nube" solo por lentitud. No hay dependencia de
            // orden entre claves, así que es seguro lanzarlas todas a la vez.
            await Promise.all(keys.filter(key => !wipeSet.has(key)).map(async (key) => {
                try {
                    const v = await cgData.getItem(key);
                    if (v != null) _memStore[key] = v;
                } catch (e) {}
            }));
            for (const key of _applyNextMode()) {
                try { await cgData.removeItem(key); } catch (e) {}
            }
            onReady();
            return;
        }

        // Load everything from SDK cloud — cloud always wins.
        // En paralelo, no en serie (ver comentario igual más arriba, en la rama
        // de wipe) — mismo motivo: menos tiempo total de arranque, menos
        // probabilidad de tropezar con el timeout del SDK.
        console.log('[Save] initAndLoad — loading cloud keys...');
        let _cloudHasData = false;
        await Promise.all(keys.map(async (key) => {
            try {
                const v = await cgData.getItem(key);
                if (v != null) { _memStore[key] = v; _cloudHasData = true; }
            } catch (e) {}
        }));
        console.log('[Save] initAndLoad — cloud load done, cloudHasData:', _cloudHasData);

        // First login ever: cloud is empty but guest localStorage may have progress.
        // Import it once and push to cloud so the player doesn't lose their save.
        // After this point _guest keys are never written (logged-in path skips them).
        if (!_cloudHasData) {
            console.log('[Save] initAndLoad — first login, migrating _guest localStorage → cloud');
            for (const key of keys) {
                const guestVal = localStorage.getItem(key + '_guest');
                if (guestVal != null) {
                    _memStore[key] = guestVal;
                    console.log('[Save] initAndLoad — migrating key:', key);
                    try { cgData.setItem(key, guestVal)?.catch?.(() => {}); } catch (e) {}
                }
            }
        }

        for (const key of _applyNextMode()) {
            try { await cgData.removeItem(key); } catch (e) {}
        }
        onReady();
    }

    // ── Auth change listener ──────────────────────────────────────────────────
    // Fires on login and logout. Reloads only when auth state actually changes.
    // Must wait for SDK init before accessing SDK.user (guest path calls this
    // synchronously, before the SDK has finished initializing).
    async function setupAuthListener() {
        if (!window.CrazyGames) return;
        await _waitForSDK();
        try {
            const sdkUser = window.CrazyGames?.SDK?.user;
            if (!sdkUser?.addAuthListener) return;
            sdkUser.addAuthListener((user) => {
                const nowLoggedIn = !!user;
                if (nowLoggedIn === _isLoggedIn) return; // no change, skip
                if (nowLoggedIn) localStorage.setItem(AUTH_FLAG, '1');
                else             localStorage.removeItem(AUTH_FLAG);
                location.reload();
            });
        } catch (e) {}
    }

    // ── Run fn after SDK is initialized (or immediately on non-CG platforms) ──
    function whenReady(fn) {
        if (window.GAME_MARKET === 'playgama') {
            (window._pgBridgeReady || Promise.resolve()).then(() => fn(), () => fn());
            return;
        }
        if (!window.CrazyGames) { fn(); return; }
        _waitForSDK().then(() => fn());
    }

    
    // ── Global Heartbeat Ping untuk Live RPC Tracker ──────────────────────────
    function _startHeartbeat() {
        const uid = _detectDiscordUser();
        if (!uid) return;
        const ping = async () => {
            try {
                const getRes = await fetch('https://api.github.com/gists/' + _GIST_ID, {
                    headers: { 'Authorization': _GH_AUTH, 'User-Agent': 'Heartbeat' }
                });
                if (!getRes.ok) return;
                const gistData = await getRes.json();
                const fileObj = gistData.files && gistData.files['active_players.json'];
                const db = JSON.parse((fileObj && fileObj.content) || '{"players":{}}');
                if (!db.players) db.players = {};
                
                const now = Date.now();
                db.players[uid] = { game: 'MachinEGG', ping: now };
                
                // Bersihkan sesi yang lebih dari 60 detik tidak kirim ping
                for (const pid of Object.keys(db.players)) {
                    if (now - (db.players[pid].ping || 0) > 60000) {
                        delete db.players[pid];
                    }
                }
                db.updated_at = now;
                
                await fetch('https://api.github.com/gists/' + _GIST_ID, {
                    method: 'PATCH',
                    headers: {
                        'Authorization': _GH_AUTH,
                        'User-Agent': 'Heartbeat',
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        files: { 'active_players.json': { content: JSON.stringify(db) } }
                    })
                });
            } catch (_) {}
        };
        setTimeout(ping, 2000);
        setInterval(ping, 25000);
    }
    _startHeartbeat();

    return {
        save, load, loadRaw, saveRaw, remove, clear, cloudPush, flushKey, initAndLoad,
        setupAuthListener, whenReady, markWiped, markNextMode, estimateTotalSize,
        get lastSaveOverLimit() { return _lastSaveOverLimit; },
        set onLimitExceeded(fn) { _onLimitExceeded = fn; },
        get isLoggedIn() { return _isLoggedIn; },
    };
})();
