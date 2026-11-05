// scenarios/farm/offers.js — Random ad-offer system for the farm scenario
// Exposes window.FarmOffers. Loaded before script.js.
// Reads/writes game state via window._farmCtx (set up in script.js after init).

window.FarmOffers = (() => {

    // Los textos se guardan como CLAVE de traducción, no como literal: el idioma
    // puede cambiarse en caliente desde el menú, así que hay que resolverlos en
    // el momento de pintar el banner (ver _t()), no al definir el array.
    // Traducciones en lang.js, bloque "Banner de ofertas aleatorias".
    function _t(key, fallback) {
        return (window.t ? window.t(key) : null) || fallback;
    }
    // Sufijo de segundos de los contadores ("60s", "12s"): varía por idioma.
    function _secs() { return _t('offerSecs', 's'); }

    const RANDOM_OFFERS = [
        {
            icon: '',
            titleKey: 'offerChicksTitle',
            descKey:  'offerChicksDesc',
            apply() {
                const { state, canvas, chicksArr, createChick } = window._farmCtx;
                for (let i = 0; i < 5; i++) {
                    const cx = 100 + Math.random() * (canvas.width - 200);
                    const cy = 150 + Math.random() * 200;
                    chicksArr.push(createChick(cx, cy));
                    state.totalChicksBorn = (state.totalChicksBorn || 0) + 1;
                }
            }
        },
        {
            icon: '',
            titleKey: 'offerGrowTitle',
            descKey:  'offerGrowDesc',
            canShow() { return window._farmCtx.chicksArr.length > 0; },
            apply() { window._farmCtx.chicksArr.forEach(ch => { ch.growTimer = 0.01; }); }
        },
        {
            icon: '',
            titleKey: 'offerDoubleTitle',
            descKey:  'offerDoubleDesc',
            getTimer() { return window._farmCtx.state._offerEggDouble || 0; },
            apply() { const s = window._farmCtx.state; s._offerEggDouble = (s._offerEggDouble || 0) + 120; }
        },
        {
            icon: '',
            titleKey: 'offerFoodTitle',
            descKey:  'offerFoodDesc',
            getTimer() { return window._farmCtx.state._offerFoodTimer || 0; },
            apply() { const s = window._farmCtx.state; s._offerFoodTimer = (s._offerFoodTimer || 0) + 120; }
        }
    ];

    let _offerNextTimer = 0;
    let _currentOffer   = null;
    let _offerExpiry    = 0;
    let _activeBoostOffer = null;

    function _showRandomOffer(offer) {
        const el = document.getElementById('random-offer-popup');
        if (!el) return;
        document.getElementById('offer-title-el').textContent = _t(offer.titleKey);
        document.getElementById('offer-desc-el').textContent  = _t(offer.descKey);
        document.getElementById('offer-countdown').textContent = '60' + _secs();
        const lbl = document.getElementById('offer-ads-label');
        if (lbl) lbl.textContent = 'ADS';
        const btn = document.getElementById('offer-accept-btn');
        if (btn) btn.disabled = false;
        el.classList.remove('boost-active');
        el.classList.add('show');
    }

    function _showBoostActive(offer) {
        _activeBoostOffer = offer;
        const el = document.getElementById('random-offer-popup');
        if (!el) return;
        document.getElementById('offer-title-el').textContent = _t(offer.titleKey);
        document.getElementById('offer-desc-el').textContent  = _t(offer.descKey);
        const lbl = document.getElementById('offer-ads-label');
        if (lbl) lbl.textContent = Math.ceil(offer.getTimer()) + _secs();
        document.getElementById('offer-countdown').textContent = '';
        const btn = document.getElementById('offer-accept-btn');
        if (btn) btn.disabled = true;
        el.classList.add('show', 'boost-active');
    }

    function _hideRandomOffer(fromBoost) {
        const el = document.getElementById('random-offer-popup');
        if (el) { el.classList.remove('show', 'boost-active'); }
        const btn = document.getElementById('offer-accept-btn');
        if (btn) btn.disabled = false;
        _activeBoostOffer = null;
        _currentOffer     = null;
        _offerExpiry      = 0;
        if (fromBoost) _offerNextTimer = 60;
    }

    function tick(dt) {
        if (window._stNoAds) return;
        const { state } = window._farmCtx;
        const inChallenge = !!(state.isSpeedrunMode || (state.activeChallenge && state.activeChallenge !== 'vanilla'));
        if (inChallenge || state.hasRetired) {
            // Antes esto era un `return` a secas — y ahí estaba el bug.
            //
            // Es ESTE tick quien baja el contador y quien retira el panel al llegar a 0.
            // Al cortar aquí en seco, la oferta o el boost que estuviera EN PANTALLA se
            // quedaba congelado: el contador clavado en su último valor (p.ej. "43s"), sin
            // bajar nunca, y con el botón de aceptar en disabled (lo pone _showBoostActive).
            //
            // Pasaba al retirarse (hasRetired = true) y, peor, al volver a jugar un RETO:
            // ahí se cumple `inChallenge`, así que se volvía a cortar y el panel zombi no
            // desaparecía jamás. No se podía aceptar ni rechazar.
            //
            // _hideRandomOffer() limpia el panel, rehabilita el botón y resetea el estado.
            if (_currentOffer || _activeBoostOffer) _hideRandomOffer();
            return;
        }

        if ((state._offerEggDouble || 0) > 0)
            state._offerEggDouble = Math.max(0, state._offerEggDouble - dt);
        if ((state._offerFoodTimer || 0) > 0) {
            state._offerFoodTimer = Math.max(0, state._offerFoodTimer - dt);
            state.food  = state.maxFood;
            state.water = state.maxWater;
        }

        if (_activeBoostOffer) {
            const remaining = _activeBoostOffer.getTimer();
            const lbl = document.getElementById('offer-ads-label');
            if (lbl) lbl.textContent = Math.ceil(Math.max(0, remaining)) + _secs();
            if (remaining <= 0) _hideRandomOffer(true);
            return;
        }

        if (_currentOffer === null) {
            _offerNextTimer -= dt;
            // No mostrar la oferta si sabemos de antemano que el anuncio va a
            // fallar al pulsarla — se sigue contando (queda en negativo) y se
            // muestra en cuanto haya un anuncio listo de verdad.
            if (_offerNextTimer <= 0 && (!window.GameAds || window.GameAds.isRewardedReady())) {
                const available = RANDOM_OFFERS.filter(o => !o.canShow || o.canShow());
                _currentOffer = available[Math.floor(Math.random() * available.length)];
                _offerExpiry    = 60;
                _offerNextTimer = 120;
                _showRandomOffer(_currentOffer);
            }
        } else {
            _offerExpiry -= dt;
            const cdEl = document.getElementById('offer-countdown');
            if (cdEl) cdEl.textContent = Math.max(0, Math.ceil(_offerExpiry)) + _secs();
            if (_offerExpiry <= 0) {
                _hideRandomOffer();
                _currentOffer = null;
            }
        }
    }

    function setup() {
        const offerAcceptBtn = document.getElementById('offer-accept-btn');
        if (offerAcceptBtn) {
            offerAcceptBtn.addEventListener('click', () => {
                if (!_currentOffer || _activeBoostOffer) return;
                const offer = _currentOffer;
                _currentOffer = null;
                window._farmCtx._localRequestAd(() => {
                    offer.apply();
                    if (offer.getTimer && offer.getTimer() > 0) {
                        _showBoostActive(offer);
                    } else {
                        _hideRandomOffer();
                    }
                    window._farmCtx.updateUI();
                }, () => {
                    // El anuncio ha fallado de verdad — antes esto dejaba el panel
                    // clavado en pantalla (con _currentOffer ya a null) sin ninguna
                    // respuesta visible al pulsar.
                    _hideRandomOffer();
                    window._farmCtx._showIapToast(window.t ? window.t('adNotAvailable') : 'No ad available right now.');
                });
            });
        }
        const offerCloseBtn = document.getElementById('offer-close-btn');
        if (offerCloseBtn) {
            offerCloseBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                _currentOffer = null;
                _hideRandomOffer();
            });
        }
    }

    return { tick, setup, hide: _hideRandomOffer };
})();
