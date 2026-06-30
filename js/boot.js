/* ============================================================
   SCENE 1 — BOOT SEQUENCE
   Typed terminal lines -> progress bar -> blast door opens ->
   green light floods through -> site is revealed.
============================================================= */
(function(){
  const bootSection = document.getElementById('boot-sequence');
  const terminal    = document.getElementById('bootTerminal');
  const barFill     = document.getElementById('bootBarFill');
  const pctLabel    = document.getElementById('bootPct');
  const statusLabel = document.getElementById('bootStatus');
  const doorLeft    = document.getElementById('doorLeft');
  const doorRight   = document.getElementById('doorRight');
  const doorLight   = document.getElementById('doorLight');
  const site        = document.getElementById('site');

  const LINES = [
    { text: 'INITIALIZING YOUNGYUU NEURAL CORE...', cls:'ok' },
    { text: 'LOADING TRADING SYSTEM MODULES...',    cls:'ok' },
    { text: 'RUNNING SECURITY VERIFICATION...',      cls:'ok' },
    { text: 'ESTABLISHING NEURAL CONNECTION...',     cls:'ok' },
    { text: 'VOICE PROTOCOL SYNCHRONIZED',           cls:'warn' },
    { text: 'ACCESS GRANTED — WELCOME, COMMANDER.',  cls:'ok' },
  ];

  function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }

  async function typeLine(lineEl, text){
    for(let i=0;i<text.length;i++){
      lineEl.textContent = text.slice(0,i+1);
      await sleep(14 + Math.random()*16);
    }
  }

  const hasGSAP = ()=> typeof gsap !== 'undefined';

  function tickProgressBar(duration){
    if(hasGSAP()){
      gsap.to({}, {
        duration, ease:'power1.inOut',
        onUpdate(){
          const p = Math.min(100, Math.round(this.progress()*100));
          barFill.style.width = p+'%';
          pctLabel.textContent = p+'%';
        }
      });
      return;
    }
    // Fallback: plain rAF tween, no GSAP dependency required.
    const start = performance.now();
    function step(now){
      const p = Math.min(100, Math.round(((now-start)/(duration*1000))*100));
      barFill.style.width = p+'%';
      pctLabel.textContent = p+'%';
      if(p < 100) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }

  async function runBoot(){
    // Progress bar ticks independently of the typed lines.
    tickProgressBar(3.6);

    for(const line of LINES){
      const el = document.createElement('div');
      el.className = 'ln ' + (line.cls||'');
      terminal.appendChild(el);
      el.style.opacity = '1';
      await typeLine(el, line.text);
      await sleep(160);
    }

    statusLabel.textContent = 'ACCESS GRANTED';
    statusLabel.style.color = 'var(--neon-green)';
    window.__stopBootNoise && window.__stopBootNoise();

    await sleep(450);
    openDoor();
  }

  function openDoor(){
    if(hasGSAP()){
      const tl = gsap.timeline({ onComplete: finishBoot });

      tl.to(doorLight, { opacity:1, width:6, duration:.4, ease:'power2.out' })
        .to(doorLight, { width:60, duration:.6, ease:'power2.out' })
        .to(doorLeft,  { xPercent:-100, duration:1.3, ease:'power3.inOut' }, '<')
        .to(doorRight, { xPercent:100,  duration:1.3, ease:'power3.inOut' }, '<')
        .to(doorLight, { opacity:0, duration:.5 }, '-=.3')
        .to(bootSection, { opacity:0, duration:.6, pointerEvents:'none' }, '-=.2');
      return;
    }

    // Fallback: plain CSS transitions, no GSAP dependency required.
    doorLight.style.transition = 'opacity .4s ease-out, width .6s ease-out';
    doorLeft.style.transition  = 'transform 1.3s cubic-bezier(.22,.61,.36,1)';
    doorRight.style.transition = 'transform 1.3s cubic-bezier(.22,.61,.36,1)';
    bootSection.style.transition = 'opacity .6s ease';

    doorLight.style.opacity = '1';
    doorLight.style.width = '6px';

    setTimeout(()=>{
      doorLight.style.width = '60px';
      doorLeft.style.transform = 'translateX(-100%)';
      doorRight.style.transform = 'translateX(100%)';
    }, 50);

    setTimeout(()=>{ doorLight.style.opacity = '0'; }, 950);

    setTimeout(()=>{
      bootSection.style.opacity = '0';
      bootSection.style.pointerEvents = 'none';
    }, 1150);

    setTimeout(finishBoot, 1750);
  }

  function finishBoot(){
    bootSection.style.display = 'none';
    site.classList.add('revealed');
    document.body.style.overflow = '';
    window.dispatchEvent(new CustomEvent('bootcomplete'));
  }

  // Kick things off once the DOM + fonts are ready.
  document.body.style.overflow = 'hidden';
  window.addEventListener('DOMContentLoaded', ()=>{});
  runBoot();
})();
