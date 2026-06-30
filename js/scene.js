/* ============================================================
   THREE.JS SPACE BACKGROUND + AI ROBOT
   Single persistent WebGL scene rendered behind the whole page:
   starfield, nebula, a rotating planet, patrol drones and the
   central AI robot core that follows the pointer.
============================================================= */
(function(){
  if(typeof THREE === 'undefined') return;
  const canvas = document.getElementById('space-canvas');
  const isMobile = matchMedia('(max-width:720px)').matches;
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  const renderer = new THREE.WebGLRenderer({ canvas, antialias:true, alpha:true });
  renderer.setPixelRatio(Math.min(devicePixelRatio, isMobile ? 1.5 : 2));
  renderer.setSize(innerWidth, innerHeight);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(55, innerWidth/innerHeight, 0.1, 2000);
  camera.position.set(0, 0, 16);

  scene.add(new THREE.AmbientLight(0x113322, 1.2));
  const keyLight = new THREE.PointLight(0x00ff41, 6, 60);
  keyLight.position.set(6, 6, 10);
  scene.add(keyLight);
  const goldLight = new THREE.PointLight(0xffd700, 3, 50);
  goldLight.position.set(-8, -4, 6);
  scene.add(goldLight);

  /* ---------- helper: soft radial-gradient sprite texture ---------- */
  function glowTexture(hex){
    const c = document.createElement('canvas'); c.width = c.height = 128;
    const ctx = c.getContext('2d');
    const g = ctx.createRadialGradient(64,64,0,64,64,64);
    g.addColorStop(0, hex+'ff'); g.addColorStop(.4, hex+'66'); g.addColorStop(1, hex+'00');
    ctx.fillStyle = g; ctx.fillRect(0,0,128,128);
    return new THREE.CanvasTexture(c);
  }

  /* ---------- starfield ---------- */
  const starCount = isMobile ? 900 : 2600;
  const starGeo = new THREE.BufferGeometry();
  const starPos = new Float32Array(starCount*3);
  for(let i=0;i<starCount;i++){
    starPos[i*3]   = (Math.random()-0.5)*400;
    starPos[i*3+1] = (Math.random()-0.5)*400;
    starPos[i*3+2] = (Math.random()-0.5)*400 - 60;
  }
  starGeo.setAttribute('position', new THREE.BufferAttribute(starPos,3));
  const starMat = new THREE.PointsMaterial({ color:0xbfffd0, size:0.9, transparent:true, opacity:.8, map:glowTexture('#bfffd0'), depthWrite:false, blending:THREE.AdditiveBlending });
  const stars = new THREE.Points(starGeo, starMat);
  scene.add(stars);

  /* ---------- nebula clouds ---------- */
  const nebulaGroup = new THREE.Group();
  const nebulaColors = ['#00ff41', '#ffd700', '#39ff14'];
  for(let i=0;i<5;i++){
    const tex = glowTexture(nebulaColors[i%nebulaColors.length]);
    const mat = new THREE.SpriteMaterial({ map:tex, transparent:true, opacity:.10, blending:THREE.AdditiveBlending, depthWrite:false });
    const spr = new THREE.Sprite(mat);
    const scale = 60+Math.random()*70;
    spr.scale.set(scale,scale,1);
    spr.position.set((Math.random()-0.5)*120,(Math.random()-0.5)*80,-100-Math.random()*100);
    nebulaGroup.add(spr);
  }
  scene.add(nebulaGroup);

  /* ---------- planet ---------- */
  const planetGeo = new THREE.SphereGeometry(7, 48, 48);
  const planetMat = new THREE.MeshStandardMaterial({ color:0x062414, emissive:0x041006, roughness:.85, metalness:.15 });
  const planet = new THREE.Mesh(planetGeo, planetMat);
  planet.position.set(28, 14, -90);
  scene.add(planet);
  const ringGeo = new THREE.RingGeometry(9.5, 11.5, 64);
  const ringMat = new THREE.MeshBasicMaterial({ color:0x00ff41, transparent:true, opacity:.18, side:THREE.DoubleSide });
  const planetRing = new THREE.Mesh(ringGeo, ringMat);
  planetRing.rotation.x = Math.PI/2.4;
  planet.add(planetRing);

  /* ---------- AI robot core ---------- */
  const robot = new THREE.Group();
  robot.position.set(0, 0.5, 0);
  scene.add(robot);

  const coreGeo = new THREE.IcosahedronGeometry(2.1, 1);
  const coreMat = new THREE.MeshStandardMaterial({ color:0x021a0c, emissive:0x00ff41, emissiveIntensity:0.6, roughness:.4, metalness:.6, wireframe:false, transparent:true, opacity:.92 });
  const core = new THREE.Mesh(coreGeo, coreMat);
  robot.add(core);

  const wireGeo = new THREE.IcosahedronGeometry(2.32, 1);
  const wireMat = new THREE.MeshBasicMaterial({ color:0x39ff14, wireframe:true, transparent:true, opacity:.5 });
  const wireShell = new THREE.Mesh(wireGeo, wireMat);
  robot.add(wireShell);

  // Eyes
  const eyeMat = new THREE.MeshBasicMaterial({ color:0x00ff41 });
  const eyeGeo = new THREE.SphereGeometry(0.16, 16, 16);
  const eyeL = new THREE.Mesh(eyeGeo, eyeMat); eyeL.position.set(-0.62, 0.35, 1.7);
  const eyeR = new THREE.Mesh(eyeGeo, eyeMat); eyeR.position.set( 0.62, 0.35, 1.7);
  robot.add(eyeL, eyeR);

  // Orbiting holographic rings
  const ringsGroup = new THREE.Group();
  robot.add(ringsGroup);
  const ringDefs = [ {r:3.2, color:0x00ff41, tilt:0.3}, {r:3.9, color:0xffd700, tilt:-0.5}, {r:4.5, color:0x39ff14, tilt:1.1} ];
  const dataRings = ringDefs.map(d=>{
    const geo = new THREE.TorusGeometry(d.r, 0.02, 8, 100);
    const mat = new THREE.MeshBasicMaterial({ color:d.color, transparent:true, opacity:.55 });
    const m = new THREE.Mesh(geo, mat);
    m.rotation.x = Math.PI/2 + d.tilt;
    ringsGroup.add(m);
    return m;
  });

  // Small patrol drones
  const droneGroup = new THREE.Group();
  scene.add(droneGroup);
  const drones = [];
  for(let i=0;i<4;i++){
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.OctahedronGeometry(0.22,0), new THREE.MeshBasicMaterial({color:0xffd700}));
    const light = new THREE.PointLight(0xffd700, 1.2, 6);
    g.add(body, light);
    g.userData = { angle: Math.random()*Math.PI*2, radius: 9+Math.random()*5, speed:.15+Math.random()*.15, y:(Math.random()-0.5)*4 };
    droneGroup.add(g);
    drones.push(g);
  }

  /* ---------- pointer parallax ---------- */
  let targetX=0, targetY=0;
  window.addEventListener('mousemove', e=>{
    targetX = (e.clientX/innerWidth - 0.5);
    targetY = (e.clientY/innerHeight - 0.5);
  });

  /* ---------- scroll-driven camera depth ---------- */
  let scrollT = 0;
  window.addEventListener('scroll', ()=>{
    scrollT = window.scrollY / (document.body.scrollHeight - innerHeight || 1);
  });

  /* ---------- resize ---------- */
  window.addEventListener('resize', ()=>{
    camera.aspect = innerWidth/innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
  });

  /* ---------- emotion / scan state, exposed for other modules ---------- */
  let blinkTimer = 0;
  window.YYRobot = {
    setEmotion(color){
      const c = new THREE.Color(color);
      eyeMat.color.copy(c);
      coreMat.emissive.copy(c);
    }
  };

  /* ---------- render loop ---------- */
  const clock = new THREE.Clock();
  let paused = false;
  document.addEventListener('visibilitychange', ()=>{ paused = document.hidden; });

  function animate(){
    requestAnimationFrame(animate);
    if(paused) return;
    const t = clock.getElapsedTime();
    const dt = clock.getDelta();

    stars.rotation.y += 0.0006;
    nebulaGroup.rotation.y += 0.0002;
    planet.rotation.y += 0.0015;

    robot.position.y = 0.5 + Math.sin(t*0.9)*0.18;
    robot.rotation.y += (targetX*0.6 - robot.rotation.y)*0.04;
    robot.rotation.x += (targetY*0.3 - robot.rotation.x)*0.04;
    wireShell.rotation.y -= dt*0.15;
    ringsGroup.rotation.z += dt*0.2;
    dataRings.forEach((r,i)=>{ r.rotation.z += dt*(0.15+i*0.08)*(i%2?-1:1); });

    // Blink
    blinkTimer += dt;
    if(blinkTimer > 4 + Math.random()*2){
      blinkTimer = 0;
      gsapBlink();
    }

    // Drone patrol
    drones.forEach(d=>{
      d.userData.angle += dt*d.userData.speed;
      d.position.set(Math.cos(d.userData.angle)*d.userData.radius, d.userData.y + Math.sin(t*1.5+d.userData.angle)*0.4, Math.sin(d.userData.angle)*d.userData.radius - 4);
    });

    camera.position.z = 16 - scrollT*4;
    camera.position.y = -scrollT*2;

    renderer.render(scene, camera);
  }

  function gsapBlink(){
    if(typeof gsap === 'undefined'){ eyeL.scale.y = eyeR.scale.y = 0.1; setTimeout(()=>{eyeL.scale.y=eyeR.scale.y=1;},120); return; }
    gsap.to([eyeL.scale, eyeR.scale], { y:0.1, duration:.08, yoyo:true, repeat:1, ease:'power1.inOut' });
  }

  if(!reducedMotion) animate();
  else renderer.render(scene, camera);
})();
