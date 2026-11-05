// shared/achievements.js — Achievement display & storage engine
// Exposes window.GameAchievements. Loaded before script.js.
// Scenario-specific definitions are injected via init(defs, getState).

window.GameAchievements = (() => {
    let _defs     = [];
    let _getState = () => ({});

    let _unlockedAchievements = new Set();
    let _achQueue   = [];
    let _achShowing = false;

    // Vía GameSave.loadRaw/saveRaw en vez de localStorage crudo — mismo motivo
    // que _bfGet/_bfSet en scenarios/farm/script.js (claves chickenIdleBeaten*/
    // pb_*): sin esto, en Playgama esta clave NUNCA llegaba a bridge.storage
    // (se quedaba en localStorage puro, que ese SDK explícitamente pide no usar
    // — y que en su entorno no persiste entre recargas), así que TODOS los
    // logros ya conseguidos se re-disparaban en cadena en cada F5. Con
    // CrazyGames logueado pasaba lo mismo en un dispositivo nuevo (la nube
    // nunca recibía esta clave). Fallback a localStorage crudo si GameSave no
    // está disponible (no debería pasar, se carga antes que este archivo).
    function _achGet() {
        return (window.GameSave && window.GameSave.loadRaw) ? window.GameSave.loadRaw('chickenIdleAchievements') : localStorage.getItem('chickenIdleAchievements');
    }
    function _achSet(raw) {
        if (window.GameSave && window.GameSave.saveRaw) window.GameSave.saveRaw('chickenIdleAchievements', raw);
        else try { localStorage.setItem('chickenIdleAchievements', raw); } catch (_) {}
    }

    function load() {
        try {
            const saved = JSON.parse(_achGet() || '[]');
            _unlockedAchievements = new Set(saved);
        } catch(e) { _unlockedAchievements = new Set(); }
    }

    function _save() {
        _achSet(JSON.stringify([..._unlockedAchievements]));
    }

    function _showNext() {
        if (_achQueue.length === 0) { _achShowing = false; return; }
        _achShowing = true;
        const ach = _achQueue.shift();
        const el  = document.getElementById('achievement-popup');
        if (!el) { _achShowing = false; return; }
        const t = window.t || (k => k);
        document.getElementById('achievement-title').textContent = t(ach.i18nKey);
        document.getElementById('achievement-desc').textContent  = t(ach.i18nKey + '_tip');
        el.classList.add('show');
        setTimeout(() => {
            el.classList.remove('show');
            setTimeout(_showNext, 500);
        }, 3500);
    }

    function _trigger(ach) {
        _unlockedAchievements.add(ach.id);
        _save();
        _achQueue.push(ach);
        if (!_achShowing) _showNext();
        // Celebración nativa de CrazyGames (confetti) — no-op fuera de ese
        // market. El popup de arriba (#achievement-popup) sigue exactamente
        // igual, esto es un extra que lo acompaña, no lo sustituye.
        window.GameAds?.happyTime?.();
        // Gemas por logro (tienda de gemas, scenarios/farm/gems.js) — no-op fuera de CrazyGames.
        try { window.FarmGems?.onAchievement?.(ach); } catch (e) {}
    }

    function init(defs, getState) {
        _defs     = defs;
        _getState = getState;
        load();
    }

    function check() {
        const s = _getState();
        _defs.forEach(a => {
            if (!_unlockedAchievements.has(a.id)) {
                try { if (a.check(s)) _trigger(a); } catch(e) {}
            }
        });
    }

    // Para la vitrina de trofeos en la escena de la granja (scenarios/farm/
    // script.js, _syncTrophyCasePixi) — necesita la lista de logros YA
    // desbloqueados para ir pintando un icono por cada uno. Devuelve las defs
    // en el mismo orden que _defs.
    function getUnlocked() {
        return _defs.filter(a => _unlockedAchievements.has(a.id));
    }

    // Rediseño (traído del panel de la versión Steam): antes cada tarjeta era
    // solo un título minúsculo con una barra de relleno sin números, y la
    // descripción solo se veía al pasar el ratón (tooltip). Ahora nombre +
    // descripción + progreso numérico ("1.2K/50K") van siempre visibles en la
    // tarjeta — sin tooltip, ya no hace falta. fmtShort (sufijos K/M/B, ver
    // shared/utils.js) en vez de fmt (con comas) para el progreso: varios
    // logros llegan a máximos de miles de millones que no caben en una
    // tarjeta de columna estrecha con fuente pixel.
    //
    // Niveles de dificultad: cada logro trae `tier` ('bronze'/'silver'/'gold'/
    // 'platinum', ver scenarios/farm/achievements.js). El panel los agrupa por
    // tier con una cabecera (trofeo + nombre + contador de esa sección) antes
    // de pintar sus tarjetas — una sección sin ningún logro definido con ese
    // tier simplemente no se pinta.
    // 'platinum' se muestra como "Rubí" (rojo) y 'diamond' como "Diamante" —
    // el nivel más alto de todos, ver lang.js/style.css. El nombre interno
    // 'platinum' no cambia (son los logros de siempre, no se toca su id).
    const TIER_ORDER = ['bronze', 'silver', 'gold', 'platinum', 'diamond'];
    const TIER_META = {
        bronze:   { i18nKey: 'achTierBronze' },
        silver:   { i18nKey: 'achTierSilver' },
        gold:     { i18nKey: 'achTierGold' },
        platinum: { i18nKey: 'achTierPlatinum' },
        diamond:  { i18nKey: 'achTierDiamond' },
    };
    // El nivel 'diamond' es nuevo y no tiene arte propio (ach_tier_diamond.png/
    // ach_card_diamond.png no existen) — reutiliza tal cual el arte azul de
    // 'platinum' (que ya visualmente parece un diamante), mientras que
    // 'platinum' en sí se pinta en rojo con un filtro CSS (.tier-platinum,
    // ver style.css) para pasar a ser "Rubí". Así no hace falta arte nuevo.
    const TIER_ASSET = { bronze: 'bronze', silver: 'silver', gold: 'gold', platinum: 'platinum', diamond: 'platinum' };

    function renderPause(fmt) {
        const countEl = document.getElementById('ach-count');
        const listEl  = document.getElementById('ach-list');
        if (!countEl || !listEl) return;
        const s = _getState();
        countEl.textContent = `(${_unlockedAchievements.size}/${_defs.length})`;
        listEl.innerHTML = '';
        const t    = window.t || (k => k);
        const fmtS = (window.GameUtils && window.GameUtils.fmtShort) ? window.GameUtils.fmtShort : fmt;

        // Alterna el sentido de la inclinación al pasar el ratón por cada
        // tarjeta — contador global (no por tier) para que la alternancia se
        // vea seguida en toda la rejilla, ver .ach-item--tilt-left/--tilt-right.
        let _tiltCounter = 0;
        TIER_ORDER.forEach(tierId => {
            const tierDefs = _defs.filter(a => (a.tier || 'bronze') === tierId);
            if (!tierDefs.length) return;
            const meta = TIER_META[tierId];
            const doneInTier = tierDefs.filter(a => _unlockedAchievements.has(a.id)).length;

            const header = document.createElement('div');
            header.className = 'ach-tier-header tier-' + tierId;
            const trophyLeft = document.createElement('div');
            trophyLeft.className = 'ach-tier-trophy';
            const _tierImgUrl = "url('pixelart_design/ach_tier_" + TIER_ASSET[tierId] + ".png')";
            // 'platinum' ("Rubí"): degradado rojo + blend-mode:color (para
            // conservar brillos/sombras del PNG original, no un rojo plano
            // sin textura) MÁS mask-image con el mismo PNG (para recortar el
            // resultado a la silueta real y no pintar un cuadrado alrededor,
            // ya que el degradado por sí solo cubre toda la caja sin mirar la
            // transparencia). Las dos técnicas juntas: color con textura Y
            // sin cuadrado — una sola no bastaba para las dos cosas a la vez.
            if (tierId === 'platinum') {
                trophyLeft.style.backgroundImage = "linear-gradient(#ff0000, #ff0000), " + _tierImgUrl;
                trophyLeft.style.maskImage = _tierImgUrl;
                trophyLeft.style.webkitMaskImage = _tierImgUrl;
            } else {
                trophyLeft.style.backgroundImage = _tierImgUrl;
            }
            const name = document.createElement('span');
            name.className = 'ach-tier-name';
            name.textContent = t(meta.i18nKey);
            const trophyRight = document.createElement('div');
            trophyRight.className = 'ach-tier-trophy';
            trophyRight.style.cssText = trophyLeft.style.cssText;
            const cnt = document.createElement('span');
            cnt.className = 'ach-tier-count';
            cnt.textContent = `${doneInTier}/${tierDefs.length}`;
            header.append(trophyLeft, name, trophyRight, cnt);
            // Gemas por cada logro de este nivel (tienda de gemas, solo CrazyGames — achGems da 0 fuera)
            const _gems = window.FarmGems && window.FarmGems.achGems ? window.FarmGems.achGems(tierId) : 0;
            if (_gems > 0) {
                const g = document.createElement('span');
                g.className = 'ach-tier-gems';
                g.innerHTML = '<img src="pixelart_design/gem.png" alt=""><span></span>';
                g.lastChild.textContent = (_gems === 1 ? t('gemsAchPer1') : t('gemsAchPerN')).replace('{n}', _gems);
                header.appendChild(g);
            }
            listEl.appendChild(header);

            tierDefs.forEach(a => {
                const done = _unlockedAchievements.has(a.id);
                const prog = a.progress ? a.progress(s) : null;
                // Logros con un `failed(s)` opcional (p.ej. GRANJA PERFECTA)
                // pueden quedar IMPOSIBLES de conseguir en la partida actual
                // sin llegar a "done". En ese caso NO se recorta cur a max (al
                // contrario que el resto, donde sí se recorta para que la
                // barra nunca pase de 100%) — así puede enseñar p.ej. "3 / 0",
                // en rojo, dejando claro que no hay vuelta atrás en esta partida.
                const failed = !done && a.failed ? !!a.failed(s) : false;
                const cur  = prog ? (failed ? prog.cur : Math.min(prog.cur, prog.max)) : 0;
                const max  = prog ? prog.max : 1;
                const pct  = failed ? 1 : (max ? Math.min(1, cur / max) : (done ? 1 : 0));

                const item = document.createElement('div');
                const _tiltClass = (_tiltCounter++ % 2 === 0) ? 'ach-item--tilt-left' : 'ach-item--tilt-right';
                item.className = 'ach-item tier-' + tierId + ' ' + _tiltClass + ' ' + (done ? 'ach-item--done' : failed ? 'ach-item--failed' : 'ach-item--locked');

                // Icono propio del logro — a color si ya está conseguido, solo
                // la silueta (filter: brightness(0), ver .ach-item-icon--locked
                // en style.css) si todavía no. a.icon es explícito (no se
                // deriva de a.id) porque los iconos disponibles vienen de un
                // proyecto hermano con sus propios ids — con fallback genérico
                // para cualquier logro sin icono propio asignado.
                const icon = document.createElement('div');
                icon.className = 'ach-item-icon' + (done ? '' : ' ach-item-icon--locked');
                const _iconUrl = "url('" + (a.icon || 'pixelart_design/achievements/_locked_generic.png') + "')";
                // "Rubí" (done + platinum): degradado + blend-mode:color
                // (conserva el sombreado/brillo real del icono, no un rojo
                // plano sin textura) MÁS mask-image con el mismo icono
                // (recorta a su silueta real, evita el cuadrado rojo
                // alrededor) — mismo criterio que el trofeo de cabecera.
                if (done && tierId === 'platinum') {
                    icon.style.backgroundImage = "linear-gradient(#ff0000, #ff0000), " + _iconUrl;
                    icon.style.maskImage = _iconUrl;
                    icon.style.webkitMaskImage = _iconUrl;
                } else {
                    icon.style.backgroundImage = _iconUrl;
                }
                item.appendChild(icon);

                const body = document.createElement('div');
                body.className = 'ach-item-body';
                item.appendChild(body);

                const head = document.createElement('div');
                head.className = 'ach-item-head';
                const label = document.createElement('span');
                label.className = 'ach-item-label';
                label.textContent = t(a.i18nKey);
                head.appendChild(label);
                if (done) {
                    const check = document.createElement('span');
                    check.className = 'ach-item-check';
                    head.appendChild(check);
                }
                body.appendChild(head);

                const desc = document.createElement('div');
                desc.className = 'ach-item-desc';
                desc.textContent = t(a.i18nKey + '_tip');
                body.appendChild(desc);

                if (prog && !done) {
                    const track = document.createElement('div');
                    track.className = 'ach-item-track';
                    // El relleno se queda SIEMPRE al 100% de la pista, fijo, y
                    // es una tapa aparte (.ach-item-mask) la que se encoge
                    // desde la derecha para ir revelando más o menos — así el
                    // degradado del relleno nunca se reescala, solo se destapa.
                    const fill = document.createElement('div');
                    fill.className = 'ach-item-fill' + (failed ? ' ach-item-fill--failed' : '');
                    track.appendChild(fill);
                    const mask = document.createElement('div');
                    mask.className = 'ach-item-mask';
                    mask.style.width = Math.round((1 - pct) * 100) + '%';
                    track.appendChild(mask);
                    const progText = document.createElement('span');
                    progText.className = 'ach-item-progtext' + (failed ? ' ach-item-progtext--failed' : '');
                    progText.textContent = fmtS(cur) + ' / ' + fmtS(max);
                    track.appendChild(progText);
                    body.appendChild(track);
                }

                listEl.appendChild(item);
            });
        });
    }

    return { init, load, check, renderPause, getUnlocked };
})();
