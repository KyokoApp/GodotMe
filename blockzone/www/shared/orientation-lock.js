// shared/orientation-lock.js — Bloqueo de orientación a portrait, SOLO iOS.
//
// Por qué existe: en iPadOS 26 el bloqueo declarativo del Info.plist
// (UISupportedInterfaceOrientations~ipad + UIRequiresFullScreen) dejó de
// honrarse — comprobado con el MISMO binario, que se queda en portrait en
// iPadOS 18 y rota en iPadOS 26.5. En iPhone sí funciona.
//
// La idea aquí es distinta: en vez de DECLARAR la orientación soportada, se
// PIDE activamente. @capacitor/screen-orientation llama por dentro a
// windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)),
// que es una petición imperativa a la escena. Bajo el modelo de ventanas
// redimensionables de iPadOS 26 puede surtir efecto donde la declaración se
// ignora. Es una hipótesis a validar en dispositivo, no una certeza.
//
// Solo iOS a propósito:
//   - Android ya bloquea por AndroidManifest (android:screenOrientation) y
//     funciona, así que no hay nada que arreglar ahí.
//   - Además el propio README del plugin avisa de que con targetSdk 36 en
//     Android 16+ el lock es un no-op en pantallas grandes, o sea que llamarlo
//     ahí no aportaría nada y sí añadiría una vía de fallo.
//   - En web/escritorio no aplica.
//
// Si esto no funciona en iPadOS 26, se puede borrar este archivo, su <script>
// en index.html y la dependencia @capacitor/screen-orientation, sin más.
(function () {
    var C = window.Capacitor;
    if (!C || typeof C.isNativePlatform !== 'function' || !C.isNativePlatform()) return;
    if (typeof C.getPlatform !== 'function' || C.getPlatform() !== 'ios') return;
    if (typeof C.registerPlugin !== 'function') return;

    try {
        // registerPlugin sin implementación web: en nativo el puente resuelve
        // los métodos vía Capacitor.PluginHeaders. Mismo mecanismo que usa el
        // resto de plugins nativos del proyecto.
        var ScreenOrientation = C.registerPlugin('ScreenOrientation');
        ScreenOrientation.lock({ orientation: 'portrait' })
            .then(function () { console.log('[Orient] lock portrait OK'); })
            .catch(function (e) { console.warn('[Orient] lock portrait falló:', e); });
    } catch (e) {
        console.warn('[Orient] no se pudo pedir el bloqueo de orientación:', e);
    }
})();
