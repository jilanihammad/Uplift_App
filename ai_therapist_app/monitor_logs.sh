#!/bin/bash

echo "Starting log monitor for AI Therapist App..."
echo "================================================"
echo "Monitoring: VoiceService, Session, AutoListening, Errors"
echo "================================================"

# Clear the log first
adb logcat -c

# Monitor with filters
adb logcat -v time | grep -E "(VoiceService|AutoListeningCoordinator|VoiceSessionBloc|Shutdown|Session marked|Beginning new session|null|Error|SharedRecorderManager|coordinator|State transition|TTS Speaking State|VAD|Session ended|Session started)" --line-buffered | while IFS= read -r line
do
    # Color code different types of messages
    if [[ $line == *"Error"* ]] || [[ $line == *"null"* ]]; then
        echo -e "\033[0;31m$line\033[0m"  # Red for errors
    elif [[ $line == *"Shutdown"* ]] || [[ $line == *"Session marked inactive"* ]]; then
        echo -e "\033[0;33m$line\033[0m"  # Yellow for shutdown
    elif [[ $line == *"Beginning new session"* ]] || [[ $line == *"Session started"* ]]; then
        echo -e "\033[0;32m$line\033[0m"  # Green for new session
    elif [[ $line == *"State transition"* ]]; then
        echo -e "\033[0;36m$line\033[0m"  # Cyan for state changes
    else
        echo "$line"
    fi
done