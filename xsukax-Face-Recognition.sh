#!/usr/bin/env bash
# xsukax Face Recognition Installer

set -Eeuo pipefail

APP_NAME="face-recognition-app"
APP_DIR="${HOME}/${APP_NAME}"
BASE_PORT="${PORT:-3000}"
NODE_MIN_MAJOR=18
MODELS_URL_BASE="https://vladmandic.github.io/face-api/model"

log(){ printf "%b\n" "$*"; }
die(){ printf "❌ %s\n" "$*" >&2; exit 1; }
on_err(){ echo "💥 Error on line $1"; } ; trap 'on_err $LINENO' ERR

usage(){ cat <<EOF
Usage: $0 [--dir PATH] [--port N] [--no-install]
  --dir PATH     Target directory (default: $APP_DIR)
  --port N       Base port to try (default: $BASE_PORT)
  --no-install   Skip apt/dnf/yum install (assume deps present)
EOF
}

NEED_INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) APP_DIR="$2"; shift 2;;
    --port) BASE_PORT="$2"; shift 2;;
    --no-install) NEED_INSTALL=0; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

install_deps(){
  if [[ "$NEED_INSTALL" -eq 0 ]]; then return; fi
  if command -v apt-get >/dev/null 2>&1; then
    log "📦 Installing deps via APT…"
    sudo apt-get update -y
    sudo apt-get install -y \
      curl wget git ca-certificates build-essential python3 python3-pip \
      pkg-config libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev \
      sqlite3 iproute2
  elif command -v dnf >/dev/null 2>&1; then
    log "📦 Installing deps via DNF…"
    sudo dnf -y groupinstall "Development Tools"
    sudo dnf -y install \
      curl wget git ca-certificates python3 python3-pip \
      cairo-devel pango-devel libjpeg-turbo-devel giflib-devel librsvg2-devel \
      sqlite iproute
  elif command -v yum >/dev/null 2>&1; then
    log "📦 Installing deps via YUM…"
    sudo yum -y groupinstall "Development Tools"
    sudo yum -y install \
      curl wget git ca-certificates python3 python3-pip \
      cairo-devel pango-devel libjpeg-turbo-devel giflib-devel librsvg2-devel \
      sqlite iproute
  else
    log "⚠️ No known package manager — ensure build tools, Python 3, cairo/pango/jpeg/gif, sqlite & iproute are installed."
  fi

  # Node.js LTS (18+) if missing or too old
  local NODE_MAJ=0
  if command -v node >/dev/null 2>&1; then NODE_MAJ=$(node -v | sed 's/v//' | cut -d. -f1); fi
  if (( NODE_MAJ < NODE_MIN_MAJOR )); then
    log "⬇️ Installing Node.js LTS (18.x)…"
    if command -v apt-get >/dev/null 2>&1; then
      curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
      sudo apt-get install -y nodejs
    elif command -v dnf >/dev/null 2>&1; then
      curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
      sudo dnf -y install nodejs
    elif command -v yum >/dev/null 2>&1; then
      curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
      sudo yum -y install nodejs
    else
      die "Please install Node.js ${NODE_MIN_MAJOR}+ manually."
    fi
  fi
}

find_free_port() {
  local base="${1:-3000}"
  local p
  for ((p=base; p<base+100; p++)); do
    if command -v ss >/dev/null 2>&1; then
      if ! ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
        printf '%s' "$p"; return 0
      fi
    else
      if ! netstat -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"; then
        printf '%s' "$p"; return 0
      fi
    fi
  done
  return 1
}

download_models(){
  local mdir="$APP_DIR/models"
  mkdir -p "$mdir"
  APP_DIR="$APP_DIR" MODELS_URL_BASE="$MODELS_URL_BASE" python3 - <<'PY'
import json, os, urllib.request
base = os.environ.get("MODELS_URL_BASE", "https://vladmandic.github.io/face-api/model")
mdir = os.path.join(os.environ.get("APP_DIR", "."), "models")
os.makedirs(mdir, exist_ok=True)

manifests = [
  "ssd_mobilenetv1_model-weights_manifest.json",
  "face_landmark_68_model-weights_manifest.json",
  "face_recognition_model-weights_manifest.json",
]

def fetch(url: str) -> bytes:
  req = urllib.request.Request(url, headers={"User-Agent": "curl/7.88"})
  with urllib.request.urlopen(req, timeout=60) as r:
    if r.status != 200:
      raise RuntimeError(f"HTTP {r.status} for {url}")
    return r.read()

def iter_paths_from_manifest(mdata):
  # Support dict {"weights":[{"paths":[...]}]} OR list [{"paths":[...]}] OR flat list
  if isinstance(mdata, dict):
    for g in mdata.get("weights", []):
      if isinstance(g, dict):
        for p in g.get("paths") or g.get("files") or []:
          if isinstance(p, str): yield p
  elif isinstance(mdata, list):
    for g in mdata:
      if isinstance(g, dict):
        for p in g.get("paths") or g.get("files") or []:
          if isinstance(p, str): yield p
      elif isinstance(g, str):
        yield g

for man in manifests:
  murl = f"{base}/{man}"
  print(f"⤵️ Download {murl}")
  mdata = json.loads(fetch(murl).decode("utf-8", "ignore"))
  with open(os.path.join(mdir, man), "wb") as f:
    f.write(json.dumps(mdata).encode())

  any_paths = False
  for rel in iter_paths_from_manifest(mdata):
    any_paths = True
    shard_url = f"{base}/{rel}"
    dst = os.path.join(mdir, os.path.basename(rel))
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
      print(f"   • exists {os.path.basename(dst)}")
      continue
    print(f"   • {shard_url}")
    with open(dst, "wb") as f:
      f.write(fetch(shard_url))
  if not any_paths:
    raise RuntimeError(f"No shard paths found in manifest {man}")
print("✅ Models ready at", mdir)
PY
}

scaffold_app(){
  mkdir -p "$APP_DIR"
  cd "$APP_DIR"

  cat > package.json <<'JSON'
{
  "name": "face-recognition-app",
  "version": "2.0.0",
  "private": true,
  "type": "module",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "@tensorflow/tfjs-node": "^4.22.0",
    "@vladmandic/face-api": "1.7.15",
    "better-sqlite3": "^9.6.0",
    "canvas": "^2.11.2",
    "express": "^4.21.2",
    "multer": "^2.0.0",
    "marked": "^9.1.6"
  }
}
JSON

  cat > server.js <<'JS'
import fs from 'fs';
import path from 'path';
import express from 'express';
import multer from 'multer';
import Database from 'better-sqlite3';
import { createWriteStream } from 'fs';
import crypto from 'crypto';

import * as faceapi from '@vladmandic/face-api';
import { createCanvas, Image, Canvas, loadImage } from 'canvas';
import { marked } from 'marked';

