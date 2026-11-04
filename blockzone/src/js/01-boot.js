(function () {
  var boot = document.getElementById('boot');
  var icon = document.getElementById('bootIcon');
  if (!boot) return;
  var MIN_MS = 2300, MAX_MS = 6000, FADE_MS = 800;
  var t0 = Date.now(), done = false;
  var pageReady = document.readyState === 'complete';
  var iconReady = !icon || icon.complete;
  window.addEventListener('load', function () { pageReady = true; });
  if (icon && icon.decode) icon.decode().then(function () { iconReady = true; }, function () { iconReady = true; });

  function finish() {
    if (done) return;
    done = true;
    boot.classList.add('out');
    var inner = document.querySelector('.menu-inner');
    if (inner) inner.classList.add('enter');
    setTimeout(function () { if (boot.parentNode) boot.parentNode.removeChild(boot); }, FADE_MS + 100);
  }
  (function tick() {
    if (done) return;
    var el = Date.now() - t0;
    if (el >= MAX_MS || (el >= MIN_MS && pageReady && iconReady)) finish();
    else setTimeout(tick, 100);
  })();
})();
