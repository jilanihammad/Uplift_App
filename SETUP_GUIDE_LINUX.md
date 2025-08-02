# Uplift App - Linux Setup Guide

Complete setup guide for installing and running Uplift App on a fresh Linux system.

## System Requirements
- **Distribution**: Ubuntu 20.04+, Debian 10+, Fedora 32+, or similar
- **RAM**: Minimum 8GB (16GB recommended)
- **Storage**: At least 15GB free space
- **Processor**: x86_64 processor

## Quick Start Script

Save this as `setup_linux.sh` and run with `bash setup_linux.sh`:

```bash
#!/bin/bash

echo "🚀 Uplift App Linux Setup Script"
echo "================================"

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Cannot detect Linux distribution"
    exit 1
fi

echo "Detected distribution: $DISTRO"

# Install system dependencies based on distribution
if [[ "$DISTRO" == "ubuntu" ]] || [[ "$DISTRO" == "debian" ]]; then
    echo "📦 Installing system dependencies for Debian/Ubuntu..."
    sudo apt update
    sudo apt install -y \
        curl git wget unzip xz-utils zip \
        build-essential cmake \
        libgtk-3-dev libblkid-dev liblzma-dev \
        ninja-build pkg-config \
        clang libstdc++-12-dev \
        python3.9 python3-pip python3-venv \
        postgresql postgresql-contrib \
        libpq-dev python3-dev \
        ffmpeg \
        keytool \
        adb

elif [[ "$DISTRO" == "fedora" ]]; then
    echo "📦 Installing system dependencies for Fedora..."
    sudo dnf install -y \
        curl git wget unzip xz \
        gcc gcc-c++ make cmake \
        gtk3-devel \
        ninja-build \
        clang \
        python3 python3-pip python3-devel \
        postgresql postgresql-server postgresql-contrib \
        postgresql-devel \
        ffmpeg \
        android-tools

else
    echo "Unsupported distribution. Please install dependencies manually."
    exit 1
fi

# Install Flutter
echo "📱 Installing Flutter..."
if [ ! -d "$HOME/flutter" ]; then
    cd $HOME
    git clone https://github.com/flutter/flutter.git -b stable
    echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
    echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.profile
    export PATH="$PATH:$HOME/flutter/bin"
else
    echo "Flutter already installed, updating..."
    cd $HOME/flutter
    git pull
fi

# Run Flutter doctor
flutter precache
flutter doctor

# Install Android SDK (if not present)
echo "📱 Setting up Android SDK..."
if [ ! -d "$HOME/Android/Sdk" ]; then
    mkdir -p $HOME/Android/Sdk
    cd $HOME/Android/Sdk
    
    # Download command line tools
    wget https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip
    unzip commandlinetools-linux-9477386_latest.zip
    mkdir -p cmdline-tools/latest
    mv cmdline-tools/* cmdline-tools/latest/ 2>/dev/null || true
    
    # Set up environment
    echo 'export ANDROID_HOME=$HOME/Android/Sdk' >> ~/.bashrc
    echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin' >> ~/.bashrc
    echo 'export PATH=$PATH:$ANDROID_HOME/platform-tools' >> ~/.bashrc
    export ANDROID_HOME=$HOME/Android/Sdk
    export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin
    export PATH=$PATH:$ANDROID_HOME/platform-tools
    
    # Install Android SDK components
    yes | sdkmanager --licenses
    sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.0"
fi

# Accept Android licenses
flutter doctor --android-licenses

echo "✅ Basic setup complete!"
echo ""
echo "Next steps:"
echo "1. Clone your repository"
echo "2. Run the project setup script"
echo "3. Configure environment variables"
echo ""
echo "Run: source ~/.bashrc to reload your PATH"
```

## Manual Step-by-Step Setup

### 1. Install Core Dependencies

