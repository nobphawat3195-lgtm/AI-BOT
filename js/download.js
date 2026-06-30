/* ============================================================
   SCENE 5 — DOWNLOAD CENTER
   Drone delivery animation, license activation and a real
   client-side download of the mission certificate.
============================================================= */
(function(){
  const aiLine     = document.getElementById('downloadAiLine');
  const licenseKey = document.getElementById('licenseKey');
  const licenseState = document.getElementById('licenseState');
  const barFill     = document.getElementById('dlBarFill');
  const pctLabel     = document.getElementById('dlPct');
  const downloadBtn  = document.getElementById('downloadBtn');
  const dronePackage  = document.getElementById('dronePackage');
  const drone        = document.getElementById('drone');
  if(!aiLine) return;

  let missionInfo = null;

  function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }
  async function typeInto(el, text, speed=24){
    el.textContent='';
    for(let i=0;i<text.length;i++){ el.textContent = text.slice(0,i+1); await sleep(speed); }
  }

  function genLicenseKey(){
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const block = ()=> Array.from({length:4},()=>chars[Math.floor(Math.random()*chars.length)]).join('');
    return [block(),block(),block(),block()].join('-');
  }

  window.addEventListener('paymentconfirmed', async (e)=>{
    missionInfo = e.detail;
    document.getElementById('download-center').scrollIntoView({ behavior:'smooth' });

    await sleep(500);
    await typeInto(aiLine, 'INBOUND DRONE DETECTED... PREPARING DELIVERY...');

    if(typeof gsap !== 'undefined'){
      gsap.to(drone, { x: 0, duration:1, ease:'power2.inOut' });
    }
    await sleep(900);
    drone.querySelector('.drone-beam').classList.add('active');
    await sleep(600);
    dronePackage.classList.add('dropped');
    await sleep(900);

    await typeInto(aiLine, 'MISSION COMPLETED, COMMANDER.');

    licenseKey.textContent = genLicenseKey();

    // Animated download progress
    let p = 0;
    const id = setInterval(()=>{
      p = Math.min(100, p + 2 + Math.random()*6);
      barFill.style.width = p+'%';
      pctLabel.textContent = Math.round(p)+'%';
      if(p>=100){
        clearInterval(id);
        licenseState.textContent = 'ACTIVE';
        licenseState.classList.add('active');
        downloadBtn.disabled = false;
      }
    }, 140);
  });

  downloadBtn.addEventListener('click', ()=>{
    const info = missionInfo || { name:'YOUNGYUU AI', price:'-', level:'00' };
    const cert = [
      'YOUNGYUU AI COMMAND CENTER',
      'MISSION CERTIFICATE',
      '----------------------------------------',
      'Mission:      ' + info.name,
      'Access Level:  MISSION ' + info.level,
      'Price:         ' + info.price + ' / month',
      'License Key:   ' + licenseKey.textContent,
      'Issued:        ' + new Date().toISOString(),
      '----------------------------------------',
      'Status: ACTIVE — Neural Core Online',
    ].join('\n');

    const blob = new Blob([cert], { type:'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'youngyuu-ai-mission-certificate.txt';
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  });
})();
