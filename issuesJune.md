 SAFE VoiceService Refactoring Plan - With Testing at Every Step             │ │
│ │                                                                             │ │
│ │ Critical Constraint                                                         │ │
│ │                                                                             │ │
│ │ Production launch tonight - ZERO tolerance for breaking changes             │ │
│ │                                                                             │ │
│ │ Revised Approach: Incremental Migration with Continuous Testing             │ │
│ │                                                                             │ │
│ │ (done) Phase 1: Create Safety Net (NO CHANGES TO EXISTING CODE)                    │ │
│ │                                                                             │ │
│ │ 1. Create comprehensive test suite for current VoiceService functionality   │ │
│ │ 2. Run app → Verify all audio features work                                 │ │
│ │ 3. Document current behavior as baseline                                    │ │
│ │                                                                             │ │
│ │ (done) Phase 2: Add New Services WITHOUT Removing Anything                         │ │
│ │                                                                             │ │
│ │ 1. Create TranscriptionService                                              │ │
│ │   - Copy transcription logic from VoiceService (don't remove from           │ │
│ │ VoiceService yet)                                                           │ │
│ │   - Test: Run app → Verify nothing broken                                   │ │
│ │ 2. Enhance AudioFileManager                                                 │ │
│ │   - Add file download/caching methods (copied from VoiceService)            │ │
│ │   - Test: Run app → Verify nothing broken                                   │ │
│ │ 3. Update SimpleTTSService                                                  │ │
│ │   - Add TTS fallback logic (copied from VoiceService)                       │ │
│ │   - Test: Run app → Verify nothing broken                                   │ │
│ │                                                                             │ │
│ │ Phase 3: Gradual Migration (One Component at a Time)                        │ │
│ │                                                                             │ │
│ │ For each component below, we'll:                                            │ │
│ │ - Make ONE small change                                                     │ │
│ │ - Run the app                                                               │ │
│ │ - Test audio recording, playback, and TTS                                   │ │
│ │ - Commit if successful                                                      │ │
│ │ - Rollback if ANY issues                                                    │ │
│ │                                                                             │ │
│ │ 1. AudioGenerator Migration                                                 │ │
│ │   - Change VoiceService callback to use ITTSService                         │ │
│ │   - Test: Full app test                                                     │ │
│ │   - Keep VoiceService reference as fallback                                 │ │
│ │ 2. AutoListeningCoordinator Migration                                       │ │
│ │   - Add optional IVoiceService parameter                                    │ │
│ │   - Keep VoiceService as default                                            │ │
│ │   - Test: Full app test                                                     │ │
│ │                                                                             │ │
│ │ 
Phase 4: Shadow Mode Testing                                                │ │
│ │                                                                             │ │
│ │ 1. Run both old and new services in parallel                                │ │
│ │   - Keep VoiceService active                                                │ │
│ │   - Route some calls through new services                                   │ │
│ │   - Compare results                                                         │ │
│ │   - Test: Extensive testing                                                 │ │
│ │                                                                             │ │
│ │ Phase 5: Final Switch (ONLY if time permits before launch)                  │ │
│ │                                                                             │ │
│ │ 1. Switch one service at a time                                             │ │
│ │   - Update service locator registrations                                    │ │
│ │   - Keep VoiceService file (just unused)                                    │ │
│ │   - Test after EACH change                                                  │ │
│ │                                                                             │ │
│ │ Rollback Plan                                                               │ │
│ │                                                                             │ │
│ │ - Git commit after each successful step                                     │ │
│ │ - If ANYTHING breaks: git reset --hard to last working commit               │ │
│ │ - VoiceService remains fully functional throughout                          │ │
│ │                                                                             │ │
│ │ Testing Checklist (Run after EVERY change)                                  │ │
│ │                                                                             │ │
│ │ - Voice recording starts/stops                                              │ │
│ │ - Audio transcription works                                                 │ │
│ │ - TTS playback works                                                        │ │
│ │ - Welcome messages play                                                     │ │
│ │ - Auto-listening mode works                                                 │ │
│ │ - No console errors                                                         │ │
│ │ - No UI freezes                                                             │ │
│ │                                                                             │ │
│ │ Safe Timeline                                                               │ │
│ │                                                                             │ │
│ │ - Phase 1-2: 30 minutes (no functional changes)                             │ │
│ │ - Phase 3: 1-2 hours (with testing)                                         │ │
│ │ - Phase 4: Optional (if > 3 hours before launch)                            │ │
│ │ - Phase 5: DO NOT ATTEMPT before launch                                     │ │
│ │                                                                             │ │
│ │ Recommendation: Only do Phases 1-3 today. Save Phase 4-5 for after          │ │
│ │ successful production launch.               