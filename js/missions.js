/* ============================================================
   SCENE 3 — MISSION CENTER
   3D tilt-on-hover, cursor-tracked glow, and the
   "accept mission" hand-off into the Payment Center.
============================================================= */
(function(){
  const cards = document.querySelectorAll('.mission-card');
  if(!cards.length) return;

  cards.forEach(card=>{
    card.addEventListener('mousemove', e=>{
      const r = card.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width;
      const py = (e.clientY - r.top) / r.height;
      const rx = (py - 0.5) * -10;
      const ry = (px - 0.5) * 12;
      card.style.transform = `rotateX(${rx}deg) rotateY(${ry}deg) translateY(-6px)`;
      card.style.setProperty('--mx', (px*100)+'%');
      card.style.setProperty('--my', (py*100)+'%');
    });
    card.addEventListener('mouseleave', ()=>{
      card.style.transform = 'rotateX(0) rotateY(0) translateY(0)';
    });

    card.querySelector('.btn-mission').addEventListener('click', ()=> acceptMission(card));
  });

  function acceptMission(card){
    cards.forEach(c=>c.classList.remove('accepted'));
    card.classList.add('accepted');

    const name  = card.dataset.name;
    const price = card.dataset.price;
    const level = card.dataset.mission;

    window.dispatchEvent(new CustomEvent('missionselected', { detail:{ name, price, level } }));

    setTimeout(()=>{
      card.classList.remove('accepted');
      document.getElementById('payment-center').scrollIntoView({ behavior:'smooth' });
    }, 1100);
  }
})();
