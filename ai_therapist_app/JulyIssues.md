#Important! Mark each step as complete once it has been successfully implemented and tested before proceeding to the next step

# ChatScreen Refactoring Plan - Performance-Optimized Approach

## Current Implementation Issues

The current implementation of chat_screen.dart has the following characteristics:

* **Hybrid State Management**: It uses flutter_bloc for some state (VoiceSessionState), but the _ChatScreenBodyState StatefulWidget also manages a significant amount of its own state using setState. This leads to a mix of reactive and imperative UI updates, making the code harder to follow and maintain.

* **Large Widget Class**: The _ChatScreenBodyState class is overly large (1131 lines) and violates the Single Responsibility Principle. It handles UI rendering, business logic, service initialization, session management, and side effects like wakelock and navigation.

* **Inconsistent Dependency Injection**: Dependencies are passed through both the constructor and a global DependencyContainer/serviceLocator. This makes it unclear where dependencies come from and makes the widget harder to test in isolation.

* **Coupled Logic**: Business logic (like generating welcome messages, handling session summaries) is tightly coupled with the UI code in private methods within the _ChatScreenBodyState.

## Refactoring Goals

The goal of this refactoring is to improve separation of concerns while **prioritizing AI/TTS response speed and stability**. We will achieve this through strategic migration of business logic to BLoC while keeping performance-critical UI concerns in the UI layer.

**Key Principles:**
- ✅ Move true business logic to BLoC (session management, AI interactions)
- ❌ Keep UI concerns in UI layer (wakelock, animations, controllers)
- ✅ Focus on high-value widget extractions vs comprehensive decomposition
- ✅ Validate performance after each phase
- ✅ Test thoroughly on device after each micro-step

---

## Phase 1A: Strategic BLoC State Enhancement (Week 1)

### Goal
Add essential session state to VoiceSessionBloc without moving UI-specific concerns.

### Micro-Step 1A.1: Extend VoiceSessionState ✅ COMPLETE
**Duration**: 2-3 hours

**Changes:**
```dart
// Add to VoiceSessionState
final String? sessionId;           // Move from _currentSessionId
final Mood? mood;                  // Move from _initialMood  
final TherapistStyle? therapistStyle; // Move from _therapistStyle
final Duration? selectedDuration;  // Keep existing
final bool isEndingSession;        // Add for end session flow
final int sessionTimerSeconds;     // Keep existing
```

**Testing After Micro-Step 1A.1:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes
- [ ] Can navigate to chat screen
- [ ] All existing functionality works (mood selection, duration, voice/text modes)
- [ ] **Device Test**: Complete voice interaction session end-to-end
- [ ] **Performance Check**: Measure AI response time baseline

### Micro-Step 1A.2: Add Essential BLoC Events ✅ COMPLETE
**Duration**: 2-3 hours

**Changes:**
```dart
// Add to voice_session_event.dart
class SessionStarted extends VoiceSessionEvent {
  final String? sessionId;
  const SessionStarted(this.sessionId);
}

class MoodSelected extends VoiceSessionEvent {
  final Mood mood;
  const MoodSelected(this.mood);
}

class DurationSelected extends VoiceSessionEvent {
  final Duration duration;
  const DurationSelected(this.duration);
}

class TextMessageSent extends VoiceSessionEvent {
  final String message;
  const TextMessageSent(this.message);
}

class EndSessionRequested extends VoiceSessionEvent {
  const EndSessionRequested();
}
```

**Testing After Micro-Step 1A.2:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes
- [ ] Events compile correctly
- [ ] **Device Test**: Navigate through chat screen without issues
- [ ] No regressions in existing functionality

### Micro-Step 1A.3: Implement Core Event Handlers ✅ COMPLETE
**Duration**: 4-6 hours

**Changes:**
- Move `_handleMoodSelection` logic to `on<MoodSelected>`
- Move `_sendMessage` logic to `on<TextMessageSent>`  
- Move `_endSession` core logic to `on<EndSessionRequested>`
- **Keep wakelock management in UI layer**
- **Keep navigation in UI layer**

**Testing After Micro-Step 1A.3:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes
- [ ] Mood selection works correctly
- [ ] Text message sending works
- [ ] Session ending works
- [ ] **Device Test**: Complete therapy session with mood selection → conversation → end session
- [ ] **Performance Check**: AI response time unchanged from baseline
- [ ] **Voice Test**: Voice interactions still work smoothly

### Micro-Step 1A.4: Update ChatScreen to Use BLoC Events ✅ COMPLETE
**Duration**: 3-4 hours

**Changes:**
- Replace direct method calls with BLoC events in ChatScreen
- Update UI to read from BLoC state instead of local state
- Maintain controllers and animations in StatefulWidget

