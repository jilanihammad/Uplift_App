#!/bin/bash
# Script to test the app in release mode

echo "===========================================" 
echo "Testing AI Therapist App in Release Mode"
echo "===========================================" 

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting dependencies..."
flutter pub get

# Run in release mode
echo "Running in release mode..."
flutter run --release

echo "Test complete!" 