#### Ubuntu/Debian:
```bash
# Update package list
sudo apt update

# Install essential build tools
sudo apt install -y curl git wget unzip xz-utils zip build-essential

# Install Flutter dependencies
sudo apt install -y libgtk-3-dev libblkid-dev liblzma-dev
sudo apt install -y ninja-build pkg-config clang cmake

# Install Python and PostgreSQL
sudo apt install -y python3.9 python3-pip python3-venv python3-dev
sudo apt install -y postgresql postgresql-contrib libpq-dev

# Install additional tools
sudo apt install -y ffmpeg  # For audio processing
```

#### Fedora:
```bash
# Install development tools
sudo dnf groupinstall "Development Tools" "Development Libraries"

# Install Flutter dependencies  
sudo dnf install -y gtk3-devel ninja-build clang cmake

# Install Python and PostgreSQL
sudo dnf install -y python3 python3-pip python3-devel
sudo dnf install -y postgresql postgresql-server postgresql-contrib postgresql-devel

# Install additional tools
sudo dnf install -y ffmpeg
```

#### Arch Linux:
```bash
# Install base development packages
sudo pacman -S base-devel git cmake ninja clang

# Install Flutter dependencies
sudo pacman -S gtk3

# Install Python and PostgreSQL
sudo pacman -S python python-pip postgresql

# Install additional tools
sudo pacman -S ffmpeg
```

### 2. Install Flutter

```bash
# Install to home directory
cd ~
git clone https://github.com/flutter/flutter.git -b stable

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

# Download Flutter dependencies
flutter precache

# Verify installation
flutter doctor
```

### 3. Install Android SDK (Without Android Studio)

```bash
# Create Android SDK directory
mkdir -p ~/Android/Sdk
cd ~/Android/Sdk

# Download command line tools
wget https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip
unzip commandlinetools-linux-9477386_latest.zip

# Organize command line tools
mkdir -p cmdline-tools/latest
mv cmdline-tools/* cmdline-tools/latest/ 2>/dev/null || true

# Add to PATH
echo 'export ANDROID_HOME=$HOME/Android/Sdk' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/platform-tools' >> ~/.bashrc
source ~/.bashrc

# Install required SDK packages
sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.0"
sdkmanager "system-images;android-33;google_apis;x86_64"  # For emulator

# Accept licenses
yes | sdkmanager --licenses
flutter doctor --android-licenses
```

### 4. Setup PostgreSQL

```bash
# Start PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create database user (use your Linux username)
sudo -u postgres createuser --superuser $USER

# Create database
createdb ai_therapist

# Verify connection
psql -d ai_therapist -c "SELECT version();"
```

### 5. Clone and Setup Project

```bash
# Clone repository
cd ~/Projects  # or your preferred directory
git clone https://github.com/YOUR_USERNAME/Uplift_App.git
cd Uplift_App

# Setup Flutter app
cd ai_therapist_app
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs

# Setup Python backend
cd ../ai_therapist_backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Run database migrations
alembic upgrade head
```

### 6. Configure Environment Files

Create `ai_therapist_app/.env`:
```env
# For local development
API_BASE_URL=http://localhost:8000

# Firebase Configuration
FIREBASE_API_KEY=your_firebase_api_key
FIREBASE_APP_ID=your_firebase_app_id
FIREBASE_MESSAGING_SENDER_ID=your_sender_id
FIREBASE_PROJECT_ID=your_project_id
FIREBASE_STORAGE_BUCKET=your_storage_bucket
```

Create `ai_therapist_backend/.env`:
```env
# Database
DATABASE_URL=postgresql://your_linux_username:@localhost/ai_therapist

# API Keys
OPENAI_API_KEY=your_openai_api_key
GROQ_API_KEY=your_groq_api_key
GOOGLE_API_KEY=your_google_api_key

# LLM Configuration
LLM_PROVIDER=google
LLM_MODEL=gemini-2.0-flash-exp
TTS_PROVIDER=openai
TRANSCRIPTION_PROVIDER=groq

# Environment
ENVIRONMENT=development
PORT=8000
```

### 7. Running the Application

#### Terminal 1 - Backend:
```bash
cd ~/Projects/Uplift_App/ai_therapist_backend
source venv/bin/activate
python dev_server.py
```

