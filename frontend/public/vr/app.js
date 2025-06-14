const placeholderVideo = 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4';
const tilesContainer = document.getElementById('tiles');
const activeSpan = document.getElementById('active');
const infoSpan = document.getElementById('info');
let activeIndex = -1;

async function loadInstances() {
  try {
    const res = await fetch('/api/config/instances');
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data) && data.length) return data;
    }
  } catch (e) {
    console.warn('Failed to fetch instances', e);
  }
  infoSpan.textContent = 'Using placeholder streams';
  return Array.from({ length: 3 }, (_, i) => ({ id: `placeholder-${i}`, streamUrl: null }));
}

function positionForIndex(i, cols, rows) {
  const x = (i % cols) - (cols - 1) / 2;
  const row = Math.floor(i / cols);
  const y = (rows - 1) / 2 - row;
  return { x: x * 1.4, y: y * 1.0 };
}

function createTile(i, inst, cols, rows) {
  const pos = positionForIndex(i, cols, rows);
  const tile = document.createElement('a-entity');
  tile.setAttribute('class', 'tile');
  tile.setAttribute('position', `${pos.x} ${pos.y} -3`);
  tile.setAttribute('geometry', { primitive: 'plane', width: 1.2, height: 0.9 });
  tile.setAttribute('material', { color: '#222' });

  const video = document.createElement('video');
  video.setAttribute('src', inst.streamUrl || placeholderVideo);
  video.setAttribute('loop', 'true');
  video.setAttribute('crossorigin', 'anonymous');
  video.play();
  video.onerror = () => {
    if (video.src !== placeholderVideo) {
      video.src = placeholderVideo;
      video.play();
      infoSpan.textContent = 'Some streams unavailable';
    }
  };

  const aVideo = document.createElement('a-video');
  aVideo.setAttribute('width', 1.2);
  aVideo.setAttribute('height', 0.9);
  aVideo.setAttribute('src', video);
  aVideo.setAttribute('position', '0 0 0.01');
  tile.appendChild(aVideo);

  tile.addEventListener('click', () => setActive(i, video));

  return { tile, video };
}

function setActive(i, vid) {
  activeIndex = i;
  activeSpan.textContent = i + 1;
  document.querySelectorAll('.tile').forEach((t, idx) => {
    if (idx === i) {
      t.setAttribute('scale', '1.4 1.4 1');
      t.setAttribute('material', 'color', '#555');
    } else {
      t.setAttribute('scale', '1 1 1');
      t.setAttribute('material', 'color', '#222');
    }
  });
  document.querySelectorAll('.volume').forEach((v, idx) => {
    v.style.display = idx === i ? 'block' : 'none';
  });
  window.onkeydown = (e) => {
    if (activeIndex === i) {
      console.log('KVM event to tile', i + 1, e.key);
    }
  };
}

async function init() {
  const instances = await loadInstances();
  const count = instances.length;
  const cols = Math.ceil(Math.sqrt(count));
  const rows = Math.ceil(count / cols);

  instances.forEach((inst, i) => {
    const { tile, video } = createTile(i, inst, cols, rows);
    tilesContainer.appendChild(tile);
    const vol = document.createElement('input');
    vol.type = 'range';
    vol.min = 0;
    vol.max = 1;
    vol.step = 0.01;
    vol.value = 1;
    vol.className = 'volume';
    vol.style.position = 'absolute';
    vol.style.display = 'none';
    vol.style.left = `${10 + (i % cols) * 160}px`;
    vol.style.top = `${200 + Math.floor(i / cols) * 120}px`;
    vol.addEventListener('input', () => {
      video.volume = vol.value;
    });
    document.getElementById('ui').appendChild(vol);
  });

  if (count > 0) setActive(0);
}

init();
