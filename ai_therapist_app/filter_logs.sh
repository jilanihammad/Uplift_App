#!/bin/bash

# AI Therapist App - Log Filtering Script
# This script provides various logcat filters to reduce noise during development

echo "AI Therapist App - Log Filters"
echo "=============================="
echo "1. Flutter logs only (clean)"
echo "2. Mute Android graphics spam"
echo "3. Show errors and warnings only"
echo "4. Custom filter (interactive)"
echo "5. Monitor app logs only"
echo ""
read -p "Select filter option (1-5): " choice

case $choice in
    1)
        echo "Showing Flutter logs only..."
        adb logcat -v time -s flutter
        ;;
    2)
        echo "Muting graphics spam but keeping other info logs..."
        adb logcat *:I \
                  BLASTBufferQueue_Java:S \
                  VRI*:S \
                  InsetsController:S \
                  InputMethodManager:S \
                  ExoPlayerImpl:S \
                  SurfaceFlinger:S
        ;;
    3)
        echo "Showing warnings and errors only..."
        adb logcat *:W
        ;;
    4)
        echo "Available tags to filter:"
        echo "  flutter, AudioPlayerManager, VADManager, ChatScreen"
        read -p "Enter custom filter (e.g., '*:I flutter:D AudioPlayerManager:S'): " custom_filter
        adb logcat $custom_filter
        ;;
    5)
        echo "Monitoring app-specific logs only..."
        adb logcat | grep -E "(flutter|AI_THERAPIST|AudioPlayerManager|VADManager|ChatScreen)"
        ;;
    *)
        echo "Invalid option. Showing all logs with reduced noise..."
        adb logcat *:I \
                  BLASTBufferQueue_Java:S \
                  VRI*:S \
                  InsetsController:S
        ;;
esac