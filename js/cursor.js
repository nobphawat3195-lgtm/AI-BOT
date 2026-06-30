/* ============================================================
   CUSTOM TARGETING CURSOR
   Smooth-follows the pointer and snaps to a "magnetic" hover
   ring whenever it passes over an interactive element.
============================================================= */
(function(){
  const cursor = document.getElementById('cursor');
  if(!cursor || matchMedia('(hover:none)').matches) return;

  let mx = window.innerWidth/2, my = window.innerHeight/2;
  let cx = mx, cy = my;

  window.addEventListener('mousemove', e=>{ mx = e.clientX; my = e.clientY; });

  window.addEventListener('mousedown', ()=> cursor.classList.add('click'));
  window.addEventListener('mouseup',   ()=> cursor.classList.remove('click'));

  document.addEventListener('mouseover', e=>{
    if(e.target.closest('[data-cursor-hover]')) cursor.classList.add('hover');
  });
  document.addEventListener('mouseout', e=>{
    if(e.target.closest('[data-cursor-hover]')) cursor.classList.remove('hover');
  });

  // Lerp toward the real pointer position for a fluid, weighted feel.
  function tick(){
    cx += (mx-cx)*0.18;
    cy += (my-cy)*0.18;
    cursor.style.transform = `translate(${cx}px,${cy}px)`;
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