// Try native TF; fall back to CPU-JS
let backend = 'cpu-js';
try { await import('@tensorflow/tfjs-node'); backend='tensorflow'; } catch {}

const __dirname = path.resolve();
faceapi.env.monkeyPatch({ Canvas, Image, createCanvas });

const app = express();
const PORT = process.env.PORT || 3000;

const DATA_DIR = path.join(__dirname, 'data');
const MODELS_DIR = path.join(__dirname, 'models');
const UPLOADS_DIR = path.join(__dirname, 'uploads');
const IMAGES_DIR = path.join(__dirname, 'person_images');

fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(UPLOADS_DIR, { recursive: true });
fs.mkdirSync(IMAGES_DIR, { recursive: true });

const db = new Database(path.join(DATA_DIR, 'faces.db'));
db.exec(`
CREATE TABLE IF NOT EXISTS persons (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  notes TEXT DEFAULT '',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS person_images (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  person_id INTEGER NOT NULL,
  descriptor TEXT NOT NULL,
  filename TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(person_id) REFERENCES persons(id) ON DELETE CASCADE
);
CREATE TRIGGER IF NOT EXISTS update_persons_timestamp 
AFTER UPDATE ON persons FOR EACH ROW
BEGIN
  UPDATE persons SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
`);

const FACE_MATCH_THRESHOLD = 0.52;
let modelsLoaded = false;

// Configure marked for safe HTML
marked.setOptions({
  breaks: true,
  gfm: true
});

async function loadModels() {
  if (modelsLoaded) return;
  await faceapi.nets.ssdMobilenetv1.loadFromDisk(MODELS_DIR);
  await faceapi.nets.faceLandmark68Net.loadFromDisk(MODELS_DIR);
  await faceapi.nets.faceRecognitionNet.loadFromDisk(MODELS_DIR);
  modelsLoaded = true;
  console.log('✅ Models loaded');
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15*1024*1024, files: 20 },
  fileFilter: (req, file, cb) => file.mimetype.startsWith('image/') ? cb(null,true) : cb(new Error('Only image/* allowed'))
});

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
app.use('/person_images', express.static(IMAGES_DIR));

// Simple session storage for admin auth
const adminSessions = new Set();
const ADMIN_PASSWORD = 'xsukax';

// Admin authentication middleware
function requireAuth(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token || !adminSessions.has(token)) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  next();
}

// Health check
app.get('/api/health', async (_,res)=>{
  res.json({ status:'ok', modelsLoaded, backend, timestamp: new Date().toISOString(), version:'2.0.0' });
});

// Admin login
app.post('/api/admin/login', (req, res) => {
  const { password } = req.body;
  if (password === ADMIN_PASSWORD) {
    const token = crypto.randomUUID();
    adminSessions.add(token);
    res.json({ success: true, token });
  } else {
    res.status(401).json({ error: 'Invalid password' });
  }
});

// Admin logout
app.post('/api/admin/logout', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (token) adminSessions.delete(token);
  res.json({ success: true });
});

// Get persons count (protected)
app.get('/api/persons/count', requireAuth, (_,res)=>{
  const total = db.prepare('SELECT COUNT(*) as n FROM persons').get().n;
  res.json({ total });
});

// Get all persons with their image count (protected)
app.get('/api/persons', requireAuth, (_,res)=>{
  const persons = db.prepare(`
    SELECT p.*, COUNT(pi.id) as image_count 
    FROM persons p 
    LEFT JOIN person_images pi ON p.id = pi.person_id 
    GROUP BY p.id 
    ORDER BY p.updated_at DESC
  `).all();
  res.json({ persons });
});

// Get specific person with images (protected)
app.get('/api/person/:id', requireAuth, (req,res)=>{
  const person = db.prepare('SELECT * FROM persons WHERE id = ?').get(req.params.id);
  if (!person) return res.status(404).json({ error: 'Person not found' });
  
  const images = db.prepare('SELECT id, filename, created_at FROM person_images WHERE person_id = ?').all(req.params.id);
  res.json({ person, images });
});

// Update person (protected)
app.put('/api/person/:id', requireAuth, (req, res) => {
  try {
    const { name, notes } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Name is required' });
    
    const existing = db.prepare('SELECT id FROM persons WHERE name = ? AND id != ?').get(name.trim(), req.params.id);
    if (existing) return res.status(400).json({ error: 'Person with this name already exists' });
    
    const updated = db.prepare('UPDATE persons SET name = ?, notes = ? WHERE id = ?').run(name.trim(), notes || '', req.params.id);
    if (updated.changes === 0) return res.status(404).json({ error: 'Person not found' });
    
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: `Update failed: ${err.message}` });
  }
});

// Delete person (protected)
app.delete('/api/person/:id', requireAuth, (req, res) => {
  try {
    const images = db.prepare('SELECT filename FROM person_images WHERE person_id = ?').all(req.params.id);
    
    // Delete image files
    images.forEach(img => {
      const imgPath = path.join(IMAGES_DIR, img.filename);
      if (fs.existsSync(imgPath)) fs.unlinkSync(imgPath);
    });
    
    const deleted = db.prepare('DELETE FROM persons WHERE id = ?').run(req.params.id);
    if (deleted.changes === 0) return res.status(404).json({ error: 'Person not found' });
    
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: `Delete failed: ${err.message}` });
  }
});

async function descriptorFromBuffer(buf) {
  const img = await loadImage(buf);
  const cv = createCanvas(img.width, img.height);
  const ctx = cv.getContext('2d'); 
  ctx.drawImage(img,0,0);
  const det = await faceapi.detectSingleFace(cv).withFaceLandmarks().withFaceDescriptor();
  if (!det) throw new Error('No face detected');
  return Array.from(det.descriptor);
}

function saveImageFile(buffer, originalName) {
  const ext = path.extname(originalName) || '.jpg';
  const filename = crypto.randomUUID() + ext;
  const filepath = path.join(IMAGES_DIR, filename);
  fs.writeFileSync(filepath, buffer);
  return filename;
}

// Add person (protected)
app.post('/api/person', requireAuth, upload.array('images', 10), async (req,res)=>{
  try{
    await loadModels();
    const name = (req.body?.name || '').trim();
    const notes = req.body?.notes || '';
    const files = req.files || [];
    if (!name || files.length===0) return res.status(400).json({ error:'Name and at least one image are required' });

    // Check for duplicate name
    const existing = db.prepare('SELECT id FROM persons WHERE name = ?').get(name);
    if (existing) return res.status(400).json({ error: 'Person with this name already exists' });

    const insertP = db.prepare('INSERT INTO persons (name, notes) VALUES (?, ?)');
    const personId = insertP.run(name, notes).lastInsertRowid;

    const insertImg = db.prepare('INSERT INTO person_images (person_id, descriptor, filename) VALUES (?, ?, ?)');
    for (const f of files) {
      const desc = await descriptorFromBuffer(f.buffer);
      const filename = saveImageFile(f.buffer, f.originalname);
      insertImg.run(personId, JSON.stringify(desc), filename);
    }
    const count = db.prepare('SELECT COUNT(*) AS c FROM person_images WHERE person_id=?').get(personId).c;
    res.json({ success:true, personId, name, notes, images: count });
  }catch(err){
    res.status(500).json({ error:`Add person failed: ${err.message}` });
  }
});

