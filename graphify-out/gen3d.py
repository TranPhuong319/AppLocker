import json, os
from pathlib import Path

graph_data = json.loads(Path('graphify-out/.graph3d_data.json').read_text(encoding='utf-8'))
graph_json = json.dumps(graph_data, ensure_ascii=False, separators=(',',':'))

html = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AppLocker — 3D Knowledge Graph</title>
<script src="https://unpkg.com/three@0.158.0/build/three.min.js"></script>
<script src="https://unpkg.com/3d-force-graph@1.73.2/dist/3d-force-graph.min.js"></script>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #020208; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; color: #e0e0ff; }
#graph { width: 100vw; height: 100vh; }

#hud { position: fixed; top: 0; left: 0; right: 0; z-index: 10; pointer-events: none; }
#title-bar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 16px 24px;
  background: linear-gradient(180deg, rgba(2,2,8,0.97) 0%, transparent 100%);
}
#title { font-size: 18px; font-weight: 700;
  background: linear-gradient(90deg, #a78bfa, #60a5fa, #34d399);
  -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
#stats { font-size: 12px; color: rgba(160,160,220,0.5); }

#sidebar {
  position: fixed; top: 0; right: 0; width: 300px; height: 100vh;
  background: rgba(4,4,18,0.9); backdrop-filter: blur(24px);
  border-left: 1px solid rgba(100,100,200,0.15);
  display: flex; flex-direction: column; z-index: 20;
  transition: transform 0.3s cubic-bezier(.4,0,.2,1);
}
#sidebar.hidden { transform: translateX(100%); }

#search-wrap { padding: 16px; border-bottom: 1px solid rgba(100,100,200,0.1); }
#search-label { font-size: 10px; color: rgba(160,160,220,0.35); text-transform: uppercase; letter-spacing: 1.2px; margin-bottom: 8px; }
#search {
  width: 100%; background: rgba(255,255,255,0.04);
  border: 1px solid rgba(100,100,200,0.2); color: #e0e0ff;
  padding: 8px 12px; border-radius: 8px; font-size: 13px; outline: none; transition: all 0.2s;
}
#search:focus { border-color: #a78bfa; background: rgba(167,139,250,0.06); }
#search::placeholder { color: rgba(160,160,220,0.2); }

#node-info { flex: 1; overflow-y: auto; padding: 14px; }
#node-info::-webkit-scrollbar { width: 3px; }
#node-info::-webkit-scrollbar-thumb { background: rgba(100,100,200,0.2); border-radius: 2px; }

