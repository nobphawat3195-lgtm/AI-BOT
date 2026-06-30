/* ============================================================
   FOOTER + HUD CLOCK
============================================================= */
(function(){
  const hudClock = document.getElementById('hudClock');
  const footerClock = document.getElementById('footerClock');
  const yearNow = document.getElementById('yearNow');
  if(yearNow) yearNow.textContent = new Date().getFullYear();

  function tick(){
    const now = new Date();
    const hh = String(now.getHours()).padStart(2,'0');
    const mm = String(now.getMinutes()).padStart(2,'0');
    const ss = String(now.getSeconds()).padStart(2,'0');
    const str = `${hh}:${mm}:${ss}`;
    if(hudClock) hudClock.textContent = str;
    if(footerClock) footerClock.textContent = str + ' UTC+7';
  }
  tick();
  setInterval(tick, 1000);
})();