// Add images to existing person (protected)
app.post('/api/person/:id/images', requireAuth, upload.array('images', 10), async (req, res) => {
  try {
    await loadModels();
    const files = req.files || [];
    if (!files.length) return res.status(400).json({ error: 'At least one image is required' });
    
    const person = db.prepare('SELECT id FROM persons WHERE id = ?').get(req.params.id);
    if (!person) return res.status(404).json({ error: 'Person not found' });
    
    const insertImg = db.prepare('INSERT INTO person_images (person_id, descriptor, filename) VALUES (?, ?, ?)');
    let added = 0;
    
    for (const f of files) {
      try {
        const desc = await descriptorFromBuffer(f.buffer);
        const filename = saveImageFile(f.buffer, f.originalname);
        insertImg.run(req.params.id, JSON.stringify(desc), filename);
        added++;
      } catch (e) {
        console.warn(`Failed to process image ${f.originalname}:`, e.message);
      }
    }
    
    res.json({ success: true, added });
  } catch (err) {
    res.status(500).json({ error: `Add images failed: ${err.message}` });
  }
});

function l2(a,b){ let s=0; for(let i=0;i<a.length;i++){ const d=a[i]-b[i]; s+=d*d; } return Math.sqrt(s); }

// Search for person
app.post('/api/search', upload.single('searchImage'), async (req,res)=>{
  try{
    await loadModels();
    if (!req.file) return res.status(400).json({ error:'searchImage required' });
    const query = await descriptorFromBuffer(req.file.buffer);
    const rows = db.prepare('SELECT person_id, descriptor FROM person_images').all();

    let best = { person_id:null, dist: Infinity };
    for (const r of rows) {
      const cand = JSON.parse(r.descriptor);
      const d = l2(query, cand);
      if (d < best.dist) best = { person_id: r.person_id, dist: d };
    }
    if (best.person_id===null) return res.json({ matches:[], message:'No faces enrolled' });

    if (best.dist <= FACE_MATCH_THRESHOLD) {
      const person = db.prepare('SELECT * FROM persons WHERE id=?').get(best.person_id);
      const images = db.prepare('SELECT filename FROM person_images WHERE person_id=? LIMIT 5').all(best.person_id);
      res.json({ 
        matches: [{ 
          id: person.id, 
          name: person.name, 
          notes: person.notes,
          notesHtml: person.notes ? marked(person.notes) : '',
          distance: best.dist,
          images: images.map(img => `/person_images/${img.filename}`)
        }], 
        threshold: FACE_MATCH_THRESHOLD 
      });
    } else {
      res.json({ matches: [], threshold: FACE_MATCH_THRESHOLD, message: 'No match found' });
    }
  }catch(err){
    res.status(500).json({ error:`Search failed: ${err.message}` });
  }
});

