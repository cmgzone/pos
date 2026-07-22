import * as THREE from 'three';

const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
const iconStates = [];
let frameId = 0;
let pageVisible = !document.hidden;

function colorFor(element) {
  return new THREE.Color(getComputedStyle(element).color);
}

function createWireBox(size, color) {
  return new THREE.LineSegments(
    new THREE.EdgesGeometry(new THREE.BoxGeometry(...size)),
    new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.82 }),
  );
}

function createIcon(type, color) {
  const group = new THREE.Group();
  const solid = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.94 });
  const translucent = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.22 });

  if (type === 'scan') {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.58, 0.06, 6, 28), solid);
    ring.rotation.x = Math.PI * 0.48;
    const sweep = new THREE.Mesh(new THREE.BoxGeometry(0.94, 0.04, 0.08), solid);
    sweep.position.z = 0.08;
    const core = new THREE.Mesh(new THREE.OctahedronGeometry(0.15, 0), translucent);
    group.add(ring, sweep, core);
    group.userData = { ring, sweep, core };
  } else if (type === 'inventory') {
    const lower = createWireBox([0.78, 0.5, 0.54], color);
    lower.position.set(-0.12, -0.21, 0);
    const upper = createWireBox([0.58, 0.4, 0.42], color);
    upper.position.set(0.2, 0.29, 0.02);
    const seal = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.15, 0.16), solid);
    seal.position.set(-0.34, -0.02, 0.28);
    group.add(lower, upper, seal);
    group.userData = { lower, upper, seal };
  } else {
    const bars = [0.38, 0.66, 0.98].map((height, index) => {
      const bar = new THREE.Mesh(new THREE.BoxGeometry(0.22, height, 0.22), solid);
      bar.position.set((index - 1) * 0.34, -0.48 + height / 2, 0);
      group.add(bar);
      return bar;
    });
    const spark = new THREE.Mesh(new THREE.OctahedronGeometry(0.12, 0), translucent);
    spark.position.set(0.55, 0.52, 0.08);
    group.add(spark);
    group.userData = { bars, spark };
  }

  return group;
}

function setSize(state) {
  const { width, height } = state.element.getBoundingClientRect();
  if (!width || !height) return;
  state.renderer.setSize(width, height, false);
  state.camera.left = -0.85;
  state.camera.right = 0.85;
  state.camera.top = (height / width) * 0.85;
  state.camera.bottom = -(height / width) * 0.85;
  state.camera.updateProjectionMatrix();
  renderState(state, performance.now());
}

function renderState(state, time) {
  const seconds = time * 0.001;
  const hoverTarget = state.hovered ? 1 : 0;
  state.hoverAmount += (hoverTarget - state.hoverAmount) * 0.09;
  const breath = Math.sin(seconds * 1.45 + state.phase);
  const sway = Math.cos(seconds * 1.1 + state.phase) * 0.12;
  const lift = breath * 0.05 + state.hoverAmount * 0.1;

  state.group.position.y = lift;
  state.group.rotation.set(0.15 + sway, seconds * 0.48 + state.phase, sway * 0.38);
  state.group.scale.setScalar(1 + state.hoverAmount * 0.12);

  if (state.type === 'scan') {
    state.group.userData.ring.rotation.z = seconds * 1.8;
    state.group.userData.sweep.position.y = Math.sin(seconds * 2.2 + state.phase) * 0.29;
    state.group.userData.core.rotation.set(seconds * 1.5, seconds * 1.2, 0);
  } else if (state.type === 'inventory') {
    state.group.userData.upper.position.y = 0.29 + breath * 0.08 + state.hoverAmount * 0.06;
    state.group.userData.seal.rotation.set(seconds * 1.4, seconds * 1.1, 0);
  } else {
    state.group.userData.bars.forEach((bar, index) => {
      const pulse = 1 + Math.sin(seconds * 2.2 + state.phase + index * 0.8) * 0.09 + state.hoverAmount * 0.08;
      bar.scale.y = pulse;
    });
    state.group.userData.spark.position.y = 0.52 + Math.sin(seconds * 2.1 + state.phase) * 0.12;
    state.group.userData.spark.rotation.set(seconds, seconds * 1.4, 0);
  }

  state.renderer.render(state.scene, state.camera);
}

function shouldAnimate() {
  return pageVisible && !motionQuery.matches && iconStates.some((state) => state.visible);
}

function animate(time) {
  iconStates.forEach((state) => {
    if (state.visible) renderState(state, time);
  });
  frameId = shouldAnimate() ? requestAnimationFrame(animate) : 0;
}

function ensureAnimation() {
  if (!frameId && shouldAnimate()) frameId = requestAnimationFrame(animate);
}

function setMotionMode() {
  if (motionQuery.matches && frameId) {
    cancelAnimationFrame(frameId);
    frameId = 0;
  }
  iconStates.forEach((state) => renderState(state, performance.now()));
  ensureAnimation();
}

function initializeIcon(element, index) {
  try {
    const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, powerPreference: 'low-power' });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
    renderer.setClearAlpha(0);
    renderer.domElement.setAttribute('aria-hidden', 'true');

    const scene = new THREE.Scene();
    const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 10);
    camera.position.z = 3;
    const type = element.dataset.threeIcon || 'scan';
    const group = createIcon(type, colorFor(element));
    scene.add(group);
    element.appendChild(renderer.domElement);

    const state = {
      element,
      renderer,
      scene,
      camera,
      group,
      type,
      phase: index * 1.75,
      hovered: false,
      hoverAmount: 0,
      visible: true,
    };
    iconStates.push(state);
    element.classList.add('is-ready');
    element.addEventListener('pointerenter', () => { state.hovered = true; ensureAnimation(); });
    element.addEventListener('pointerleave', () => { state.hovered = false; });
    if ('ResizeObserver' in window) {
      new ResizeObserver(() => setSize(state)).observe(element);
    }
    setSize(state);
    return state;
  } catch (_) {
    return null;
  }
}

function initialize() {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      const state = iconStates.find((item) => item.element === entry.target);
      if (state) state.visible = entry.isIntersecting;
    });
    ensureAnimation();
  }, { rootMargin: '180px 0px', threshold: 0.01 });

  document.querySelectorAll('[data-three-icon]').forEach((element, index) => {
    const state = initializeIcon(element, index);
    if (state) observer.observe(element);
  });

  motionQuery.addEventListener?.('change', setMotionMode);
  document.addEventListener('visibilitychange', () => {
    pageVisible = !document.hidden;
    ensureAnimation();
  });
  window.addEventListener('resize', () => iconStates.forEach(setSize), { passive: true });
  ensureAnimation();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initialize, { once: true });
} else {
  initialize();
}
