/* ============================================================
   LEFT HUD PANEL — NEURAL CORE LOG
   Endless typewriter console + the robot's one-line speech
   bubble above the hero title.
============================================================= */
(function(){
  const body = document.getElementById('terminalBody');
  const speechText = document.getElementById('robotSpeechText');
  if(!body) return;

  const LOG_LINES = [
    '> AI STARTED',
    '> NEURAL CORE LOADED',
    '> KELLY CALCULATION COMPLETE',
    '> ATR MODULE READY',
    '> GOLD ANALYSIS COMPLETE',
    '> AI CONFIDENCE 97%',
    '> SCANNING XAUUSD / EURUSD / GBPUSD',
    '> RISK ENGINE NOMINAL',
    '> WAITING FOR COMMANDER...',
  ];

  const SPEECH_LINES = [
    'Welcome, Commander.',
    'Neural core stable. Markets are quiet.',
    'Awaiting your next directive.',
  ];

  function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }

  async function typeInto(el, text, speed=22){
    el.textContent='';
    for(let i=0;i<text.length;i++){
      el.textContent = text.slice(0,i+1);
      await sleep(speed + Math.random()*14);
    }
  }

  async function runLog(){
    const MAX_LINES = 9;
    let i = 0;
    while(true){
      const line = LOG_LINES[i % LOG_LINES.length];
      const el = document.createElement('div');
      el.className = 'ln' + (line.includes('%') ? ' tag' : '');
      body.appendChild(el);
      el.style.opacity = '1';
      await typeInto(el, line);

      while(body.children.length > MAX_LINES){ body.removeChild(body.firstElementChild); }
      body.scrollTop = body.scrollHeight;

      i++;
      await sleep(900);
    }
  }

  async function runSpeech(){
    let i = 0;
    while(true){
      await typeInto(speechText, SPEECH_LINES[i % SPEECH_LINES.length], 32);
      await sleep(4200);
      i++;
    }
  }

  window.addEventListener('bootcomplete', ()=>{
    runLog();
    if(speechText) runSpeech();
  }, { once:true });
})();