.info-placeholder { color: rgba(160,160,220,0.2); font-size: 13px; text-align: center; margin-top: 50px; line-height: 2.2; }
.info-card { background: rgba(255,255,255,0.025); border: 1px solid rgba(100,100,200,0.12); border-radius: 10px; padding: 14px; margin-bottom: 10px; }
.info-card-title { font-size: 10px; color: rgba(160,160,220,0.35); text-transform: uppercase; letter-spacing: 1.2px; margin-bottom: 10px; }
.info-label { font-size: 15px; font-weight: 600; color: #e0e0ff; margin-bottom: 4px; word-break: break-all; }
.info-community { font-size: 12px; margin-top: 2px; }
.info-badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 10px; font-weight: 500; margin: 4px 3px 0 0; }
.code { background: rgba(52,211,153,0.1); color: #34d399; border: 1px solid rgba(52,211,153,0.18); }
.document { background: rgba(96,165,250,0.1); color: #60a5fa; border: 1px solid rgba(96,165,250,0.18); }
.image { background: rgba(251,146,60,0.1); color: #fb923c; border: 1px solid rgba(251,146,60,0.18); }
.concept { background: rgba(167,139,250,0.1); color: #a78bfa; border: 1px solid rgba(167,139,250,0.18); }
.rationale { background: rgba(244,114,182,0.1); color: #f472b6; border: 1px solid rgba(244,114,182,0.18); }
.info-source { font-size: 10px; color: rgba(160,160,220,0.25); margin-top: 8px; word-break: break-all; line-height: 1.5; }
.nb-item { font-size: 12px; color: rgba(200,200,255,0.7); padding: 5px 0; border-bottom: 1px solid rgba(100,100,200,0.07); display: flex; align-items: center; gap: 7px; cursor: pointer; transition: color 0.15s; }
.nb-item:last-child { border: none; }
.nb-item:hover { color: #a78bfa; }
.nb-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
.nb-rel { font-size: 10px; color: rgba(160,160,220,0.25); margin-left: auto; white-space: nowrap; }

#legend {
  position: fixed; bottom: 0; left: 0; width: 230px;
  background: rgba(4,4,18,0.88); backdrop-filter: blur(16px);
  border-top: 1px solid rgba(100,100,200,0.1); border-right: 1px solid rgba(100,100,200,0.1);
  border-radius: 0 14px 0 0; z-index: 20; padding: 14px;
  max-height: 42vh; overflow-y: auto;
}
#legend::-webkit-scrollbar { width: 3px; }
#legend::-webkit-scrollbar-thumb { background: rgba(100,100,200,0.15); border-radius: 2px; }
#legend-title { font-size: 10px; color: rgba(160,160,220,0.35); text-transform: uppercase; letter-spacing: 1.2px; margin-bottom: 10px; }
.leg-item { display: flex; align-items: center; gap: 8px; padding: 3px 0; cursor: pointer; transition: opacity 0.15s; }
.leg-item:hover { opacity: 0.75; }
.leg-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; box-shadow: 0 0 4px currentColor; }
.leg-name { font-size: 11px; color: rgba(200,200,255,0.6); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

#controls { position: fixed; bottom: 16px; right: 316px; display: flex; gap: 8px; z-index: 20; }
.ctrl-btn {
  background: rgba(4,4,18,0.88); backdrop-filter: blur(12px);
  border: 1px solid rgba(100,100,200,0.18); color: rgba(200,200,255,0.7);
  padding: 8px 14px; border-radius: 8px; font-size: 12px; cursor: pointer; transition: all 0.2s;
}
.ctrl-btn:hover { background: rgba(167,139,250,0.1); border-color: rgba(167,139,250,0.4); color: #a78bfa; }

#toggle-sidebar {
  position: fixed; top: 50%; right: 0; transform: translateY(-50%);
  background: rgba(4,4,18,0.88); backdrop-filter: blur(12px);
  border: 1px solid rgba(100,100,200,0.18); border-right: none; color: rgba(200,200,255,0.5);
  padding: 12px 7px; cursor: pointer; border-radius: 8px 0 0 8px; z-index: 25;
  writing-mode: vertical-rl; font-size: 10px; letter-spacing: 2px; text-transform: uppercase; transition: all 0.2s;
}
#toggle-sidebar:hover { color: #a78bfa; border-color: rgba(167,139,250,0.4); }

#loading {
  position: fixed; inset: 0; background: #020208;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  z-index: 100; gap: 20px; transition: opacity 0.6s;
}
#loading-title { font-size: 26px; font-weight: 700;
  background: linear-gradient(90deg, #a78bfa, #60a5fa, #34d399);
  -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
#loading-sub { font-size: 13px; color: rgba(160,160,220,0.35); }
.load-bar-wrap { width: 200px; height: 2px; background: rgba(100,100,200,0.1); border-radius: 2px; overflow: hidden; }
.load-bar { height: 40%; width: 40%; margin-top: 30%; background: linear-gradient(90deg, #a78bfa, #60a5fa); border-radius: 2px; animation: lpulse 1.4s linear infinite; }
@keyframes lpulse { 0% { transform: translateX(-100%); } 100% { transform: translateX(350%); } }

#tooltip {
  position: fixed; background: rgba(4,4,18,0.95); backdrop-filter: blur(12px);
  border: 1px solid rgba(100,100,200,0.2); border-radius: 8px;
  padding: 7px 11px; font-size: 12px; color: #e0e0ff;
  pointer-events: none; z-index: 30; display: none; max-width: 200px;
}
#tooltip b { display: block; margin-bottom: 2px; font-size: 13px; }
#tooltip small { color: rgba(160,160,220,0.4); font-size: 11px; }
</style>
</head>
<body>

<div id="loading">
  <div id="loading-title">AppLocker · 3D Graph</div>
  <div id="loading-sub">Simulating 1,161 nodes · 2,419 edges · 89 communities...</div>
  <div class="load-bar-wrap"><div class="load-bar"></div></div>
</div>

<div id="graph"></div>
<div id="tooltip"></div>

<div id="hud">
  <div id="title-bar">
    <div id="title">AppLocker — 3D Knowledge Graph</div>
    <div id="stats">1,161 nodes &nbsp;·&nbsp; 2,419 edges &nbsp;·&nbsp; 89 communities</div>
  </div>
</div>

<div id="sidebar">
  <div id="search-wrap">
    <div id="search-label">Search nodes</div>
    <input id="search" type="text" placeholder="Search functions, classes..." autocomplete="off">
  </div>
  <div id="node-info">
    <div class="info-placeholder">✦<br>Click any sphere<br>to explore it</div>
  </div>
</div>

<button id="toggle-sidebar" onclick="toggleSidebar()">Panel</button>

<div id="legend">
  <div id="legend-title">Communities</div>
  <div id="legend-list"></div>
</div>

<div id="controls">
  <button class="ctrl-btn" onclick="resetCamera()">⟳ Reset</button>
  <button class="ctrl-btn" id="rotate-btn" onclick="toggleRotate()">⏸ Pause</button>
  <button class="ctrl-btn" onclick="focusGodNodes()">⚡ God Nodes</button>
</div>

<script>
const GRAPH_DATA = """ + "GRAPH_JSON_PLACEHOLDER" + r""";

const adjMap = {};
GRAPH_DATA.links.forEach(l => {
  if (!adjMap[l.s]) adjMap[l.s] = [];
  if (!adjMap[l.t]) adjMap[l.t] = [];
  adjMap[l.s].push({id: l.t, rel: l.r});
  adjMap[l.t].push({id: l.s, rel: l.r});
});
const nodeMap = {};
GRAPH_DATA.nodes.forEach(n => { nodeMap[n.id] = n; });

// Legend
const legendList = document.getElementById('legend-list');
Object.entries(GRAPH_DATA.community_names).forEach(([cid, name]) => {
  const color = GRAPH_DATA.community_colors[cid] || '#888';
  const div = document.createElement('div');
  div.className = 'leg-item';
  div.title = name;
  div.innerHTML = `<div class="leg-dot" style="background:${color};box-shadow:0 0 5px ${color}55"></div><div class="leg-name">${name}</div>`;
  div.onclick = () => highlightCommunity(parseInt(cid));
  legendList.appendChild(div);
});

// ── THREE.js sphere factory ──────────────────────────────────────────────────
// Materials cache by color to avoid creating thousands of duplicate materials
const matCache = {};
function getMat(hexColor, emissive) {
  const key = hexColor + (emissive ? '1' : '0');
  if (!matCache[key]) {
    matCache[key] = new THREE.MeshPhongMaterial({
      color: new THREE.Color(hexColor),
      emissive: new THREE.Color(hexColor).multiplyScalar(emissive ? 0.35 : 0.05),
      specular: new THREE.Color(0x9999ff),
      shininess: emissive ? 120 : 60,
      transparent: false,
    });
  }
  return matCache[key];
}

const sphereGeo = {}; // cache geometry by radius
function getSphereGeo(r) {
  const key = r.toFixed(1);
  if (!sphereGeo[key]) sphereGeo[key] = new THREE.SphereGeometry(r, 16, 12);
  return sphereGeo[key];
}

// Degree map for god-node detection
const deg = {};
GRAPH_DATA.links.forEach(l => { deg[l.s] = (deg[l.s]||0)+1; deg[l.t] = (deg[l.t]||0)+1; });
const godList = Object.entries(deg).sort((a,b)=>b[1]-a[1]).slice(0,10).map(([id])=>id);
const godSet = new Set(godList);

// ── Build 3D graph ───────────────────────────────────────────────────────────
const Graph = ForceGraph3D({ antialias: true, alpha: false })(document.getElementById('graph'))
  .backgroundColor('#020208')
  .nodeId('id')
  .nodeLabel(n => `<div style="background:rgba(2,2,8,0.97);border:1px solid rgba(100,100,200,0.3);border-radius:7px;padding:7px 12px;font-size:12px;color:#e0e0ff;pointer-events:none"><b>${n.label}</b><br><small style="color:rgba(160,160,220,0.4)">${n.community_name}</small></div>`)
  // 🔑 Custom Three.js sphere per node
  .nodeThreeObject(n => {
    const isGod = godSet.has(n.id);
    const r = Math.max(2, Math.min(n.val * 1.4, isGod ? 14 : 9));
    const mesh = new THREE.Mesh(getSphereGeo(r), getMat(n.color, isGod));
    // Glow halo for god nodes
    if (isGod) {
      const haloGeo = new THREE.SphereGeometry(r * 1.6, 16, 12);
      const haloMat = new THREE.MeshBasicMaterial({
        color: new THREE.Color(n.color),
        transparent: true, opacity: 0.08, side: THREE.BackSide
      });
      mesh.add(new THREE.Mesh(haloGeo, haloMat));
    }
    mesh.__nodeId = n.id;
    return mesh;
  })
  .nodeThreeObjectExtend(false)
  // Links
  .linkColor(() => 'rgba(80,100,220,0.18)')
  .linkWidth(0.5)
  .linkOpacity(1)
  .linkCurvature(0.1)
  .graphData({
    nodes: GRAPH_DATA.nodes,
    links: GRAPH_DATA.links.map(l => ({ source: l.s, target: l.t, relation: l.r }))
  })
  .onNodeClick(handleNodeClick)
  .onNodeHover(handleNodeHover)
  .onBackgroundClick(clearSelection)
  .onEngineStop(() => {
    const el = document.getElementById('loading');
    el.style.opacity = '0';
    setTimeout(() => el.style.display = 'none', 600);
    // Add scene lights after engine has renderer
    addLights();
  });

// ── Lighting ─────────────────────────────────────────────────────────────────
function addLights() {
  const scene = Graph.scene();
  if (!scene || scene.__lightsAdded) return;
  scene.__lightsAdded = true;

  // Ambient — base fill
  scene.add(new THREE.AmbientLight(0x222244, 1.2));

  // Key light (top-left blue-white)
  const key = new THREE.DirectionalLight(0x8888ff, 2.0);
  key.position.set(400, 600, 400);
  scene.add(key);

  // Fill light (bottom-right warm)
  const fill = new THREE.DirectionalLight(0xaa88ff, 0.8);
  fill.position.set(-400, -300, 200);
  scene.add(fill);

  // Rim light (behind, deep blue)
  const rim = new THREE.DirectionalLight(0x4466ff, 0.6);
  rim.position.set(0, -200, -800);
  scene.add(rim);

  // Point light at center (warm purple glow)
  const center = new THREE.PointLight(0x7755ff, 0.6, 1200);
  center.position.set(0, 0, 0);
  scene.add(center);
}

// ── Auto rotate ───────────────────────────────────────────────────────────────
let rotating = true, rotAngle = 0;
function tick() {
  if (rotating) {
    rotAngle += 0.0012;
    Graph.cameraPosition({ x: 950 * Math.sin(rotAngle), z: 950 * Math.cos(rotAngle) });
  }
  requestAnimationFrame(tick);
}
tick();

function toggleRotate() {
  rotating = !rotating;
  document.getElementById('rotate-btn').textContent = rotating ? '⏸ Pause' : '▶ Rotate';
}
function resetCamera() {
  rotating = false;
  document.getElementById('rotate-btn').textContent = '▶ Rotate';
  Graph.cameraPosition({ x: 0, y: 0, z: 1300 }, { x:0,y:0,z:0 }, 1000);
  clearSelection();
}

// ── Node interaction ─────────────────────────────────────────────────────────
function focusGodNodes() {
  rotating = false;
  document.getElementById('rotate-btn').textContent = '▶ Rotate';
  applyHighlight(new Set(godList), null);
  const gn = Graph.graphData().nodes.find(n => n.id === godList[0]);
  if (gn) {
    const d = 400;
    Graph.cameraPosition({ x:(gn.x||0)+d, y:(gn.y||0)+50, z:(gn.z||0)+d },
      { x:gn.x||0, y:gn.y||0, z:gn.z||0 }, 1200);
  }
  showNodeInfo(nodeMap[godList[0]]);
}

function handleNodeClick(node) {
  rotating = false;
  document.getElementById('rotate-btn').textContent = '▶ Rotate';
  const r = 1 + 180 / Math.hypot(node.x||1, node.y||1, node.z||1);
  Graph.cameraPosition(
    { x:(node.x||0)*r, y:(node.y||0)*r, z:(node.z||0)*r },
    { x:node.x||0, y:node.y||0, z:node.z||0 }, 700
  );
  const nbSet = new Set((adjMap[node.id]||[]).map(x=>x.id));
  nbSet.add(node.id);
  applyHighlight(nbSet, node.id);
  showNodeInfo(node);
}

function handleNodeHover(node) {
  const tt = document.getElementById('tooltip');
  document.getElementById('graph').style.cursor = node ? 'pointer' : 'default';
  if (node) {
    tt.style.display = 'block';
    tt.innerHTML = `<b>${node.label}</b><small>${node.community_name}</small>`;
    document.onmousemove = e => {
      tt.style.left = (e.clientX + 14) + 'px';
      tt.style.top = (e.clientY - 8) + 'px';
    };
  } else {
    tt.style.display = 'none';
    document.onmousemove = null;
  }
}

// ── Highlight system ─────────────────────────────────────────────────────────
// Instead of recreating materials per node (expensive), we just call Graph.nodeColor
// and let the nodeThreeObject handle colour via material.color updates via refresh.
// Simpler: toggle opacity on nodeThreeObject meshes via nodeColor passthrough.
function applyHighlight(activeSet, centerId) {
  Graph.nodeColor(n => {
    if (centerId && n.id === centerId) return '#ffffff';
    if (activeSet.has(n.id)) return n.color;
    return 'rgba(30,30,60,0.08)';
  });
  Graph.nodeVal(n => {
    if (centerId && n.id === centerId) return n.val * 3;
    if (activeSet.has(n.id)) return n.val * 1.2;
    return n.val * 0.25;
  });
  Graph.linkColor(l => {
    const sid = typeof l.source==='object' ? l.source.id : l.source;
    const tid = typeof l.target==='object' ? l.target.id : l.target;
    const isActive = (centerId && (sid===centerId || tid===centerId)) ||
      (!centerId && activeSet.has(sid) && activeSet.has(tid));
    return isActive ? 'rgba(167,139,250,0.75)' : 'rgba(40,40,80,0.04)';
  });
  Graph.linkWidth(l => {
    const sid = typeof l.source==='object' ? l.source.id : l.source;
    const tid = typeof l.target==='object' ? l.target.id : l.target;
    return (centerId && (sid===centerId||tid===centerId)) ? 1.8 : 0.2;
  });
}

function clearSelection() {
  Graph.nodeColor(n => n.color);
  Graph.nodeVal(n => n.val);
  Graph.linkColor(() => 'rgba(80,100,220,0.18)');
  Graph.linkWidth(() => 0.5);
  document.getElementById('node-info').innerHTML =
    '<div class="info-placeholder">✦<br>Click any sphere<br>to explore it</div>';
}

function highlightCommunity(cid) {
  rotating = false;
  document.getElementById('rotate-btn').textContent = '▶ Rotate';
  const active = new Set(GRAPH_DATA.nodes.filter(n=>n.community===cid).map(n=>n.id));
  applyHighlight(active, null);
}

function showNodeInfo(node) {
  const nbs = adjMap[node.id] || [];
  const ft = node.file_type || 'code';
  document.getElementById('node-info').innerHTML = `
    <div class="info-card">
      <div class="info-card-title">Selected Node</div>
      <div class="info-label">${node.label}</div>
      <div class="info-community" style="color:${node.color}">${node.community_name}</div>
      <div style="margin-top:8px">
        <span class="info-badge ${ft}">${ft}</span>
        <span class="info-badge concept">${nbs.length} connections</span>
        ${godSet.has(node.id) ? '<span class="info-badge rationale">⚡ God Node</span>' : ''}
      </div>
      ${node.source_file ? `<div class="info-source">📄 ${node.source_file}</div>` : ''}
    </div>
    <div class="info-card">
      <div class="info-card-title">Connected (${nbs.length})</div>
      ${nbs.slice(0,20).map(nb => {
        const nn = nodeMap[nb.id]; if (!nn) return '';
        return `<div class="nb-item" onclick="handleNodeClick(nodeMap['${nb.id}'])">
          <div class="nb-dot" style="background:${nn.color}"></div>
          <span>${nn.label}</span><span class="nb-rel">${nb.rel}</span></div>`;
      }).join('')}
      ${nbs.length > 20 ? `<div style="font-size:10px;color:rgba(160,160,220,0.2);text-align:center;padding-top:8px">+${nbs.length-20} more</div>` : ''}
    </div>`;
}

// Search
document.getElementById('search').addEventListener('input', function() {
  const q = this.value.trim().toLowerCase();
  if (!q) { clearSelection(); return; }
  const hits = GRAPH_DATA.nodes.filter(n => n.label.toLowerCase().includes(q) || n.id.includes(q));
  if (!hits.length) return;
  const hitSet = new Set(hits.map(n=>n.id));
  applyHighlight(hitSet, hits.length===1 ? hits[0].id : null);
  if (hits.length === 1) handleNodeClick(hits[0]);
});

function toggleSidebar() {
  document.getElementById('sidebar').classList.toggle('hidden');
}
</script>
</body>
</html>"""

html = html.replace("GRAPH_JSON_PLACEHOLDER", graph_json)
Path('graphify-out/graph3d.html').write_text(html, encoding='utf-8')
size = os.path.getsize('graphify-out/graph3d.html')
print(f'Written: graphify-out/graph3d.html ({size/1024:.0f} KB)')