// Serve user interface
app.get('/', (_, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

// Serve admin interface  
app.get('/admin', (_, res) => res.sendFile(path.join(__dirname, 'public', 'admin.html')));

// Catch all other routes
app.get('*', (_, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));

await loadModels().catch(e=>console.error('Model load error:', e));
app.listen(PORT,'0.0.0.0', ()=>{
  console.log(`🌐 User Interface: http://0.0.0.0:${PORT}`);
  console.log(`🛠️  Admin Panel: http://0.0.0.0:${PORT}/admin`);
});
JS

  mkdir -p public

  # User Search Interface
  cat > public/index.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>xsukax Face Recognition Search</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
  background: linear-gradient(135deg, #0c0c0c 0%, #1a1a1a 100%);
  color: #ffffff;
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
}
.container {
  max-width: 800px;
  width: 100%;
  padding: 40px 20px;
}
.header {
  text-align: center;
  margin-bottom: 60px;
}
.header h1 {
  font-size: 3rem;
  font-weight: 300;
  background: linear-gradient(135deg, #ff6b6b, #4ecdc4, #45b7d1);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 10px;
  letter-spacing: -2px;
}
.header p {
  font-size: 1.1rem;
  color: #888;
  font-weight: 300;
}
.search-card {
  background: rgba(255, 255, 255, 0.03);
  backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 24px;
  padding: 48px;
  box-shadow: 0 25px 50px rgba(0, 0, 0, 0.3);
}
.upload-area {
  border: 2px dashed rgba(255, 255, 255, 0.2);
  border-radius: 16px;
  padding: 48px 24px;
  text-align: center;
  margin-bottom: 32px;
  cursor: pointer;
  transition: all 0.3s ease;
  background: rgba(255, 255, 255, 0.02);
}
.upload-area:hover {
  border-color: rgba(77, 182, 172, 0.5);
  background: rgba(77, 182, 172, 0.05);
  transform: translateY(-2px);
}
.upload-area.dragover {
  border-color: #4db6ac;
  background: rgba(77, 182, 172, 0.1);
}
.upload-icon {
  font-size: 4rem;
  margin-bottom: 16px;
  opacity: 0.7;
}
.upload-text {
  font-size: 1.2rem;
  margin-bottom: 8px;
  color: #ccc;
}
.upload-hint {
  color: #888;
  font-size: 0.9rem;
}
.file-input {
  position: absolute;
  opacity: 0;
  width: 0;
  height: 0;
}
.search-btn {
  width: 100%;
  padding: 18px;
  background: linear-gradient(135deg, #ff6b6b, #4ecdc4);
  border: none;
  border-radius: 12px;
  color: white;
  font-size: 1.1rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
  margin-bottom: 24px;
}
.search-btn:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 15px 30px rgba(78, 205, 196, 0.3);
}
.search-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.result {
  display: none;
  animation: slideUp 0.5s ease;
}
@keyframes slideUp {
  from { opacity: 0; transform: translateY(30px); }
  to { opacity: 1; transform: translateY(0); }
}
.result.success {
  background: rgba(76, 175, 80, 0.1);
  border: 1px solid rgba(76, 175, 80, 0.3);
  border-radius: 16px;
  padding: 32px;
}
.result.error {
  background: rgba(244, 67, 54, 0.1);
  border: 1px solid rgba(244, 67, 54, 0.3);
  border-radius: 16px;
  padding: 24px;
  color: #ff6b6b;
}
.person-card {
  display: flex;
  gap: 24px;
  align-items: flex-start;
}
.person-info {
  flex: 1;
}
.person-name {
  font-size: 2rem;
  font-weight: 600;
  margin-bottom: 16px;
  color: #4ecdc4;
}
.person-notes {
  background: rgba(255, 255, 255, 0.05);
  padding: 16px;
  border-radius: 12px;
  margin-bottom: 20px;
  line-height: 1.6;
}
.person-notes h1, .person-notes h2, .person-notes h3 {
  color: #4ecdc4;
  margin: 16px 0 8px 0;
}
.person-notes h1 { font-size: 1.5rem; }
.person-notes h2 { font-size: 1.3rem; }
.person-notes h3 { font-size: 1.1rem; }
.person-notes p { margin-bottom: 12px; }
.person-notes ul, .person-notes ol { 
  margin: 8px 0 12px 20px; 
}
.person-notes li { margin-bottom: 4px; }
.person-notes blockquote {
  border-left: 3px solid #4ecdc4;
  padding-left: 16px;
  margin: 12px 0;
  font-style: italic;
  color: #ccc;
}
.person-notes code {
  background: rgba(255, 255, 255, 0.1);
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'Monaco', 'Consolas', monospace;
  font-size: 0.9em;
}
.person-notes pre {
  background: rgba(255, 255, 255, 0.1);
  padding: 12px;
  border-radius: 8px;
  overflow-x: auto;
  margin: 12px 0;
}
.person-notes a {
  color: #4ecdc4;
  text-decoration: underline;
}
.person-notes strong { color: #fff; }
.person-notes em { color: #ddd; }
.match-confidence {
  font-size: 0.9rem;
  color: #888;
  background: rgba(255, 255, 255, 0.05);
  padding: 8px 12px;
  border-radius: 8px;
  display: inline-block;
}
.person-images {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 12px;
  margin-top: 24px;
}
.person-images img {
  width: 100%;
  height: 120px;
  object-fit: cover;
  border-radius: 12px;
  border: 2px solid rgba(255, 255, 255, 0.1);
  transition: transform 0.3s ease;
}
.person-images img:hover {
  transform: scale(1.05);
  border-color: #4ecdc4;
}
.admin-link {
  position: fixed;
  top: 24px;
  right: 24px;
  background: rgba(255, 255, 255, 0.1);
  color: white;
  text-decoration: none;
  padding: 12px 20px;
  border-radius: 25px;
  font-size: 0.9rem;
  transition: all 0.3s ease;
  backdrop-filter: blur(10px);
}
.admin-link:hover {
  background: rgba(255, 255, 255, 0.2);
  transform: translateY(-2px);
}
.loading {
  display: none;
  text-align: center;
  padding: 20px;
}
.spinner {
  border: 3px solid rgba(255, 255, 255, 0.1);
  border-top: 3px solid #4ecdc4;
  border-radius: 50%;
  width: 40px;
  height: 40px;
  animation: spin 1s linear infinite;
  margin: 0 auto 16px;
}
@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
</style>
</head>
<body>
<a href="/admin" class="admin-link">🛠️ Admin Panel</a>
<div class="container">
  <div class="header">
    <h1>xsukax Face Recognition</h1>
    <p>Upload a photo to search for a person in our database</p>
  </div>
  
  <div class="search-card">
    <div class="upload-area" id="uploadArea">
      <div class="upload-icon">📷</div>
      <div class="upload-text">Click or drag to upload image</div>
      <div class="upload-hint">Supports JPG, PNG, GIF up to 15MB</div>
      <input type="file" id="searchImage" class="file-input" accept="image/*" />
    </div>
    
    <button id="searchBtn" class="search-btn" disabled>Search Person</button>
    
    <div id="loading" class="loading">
      <div class="spinner"></div>
      <div>Analyzing image...</div>
    </div>
    
    <div id="result" class="result"></div>
  </div>
</div>

<script>
(function() {
  const uploadArea = document.getElementById('uploadArea');
  const fileInput = document.getElementById('searchImage');
  const searchBtn = document.getElementById('searchBtn');
  const result = document.getElementById('result');
  const loading = document.getElementById('loading');

  // Upload area interactions
  uploadArea.addEventListener('click', () => fileInput.click());
  uploadArea.addEventListener('dragover', (e) => {
    e.preventDefault();
    uploadArea.classList.add('dragover');
  });
  uploadArea.addEventListener('dragleave', () => {
    uploadArea.classList.remove('dragover');
  });
  uploadArea.addEventListener('drop', (e) => {
    e.preventDefault();
    uploadArea.classList.remove('dragover');
    const files = e.dataTransfer.files;
    if (files.length && files[0].type.startsWith('image/')) {
      fileInput.files = files;
      updateUploadArea();
    }
  });

  fileInput.addEventListener('change', updateUploadArea);

  function updateUploadArea() {
    const file = fileInput.files[0];
    if (file) {
      uploadArea.innerHTML = `
        <div class="upload-icon">✅</div>
        <div class="upload-text">${file.name}</div>
        <div class="upload-hint">Ready to search</div>
      `;
      searchBtn.disabled = false;
    } else {
      searchBtn.disabled = true;
    }
  }

  searchBtn.addEventListener('click', async () => {
    const file = fileInput.files[0];
    if (!file) return;

    loading.style.display = 'block';
    result.style.display = 'none';
    searchBtn.disabled = true;

    try {
      const formData = new FormData();
      formData.append('searchImage', file);
      
      const response = await fetch('/api/search', {
        method: 'POST',
        body: formData
      });
      
      const data = await response.json();
      
      if (!response.ok) throw new Error(data.error || 'Search failed');
      
      if (data.matches && data.matches.length > 0) {
        const person = data.matches[0];
        result.className = 'result success';
        result.innerHTML = `
          <div class="person-card">
            <div class="person-info">
              <div class="person-name">${person.name}</div>
              ${person.notesHtml ? `<div class="person-notes">${person.notesHtml}</div>` : ''}
              <div class="match-confidence">Match Confidence: ${(100 - person.distance * 100).toFixed(1)}%</div>
            </div>
          </div>
          ${person.images && person.images.length ? `
            <div class="person-images">
              ${person.images.map(img => `<img src="${img}" alt="Person image" />`).join('')}
            </div>
          ` : ''}
        `;
      } else {
        result.className = 'result error';
        result.innerHTML = `
          <div style="text-align: center;">
            <div style="font-size: 3rem; margin-bottom: 16px;">❌</div>
            <div style="font-size: 1.2rem; margin-bottom: 8px;">No Match Found</div>
            <div>This person is not in our database.</div>
          </div>
        `;
      }
    } catch (error) {
      result.className = 'result error';
      result.innerHTML = `
        <div style="text-align: center;">
          <div style="font-size: 3rem; margin-bottom: 16px;">⚠️</div>
          <div style="font-size: 1.2rem; margin-bottom: 8px;">Search Error</div>
          <div>${error.message}</div>
        </div>
      `;
    } finally {
      loading.style.display = 'none';
      result.style.display = 'block';
      searchBtn.disabled = false;
    }
  });
})();
</script>
</body>
</html>
EOF

  # Admin Control Panel
  cat > public/admin.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>xsukax Face Recognition - Admin Panel</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: linear-gradient(135deg, #0a0a0a 0%, #1a1a1a 100%);
  color: #ffffff;
  min-height: 100vh;
}

/* Login Page */
.login-container {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}
.login-card {
  background: rgba(255, 255, 255, 0.05);
  backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 24px;
  padding: 48px;
  width: 100%;
  max-width: 400px;
  text-align: center;
  box-shadow: 0 25px 50px rgba(0, 0, 0, 0.3);
}
.login-logo {
  font-size: 4rem;
  margin-bottom: 16px;
}
.login-title {
  font-size: 2rem;
  font-weight: 300;
  background: linear-gradient(135deg, #ff6b6b, #4ecdc4);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 8px;
}
.login-subtitle {
  color: #888;
  margin-bottom: 32px;
}
.login-form {
  text-align: left;
}

/* Main App */
.app-container {
  display: none;
}
.navbar {
  background: rgba(0, 0, 0, 0.8);
  backdrop-filter: blur(20px);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  padding: 16px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.logo {
  font-size: 1.5rem;
  font-weight: 600;
  background: linear-gradient(135deg, #ff6b6b, #4ecdc4);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}
.nav-links a {
  color: #ccc;
  text-decoration: none;
  margin: 0 16px;
  transition: color 0.3s;
}
.nav-links a:hover { color: #4ecdc4; }
.logout-btn {
  background: rgba(255, 107, 107, 0.2);
  color: #ff6b6b;
  border: 1px solid rgba(255, 107, 107, 0.3);
  padding: 8px 16px;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s;
}
.logout-btn:hover {
  background: rgba(255, 107, 107, 0.3);
}
.container {
  max-width: 1400px;
  margin: 0 auto;
  padding: 40px 24px;
}
.dashboard {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 32px;
  margin-bottom: 48px;
}
.card {
  background: rgba(255, 255, 255, 0.05);
  backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 20px;
  padding: 32px;
  transition: transform 0.3s ease;
}
.card:hover { transform: translateY(-4px); }
.card h3 {
  font-size: 1.5rem;
  margin-bottom: 24px;
  color: #4ecdc4;
}
.form-group {
  margin-bottom: 20px;
}
.form-group label {
  display: block;
  margin-bottom: 8px;
  font-weight: 500;
  color: #ddd;
}
input[type="text"], input[type="password"], textarea, input[type="file"] {
  width: 100%;
  padding: 14px;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 12px;
  color: white;
  font-size: 1rem;
  transition: all 0.3s ease;
}
input[type="text"]:focus, input[type="password"]:focus, textarea:focus {
  outline: none;
  border-color: #4ecdc4;
  box-shadow: 0 0 0 3px rgba(78, 205, 196, 0.2);
}
textarea {
  resize: vertical;
  min-height: 100px;
  font-family: 'Monaco', 'Consolas', 'Courier New', monospace;
}
.markdown-editor {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-top: 8px;
}
.markdown-input {
  position: relative;
}
.markdown-toolbar {
  display: flex;
  gap: 8px;
  margin-bottom: 8px;
  flex-wrap: wrap;
}
.md-btn {
  padding: 4px 8px;
  background: rgba(255, 255, 255, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 6px;
  color: #ccc;
  cursor: pointer;
  font-size: 0.8rem;
  transition: all 0.2s;
}
.md-btn:hover {
  background: rgba(78, 205, 196, 0.2);
  border-color: #4ecdc4;
}
.markdown-preview {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 12px;
  padding: 14px;
  min-height: 150px;
  color: #eee;
  line-height: 1.6;
}
.markdown-preview h1, .markdown-preview h2, .markdown-preview h3 {
  color: #4ecdc4;
  margin: 12px 0 6px 0;
}
.markdown-preview h1 { font-size: 1.4rem; }
.markdown-preview h2 { font-size: 1.2rem; }
.markdown-preview h3 { font-size: 1rem; }
.markdown-preview p { margin-bottom: 10px; }
.markdown-preview ul, .markdown-preview ol { 
  margin: 6px 0 10px 18px; 
}
.markdown-preview li { margin-bottom: 3px; }
.markdown-preview blockquote {
  border-left: 3px solid #4ecdc4;
  padding-left: 12px;
  margin: 10px 0;
  font-style: italic;
  color: #bbb;
}
.markdown-preview code {
  background: rgba(255, 255, 255, 0.1);
  padding: 2px 5px;
  border-radius: 3px;
  font-family: 'Monaco', 'Consolas', monospace;
  font-size: 0.85em;
}
.markdown-preview pre {
  background: rgba(255, 255, 255, 0.1);
  padding: 10px;
  border-radius: 6px;
  overflow-x: auto;
  margin: 10px 0;
}
.markdown-preview a {
  color: #4ecdc4;
  text-decoration: underline;
}
.markdown-preview strong { color: #fff; }
.markdown-preview em { color: #ddd; }
.preview-label {
  font-size: 0.9rem;
  color: #888;
  margin-bottom: 8px;
}
@media (max-width: 768px) {
  .markdown-editor {
    grid-template-columns: 1fr;
  }
}
.btn {
  padding: 14px 28px;
  border: none;
  border-radius: 12px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
  font-size: 1rem;
}
.btn-primary {
  background: linear-gradient(135deg, #4ecdc4, #44a08d);
  color: white;
}
.btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 10px 25px rgba(78, 205, 196, 0.3);
}
.btn-danger {
  background: linear-gradient(135deg, #ff6b6b, #ee5a52);
  color: white;
}
.btn-danger:hover {
  transform: translateY(-2px);
  box-shadow: 0 10px 25px rgba(255, 107, 107, 0.3);
}
.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  transform: none !important;
}
.persons-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
  gap: 24px;
  margin-top: 32px;
}
.person-card {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 16px;
  padding: 24px;
  transition: all 0.3s ease;
}
.person-card:hover {
  border-color: rgba(78, 205, 196, 0.3);
  transform: translateY(-2px);
}
.person-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 16px;
}
.person-name {
  font-size: 1.3rem;
  font-weight: 600;
  color: #4ecdc4;
  margin-bottom: 4px;
}
.person-meta {
  font-size: 0.9rem;
  color: #888;
}
.person-notes {
  background: rgba(255, 255, 255, 0.05);
  padding: 12px;
  border-radius: 8px;
  margin-bottom: 16px;
  font-size: 0.9rem;
  line-height: 1.4;
}
.person-actions {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.btn-small {
  padding: 8px 16px;
  font-size: 0.85rem;
  border-radius: 8px;
}

/* Modal System */
.modal {
  display: none;
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background: rgba(0, 0, 0, 0.8);
  z-index: 1000;
  backdrop-filter: blur(5px);
  animation: modalFadeIn 0.3s ease;
}
@keyframes modalFadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}
.modal-content {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background: #1a1a1a;
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 20px;
  padding: 32px;
  max-width: 600px;
  width: 90%;
  max-height: 80vh;
  overflow-y: auto;
  animation: modalSlideIn 0.3s ease;
}
@keyframes modalSlideIn {
  from { opacity: 0; transform: translate(-50%, -60%); }
  to { opacity: 1; transform: translate(-50%, -50%); }
}
.modal h3 {
  margin-bottom: 24px;
  color: #4ecdc4;
}
.close {
  position: absolute;
  top: 16px;
  right: 20px;
  font-size: 28px;
  cursor: pointer;
  color: #888;
  transition: color 0.3s;
}
.close:hover { color: #fff; }

/* Message Modal */
.message-modal .modal-content {
  max-width: 400px;
  text-align: center;
}
.message-icon {
  font-size: 4rem;
  margin-bottom: 16px;
}
.message-icon.success { color: #4caf50; }
.message-icon.error { color: #ff6b6b; }
.message-title {
  font-size: 1.3rem;
  margin-bottom: 12px;
  font-weight: 600;
}
.message-text {
  color: #ccc;
  line-height: 1.5;
  margin-bottom: 24px;
}
.message-btn {
  background: linear-gradient(135deg, #4ecdc4, #44a08d);
  color: white;
  border: none;
  padding: 12px 24px;
  border-radius: 8px;
  cursor: pointer;
  font-weight: 600;
  transition: all 0.3s;
}
.message-btn:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 20px rgba(78, 205, 196, 0.3);
}

/* Confirm Modal */
.confirm-modal .modal-content {
  max-width: 450px;
  text-align: center;
}
.confirm-buttons {
  display: flex;
  gap: 16px;
  justify-content: center;
  margin-top: 24px;
}
.confirm-btn {
  padding: 12px 20px;
  border: none;
  border-radius: 8px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s;
}
.confirm-btn.cancel {
  background: rgba(255, 255, 255, 0.1);
  color: #ccc;
}
.confirm-btn.cancel:hover {
  background: rgba(255, 255, 255, 0.2);
}
.confirm-btn.delete {
  background: linear-gradient(135deg, #ff6b6b, #ee5a52);
  color: white;
}
.confirm-btn.delete:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 20px rgba(255, 107, 107, 0.3);
}

.loading {
  display: none;
  text-align: center;
  padding: 20px;
}
.spinner {
  border: 3px solid rgba(255, 255, 255, 0.1);
  border-top: 3px solid #4ecdc4;
  border-radius: 50%;
  width: 40px;
  height: 40px;
  animation: spin 1s linear infinite;
  margin: 0 auto 16px;
}
@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
</style>
</head>
<body>

<!-- Login Screen -->
<div id="loginContainer" class="login-container">
  <div class="login-card">
    <div class="login-logo">🛠️</div>
    <h1 class="login-title">Admin Access</h1>
    <p class="login-subtitle">Enter password to continue</p>
    <form id="loginForm" class="login-form">
      <div class="form-group">
        <label>Password</label>
        <input type="password" id="loginPassword" required placeholder="Enter admin password" />
      </div>
      <button type="submit" class="btn btn-primary">🔓 Access Admin Panel</button>
      <div id="loginLoading" class="loading">
        <div class="spinner"></div>
        <div>Authenticating...</div>
      </div>
    </form>
  </div>
</div>

<!-- Main Admin App -->
<div id="appContainer" class="app-container">
  <div class="navbar">
    <div class="logo">🛠️ Admin Panel</div>
    <div class="nav-links">
      <a href="/">🔍 Search</a>
      <span id="totalPersons" style="color: #888;">Loading...</span>
      <button class="logout-btn" onclick="logout()">🚪 Logout</button>
    </div>
  </div>

  <div class="container">
    <div class="dashboard">
      <div class="card">
        <h3>➕ Add New Person</h3>
        <form id="addPersonForm">
          <div class="form-group">
            <label>Full Name *</label>
            <input type="text" id="personName" required />
          </div>
          <div class="form-group">
            <label>Notes (Markdown supported)</label>
            <div class="markdown-editor">
              <div class="markdown-input">
                <div class="markdown-toolbar">
                  <button type="button" class="md-btn" onclick="insertMd('**', '**', 'bold text')">**Bold**</button>
                  <button type="button" class="md-btn" onclick="insertMd('*', '*', 'italic')">*Italic*</button>
                  <button type="button" class="md-btn" onclick="insertMd('### ', '', 'Heading')">### H3</button>
                  <button type="button" class="md-btn" onclick="insertMd('> ', '', 'Quote')">Quote</button>
                  <button type="button" class="md-btn" onclick="insertMd('- ', '', 'List item')">• List</button>
                  <button type="button" class="md-btn" onclick="insertMd('`', '`', 'code')">`Code`</button>
                </div>
                <textarea id="personNotes" placeholder="Use **bold**, *italic*, ### headings, > quotes, - lists, and `code`..."></textarea>
              </div>
              <div>
                <div class="preview-label">Preview:</div>
                <div id="notesPreview" class="markdown-preview">Start typing to see preview...</div>
              </div>
            </div>
          </div>
          <div class="form-group">
            <label>Photos *</label>
            <input type="file" id="personImages" multiple accept="image/*" required />
          </div>
          <button type="submit" class="btn btn-primary">Add Person</button>
          <div id="addLoading" class="loading">
            <div class="spinner"></div>
            <div>Processing images...</div>
          </div>
        </form>
      </div>

      <div class="card" style="display: flex; flex-direction: column; justify-content: center; align-items: center; text-align: center;">
        <h3>📊 Database Stats</h3>
        <div style="font-size: 3rem; margin: 16px 0; color: #4ecdc4;" id="personCount">-</div>
        <div style="font-size: 1.1rem; color: #888;">Total Persons</div>
        <button class="btn btn-primary" style="margin-top: 24px;" onclick="refreshData()">🔄 Refresh</button>
      </div>
    </div>

    <div id="personsSection">
      <h2 style="margin-bottom: 24px; color: #4ecdc4;">👥 Manage Persons</h2>
      <div id="personsGrid" class="persons-grid"></div>
    </div>
  </div>
</div>

<!-- Edit Person Modal -->
<div id="editModal" class="modal">
  <div class="modal-content">
    <span class="close" onclick="closeModal('editModal')">&times;</span>
    <h3>✏️ Edit Person</h3>
    <form id="editPersonForm">
      <div class="form-group">
        <label>Full Name *</label>
        <input type="text" id="editName" required />
      </div>
      <div class="form-group">
        <label>Notes (Markdown supported)</label>
        <div class="markdown-editor">
          <div class="markdown-input">
            <div class="markdown-toolbar">
              <button type="button" class="md-btn" onclick="insertEditMd('**', '**', 'bold text')">**Bold**</button>
              <button type="button" class="md-btn" onclick="insertEditMd('*', '*', 'italic')">*Italic*</button>
              <button type="button" class="md-btn" onclick="insertEditMd('### ', '', 'Heading')">### H3</button>
              <button type="button" class="md-btn" onclick="insertEditMd('> ', '', 'Quote')">Quote</button>
              <button type="button" class="md-btn" onclick="insertEditMd('- ', '', 'List item')">• List</button>
              <button type="button" class="md-btn" onclick="insertEditMd('`', '`', 'code')">`Code`</button>
            </div>
            <textarea id="editNotes" placeholder="Use markdown formatting..."></textarea>
          </div>
          <div>
            <div class="preview-label">Preview:</div>
            <div id="editNotesPreview" class="markdown-preview">Start typing to see preview...</div>
          </div>
        </div>
      </div>
      <div class="form-group">
        <label>Add More Photos</label>
        <input type="file" id="editImages" multiple accept="image/*" />
      </div>
      <div style="display: flex; gap: 12px;">
        <button type="submit" class="btn btn-primary">💾 Save Changes</button>
        <button type="button" class="btn btn-danger" onclick="confirmDelete()">🗑️ Delete Person</button>
      </div>
      <div id="editLoading" class="loading">
        <div class="spinner"></div>
        <div>Saving changes...</div>
      </div>
    </form>
  </div>
</div>

<!-- Message Modal -->
<div id="messageModal" class="modal message-modal">
  <div class="modal-content">
    <div id="messageIcon" class="message-icon"></div>
    <div id="messageTitle" class="message-title"></div>
    <div id="messageText" class="message-text"></div>
    <button class="message-btn" onclick="closeModal('messageModal')">OK</button>
  </div>
</div>

<!-- Confirm Modal -->
<div id="confirmModal" class="modal confirm-modal">
  <div class="modal-content">
    <div class="message-icon error">⚠️</div>
    <div class="message-title">Confirm Delete</div>
    <div class="message-text">Are you sure you want to delete this person? This action cannot be undone and will remove all associated images.</div>
    <div class="confirm-buttons">
      <button class="confirm-btn cancel" onclick="closeModal('confirmModal')">Cancel</button>
      <button class="confirm-btn delete" onclick="deletePerson()">Delete Person</button>
    </div>
  </div>
</div>

<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/9.1.6/marked.min.js"></script>
<script>
(function() {
  let currentEditId = null;
  let authToken = localStorage.getItem('adminToken');

  // Check if user is already logged in
  if (authToken) {
    checkAuth();
  }

  // Modal system
  function showModal(modalId) {
    document.getElementById(modalId).style.display = 'block';
  }

  function closeModal(modalId) {
    document.getElementById(modalId).style.display = 'none';
  }

  window.closeModal = closeModal;

  // Message system
  function showMessage(text, type, title = null) {
    const modal = document.getElementById('messageModal');
    const icon = document.getElementById('messageIcon');
    const titleEl = document.getElementById('messageTitle');
    const textEl = document.getElementById('messageText');
    
    icon.className = `message-icon ${type}`;
    icon.textContent = type === 'success' ? '✅' : '❌';
    titleEl.textContent = title || (type === 'success' ? 'Success' : 'Error');
    textEl.textContent = text;
    
    showModal('messageModal');
  }

  // Authentication
  async function checkAuth() {
    try {
      const response = await fetch('/api/persons/count', {
        headers: { Authorization: `Bearer ${authToken}` }
      });
      
      if (response.ok) {
        showApp();
        refreshData();
      } else {
        logout();
      }
    } catch (error) {
      logout();
    }
  }

  function showApp() {
    document.getElementById('loginContainer').style.display = 'none';
    document.getElementById('appContainer').style.display = 'block';
  }

  function showLogin() {
    document.getElementById('loginContainer').style.display = 'flex';
    document.getElementById('appContainer').style.display = 'none';
  }

  window.logout = function() {
    localStorage.removeItem('adminToken');
    authToken = null;
    showLogin();
  };

  // Login form
  document.getElementById('loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const password = document.getElementById('loginPassword').value;
    const loading = document.getElementById('loginLoading');
    
    loading.style.display = 'block';
    
    try {
      const response = await fetch('/api/admin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password })
      });
      
      const data = await response.json();
      
      if (response.ok) {
        authToken = data.token;
        localStorage.setItem('adminToken', authToken);
        showApp();
        refreshData();
      } else {
        showMessage(data.error || 'Invalid password', 'error', 'Access Denied');
      }
    } catch (error) {
      showMessage('Connection error. Please try again.', 'error', 'Connection Failed');
    } finally {
      loading.style.display = 'none';
    }
  });

  // API helper with auth
  async function apiCall(url, options = {}) {
    const headers = {
      ...options.headers,
      Authorization: `Bearer ${authToken}`
    };
    
    const response = await fetch(url, { ...options, headers });
    
    if (response.status === 401) {
      logout();
      throw new Error('Authentication required');
    }
    
    return response;
  }

  // Markdown parsing
  function parseMarkdown(text) {
    if (!text.trim()) return 'Start typing to see preview...';
    return marked.parse(text);
  }

  // Markdown editor functions
  function insertMd(before, after, placeholder) {
    const textarea = document.getElementById('personNotes');
    insertMarkdown(textarea, before, after, placeholder);
    updatePreview('personNotes', 'notesPreview');
  }

  function insertEditMd(before, after, placeholder) {
    const textarea = document.getElementById('editNotes');
    insertMarkdown(textarea, before, after, placeholder);
    updatePreview('editNotes', 'editNotesPreview');
  }

  function insertMarkdown(textarea, before, after, placeholder) {
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const selectedText = textarea.value.substring(start, end);
    const textToInsert = selectedText || placeholder;
    
    const newText = textarea.value.substring(0, start) + 
                   before + textToInsert + after + 
                   textarea.value.substring(end);
    
    textarea.value = newText;
    textarea.focus();
    
    if (!selectedText) {
      textarea.setSelectionRange(start + before.length, start + before.length + placeholder.length);
    } else {
      textarea.setSelectionRange(start + before.length + textToInsert.length + after.length, start + before.length + textToInsert.length + after.length);
    }
  }

  function updatePreview(textareaId, previewId) {
    const text = document.getElementById(textareaId).value;
    const preview = document.getElementById(previewId);
    preview.innerHTML = parseMarkdown(text);
  }

  // Initialize markdown editors
  document.getElementById('personNotes').addEventListener('input', () => {
    updatePreview('personNotes', 'notesPreview');
  });

  document.getElementById('editNotes').addEventListener('input', () => {
    updatePreview('editNotes', 'editNotesPreview');
  });

  // Make functions global
  window.insertMd = insertMd;
  window.insertEditMd = insertEditMd;

  // Add person form
  document.getElementById('addPersonForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const name = document.getElementById('personName').value.trim();
    const notes = document.getElementById('personNotes').value.trim();
    const files = document.getElementById('personImages').files;
    
    if (!name || !files.length) {
      showMessage('Name and at least one image are required', 'error');
      return;
    }
    
    const loading = document.getElementById('addLoading');
    loading.style.display = 'block';
    
    try {
      const formData = new FormData();
      formData.append('name', name);
      formData.append('notes', notes);
      for (let file of files) {
        formData.append('images', file);
      }
      
      const response = await apiCall('/api/person', {
        method: 'POST',
        body: formData
      });
      
      const data = await response.json();
      
      if (!response.ok) throw new Error(data.error || 'Failed to add person');
      
      showMessage(`Successfully added ${data.name} with ${data.images} images`, 'success', 'Person Added');
      document.getElementById('addPersonForm').reset();
      updatePreview('personNotes', 'notesPreview');
      refreshData();
    } catch (error) {
      showMessage(error.message, 'error');
    } finally {
      loading.style.display = 'none';
    }
  });

  // Edit person form
  document.getElementById('editPersonForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const name = document.getElementById('editName').value.trim();
    const notes = document.getElementById('editNotes').value.trim();
    const files = document.getElementById('editImages').files;
    
    if (!name) {
      showMessage('Name is required', 'error');
      return;
    }
    
    const loading = document.getElementById('editLoading');
    loading.style.display = 'block';
    
    try {
      // Update person info
      const response = await apiCall(`/api/person/${currentEditId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, notes })
      });
      
      if (!response.ok) {
        const data = await response.json();
        throw new Error(data.error || 'Failed to update person');
      }
      
      // Add new images if any
      if (files.length > 0) {
        const formData = new FormData();
        for (let file of files) {
          formData.append('images', file);
        }
        
        const imgResponse = await apiCall(`/api/person/${currentEditId}/images`, {
          method: 'POST',
          body: formData
        });
        
        if (imgResponse.ok) {
          const imgData = await imgResponse.json();
          showMessage(`Updated person and added ${imgData.added} new images`, 'success', 'Person Updated');
        } else {
          showMessage('Person updated but failed to add some images', 'error');
        }
      } else {
        showMessage('Person updated successfully', 'success', 'Changes Saved');
      }
      
      closeModal('editModal');
      refreshData();
    } catch (error) {
      showMessage(error.message, 'error');
    } finally {
      loading.style.display = 'none';
    }
  });

  // Delete confirmation
  window.confirmDelete = function() {
    showModal('confirmModal');
  };

  window.deletePerson = async function() {
    try {
      const response = await apiCall(`/api/person/${currentEditId}`, {
        method: 'DELETE'
      });
      
      if (!response.ok) {
        const data = await response.json();
        throw new Error(data.error || 'Failed to delete person');
      }
      
      showMessage('Person deleted successfully', 'success', 'Person Deleted');
      closeModal('confirmModal');
      closeModal('editModal');
      refreshData();
    } catch (error) {
      showMessage(error.message, 'error');
    }
  };

  async function refreshData() {
    if (!authToken) return;
    
    try {
      const [countResponse, personsResponse] = await Promise.all([
        apiCall('/api/persons/count'),
        apiCall('/api/persons')
      ]);
      
      const countData = await countResponse.json();
      const personsData = await personsResponse.json();
      
      document.getElementById('personCount').textContent = countData.total;
      document.getElementById('totalPersons').textContent = `${countData.total} persons`;
      
      renderPersons(personsData.persons);
    } catch (error) {
      console.error('Failed to refresh data:', error);
    }
  }

  function renderPersons(persons) {
    const grid = document.getElementById('personsGrid');
    grid.innerHTML = persons.map(person => `
      <div class="person-card">
        <div class="person-header">
          <div>
            <div class="person-name">${person.name}</div>
            <div class="person-meta">${person.image_count} images • Added ${new Date(person.created_at).toLocaleDateString()}</div>
          </div>
        </div>
        ${person.notes ? `<div class="person-notes">${person.notes}</div>` : ''}
        <div class="person-actions">
          <button class="btn btn-primary btn-small" onclick="editPerson(${person.id})">✏️ Edit</button>
        </div>
      </div>
    `).join('');
  }

  window.editPerson = async (id) => {
    try {
      const response = await apiCall(`/api/person/${id}`);
      const data = await response.json();
      
      if (!response.ok) throw new Error(data.error || 'Failed to load person');
      
      currentEditId = id;
      document.getElementById('editName').value = data.person.name;
      document.getElementById('editNotes').value = data.person.notes || '';
      document.getElementById('editImages').value = '';
      
      updatePreview('editNotes', 'editNotesPreview');
      showModal('editModal');
    } catch (error) {
      showMessage(error.message, 'error');
    }
  };

  window.refreshData = refreshData;
})();
</script>
</body>
</html>
EOF
}

install_node_modules(){
  cd "$APP_DIR"
  rm -rf node_modules package-lock.json >/dev/null 2>&1 || true
  npm i
}

start_app(){
  cd "$APP_DIR" || exit 1
  local attempt=0
  while (( attempt < 10 )); do
    local p
    if ! p="$(find_free_port "$BASE_PORT")"; then
      die "No free port found starting at $BASE_PORT"
    fi
    export PORT="$p"
    log "▶️ Starting server on free port: $PORT"

    : > server.log
    PORT="$PORT" node server.js > server.log 2>&1 &
    local pid=$!

    # Wait up to ~15s per attempt for health
    for i in {1..15}; do
      sleep 1
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      if curl -sf "http://127.0.0.1:$PORT/api/health" | grep -q '"modelsLoaded":true'; then
        local ip
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || ip="localhost"
        [[ -z "$ip" ]] && ip="localhost"
        log "✅ Ready!"
        log "🔍 User Interface: http://$ip:$PORT"
        log "🛠️  Admin Panel: http://$ip:$PORT/admin"
        log "🔐 Admin Password: xsukax"
        return 0
      fi
    done

    if grep -q 'EADDRINUSE' server.log; then
      log "♻️ Port $PORT got busy, retrying…"
      (( attempt++ ))
      continue
    fi

    log "⚠️ Server exited unexpectedly. Check logs:"
    log "   tail -n +1 -f $APP_DIR/server.log"
    return 1
  done
  die "Could not start the server after multiple attempts."
}

# ------------------------ run ------------------------
log "🚀 xsukax Face Recognition installer"
log "📁 Target dir: $APP_DIR"
log "🌐 Base port:  $BASE_PORT"

mkdir -p "$APP_DIR"/{data,uploads,models,public,person_images}
install_deps
scaffold_app
download_models
install_node_modules
start_app