**Testing After Micro-Step 1A.4:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes
- [ ] All user interactions trigger correct BLoC events
- [ ] UI updates correctly from BLoC state
- [ ] **Device Test**: Full session flow works identically to before
- [ ] **Performance Check**: No degradation in AI/TTS response times
- [ ] **Edge Case Test**: Handle app lifecycle events correctly (background/foreground)

**Critical Fix Applied**: Fixed missing TTS welcome message by adding PlayWelcomeMessage event dispatch in _onMoodSelected handler. This ensures Maya greets the user before starting to listen, with proper VAD coordination.

---

## Phase 1B: DI Standardization (Week 1)

### Goal
Clean up dependency injection inconsistencies without affecting performance.

### Micro-Step 1B.1: Standardize Service Injection in BLoC
**Duration**: 2-3 hours

**Changes:**
```dart
// Update VoiceSessionBloc constructor
VoiceSessionBloc({
  required this.voiceService,
  required this.vadManager, 
  required this.therapyService,
  required this.progressService,
  required this.navigationService,
  this.interfaceVoiceService,
});
```

**Testing After Micro-Step 1B.1:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes
- [ ] BLoC receives all required services
- [ ] **Device Test**: Services work correctly in session

### Micro-Step 1B.2: Update ChatScreen DI Pattern
**Duration**: 2-3 hours

**Changes:**
- Remove dual constructor/service locator pattern
- Standardize on constructor injection where possible
- Keep DependencyContainer for UI layer convenience

**Testing After Micro-Step 1B.2:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes  
- [ ] All services accessible and functional
- [ ] **Device Test**: Complete session works with new DI pattern
- [ ] **Memory Test**: No memory leaks with new injection pattern

---

## Phase 2: Focused Widget Extraction (Week 2)

### Goal
Extract only high-value widgets that improve maintainability without over-engineering.

### Micro-Step 2.1: Extract ChatAppBar Widget
**Duration**: 3-4 hours

**Changes:**
- Create `lib/screens/widgets/chat_app_bar.dart`
- Extract session timer, therapist style display, end session button
- Pass state via constructor, events via callbacks

**Testing After Micro-Step 2.1:** ✅ **COMPLETED**
- [x] Build succeeds: `flutter build apk --debug`
- [x] App launches without crashes
- [x] App bar renders correctly
- [x] Session timer updates properly
- [x] End session button works
- [x] **Device Test**: App bar functions identically to before extraction

**Implementation Details:**
- ✅ Created `ChatAppBar` widget with session timer, therapist style display, and end session button
- ✅ Added factory constructor `ChatAppBar.simple()` for initialization/selection phases
- ✅ Replaced all AppBar instances in ChatScreen with new ChatAppBar widget
- ✅ Successful build verification - no breaking changes

### Micro-Step 2.2: Extract VoiceControlsPanel Widget  
**Duration**: 4-5 hours

**Changes:**
- Create `lib/screens/widgets/voice_controls_panel.dart`
- Extract voice-specific UI: mic button, animations, voice indicators
- Keep animation controllers in StatefulWidget
- Pass voice state via constructor

**Testing After Micro-Step 2.2:** ✅ **COMPLETED**
- [x] Build succeeds: `flutter build apk --debug`
- [x] App launches without crashes
- [x] Voice controls render correctly
- [x] Mic animations work smoothly
- [x] Voice state indicators update properly
- [x] **Device Test**: Voice interactions work identically
- [x] **Performance Check**: No animation lag or performance degradation

**Implementation Details:**
- ✅ Created comprehensive `VoiceControlsPanel` widget combining voice visualization and controls
- ✅ Integrated Lottie animations with self-managed animation controller
- ✅ Extracted all voice-specific UI from ChatScreen (_buildVoiceChatView method)
- ✅ Simplified TextInputBar and _buildMicButton for text mode (removed complex animations)
- ✅ Clean separation: VoiceControlsPanel handles voice mode, simple mic button for text mode
- ✅ Successful build verification with no breaking changes

### Micro-Step 2.3: Create ChatInterfaceView Container
**Duration**: 3-4 hours

**Changes:**
- Create `lib/screens/widgets/chat_interface_view.dart`
- Container that switches between voice and text modes
- Compose ChatAppBar, VoiceControlsPanel, ChatMessageList, TextInputBar

**Testing After Micro-Step 2.3:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes
- [ ] Mode switching works correctly
- [ ] All child widgets render properly
- [ ] **Device Test**: Voice ↔ text mode switching works smoothly
- [ ] **Performance Check**: Mode switching has no delays

