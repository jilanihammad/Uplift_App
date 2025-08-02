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

# Setup project if we're in the Uplift_App directory
if [[ "${PWD##*/}" == "Uplift_App" ]]; then
    echo "🔧 Setting up Uplift App project..."
    
    # Setup Flutter app
    cd ai_therapist_app
    flutter pub get
    flutter pub run build_runner build --delete-conflicting-outputs || true
    
    # Setup backend
    cd ../ai_therapist_backend
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
    pip install -r requirements-dev.txt || true
    
    # PostgreSQL setup
    echo "🗄️ Setting up PostgreSQL..."
    sudo systemctl start postgresql || true
    sudo systemctl enable postgresql || true
    
    # Create database user and database
    sudo -u postgres createuser --superuser $USER 2>/dev/null || true
    createdb ai_therapist 2>/dev/null || true
    
    echo "✅ Project setup complete!"
else
    echo "ℹ️  Not in Uplift_App directory. Skipping project setup."
fi

echo ""
echo "✅ Linux setup complete!"
echo ""
echo "Next steps:"
echo "1. Run: source ~/.bashrc"
echo "2. Clone your repository (if not done)"
echo "3. Configure .env files in both app and backend directories"
echo "4. Run 'flutter doctor' to verify setup"
echo ""
echo "To start development:"
echo "- Backend: cd ai_therapist_backend && source venv/bin/activate && python dev_server.py"
echo "- Flutter: cd ai_therapist_app && flutter run"