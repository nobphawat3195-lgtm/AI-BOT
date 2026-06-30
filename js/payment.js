/* ============================================================
   SCENE 4 — PAYMENT CENTER
   Renders a holographic QR preview, reacts to the mission the
   commander selected, and simulates a payment confirmation.
============================================================= */
(function(){
  const selMission = document.getElementById('paySelMission');
  const selLevel   = document.getElementById('paySelLevel');
  const selPrice   = document.getElementById('paySelPrice');
  const confirmBtn = document.getElementById('confirmPayBtn');
  const statusEl   = document.getElementById('paymentStatus');
  const qrCanvas   = document.getElementById('qrCanvas');
  if(!qrCanvas) return;
  const ctx = qrCanvas.getContext('2d');

  let current = null;

  /* ---------- deterministic pseudo-QR pattern (decorative preview) ---------- */
  function hashSeed(str){
    let h = 0;
    for(let i=0;i<str.length;i++){ h = (h*31 + str.charCodeAt(i)) >>> 0; }
    return h;
  }
  function mulberry32(seed){
    return function(){
      seed |= 0; seed = seed + 0x6D2B79F5 | 0;
      let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }

  function drawQR(seedText){
    const N = 21; // module grid
    const size = qrCanvas.width;
    const cell = size / N;
    const rand = mulberry32(hashSeed(seedText || 'YOUNGYUU-AI'));

    ctx.clearRect(0,0,size,size);
    ctx.fillStyle = 'rgba(0,255,65,.05)';
    ctx.fillRect(0,0,size,size);

    function module(x,y,on){
      if(!on) return;
      ctx.fillStyle = '#00ff41';
      ctx.shadowColor = '#00ff41';
      ctx.shadowBlur = 4;
      ctx.fillRect(x*cell+1, y*cell+1, cell-2, cell-2);
    }
    function finder(ox,oy){
      for(let x=0;x<7;x++) for(let y=0;y<7;y++){
        const border = (x===0||x===6||y===0||y===6);
        const inner  = (x>=2&&x<=4&&y>=2&&y<=4);
        module(ox+x, oy+y, border || inner);
      }
    }

    for(let x=0;x<N;x++){
      for(let y=0;y<N;y++){
        const inFinderZone =
          (x<7 && y<7) || (x>N-8 && y<7) || (x<7 && y>N-8);
        if(inFinderZone) continue;
        module(x, y, rand() > 0.58);
      }
    }
    finder(0,0); finder(N-7,0); finder(0,N-7);
    ctx.shadowBlur = 0;
  }

  drawQR('YOUNGYUU-AI-PREVIEW');

  window.addEventListener('missionselected', e=>{
    const { name, price, level } = e.detail;
    current = e.detail;
    selMission.textContent = name;
    selLevel.textContent   = 'MISSION 0' + level.replace(/^0/,'');
    selPrice.textContent   = price;
    confirmBtn.disabled = false;
    statusEl.textContent = 'READY FOR TRANSMISSION';
    statusEl.classList.remove('success');
    drawQR(name + price + Date.now());
  });

  confirmBtn.addEventListener('click', ()=>{
    if(!current) return;
    confirmBtn.disabled = true;
    statusEl.textContent = 'TRANSMITTING... VERIFYING SIGNATURE...';

    if(typeof gsap !== 'undefined'){
      gsap.to('.qr-ring', { duration:.6, scale:1.15, yoyo:true, repeat:1, ease:'power2.inOut' });
    }

    setTimeout(()=>{
      statusEl.textContent = 'PAYMENT CONFIRMED — MISSION READY';
      statusEl.classList.add('success');
      window.dispatchEvent(new CustomEvent('paymentconfirmed', { detail: current }));
    }, 1800);
  });
})();