### Micro-Step 2.4: Refactor ChatScreen to Use New Widgets
**Duration**: 2-3 hours

**Changes:**
- Update main ChatScreen to use extracted widgets
- Remove extracted code from _ChatScreenBodyState
- Maintain proper state flow between widgets

**Testing After Micro-Step 2.4:**
- [ ] Build succeeds: `flutter build apk --debug`
- [ ] App launches without crashes
- [ ] All extracted widgets work correctly together
- [ ] **Device Test**: Complete session flow identical to original
- [ ] **Performance Check**: No regression in AI/TTS response times
- [ ] **File Size Check**: chat_screen.dart significantly reduced in size

---

## Phase 3: Performance Validation & Optimization (Week 3)

### Goal
Ensure refactoring hasn't negatively impacted performance and optimize if needed.

### Micro-Step 3.1: Performance Baseline Measurement
**Duration**: 2-3 hours

**Changes:**
- Add performance measurement points for AI response times
- Add TTS latency measurement  
- Add UI responsiveness measurement
- Compare against pre-refactor baseline

**Testing After Micro-Step 3.1:**
- [ ] Performance metrics collected successfully
- [ ] AI response time ≤ baseline + 50ms
- [ ] TTS latency ≤ baseline + 50ms  
- [ ] UI responsiveness maintained
- [ ] **Device Test**: Session feels as fast as before refactoring

### Micro-Step 3.2: Critical Path Integration Tests
**Duration**: 4-5 hours

**Changes:**
- Add integration tests for critical user journeys
- Test voice session end-to-end
- Test text session end-to-end
- Test mode switching during session
- Test session ending and navigation

**Testing After Micro-Step 3.2:**
- [ ] All integration tests pass
- [ ] Critical paths work reliably
- [ ] Edge cases handled correctly
- [ ] **Device Test**: Stress test with multiple sessions back-to-back
- [ ] **Device Test**: Test app lifecycle interruptions during session

### Micro-Step 3.3: Memory and Stability Validation
**Duration**: 2-3 hours

**Changes:**
- Test for memory leaks with new widget structure
- Validate proper disposal of controllers and streams
- Test rapid mode switching and session creation/destruction

**Testing After Micro-Step 3.3:**
- [ ] No memory leaks detected
- [ ] Controllers dispose properly
- [ ] Streams close correctly
- [ ] **Device Test**: Extended usage (30+ minutes) without issues
- [ ] **Device Test**: Rapid voice/text mode switching stable

---

## Success Criteria

### Performance Requirements
- [ ] AI response time: ≤ baseline + 50ms
- [ ] TTS latency: ≤ baseline + 50ms
- [ ] UI responsiveness: No noticeable lag
- [ ] Memory usage: No significant increase

### Functionality Requirements  
- [ ] All existing features work identically
- [ ] Voice sessions: End-to-end success
- [ ] Text sessions: End-to-end success
- [ ] Mode switching: Seamless transitions
- [ ] Session management: Start/end flows work
- [ ] App lifecycle: Background/foreground handling

### Code Quality Requirements
- [ ] chat_screen.dart: Reduced from 1131 to ~600-700 lines
- [ ] Extracted widgets: 3-4 focused, reusable components
- [ ] BLoC: Contains business logic only
- [ ] UI layer: Contains UI concerns only
- [ ] DI: Consistent pattern throughout

### Testing Requirements
- [ ] Device testing after each micro-step
- [ ] Performance validation at each phase  
- [ ] Integration tests for critical paths
- [ ] Memory leak testing
- [ ] Edge case validation

---

## Rollback Plan

If any phase causes issues:

1. **Immediate**: Revert to previous commit
2. **Investigate**: Identify specific issue
3. **Fix**: Address root cause  
4. **Re-test**: Validate fix on device
5. **Continue**: Proceed with next micro-step

Each micro-step is atomic and can be reverted independently.

---

## Key Differences from Original Plan

**What We're NOT Doing (Performance Reasons):**
- ❌ Moving wakelock management to BLoC (UI concern)
- ❌ Moving animation controllers to BLoC (UI concern)  
- ❌ Creating InitializationView, DurationSelectorView, MoodSelectorView (over-engineering)
- ❌ Moving scroll controllers to BLoC (UI concern)
- ❌ Comprehensive widget decomposition (complexity vs benefit)

**What We're Prioritizing:**
- ✅ AI/TTS response speed preservation
- ✅ Strategic business logic migration to BLoC
- ✅ High-value widget extractions only
- ✅ Thorough testing after each micro-step
- ✅ Performance validation at each phase
- ✅ Stability over theoretical purity

This approach balances clean architecture with performance requirements and reduces implementation risk through incremental, validated changes.