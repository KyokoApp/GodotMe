// shared/pixi.js — PixiJS initialisation & canvas-sync utilities
// Exposes window.GamePixi. Loaded before scenario scripts.

window.GamePixi = (() => {

    // init(canvas, containerEl) — creates a transparent PixiJS overlay attached to containerEl.
    // Returns { app: PIXI.Application, container: PIXI.Container } on success, null on failure.
    function init(canvas, containerEl) {
        if (typeof PIXI === 'undefined') return null;
        // file:// blocks WebGL texture uploads — fall back to Canvas 2D.
        if (window.location.protocol === 'file:') return null;

        let app;
        try {
            app = new PIXI.Application({
                width:           canvas.width,
                height:          canvas.height,
                backgroundAlpha: 0,
                autoStart:       false,
                antialias:       false,
                resolution:      1,
            });
        } catch (e) {
            return null;
        }

        const view = app.view;
        view.style.position      = 'absolute';
        view.style.top           = '0';
        view.style.left          = '0';
        view.style.pointerEvents = 'none';
        view.style.imageRendering = 'pixelated';
        view.style.zIndex        = '5';
        containerEl.appendChild(view);

        const container = new PIXI.Container();
        container.sortableChildren = true;
        app.stage.addChild(container);

        return { app, container };
    }

    // sync(canvas, pixiApp) — keeps the PixiJS overlay aligned with the CSS-scaled game canvas.
    // Also resizes the internal renderer if the canvas logical dimensions changed after init
    // (e.g. responsive.js updates canvas.width/height on DOMContentLoaded, after initPixi ran).
    function sync(canvas, pixiApp) {
        if (!pixiApp) return;
        const pv = pixiApp.view;

        // Resize internal renderer if canvas logical dimensions changed after PixiJS was created.
        // This fixes the Y-scale mismatch when portrait mode sets canvas to 800x900 but PixiJS
        // was initialised from the original HTML attributes (800x650).
        if (pixiApp.renderer.width !== canvas.width || pixiApp.renderer.height !== canvas.height) {
            pixiApp.renderer.resize(canvas.width, canvas.height);
        }

        // getBoundingClientRect(), NO offsetTop/offsetLeft/clientWidth/clientHeight: estas
        // últimas son SIEMPRE enteras por spec (redondean la posición real del layout), y en
        // ciertos tamaños de pantalla (medido en varios anchos de iPad) ese redondeo deja a este
        // overlay hasta ~0.25px CSS por debajo del borde real del canvas. Como #gameCanvas se
        // rellena de un color sólido de base (ver draw() en scenarios/farm/script.js) para que
        // este overlay lo cubra encima, ese hueco sub-píxel se veía como una línea fina de ese
        // color asomando en el borde superior. offsetParent es el mismo para canvas y para este
        // overlay (ambos hijos directos de canvas.parentNode, ver init() más abajo), así que basta
        // restar el rect de ese padre para obtener la posición fraccionaria correcta.
        const cr = canvas.getBoundingClientRect();
        const pr = canvas.offsetParent ? canvas.offsetParent.getBoundingClientRect() : { left: 0, top: 0 };
        const cw = cr.width, ch = cr.height;
        const cl = cr.left - pr.left, ct = cr.top - pr.top;
        if (cw <= 0 || ch <= 0) return;
        if (pv.style.width  !== cw + 'px' || pv.style.height !== ch + 'px' ||
            pv.style.left   !== cl + 'px' || pv.style.top    !== ct + 'px') {
            pv.style.width  = cw + 'px';
            pv.style.height = ch + 'px';
            pv.style.left   = cl + 'px';
            pv.style.top    = ct + 'px';
        }
    }

    return { init, sync };
})();
