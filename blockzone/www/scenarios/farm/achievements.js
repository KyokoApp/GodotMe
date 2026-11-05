// scenarios/farm/achievements.js — Farm achievement definitions
// Exposes window.FarmAchievements. Loaded before script.js.
// check(s) and progress(s) receive the game state object as first argument.

// chickenIdleBeaten* vía GameSave.loadRaw en vez de localStorage crudo — mismo
// motivo que _bfGet en scenarios/farm/script.js (esa función es local a su
// propio IIFE, no accesible desde aquí, así que se repite el mismo patrón
// inline): script.js SÍ escribe estas claves a través de GameSave/_bfSet, pero
// esta comprobación las leía directamente de localStorage — en Playgama esa
// lectura nunca ve el dato real (vive en bridge.storage, no en localStorage).
function _famGetBeaten(key) {
    return (window.GameSave && window.GameSave.loadRaw) ? window.GameSave.loadRaw(key) : localStorage.getItem(key);
}

// tier/icon: puramente visuales para el panel de logros (shared/achievements.js
// renderPause()) — nunca afectan a id/i18nKey/check/progress, así que no tocan
// ni el guardado (chickenIdleAchievements) ni el desbloqueo ya conseguido por
// los jugadores. Iconos traídos de TM_Steam/pixelart_design/achievements/
// emparejados por TEMA (los ids de ese proyecto no coinciden con los de este).
window.FarmAchievements = [
    { id: 'chicken_1',      i18nKey: 'ach_chicken_1',      title: 'FIRST CHICKEN',  desc: 'Buy your first chicken',
      tier: 'bronze', icon: 'pixelart_design/achievements/chicken_10.png',
      check: s => s.chickens >= 1,
      progress: s => ({ cur: s.chickens, max: 1 }) },
    { id: 'chicken_25',     i18nKey: 'ach_chicken_25',     title: '25 CHICKENS',    desc: 'Have 25 chickens at once',
      tier: 'silver', icon: 'pixelart_design/achievements/chicken_100.png',
      check: s => (s.chickensWeighted ?? s.chickens) >= 25,
      progress: s => ({ cur: s.chickensWeighted ?? s.chickens, max: 25 }) },
    { id: 'chicken_250',    i18nKey: 'ach_chicken_250',    title: '250 CHICKENS',   desc: 'Have 250 chickens at once',
      tier: 'gold', icon: 'pixelart_design/achievements/chicken_250.png',
      check: s => (s.chickensWeighted ?? s.chickens) >= 250,
      progress: s => ({ cur: s.chickensWeighted ?? s.chickens, max: 250 }) },
    { id: 'chicken_500',    i18nKey: 'ach_chicken_500',    title: '500 CHICKENS',   desc: 'Have 500 chickens at once',
      // Rubí — PNG ya teñido de rojo (chicken_400_ruby.png), no en tiempo de
      // ejecución (ver bake_tints.js / _makeRubyTintedCanvas ya retirada de
      // script.js). El original chicken_400.png (azul/hielo) lo usa
      // chicken_100k_endless (Diamante, sin teñir) — mismo dibujo, colores
      // distintos, ya no comparten fichero.
      tier: 'platinum', icon: 'pixelart_design/achievements/chicken_400_ruby.png',
      check: s => (s.chickensWeighted ?? s.chickens) >= 500,
      progress: s => ({ cur: s.chickensWeighted ?? s.chickens, max: 500 }) },
    { id: 'chick_1',        i18nKey: 'ach_chick_1',        title: 'FIRST CHICK!',   desc: 'Hatch your first chick',
      tier: 'bronze', icon: 'pixelart_design/achievements/chick_1.png',
      check: s => (s.totalChicksBorn || 0) >= 1,
      progress: s => ({ cur: s.totalChicksBorn || 0, max: 1 }) },
    { id: 'chicks_100',     i18nKey: 'ach_chicks_100',     title: '100 CHICKS',     desc: 'Breed 100 chicks total',
      tier: 'silver', icon: 'pixelart_design/achievements/chicks_50.png',
      check: s => (s.totalChicksBorn || 0) >= 100,
      progress: s => ({ cur: s.totalChicksBorn || 0, max: 100 }) },
    { id: 'pet_10k',        i18nKey: 'ach_pet_10k',        title: 'PET MANIAC',     desc: 'Pet chickens 10,000 times',
      tier: 'silver', icon: 'pixelart_design/achievements/pet_10k.png',
      check: s => (s.totalPets || 0) >= 10000,
      progress: s => ({ cur: s.totalPets || 0, max: 10000 }) },
    { id: 'eggs_50k',       i18nKey: 'ach_eggs_50k',       title: 'EGG DEALER',     desc: 'Sell 50,000 eggs',
      tier: 'gold', icon: 'pixelart_design/achievements/eggs_30k.png',
      check: s => (s.eggsSold || 0) >= 50000,
      progress: s => ({ cur: s.eggsSold || 0, max: 50000 }) },
    { id: 'retire',         i18nKey: 'ach_retire',         title: 'RETIRED!',       desc: 'Complete a game (retire)',
      tier: 'gold', icon: 'pixelart_design/achievements/retire.png',
      check: s => !!s.hasRetired,
      progress: s => ({ cur: s.hasRetired ? 1 : 0, max: 1 }) },
    { id: 'perfect_retire', i18nKey: 'ach_perfect_retire', title: 'PERFECT FARM',   desc: 'Retire without any chicken suffering or dying of hunger',
      // Rubí — PNG ya teñido (perfect_retire_ruby.png), ver nota en chicken_500.
      tier: 'platinum', icon: 'pixelart_design/achievements/perfect_retire_ruby.png',
      check: s => !!s.hasRetired && (s.deadChickens || 0) === 0 && (s.chickensSuffered || 0) === 0,
      // max: 0 (el máximo PERMITIDO de gallinas que pasen hambre) — mientras
      // vaya perfecto se lee "0 / 0", y si una sola pasa hambre sube a p.ej.
      // "1 / 0" (ver `failed` más abajo, que evita que renderPause recorte
      // cur a max en ese caso) — dejando claro que ya se ha superado el
      // límite permitido, no un progreso normal hacia una meta positiva.
      progress: s => ({ cur: s.chickensSuffered || 0, max: 0 }),
      // Aditivo — no cambia check(): en cuanto una gallina/pollito/gallo pasa
      // hambre este logro ya no se puede conseguir en ESTA partida, así que la
      // tarjeta se pinta en rojo (ver .ach-item--failed) en vez de seguir
      // mostrando progreso "en curso" de algo ya imposible.
      failed: s => (s.chickensSuffered || 0) > 0 },
    { id: 'all_chals',      i18nKey: 'ach_all_chals',      title: 'CHALLENGER',     desc: 'Beat all 5 challenges',
      // Antes reutilizaba el icono de "eggs_1m" (un huevo, sin relación
      // temática). Ahora usa la estrella de combo_500.png (sin usar en
      // ningún otro logro) ya teñida de rojo (combo_500_ruby.png) — una
      // estrella encaja mucho mejor con "completar todo" que un huevo.
      tier: 'platinum', icon: 'pixelart_design/achievements/combo_500_ruby.png',
      // 5 retos desde Gallinas Mimosas; quien ya lo tenía con 4 lo conserva (no se re-comprueba).
      check: () => ['Vanilla','Speedrun','Adam','Manual','Mimosas'].every(c => _famGetBeaten('chickenIdleBeaten'+c) === 'true'),
      progress: () => ({ cur: ['Vanilla','Speedrun','Adam','Manual','Mimosas'].filter(c => _famGetBeaten('chickenIdleBeaten'+c) === 'true').length, max: 5 }) },
    { id: 'manual_10k',     i18nKey: 'ach_manual_10k',     title: 'EGG HUSTLER',   desc: 'Move 10,000 eggs manually',
      tier: 'silver', icon: 'pixelart_design/achievements/manual_10k.png',
      check: s => (s.manualEggsMovedToMarket || 0) >= 10000,
      progress: s => ({ cur: s.manualEggsMovedToMarket || 0, max: 10000 }) },
    { id: 'earn_1m',        i18nKey: 'ach_earn_1m',        title: 'MILLIONAIRE',   desc: 'Earn $1,000,000',
      tier: 'silver', icon: 'pixelart_design/achievements/earn_1m.png',
      check: s => (s.totalEarnings || 0) >= 1000000,
      progress: s => ({ cur: s.totalEarnings || 0, max: 1000000 }) },
    { id: 'earn_50m',       i18nKey: 'ach_earn_50m',       title: 'BIG BUSINESS',  desc: 'Earn $50,000,000',
      tier: 'gold', icon: 'pixelart_design/achievements/earn_50m.png',
      check: s => (s.totalEarnings || 0) >= 50000000,
      progress: s => ({ cur: s.totalEarnings || 0, max: 50000000 }) },
    { id: 'earn_1b',        i18nKey: 'ach_earn_1b',        title: 'BILLIONAIRE',   desc: 'Earn $1,000,000,000',
      // Rubí — PNG ya teñido (earn_1b_ruby.png), ver nota en chicken_500.
      tier: 'platinum', icon: 'pixelart_design/achievements/earn_1b_ruby.png',
      check: s => (s.totalEarnings || 0) >= 1000000000,
      progress: s => ({ cur: s.totalEarnings || 0, max: 1000000000 }) },
    { id: 'earn_100b',      i18nKey: 'ach_earn_100b',      title: 'INSANE WEALTH', desc: 'Earn $100,000,000,000',
      // Pedido explícito: mismo trofeo que "eggs_50k" (TRAFICANTE DE HUEVOS),
      // en rubí (eggs_30k_ruby.png en vez de earn_100b_ruby.png). El original
      // earn_100b.png (azul/hielo) lo usa earn_1qa (Diamante, sin teñir) — ya
      // no comparten fichero.
      tier: 'platinum', icon: 'pixelart_design/achievements/eggs_30k_ruby.png',
      check: s => (s.totalEarnings || 0) >= 100000000000,
      progress: s => ({ cur: s.totalEarnings || 0, max: 100000000000 }) },

    // ── Nivel Diamante — el más alto, por encima de Rubí (antes 'platinum'
    // se llamaba "Diamante"; ahora ese nombre pasa a este nivel nuevo, ver
    // lang.js). Los 4 de aquí abajo no tienen icono propio en TM_Steam (son
    // nuevos, no existen allí) — reutilizan el icono más parecido temáticamente
    // de otro logro ya existente, SIN teñir (Diamante conserva el color
    // original del PNG, solo Rubí se tiñe — ver style.css), y su posición en
    // la vitrina del sótano usa huecos libres del estante de Steam (ver
    // _TROPHY_ID_POSITIONS en script.js).
    { id: 'chicks_10k_endless',   i18nKey: 'ach_chicks_10k_endless',   title: 'SUPREME BREEDER', desc: 'Breed 10,000 chicks in Endless Farm',
      // Único de los 4 sin ningún icono de sobra con su misma temática
      // (pollitos) — chicks_100 ya usa el único chicks_50.png que hay. En vez
      // de reutilizarlo igual (quedarían idénticos), PNG propio ya teñido de
      // cian (chicks_50_diamond.png, #7fd8e8 — mismo color que la etiqueta de
      // categoría "Diamante" en style.css) horneado con el mismo método que
      // Rubí (ver bake_tints.js).
      tier: 'diamond', icon: 'pixelart_design/achievements/chicks_50_diamond.png',
      check: s => s.activeChallenge === 'endless' && (s.totalChicksBorn || 0) >= 10000,
      progress: s => ({ cur: s.totalChicksBorn || 0, max: 10000 }) },
    { id: 'chicken_100k_endless', i18nKey: 'ach_chicken_100k_endless', title: 'POULTRY EMPIRE',  desc: 'Have 100,000 chickens at once in Endless Farm',
      tier: 'diamond', icon: 'pixelart_design/achievements/chicken_400.png',
      check: s => s.activeChallenge === 'endless' && (s.chickensWeighted ?? s.chickens) >= 100000,
      progress: s => ({ cur: s.chickensWeighted ?? s.chickens, max: 100000 }) },
    { id: 'eggs_1m',              i18nKey: 'ach_eggs_1m',              title: 'EGG MAGNATE',     desc: 'Sell 1,000,000 eggs',
      // Antes compartía eggs_30k.png con eggs_50k (idénticos, ninguno de los
      // dos se tiñe). Ahora usa platinum_eggs_100.png (huevo azul/hielo, sin
      // usar en ningún otro logro) — distinto de verdad, sin necesidad de
      // teñir nada.
      tier: 'diamond', icon: 'pixelart_design/achievements/platinum_eggs_100.png',
      check: s => (s.eggsSold || 0) >= 1000000,
      progress: s => ({ cur: s.eggsSold || 0, max: 1000000 }) },
    { id: 'earn_1qa',             i18nKey: 'ach_earn_1qa',             title: 'TRILLIONAIRE',    desc: 'Earn $1,000,000,000,000,000',
      tier: 'diamond', icon: 'pixelart_design/achievements/earn_100b.png',
      check: s => (s.totalEarnings || 0) >= 1000000000000000,
      progress: s => ({ cur: s.totalEarnings || 0, max: 1000000000000000 }) },
];
