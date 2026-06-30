/* ============================================================
   RIGHT HUD PANEL — LIVE AI DASHBOARD
   Numbers drift continuously using small random walks so the
   panel always feels alive, never static.
============================================================= */
(function(){
  const els = {
    cpu: document.getElementById('d-cpu'), cpuVal: document.getElementById('d-cpu-val'),
    gpu: document.getElementById('d-gpu'), gpuVal: document.getElementById('d-gpu-val'),
    ram: document.getElementById('d-ram'), ramVal: document.getElementById('d-ram-val'),
    lat: document.getElementById('d-lat'), latVal: document.getElementById('d-lat-val'),
    kelly: document.getElementById('s-kelly'),
    atr: document.getElementById('s-atr'),
    winrate: document.getElementById('s-winrate'),
    risk: document.getElementById('s-risk'),
    spread: document.getElementById('s-spread'),
    signal: document.getElementById('s-signal'),
    regime: document.getElementById('s-regime'),
    confPct: document.getElementById('s-conf-pct'),
    confFill: document.getElementById('s-conf-fill'),
  };
  if(!els.cpu) return;

  const REGIMES = ['TRENDING UP ↑', 'TRENDING DOWN ↓', 'SIDEWAYS ↔', 'HIGH VOLATILITY ⚡', 'ACCUMULATION'];

  // Random-walk state so values drift smoothly instead of jumping.
  const state = { cpu:34, gpu:52, ram:41, lat:28, kelly:1.42, atr:0.86, winrate:87, risk:12, spread:1.4, signal:74, conf:91 };

  function walk(v, min, max, step){
    v += (Math.random()-0.5)*step;
    return Math.max(min, Math.min(max, v));
  }

  function render(){
    state.cpu = walk(state.cpu, 18, 78, 6);
    state.gpu = walk(state.gpu, 30, 92, 7);
    state.ram = walk(state.ram, 25, 70, 4);
    state.lat = walk(state.lat, 8, 55, 8);
    state.kelly = walk(state.kelly, 0.8, 2.4, 0.12);
    state.atr = walk(state.atr, 0.4, 1.6, 0.06);
    state.winrate = walk(state.winrate, 78, 96, 1.4);
    state.risk = walk(state.risk, 4, 22, 2.2);
    state.spread = walk(state.spread, 0.6, 3.2, 0.2);
    state.signal = walk(state.signal, 55, 99, 5);
    state.conf = walk(state.conf, 80, 99, 2.4);

    els.cpu.style.width = state.cpu+'%';        els.cpuVal.textContent = Math.round(state.cpu)+'%';
    els.gpu.style.width = state.gpu+'%';        els.gpuVal.textContent = Math.round(state.gpu)+'%';
    els.ram.style.width = state.ram+'%';        els.ramVal.textContent = Math.round(state.ram)+'%';
    els.lat.style.width = Math.min(100,state.lat*1.6)+'%'; els.latVal.textContent = Math.round(state.lat)+'ms';

    els.kelly.textContent   = state.kelly.toFixed(2);
    els.atr.textContent     = state.atr.toFixed(2);
    els.winrate.textContent = Math.round(state.winrate)+'%';
    els.risk.textContent    = Math.round(state.risk)+'%';
    els.spread.textContent  = state.spread.toFixed(1);
    els.signal.textContent  = Math.round(state.signal)+'%';

    els.confPct.textContent = Math.round(state.conf)+'%';
    els.confFill.style.width = state.conf+'%';
  }

  function cycleRegime(){
    els.regime.style.opacity = 0;
    setTimeout(()=>{
      els.regime.textContent = REGIMES[Math.floor(Math.random()*REGIMES.length)];
      els.regime.style.opacity = 1;
    }, 250);
  }

  render();
  cycleRegime();
  setInterval(render, 1400);
  setInterval(cycleRegime, 6000);
})();
