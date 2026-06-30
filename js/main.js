/* ============================================================
   MAIN ORCHESTRATOR
   Nav scroll state, scroll-reveal animations and the robot's
   emotion changes as the commander moves through each scene.
============================================================= */
(function(){
  const hudNav = document.getElementById('hudNav');
  window.addEventListener('scroll', ()=>{
    hudNav.classList.toggle('scrolled', window.scrollY > 40);
  });

  if(typeof gsap !== 'undefined' && gsap.registerPlugin && window.ScrollTrigger){
    gsap.registerPlugin(ScrollTrigger);

    gsap.utils.toArray('.mission-card').forEach((card,i)=>{
      gsap.from(card, {
        opacity:0, y:60, duration:.8, ease:'power3.out', delay:i*0.08,
        scrollTrigger: { trigger: card, start:'top 88%' }
      });
    });

    gsap.from('.payment-console', {
      opacity:0, y:40, duration:.9, ease:'power3.out',
      scrollTrigger: { trigger:'.payment-console', start:'top 85%' }
    });

    gsap.from('.drone-stage', {
      opacity:0, y:40, duration:.9, ease:'power3.out',
      scrollTrigger: { trigger:'.drone-stage', start:'top 85%' }
    });

    gsap.from('.status-grid', {
      opacity:0, y:30, duration:.8, ease:'power3.out',
      scrollTrigger: { trigger:'.status-grid', start:'top 90%' }
    });

    // Robot emotion shifts to gold ("analyzing") near the mission center,
    // and back to green elsewhere.
    ScrollTrigger.create({
      trigger: '#mission-center', start:'top center', end:'bottom center',
      onEnter: ()=> window.YYRobot && window.YYRobot.setEmotion(0xffd700),
      onLeave: ()=> window.YYRobot && window.YYRobot.setEmotion(0x00ff41),
      onEnterBack: ()=> window.YYRobot && window.YYRobot.setEmotion(0xffd700),
      onLeaveBack: ()=> window.YYRobot && window.YYRobot.setEmotion(0x00ff41),
    });
  }
})();
