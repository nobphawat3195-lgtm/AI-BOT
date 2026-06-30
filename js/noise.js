/* ============================================================
   DIGITAL NOISE — boot screen static, drawn on a tiny canvas
   then scaled up by CSS for a cheap, GPU-friendly grain effect.
============================================================= */
(function(){
  const canvas = document.getElementById('noise-canvas');
  if(!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = 160, H = 100;
  canvas.width = W; canvas.height = H;

  let running = true;
  function draw(){
    if(!running) return;
    const img = ctx.createImageData(W,H);
    for(let i=0;i<img.data.length;i+=4){
      const v = Math.random()*255;
      img.data[i]=v; img.data[i+1]=v; img.data[i+2]=v; img.data[i+3]=255;
    }
    ctx.putImageData(img,0,0);
    requestAnimationFrame(draw);
  }
  requestAnimationFrame(draw);

  window.__stopBootNoise = ()=>{ running = false; };
})();