#### Terminal 2 - Flutter:
```bash
cd ~/Projects/Uplift_App/ai_therapist_app

# List available devices
flutter devices

# Run on specific device
flutter run -d linux     # Linux desktop
flutter run -d chrome    # Web browser
flutter run -d <device>  # Connected Android device
```

### 8. Linux Desktop Specific Setup

For Flutter Linux desktop development:
```bash
# Additional dependencies for Linux desktop
sudo apt install -y libgtk-3-dev libblkid-dev liblzma-dev

# Enable Linux desktop support
flutter config --enable-linux-desktop

# Verify Linux is available
flutter devices  # Should show Linux device
```

### 9. VS Code Setup (Recommended IDE)

```bash
# Install VS Code
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
sudo apt update
sudo apt install code

# Install recommended extensions
code --install-extension Dart-Code.dart-code
code --install-extension Dart-Code.flutter
code --install-extension ms-python.python
code --install-extension ms-vscode.cpptools
```

## Troubleshooting

### Flutter Doctor Issues

```bash
# Missing Android SDK
flutter config --android-sdk ~/Android/Sdk

# Missing Android licenses
flutter doctor --android-licenses

# Linux toolchain issues
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
```

### PostgreSQL Issues

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Fix authentication issues
sudo nano /etc/postgresql/*/main/pg_hba.conf
# Change "peer" to "trust" for local connections
sudo systemctl restart postgresql
```

### Python Virtual Environment

```bash
# If venv fails
sudo apt install python3.9-venv

# Alternative: use pip directly
pip3 install --user -r requirements.txt
```

### Audio Issues on Linux

```bash
# Install PulseAudio (if not present)
sudo apt install pulseaudio pavucontrol

# For ALSA
sudo apt install alsa-utils
```

### Permission Issues

```bash
# Add user to required groups
sudo usermod -aG audio $USER
sudo usermod -aG plugdev $USER  # For Android devices

# Logout and login for changes to take effect
```

## Performance Optimization

### 1. Increase inotify watches (for Flutter hot reload)
```bash
echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 2. Setup Android device for development
```bash
# Enable developer options on Android device
# Enable USB debugging
# Connect device and authorize

# Verify device is connected
adb devices
flutter devices
```

### 3. Optimize PostgreSQL for development
```bash
# Edit postgresql.conf
sudo nano /etc/postgresql/*/main/postgresql.conf

# Set for development (not production!)
# shared_buffers = 256MB
# work_mem = 4MB
# maintenance_work_mem = 64MB
```

## Daily Development Workflow

```bash
# 1. Start PostgreSQL (if not running)
sudo systemctl start postgresql

# 2. Start backend
cd ~/Projects/Uplift_App/ai_therapist_backend
source venv/bin/activate
python dev_server.py

# 3. In new terminal, run Flutter
cd ~/Projects/Uplift_App/ai_therapist_app
flutter run -d linux  # or your preferred device

# 4. For hot reload, press 'r' in Flutter terminal
# For hot restart, press 'R'
```

## Useful Aliases

Add to `~/.bashrc`:
```bash
# Uplift App shortcuts
alias uplift-backend='cd ~/Projects/Uplift_App/ai_therapist_backend && source venv/bin/activate'
alias uplift-app='cd ~/Projects/Uplift_App/ai_therapist_app'
alias uplift-run='cd ~/Projects/Uplift_App/ai_therapist_backend && source venv/bin/activate && python dev_server.py'

# Flutter shortcuts
alias fr='flutter run'
alias fpg='flutter pub get'
alias fd='flutter devices'
alias fdoc='flutter doctor -v'
```

## Security Notes

1. Never commit `.env` files
2. Use `keyring` for storing API keys securely:
   ```bash
   pip install keyring
   keyring set uplift openai_api_key
   ```

3. Set appropriate file permissions:
   ```bash
   chmod 600 .env
   chmod 600 ~/.pgpass  # PostgreSQL password file
   ```