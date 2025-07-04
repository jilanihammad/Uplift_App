PHASE 6: COMPREHENSIVE & CAREFUL INTERFACE MIGRATION PLAN                             │ │
│ │                                                                                       │ │
│ │ Overview                                                                              │ │
│ │                                                                                       │ │
│ │ Complete the remaining dependency injection migration from concrete VoiceService to   │ │
│ │ IVoiceService interface, with extreme care to avoid breaking Maya's audio pipeline.   │ │
│ │                                                                                       │ │
│ │ Current State Analysis                                                                │ │
│ │                                                                                       │ │
│ │ ✅ Working Baseline: "hybrid architecture" commit with Maya speaking AND listening     │ │
│ │ properly✅ Completed: ChatScreen, DiagnosticScreen, AutoListeningToggle❌ Remaining:    │ │
│ │ VoiceSessionBloc, main.dart initialization, some legacy references                    │ │
│ │                                                                                       │ │
│ │ Key Lessons from Previous Failures                                                    │ │
│ │                                                                                       │ │
│ │ 1. Never modify service registration without testing each step                        │ │
│ │ 2. Never change from sync to async registrations in one step                          │ │
│ │ 3. Always test Maya's audio pipeline after each change                                │ │
│ │ 4. Make minimal, incremental changes with rollback points                             │ │
│ │ 5. Test app startup, TTS, AND listening after each migration                          │ │
│ │                                                                                       │ │
│ │ Migration Strategy: Ultra-Safe Incremental Approach                                   │ │
│ │                                                                                       │ │
│ │ Phase 6A: Preparation & Analysis                                                      │ │
│ │                                                                                       │ │
│ │ - Audit all remaining VoiceService dependencies with exact file/line references       │ │
│ │ - Create isolated test branches for each major component                              │ │
│ │ - Establish Maya audio pipeline regression tests                                      │ │
│ │                                                                                       │ │
│ │ Phase 6B: VoiceSessionBloc Migration (HIGHEST RISK)                                   │ │
│ │                                                                                       │ │
│ │ Why Critical: VoiceSessionBloc is the core audio coordinator - any breakage kills     │ │
│ │ Maya                                                                                  │ │
│ │                                                                                       │ │
│ │ 6B-1: Optional Parameter Preparation                                                  │ │
│ │ - Add optional IVoiceService? parameter to VoiceSessionBloc constructor               │ │
│ │ - Keep concrete VoiceService as fallback for full backward compatibility              │ │
│ │ - No behavioral changes - pure preparation step                                       │ │
│ │ - Test: Maya must work exactly the same                                               │ │
│ │                                                                                       │ │
│ │ 6B-2: Single Caller Migration                                                         │ │
│ │ - Migrate ONE caller (main.dart) to pass IVoiceService to VoiceSessionBloc            │ │
│ │ - All other callers still use legacy path                                             │ │
│ │ - Test: Maya must work exactly the same                                               │ │
│ │ - Rollback: If broken, revert immediately                                             │ │
│ │                                                                                       │ │
│ │ 6B-3: Interface Usage                                                                 │ │
│ │ - Update internal VoiceSessionBloc logic to use interface methods only                │ │
│ │ - Maintain backward compatibility with legacy concrete type                           │ │
│ │ - Test: Maya audio pipeline must work perfectly                                       │ │
│ │                                                                                       │ │
│ │ Phase 6C: Cleanup & Hardening                                                         │ │
│ │                                                                                       │ │
│ │ 6C-1: Remove Legacy Concrete Dependencies                                             │ │
│ │ - Only after 6B is 100% stable and tested                                             │ │
│ │ - Remove concrete VoiceService parameters from constructors                           │ │
│ │ - Make IVoiceService required instead of optional                                     │ │
│ │                                                                                       │ │
│ │ 6C-2: Dead Code Elimination                                                           │ │
│ │ - Remove unused serviceLocator<VoiceService>() calls                                  │ │
│ │ - Clean up imports and concrete type references                                       │ │
│ │                                                                                       │ │
│ │ Phase 6D: Verification & Documentation                                                │ │
│ │                                                                                       │ │
│ │ 6D-1: Full Regression Testing                                                         │ │
│ │ - Test all Maya audio pipeline scenarios                                              │ │
│ │ - Test app startup/shutdown cycles                                                    │ │
│ │ - Test memory management and service lifecycle                                        │ │
│ │                                                                                       │ │
│ │ 6D-2: Update Documentation                                                            │ │
│ │ - Mark Phase 6 as complete in CLAUDE.md                                               │ │
│ │ - Document the final architecture                                                     │ │
│ │                                                                                       │ │
│ │ Safety Guardrails                                                                     │ │
│ │                                                                                       │ │
│ │ Mandatory Testing After Each Step                                                     │ │
│ │                                                                                       │ │
│ │ 1. App Startup: Must complete without hanging                                         │ │
│ │ 2. Maya Welcome: Must speak her initial message                                       │ │
│ │ 3. Maya Listening: Must automatically start listening after speaking                  │ │
│ │ 4. User Speech: Must transcribe and respond within 2 seconds                          │ │
│ │ 5. Multiple Conversations: Must handle back-and-forth dialogue                        │ │
│ │                                                                                       │ │
│ │ Rollback Triggers                                                                     │ │
│ │                                                                                       │ │
│ │ - Any step that breaks Maya's listening capability = immediate rollback               │ │
│ │ - Any step that causes app startup hang = immediate rollback                          │ │
│ │ - Any step that breaks TTS/speech generation = immediate rollback                     │ │
│ │                                                                                       │ │
│ │ Change Size Limits                                                                    │ │
│ │                                                                                       │ │
│ │ - Maximum 1 constructor parameter change per commit                                   │ │
│ │ - Maximum 1 file migration per step                                                   │ │
│ │ - No service registration changes unless absolutely necessary                         │ │
│ │ - No async/await modifications unless critical                                        │ │
│ │                                                                                       │ │
│ │ Branch Strategy                                                                       │ │
│ │                                                                                       │ │
│ │ - Create feature branch for each phase (6B-1, 6B-2, etc.)                             │ │
│ │ - Test thoroughly on branch before merging to main                                    │ │
│ │ - Keep hybrid architecture commit as permanent fallback point                         │ │
│ │                                                                                       │ │
│ │ Risk Assessment                                                                       │ │
│ │                                                                                       │ │
│ │ HIGH RISK: VoiceSessionBloc migration (Phase 6B)                                      │ │
│ │ - Core audio coordinator - failure kills entire Maya pipeline                         │ │
│ │ - Multiple complex state transitions and timing dependencies                          │ │
│ │ - Interfaces with both legacy and new services                                        │ │
│ │                                                                                       │ │
│ │ MEDIUM RISK: Service locator cleanup (Phase 6C)                                       │ │
│ │ - Could affect service initialization order                                           │ │
│ │ - Potential circular dependency issues                                                │ │
│ │                                                                                       │ │
│ │ LOW RISK: Documentation and verification (Phase 6D)                                   │ │
│ │ - No code changes, only testing and documentation                                     │ │
│ │                                                                                       │ │
│ │ Success Criteria                                                                      │ │
│ │                                                                                       │ │
│ │ - Maya works exactly the same as current hybrid architecture                          │ │
│ │ - All services use IVoiceService interface exclusively                                │ │
│ │ - No concrete VoiceService dependencies remain                                        │ │
│ │ - Full regression test suite passes                                                   │ │
│ │ - Documentation reflects completed migration                                          │ │
│ │                                                                                       │ │
│ │ This plan prioritizes Maya's audio pipeline stability above all else, with multiple   │ │
│ │ safety nets and rollback points.     