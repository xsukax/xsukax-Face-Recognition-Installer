# 🎯 xsukax Face Recognition Web Application Installer

[![Node.js](https://img.shields.io/badge/Node.js-18+-green.svg)](https://nodejs.org/)
[![Express.js](https://img.shields.io/badge/Express.js-4.21+-blue.svg)](https://expressjs.com/)
[![TensorFlow.js](https://img.shields.io/badge/TensorFlow.js-4.22+-orange.svg)](https://www.tensorflow.org/js)

A sophisticated, AI-powered face recognition web application with modern UI/UX design, featuring separate user and admin interfaces, markdown-supported notes, and advanced person management capabilities.

## 📸 Screenshots

![](https://raw.githubusercontent.com/xsukax/xsukax-Face-Recognition-Installer/refs/heads/main/ScreenShots/Homepage.jpg)
![](https://raw.githubusercontent.com/xsukax/xsukax-Face-Recognition-Installer/refs/heads/main/ScreenShots/Search-Result.jpg)
![](https://raw.githubusercontent.com/xsukax/xsukax-Face-Recognition-Installer/refs/heads/main/ScreenShots/AdminCP.jpg)
![](https://raw.githubusercontent.com/xsukax/xsukax-Face-Recognition-Installer/refs/heads/main/ScreenShots/AdminCP-Person-Manager.jpg)

```
[User Interface] - [Admin Panel] - [Search Results]
```

## ✨ Features

### 🔍 **User Search Interface**
- **Modern Glassmorphism Design** - Luxurious dark theme with glass effects
- **Drag & Drop Upload** - Intuitive image upload with visual feedback
- **Real-time Face Recognition** - Powered by TensorFlow.js and face-api.js
- **Rich Search Results** - Display person's name, notes, and up to 5 images
- **Responsive Design** - Perfect on desktop, tablet, and mobile devices

### 🛠️ **Admin Control Panel**
- **Secure Authentication** - Password-protected admin access
- **Complete Person Management** - Add, edit, delete persons with full CRUD operations
- **Markdown Editor** - Live preview notes editor with formatting toolbar
- **Multiple Image Support** - Upload and manage multiple photos per person
- **Duplicate Prevention** - Database-level unique name constraints
- **Beautiful Modal System** - Ad-blocker friendly custom modals instead of popups

### 🧠 **AI & Technology**
- **Advanced Face Detection** - Using SSD MobileNet v1 for face detection
- **Face Landmark Recognition** - 68-point facial landmark detection
- **Face Descriptors** - 128-dimensional face embeddings for matching
- **High Accuracy Matching** - Configurable similarity thresholds
- **Real-time Processing** - Fast inference with TensorFlow.js

### 📝 **Data Management**
- **SQLite Database** - Lightweight, embedded database
- **Image Storage** - Organized file system with UUID-based naming
- **Markdown Support** - Rich text formatting for person notes
- **Data Integrity** - Foreign key constraints and triggers
- **Backup Ready** - Simple file-based backup and restore

## 🚀 Quick Start

### Prerequisites
- **Node.js 18+**
- **Linux/macOS/WSL** (for native dependencies)
- **Build tools** (automatically installed by script)

### One-Command Installation
```bash
# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/face-recognition-app/main/install.sh | bash

# Or clone and run locally
git clone https://github.com/YOUR_USERNAME/face-recognition-app.git
cd face-recognition-app
chmod +x install.sh
./install.sh
```

### Manual Installation Options
```bash
# Custom directory
./install.sh --dir /custom/path

# Custom port
./install.sh --port 8080

# Skip dependency installation
./install.sh --no-install

# Help
./install.sh --help
```

## 💡 Usage

### 🔍 User Search
1. Navigate to `http://localhost:3000`
2. Upload a photo by clicking or dragging to the upload area
3. Click "Search Person" to find matching faces
4. View detailed results with person info and images

### 🛠️ Admin Panel
1. Go to `http://localhost:3000/admin`
2. Enter password: `xsukax`
3. **Add Person**: Name + Notes + Multiple Images
4. **Manage Database**: Edit, delete, and organize persons
5. **Markdown Notes**: Use rich formatting for detailed descriptions

### 📝 Markdown Formatting
The notes field supports full Markdown syntax:

```markdown
### John Smith
**Role**: Senior Developer  
*Department*: Engineering

> "Innovation distinguishes between a leader and a follower"

**Skills:**
- JavaScript & Python
- Machine Learning
- `React.js` & `Node.js`

**Contact:** john@company.com
```

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User Interface│    │  Admin Panel    │    │   AI Models     │
│                 │    │                 │    │                 │
│ • Search        │    │ • Authentication│    │ • Face Detection│
│ • Results       │    │ • CRUD Ops      │    │ • Landmarks     │
│ • Responsive    │    │ • Markdown Edit │    │ • Recognition   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                        ┌─────────────────┐
                        │   Backend API   │
                        │                 │
                        │ • Express.js    │
                        │ • Authentication│
                        │ • File Upload   │
                        │ • Face Analysis │
                        └─────────────────┘
                                 │
                        ┌─────────────────┐
                        │   Data Layer    │
                        │                 │
                        │ • SQLite DB     │
                        │ • File Storage  │
                        │ • Face Vectors  │
                        └─────────────────┘
```

## 🔧 Configuration

### Environment Variables
```bash
PORT=3000                    # Server port
NODE_ENV=production          # Environment mode
FACE_MATCH_THRESHOLD=0.52    # Similarity threshold (lower = stricter)
```

### Default Settings
- **Admin Password**: `xsukax` (change in `server.js`)
- **Max File Size**: 15MB per image
- **Max Files**: 10 images per upload
- **Supported Formats**: JPG, PNG, GIF
- **Match Threshold**: 0.52 (adjustable)

## 📚 API Documentation

### Authentication
```bash
# Login
POST /api/admin/login
Content-Type: application/json
{
  "password": "xsukax"
}

# Logout
POST /api/admin/logout
Authorization: Bearer <token>
```

### Person Management
```bash
# Add person
POST /api/person
Authorization: Bearer <token>
Content-Type: multipart/form-data

# Get all persons
GET /api/persons
Authorization: Bearer <token>

# Update person
PUT /api/person/:id
Authorization: Bearer <token>
Content-Type: application/json

# Delete person
DELETE /api/person/:id
Authorization: Bearer <token>
```

### Face Search
```bash
# Search by image
POST /api/search
Content-Type: multipart/form-data
Form field: searchImage (file)

Response:
{
  "matches": [{
    "id": 1,
    "name": "John Doe",
    "notes": "...",
    "notesHtml": "<p>...</p>",
    "distance": 0.45,
    "images": ["/person_images/uuid.jpg"]
  }],
  "threshold": 0.52
}
```

## 🎨 Customization

### Themes & Styling
- Modern glassmorphism design with dark gradient backgrounds
- CSS custom properties for easy color scheme changes
- Responsive grid layouts and flexbox components
- Smooth animations and hover effects

### Face Recognition Tuning
```javascript
// Adjust in server.js
const FACE_MATCH_THRESHOLD = 0.52;  // Lower = stricter matching

// Model configuration
await faceapi.nets.ssdMobilenetv1.loadFromDisk(MODELS_DIR);
await faceapi.nets.faceLandmark68Net.loadFromDisk(MODELS_DIR);  
await faceapi.nets.faceRecognitionNet.loadFromDisk(MODELS_DIR);
```

## 🔒 Security Features

- **Password Authentication** for admin access
- **Session Management** with secure tokens
- **File Type Validation** for uploaded images
- **SQL Injection Protection** with prepared statements
- **XSS Prevention** with sanitized HTML output
- **CSRF Protection** with proper headers

## 🚦 Performance

- **Fast Inference**: TensorFlow.js with optimized models
- **Efficient Storage**: UUID-based file organization
- **Database Indexing**: Optimized SQLite schema
- **Responsive Design**: Mobile-first approach
- **Lazy Loading**: Efficient resource management

## 🧪 Development

### Local Development
```bash
# Clone repository
git clone https://github.com/xsukax/xsukax-Face-Recognition-Installer.git
cd xsukax-Face-Recognition-Installer

# Install dependencies
npm install

# Start development server
npm start

# Run with custom port
PORT=8080 npm start
```

### Project Structure
```
face-recognition-app/
├── install.sh              # One-click installer script
├── server.js               # Main Express.js server
├── package.json            # Dependencies and scripts
├── public/                 # Frontend assets
│   ├── index.html          # User search interface
│   └── admin.html          # Admin control panel
├── models/                 # AI model files
├── data/                   # SQLite database
├── person_images/          # Stored person photos
└── uploads/               # Temporary upload directory
```

## 🐛 Troubleshooting

### Common Issues

**Port Already in Use**
```bash
# The installer automatically finds free ports
# Or specify a custom port:
./install.sh --port 8080
```

**Models Not Loading**
```bash
# Check model directory and re-download:
rm -rf models/
./install.sh  # Will re-download models
```

**Face Detection Issues**
- Ensure good image quality and lighting
- Face should be clearly visible and front-facing
- Supported formats: JPG, PNG, GIF
- Maximum file size: 15MB

**Database Errors**
```bash
# Reset database (loses all data):
rm -rf data/
# Restart application to recreate tables
```

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines
- Follow existing code style and conventions
- Add tests for new features
- Update documentation as needed
- Ensure backward compatibility

## 📋 TODO / Roadmap

- [ ] **Batch Processing**: Upload and process multiple search images
- [ ] **Advanced Analytics**: Face matching statistics and reports
- [ ] **REST API Documentation**: OpenAPI/Swagger integration
- [ ] **Docker Support**: Containerized deployment
- [ ] **Database Options**: MySQL/PostgreSQL support
- [ ] **Cloud Storage**: S3/GCS integration for images
- [ ] **Mobile App**: React Native companion app
- [ ] **Video Processing**: Real-time video stream recognition
- [ ] **Multi-language**: Internationalization support

## 📊 Technical Specifications

| Component | Technology | Version |
|-----------|------------|---------|
| Backend | Node.js + Express.js | 18.x + 4.21.x |
| Database | SQLite | 3.x |
| AI Framework | TensorFlow.js | 4.22.x |
| Face Recognition | @vladmandic/face-api | 1.7.15 |
| UI Framework | Vanilla JavaScript | - |
| Styling | CSS3 + Glassmorphism | - |
| Markdown | marked.js | 9.1.6 |
| Image Processing | Canvas API | - |

## 📜 License

This project is licensed under the **GNU General Public License v3.0** - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **TensorFlow.js Team** - For the amazing ML framework
- **@vladmandic** - For the excellent face-api.js library
- **Express.js Community** - For the robust web framework
- **SQLite Team** - For the reliable embedded database
- **Contributors** - Everyone who helps improve this project

---

⭐ **Star this repository if it helped you!**

Made with ❤️ and 🤖 AI Technology
