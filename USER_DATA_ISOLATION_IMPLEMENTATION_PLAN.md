# User Data Isolation - Problem Statement & Implementation Plan

**Date:** 2025-10-22
**Priority:** HIGH - Data Privacy & Security Issue
**Effort Estimate:** 2-3 days (Backend: 1 day, Frontend: 1.5-2 days, Testing: 0.5 day)

---

## Executive Summary

**PROBLEM:** Users who log in using different authentication methods (Gmail, phone number, different Gmail accounts) can see the same session histories and user data. This is a critical data isolation issue that violates user privacy expectations.

**ROOT CAUSE:**
1. **Backend** merges different authentication methods into the same user account based on email matching
2. **Frontend** stores all user data in a single device-wide SQLite database without user-based partitioning

**SOLUTION:** Implement strict user data isolation by treating each authentication method as a separate user identity, and partition local data by Firebase UID.

---

## Problem Statement

### Current Behavior (Incorrect)

When a user logs in using different methods on the same device:

1. **Scenario A - Different Gmail Accounts:**
   - User logs in with `alice@gmail.com` → sees 5 sessions
   - User logs out, then logs in with `bob@gmail.com` → **still sees the same 5 sessions**

2. **Scenario B - Phone vs Email:**
   - User logs in with phone `+15551234567` → creates 3 sessions
   - User logs out, then logs in with `alice@gmail.com` → **sees the same 3 sessions**

3. **Scenario C - Same Device, Multiple Users:**
   - User A logs in, creates personal therapy sessions
   - User A logs out
   - User B logs in on the same device → **can see User A's private therapy sessions**

### Expected Behavior (Correct)

Each unique authentication method should maintain **completely isolated data**:

- `alice@gmail.com` (Google Sign-In) → Independent user profile, sessions, mood logs
- `bob@gmail.com` (Google Sign-In) → Independent user profile, sessions, mood logs
- `+15551234567` (Phone Auth) → Independent user profile, sessions, mood logs
- `alice@gmail.com` (Email/Password) → Independent user profile, sessions, mood logs

### Why This is Critical

1. **Privacy Violation:** Users expect their therapy session data to be private and isolated
2. **HIPAA/Privacy Compliance:** Mixing user data could violate healthcare privacy regulations
3. **User Trust:** Discovery of this issue severely damages user confidence in the app
4. **Data Integrity:** Session histories become meaningless when mixed across users

---

## Root Cause Analysis

### Backend Issue: Identity Merging Logic

**File:** `ai_therapist_backend/app/api/deps/auth.py`
**Function:** `_get_or_create_user()` (lines 159-197)

**Problem Code:**
```python
def _get_or_create_user(
    db: Session,
    *,
    provider: str,
    uid: str,
    email: Optional[str],
    name: Optional[str],
) -> User:
    identity = crud_user_identity.get_by_provider_uid(db, provider=provider, uid=uid)
    if identity:
        user = identity.user
        # ... existing user found
        return user

    normalized_email = _normalize_email(provider, uid, email)

    # PROBLEM: Reuses existing user if email matches
    user = crud_user.get_by_email(db, normalized_email)  # ← Lines 177-178
    if not user:
        user = crud_user.create(db, email=normalized_email, name=name)

    # Links new identity to existing user
    identity = crud_user_identity.create(
        db,
        user_id=user.id,  # ← Reuses same user_id
        provider=provider,
        uid=uid,
        email=email,
    )
    return identity.user
```

**Why It Fails:**
- When a user logs in with `alice@gmail.com` via Google, a `user` record is created
- When the same person logs in with phone `+15551234567`, Firebase might associate the same email
- The backend finds the existing `user` by email and **reuses the same `user.id`**
- Both identities (`google:alice@gmail.com` and `phone:+15551234567`) now point to the same user record
- All sessions with that `user_id` are returned regardless of login method

### Frontend Issue: Shared Local Database

**File:** `ai_therapist_app/lib/data/datasources/local/app_database.dart`
**Tables Affected:** `sessions`, `messages`, `mood_logs`, `mood_entries`, `conversations`, `user_anchors`

**Problem Schema:**
```sql
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  title TEXT,
  summary TEXT,
  action_items TEXT,
  created_at TEXT,
  last_modified TEXT,
  is_synced INTEGER
  -- MISSING: user_id column!
)
```

**Why It Fails:**
- SQLite database `app_database.db` is stored per device, not per user
- All users who log in on the same device write to the **same tables**
- When fetching sessions, the query is:
  ```dart
  final results = await appDatabase.query('sessions');  // No user filter!
  ```
- Returns **all sessions** from all users who have ever logged in on that device

**File:** `ai_therapist_app/lib/data/repositories/session_repository.dart`
**Function:** `getSessions()` (lines 112-174)

```dart
Future<List<Session>> getSessions() async {
  try {
    // Fetches from backend (filtered by user on server)
    final response = await apiClient.get('/sessions');
    final sessions = sessionsJson.map((json) => Session.fromJson(json)).toList();

    // Saves to local DB WITHOUT user_id
    await appDatabase.insert('sessions', {
      'id': session.id,
      'title': session.title,
      // ... no user_id stored
    });

    return sessions;
  } catch (e) {
    // Falls back to local DB - returns ALL sessions for ALL users!
    final results = await appDatabase.query('sessions');  // ← No filter
    return results.map((data) => Session(...)).toList();
  }
}
```

---

## Implementation Plan - Option B: Strict User Isolation

### Phase 1: Backend Changes (1 day)

#### 1.1 Modify User Creation Logic
**File:** `ai_therapist_backend/app/api/deps/auth.py`

**Change:** Remove email-based user merging

**Before:**
```python
def _get_or_create_user(...) -> User:
    # ...
    normalized_email = _normalize_email(provider, uid, email)
    user = crud_user.get_by_email(db, normalized_email)  # ← REMOVE THIS
    if not user:
        user = crud_user.create(db, email=normalized_email, name=name)
    # ...
```

**After:**
```python
def _get_or_create_user(
    db: Session,
    *,
    provider: str,
    uid: str,
    email: Optional[str],
    name: Optional[str],
) -> User:
    # Check if identity exists
    identity = crud_user_identity.get_by_provider_uid(db, provider=provider, uid=uid)
    if identity:
        user = identity.user
        if email and identity.email != email:
            identity.email = email
            db.commit()
        return user

    # CHANGED: Always create a NEW user for each unique provider+uid
    normalized_email = _normalize_email(provider, uid, email)

    user = crud_user.create(
        db,
        email=normalized_email,
        name=name,
    )

    identity = crud_user_identity.create(
        db,
        user_id=user.id,
        provider=provider,
        uid=uid,
        email=email,
    )

    logger.info(
        "Created new user_id=%s for identity provider=%s uid=%s",
        user.id,
        provider,
        uid,
    )
    return identity.user
```

**Testing:**
```bash
# Test different auth methods create different users
curl -X POST http://localhost:8000/auth/google -d '{"email":"alice@gmail.com"}'
# Should create user_id=1

curl -X POST http://localhost:8000/auth/phone -d '{"phone":"+15551234567"}'
# Should create user_id=2 (NOT reuse user_id=1)
```

#### 1.2 Add User Merge Endpoint (Optional - Future)
**File:** `ai_therapist_backend/app/api/endpoints/auth.py`

For users who want to explicitly link accounts:
```python
@router.post("/auth/link-identity")
async def link_identity(
    primary_provider: str,
    primary_uid: str,
    secondary_provider: str,
    secondary_uid: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Allows users to explicitly merge two identities.
    NOT implemented in initial release.
    """
    pass
```

#### 1.3 Update Documentation
**File:** `ai_therapist_backend/README.md`

Document the new behavior:
```markdown
## Authentication Identity Model

Each authentication method creates a separate user account:
- Google Sign-In with alice@gmail.com → user_id=1
- Phone Auth with +15551234567 → user_id=2
- Email/Password with alice@gmail.com → user_id=3

Users are NOT automatically merged by email address.
This ensures strict data isolation between login methods.
```

---

### Phase 2: Frontend Changes (1.5-2 days)

#### 2.1 Database Schema Migration
**File:** `ai_therapist_app/lib/data/datasources/local/app_database.dart`

**Step 1:** Increment database version
```dart
// Change from version 8 to version 9
static const int _databaseVersion = 9;
```

**Step 2:** Add migration for version 9
```dart
Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
  // ... existing migrations ...

  // Migration to version 9: Add user_id to all tables
  if (oldVersion < 9) {
    await _migrateToV9(txn);
  }
}

/// Migration to version 9: Add user_id column and isolate user data
Future<void> _migrateToV9(Transaction txn) async {
  debugPrint('Applying migration to version 9 (user data isolation)...');

  try {
    // 1. Add user_id column to sessions table
    await txn.execute('ALTER TABLE sessions ADD COLUMN user_id TEXT');

    // 2. Add user_id column to messages table
    await txn.execute('ALTER TABLE messages ADD COLUMN user_id TEXT');

    // 3. Add user_id column to mood_logs table
    await txn.execute('ALTER TABLE mood_logs ADD COLUMN user_id TEXT');

    // 4. user_id already exists in mood_entries (line 188)

    // 5. Add user_id column to conversations table
    await txn.execute('ALTER TABLE conversations ADD COLUMN user_id TEXT');

    // 6. Add user_id column to conversation_memories table
    await txn.execute('ALTER TABLE conversation_memories ADD COLUMN user_id TEXT');

    // 7. Add user_id column to therapy_insights table
    await txn.execute('ALTER TABLE therapy_insights ADD COLUMN user_id TEXT');

    // 8. Add user_id column to emotional_states table
    await txn.execute('ALTER TABLE emotional_states ADD COLUMN user_id TEXT');

    // 9. Add user_id column to user_anchors table
    await txn.execute('ALTER TABLE user_anchors ADD COLUMN user_id TEXT');

    // 10. Add user_id column to user_progress table
    await txn.execute('ALTER TABLE user_progress ADD COLUMN user_id TEXT');

    // 11. Create indexes for fast user-based queries
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_mood_logs_user_id ON mood_logs(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_conversation_memories_user_id ON conversation_memories(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_therapy_insights_user_id ON therapy_insights(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_emotional_states_user_id ON emotional_states(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_user_anchors_user_id ON user_anchors(user_id)');
    await txn.execute('CREATE INDEX IF NOT EXISTS idx_user_progress_user_id ON user_progress(user_id)');

    debugPrint('Migration to version 9 completed - all tables now have user_id');
  } catch (e) {
    debugPrint('Error during migration to version 9: $e');
    rethrow;
  }
}
```

**Step 3:** Update table creation for new installs
```dart
Future<void> _createDatabase(Database db, int version) async {
  // ... existing code ...

  // Update sessions table
  await txn.execute('''
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,  -- ADDED
      title TEXT,
      summary TEXT,
      action_items TEXT,
      created_at TEXT,
      last_modified TEXT,
      is_synced INTEGER
    )
  ''');

  // Update messages table
  await txn.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      session_id TEXT,
      user_id TEXT NOT NULL,  -- ADDED
      content TEXT,
      is_user INTEGER,
      timestamp TEXT,
      audio_url TEXT,
      FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
    )
  ''');

  // Update mood_logs table
  await txn.execute('''
    CREATE TABLE mood_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,  -- ADDED
      mood TEXT,
      timestamp TEXT,
      notes TEXT
    )
  ''');

  // Update conversations table
  await txn.execute('''
    CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,  -- ADDED
      user_message TEXT NOT NULL,
      ai_response TEXT NOT NULL,
      metadata TEXT,
      timestamp TEXT NOT NULL
    )
  ''');

  // ... repeat for all other tables ...

  // Create indexes
  await txn.execute('CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)');
  await txn.execute('CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id)');
  // ... create indexes for all tables ...
}
```

#### 2.2 Create User Context Service
**File:** `ai_therapist_app/lib/services/user_context_service.dart` (NEW FILE)

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service to provide current user context throughout the app
class UserContextService {
  static final UserContextService _instance = UserContextService._internal();
  factory UserContextService() => _instance;
  UserContextService._internal();

  /// Get the current Firebase user ID (UID)
  /// This is the source of truth for user identity
  String? getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('UserContextService: No authenticated user found');
      return null;
    }

    debugPrint('UserContextService: Current user_id = ${user.uid}');
    return user.uid;
  }

  /// Check if a user is currently authenticated
  bool isUserAuthenticated() {
    return FirebaseAuth.instance.currentUser != null;
  }

  /// Get current user email (if available)
  String? getCurrentUserEmail() {
    return FirebaseAuth.instance.currentUser?.email;
  }

  /// Get current user phone (if available)
  String? getCurrentUserPhone() {
    return FirebaseAuth.instance.currentUser?.phoneNumber;
  }

  /// Get provider-specific info
  Map<String, dynamic> getCurrentUserInfo() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    return {
      'uid': user.uid,
      'email': user.email,
      'phone': user.phoneNumber,
      'displayName': user.displayName,
      'providers': user.providerData.map((p) => p.providerId).toList(),
    };
  }
}
```

**Register in DI:**
```dart
// In service_locator.dart or dependency_container.dart
final userContextService = UserContextService();
```

#### 2.3 Update Session Repository
**File:** `ai_therapist_app/lib/data/repositories/session_repository.dart`

**Changes:**

1. **Inject UserContextService:**
```dart
class SessionRepository implements ISessionRepository {
  final IApiClient apiClient;
  final IAppDatabase appDatabase;
  final UserContextService userContextService;  // ADDED

  SessionRepository({
    required this.apiClient,
    required this.appDatabase,
    required this.userContextService,  // ADDED
  });
```

2. **Update createSession:**
```dart
@override
Future<Session> createSession(String title, {String? id}) async {
  final userId = userContextService.getCurrentUserId();
  if (userId == null) {
    throw Exception('No authenticated user - cannot create session');
  }

  // ... existing server call code ...

  // Save to local database WITH user_id
  await appDatabase.insert('sessions', {
    'id': id ?? session.id,
    'user_id': userId,  // ADDED
    'title': session.title,
    'summary': session.summary,
    'action_items': jsonEncode(session.actionItems),
    'created_at': session.createdAt.toUtc().toIso8601String(),
    'last_modified': session.lastModified.toUtc().toIso8601String(),
    'is_synced': 1,
  });

  return session;
}
```

3. **Update getSessions with user filtering:**
```dart
@override
Future<List<Session>> getSessions() async {
  final userId = userContextService.getCurrentUserId();
  if (userId == null) {
    throw Exception('No authenticated user - cannot fetch sessions');
  }

  try {
    // Fetch from server (already filtered by auth token)
    final response = await apiClient.get('/sessions');
    final sessions = sessionsJson.map((json) => Session.fromJson(json)).toList();

    // Save to local DB WITH user_id
    await appDatabase.transaction((txn) async {
      for (final session in sessions) {
        await txn.insert('sessions', {
          'id': session.id,
          'user_id': userId,  // ADDED
          'title': session.title,
          // ... rest of fields
        });
      }
    });

    return sessions;
  } catch (e) {
    print('Error fetching from server, falling back to local DB: $e');

    // CRITICAL: Filter local sessions by user_id
    final results = await appDatabase.query(
      'sessions',
      where: 'user_id = ?',        // ADDED
      whereArgs: [userId],          // ADDED
    );

    return results.map((data) => Session(
      id: data['id'] as String,
      title: data['title'] as String,
      // ... rest of mapping
    )).toList();
  }
}
```

4. **Update saveSession:**
```dart
@override
Future<Session> saveSession({
  required String sessionId,
  required String title,
  required String summary,
  List<String> actionItems = const [],
  required List<Map<String, dynamic>> messages,
  bool sync = true,
}) async {
  final userId = userContextService.getCurrentUserId();
  if (userId == null) {
    throw Exception('No authenticated user - cannot save session');
  }

  final now = DateTime.now();

  await appDatabase.transaction((txn) async {
    int updated = await txn.update(
      'sessions',
      {
        'title': title,
        'summary': summary,
        'action_items': jsonEncode(actionItems),
        'last_modified': now.toIso8601String(),
        'is_synced': 0,
      },
      where: 'id = ? AND user_id = ?',     // ADDED user_id check
      whereArgs: [sessionId, userId],       // ADDED userId
    );

    if (updated == 0) {
      await txn.insert('sessions', {
        'id': sessionId,
        'user_id': userId,  // ADDED
        'title': title,
        'summary': summary,
        'action_items': jsonEncode(actionItems),
        'created_at': now.toIso8601String(),
        'last_modified': now.toIso8601String(),
        'is_synced': 0,
      });
    }

    // Save messages with user_id
    await _saveMessagesToLocalDBTxn(txn, sessionId, userId, messages, now);
  });

  // ... rest of method
}
```

5. **Update message saving helper:**
```dart
Future<void> _saveMessagesToLocalDBTxn(
  dynamic txn,
  String sessionId,
  String userId,  // ADDED parameter
  List<dynamic> messages,
  DateTime timestamp
) async {
  for (final message in messages) {
    if (message is Map<String, dynamic>) {
      await txn.insert('messages', {
        'id': message['id'] ?? 'msg_${timestamp.millisecondsSinceEpoch}_${messages.indexOf(message)}',
        'session_id': sessionId,
        'user_id': userId,  // ADDED
        'content': message['content'] ?? '',
        'is_user': message['isUser'] == true ? 1 : 0,
        'timestamp': message['timestamp'] ?? timestamp.toIso8601String(),
        'audio_url': message['audioUrl'],
      });
    }
  }
}
```

#### 2.4 Update Other Repositories
**Files to Update:**

1. **`message_repository.dart`** - Add user_id filtering
2. **`log_repo.dart`** - Add user_id to mood logs
3. **Any repository that accesses:** `conversations`, `therapy_insights`, `emotional_states`, `user_anchors`, `user_progress`

**Pattern to follow:**
```dart
// Inject UserContextService
final UserContextService userContextService;

// Add user_id when inserting
await appDatabase.insert('table_name', {
  'user_id': userContextService.getCurrentUserId(),
  // ... other fields
});

// Filter by user_id when querying
final results = await appDatabase.query(
  'table_name',
  where: 'user_id = ?',
  whereArgs: [userContextService.getCurrentUserId()],
);
```

#### 2.5 Add Logout Data Cleanup (Optional but Recommended)
**File:** `ai_therapist_app/lib/services/auth_service.dart`

```dart
@override
Future<bool> logout() async {
  try {
    await _ensureInitialized();

    final userId = await _getCurrentUserId();

    // Firebase logout
    await FirebaseAuth.instance.signOut();

    // Clear auth tokens
    await _secureStorage.delete(key: AUTH_TOKEN_KEY);
    await _prefs.remove(AUTH_TOKEN_KEY);
    _cachedAuthToken = null;
    _apiClientInstance?.clearAuthToken();

    // OPTIONAL: Clear local data for this user
    // (User data remains in DB but won't be shown to next user)
    // If you want to delete user data on logout:
    /*
    final db = await AppDatabase().database;
    await db.delete('sessions', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('messages', where: 'user_id = ?', whereArgs: [userId]);
    // ... delete from other tables
    */

    // Emit logout event
    await _authEventHandler.handleUserLoggedOut(UserLoggedOutEvent(
      userId: userId,
    ));

    return true;
  } catch (e) {
    print('Logout error: $e');
    return false;
  }
}
```

---

### Phase 3: Data Migration Strategy

#### 3.1 Handle Existing Users

**Problem:** Existing local data has no `user_id` values.

**Option A: Delete All Local Data (Simplest)**
```dart
Future<void> _migrateToV9(Transaction txn) async {
  // ... add user_id columns ...

  // Delete all existing data (fresh start)
  await txn.delete('sessions');
  await txn.delete('messages');
  await txn.delete('mood_logs');
  // ... delete from all tables

  debugPrint('Deleted all local data during migration to v9 - users will re-sync from server');
}
```

**Option B: Assign to Current User (Risky)**
```dart
Future<void> _migrateToV9(Transaction txn) async {
  // ... add user_id columns ...

  // Get current Firebase user
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  if (currentUserId != null) {
    // Assign all existing data to current user
    await txn.rawUpdate('UPDATE sessions SET user_id = ?', [currentUserId]);
    await txn.rawUpdate('UPDATE messages SET user_id = ?', [currentUserId]);
    // ... update all tables

    debugPrint('Assigned all existing data to current user: $currentUserId');
  } else {
    // No user logged in - delete everything
    await txn.delete('sessions');
    await txn.delete('messages');
    // ...
  }
}
```

**Recommendation:** Use Option A (delete all local data) and force re-sync from backend on next login. This is safest and prevents data leakage.

#### 3.2 Backend Migration (None Required)

Backend schema already has proper user isolation:
- `sessions` table has `user_id` column (line 13 in `app/models/session.py`)
- Backend endpoints already filter by authenticated user's `user_id`
- No backend data migration needed

---

### Phase 4: Testing Plan (0.5 day)

#### 4.1 Backend Testing

**Test Script:** `test_user_isolation.sh`
```bash
#!/bin/bash

# Start local backend
cd ai_therapist_backend
python dev_server.py &
BACKEND_PID=$!

sleep 3

echo "=== Test 1: Different Google emails create different users ==="
curl -X POST http://localhost:8000/auth/test \
  -H "Content-Type: application/json" \
  -d '{"provider":"google","uid":"alice123","email":"alice@gmail.com"}' \
  | jq '.user_id'
# Expected: user_id=1

curl -X POST http://localhost:8000/auth/test \
  -H "Content-Type: application/json" \
  -d '{"provider":"google","uid":"bob456","email":"bob@gmail.com"}' \
  | jq '.user_id'
# Expected: user_id=2 (different from alice)

echo "=== Test 2: Phone auth creates separate user ==="
curl -X POST http://localhost:8000/auth/test \
  -H "Content-Type: application/json" \
  -d '{"provider":"phone","uid":"phone123","email":null}' \
  | jq '.user_id'
# Expected: user_id=3 (different from alice and bob)

echo "=== Test 3: Same provider+uid returns same user ==="
curl -X POST http://localhost:8000/auth/test \
  -H "Content-Type: application/json" \
  -d '{"provider":"google","uid":"alice123","email":"alice@gmail.com"}' \
  | jq '.user_id'
# Expected: user_id=1 (same as first request)

kill $BACKEND_PID
```

#### 4.2 Frontend Testing

**Manual Test Cases:**

1. **Test User Isolation:**
   ```
   1. Clear app data completely
   2. Login with alice@gmail.com (Google)
   3. Create session "Alice Session 1"
   4. Logout
   5. Login with bob@gmail.com (Google)
   6. Verify: No sessions visible
   7. Create session "Bob Session 1"
   8. Logout
   9. Login with alice@gmail.com (Google) again
   10. Verify: Only "Alice Session 1" visible, NOT "Bob Session 1"
   ```

2. **Test Phone Auth Isolation:**
   ```
   1. Login with phone +15551111111
   2. Create session "Phone Session 1"
   3. Logout
   4. Login with alice@gmail.com
   5. Verify: No sessions visible
   ```

3. **Test Data Persistence:**
   ```
   1. Login with alice@gmail.com
   2. Create 3 sessions
   3. Force close app
   4. Reopen app
   5. Verify: All 3 sessions still visible for alice@gmail.com
   6. Logout
   7. Login with bob@gmail.com
   8. Verify: No sessions visible for bob
   ```

4. **Test Migration:**
   ```
   1. Install old version with existing data
   2. Create 2 sessions while logged in as alice@gmail.com
   3. Install new version (auto-runs migration)
   4. Verify: Alice's sessions are retained
   5. Logout, login as bob@gmail.com
   6. Verify: Bob sees empty state
   ```

#### 4.3 Automated Tests

**File:** `ai_therapist_app/test/repositories/session_repository_test.dart`

```dart
void main() {
  group('SessionRepository - User Isolation', () {
    late MockAppDatabase mockDatabase;
    late MockApiClient mockApiClient;
    late MockUserContextService mockUserContext;
    late SessionRepository repository;

    setUp(() {
      mockDatabase = MockAppDatabase();
      mockApiClient = MockApiClient();
      mockUserContext = MockUserContextService();
      repository = SessionRepository(
        apiClient: mockApiClient,
        appDatabase: mockDatabase,
        userContextService: mockUserContext,
      );
    });

    test('getSessions filters by current user ID', () async {
      // Setup
      when(() => mockUserContext.getCurrentUserId()).thenReturn('user_alice');
      when(() => mockApiClient.get('/sessions')).thenThrow(Exception('Network error'));
      when(() => mockDatabase.query('sessions', where: 'user_id = ?', whereArgs: ['user_alice']))
          .thenAnswer((_) async => [
            {'id': 'session1', 'user_id': 'user_alice', 'title': 'Alice Session'},
          ]);

      // Execute
      final sessions = await repository.getSessions();

      // Verify
      expect(sessions.length, 1);
      expect(sessions[0].title, 'Alice Session');
      verify(() => mockDatabase.query('sessions', where: 'user_id = ?', whereArgs: ['user_alice']));
    });

    test('createSession throws when no user authenticated', () async {
      // Setup
      when(() => mockUserContext.getCurrentUserId()).thenReturn(null);

      // Execute & Verify
      expect(
        () => repository.createSession('Test Session'),
        throwsA(isA<Exception>()),
      );
    });

    test('saveSession includes user_id in database insert', () async {
      // Setup
      when(() => mockUserContext.getCurrentUserId()).thenReturn('user_bob');
      when(() => mockDatabase.transaction(any())).thenAnswer((invocation) async {
        final callback = invocation.positionalArguments[0] as Function;
        final mockTxn = MockTransaction();
        return await callback(mockTxn);
      });

      // Execute
      await repository.saveSession(
        sessionId: 'session123',
        title: 'Bob Session',
        summary: 'Summary',
        messages: [],
      );

      // Verify user_id was included in insert
      verify(() => mockDatabase.transaction(any()));
    });
  });
}
```

---

## Rollout Plan

### Step 1: Backend Deployment (Low Risk)
1. Deploy backend changes to staging environment
2. Run backend test script
3. Verify different auth methods create different users
4. Deploy to production
5. **No impact on existing users** (existing user_id values remain unchanged)

### Step 2: Frontend Deployment (Medium Risk)
1. **Release v1.X.0 with migration** to internal testers
2. Test migration on devices with existing data
3. Verify user isolation works correctly
4. **Release to production** with staged rollout:
   - Day 1: 10% of users
   - Day 3: 50% of users
   - Day 7: 100% of users
5. Monitor crash reports and support tickets

### Step 3: User Communication
**In-app notification (optional):**
```
"Security Update: We've improved account security.
Each login method now maintains separate data.
If you use multiple login methods, you may need to
choose one as your primary account."
```

---

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Data loss during migration | HIGH | MEDIUM | Use Option A (delete local data, force re-sync from backend) |
| Users locked out after update | HIGH | LOW | Ensure Firebase Auth remains unchanged; only data isolation changes |
| Performance impact from user_id filtering | MEDIUM | LOW | Database indexes on user_id columns (already in plan) |
| Users confused by separate accounts | MEDIUM | MEDIUM | Add in-app guidance; support documentation |
| Backend API breaking changes | LOW | LOW | Backend changes are additive only (no breaking changes) |

---

## Success Metrics

### Functional Metrics
- ✅ User A cannot see User B's sessions
- ✅ Same user can see their sessions after logout/login
- ✅ Different auth methods maintain separate data
- ✅ No crashes during migration

### Performance Metrics
- Session load time: < 500ms (same as current)
- Database migration time: < 2 seconds
- App launch time: No degradation

### User Metrics
- Crash-free rate: > 99.5%
- Support tickets about "missing data": < 5% of users
- User retention: No negative impact

---

## Estimated Effort

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| **Backend** | Modify auth logic, testing | 1 day |
| **Frontend - Schema** | Database migration, UserContextService | 0.5 day |
| **Frontend - Repositories** | Update all repositories with user filtering | 1 day |
| **Testing** | Automated tests, manual QA | 0.5 day |
| **Documentation** | Update README, migration guide | 0.5 day |
| **TOTAL** | | **3.5 days** |

With buffer for edge cases and bug fixes: **4-5 days total**

---

## Open Questions

1. **Should we provide a "merge accounts" feature in the future?**
   - Allow users to explicitly link Google + Phone identities
   - Complexity: High (requires data migration logic)
   - User demand: Unknown

2. **How should we handle users who already use multiple login methods?**
   - Option A: Treat as separate accounts (current plan)
   - Option B: Provide one-time migration to merge
   - Recommendation: Start with Option A, add Option B if users request it

3. **Should we delete local data on logout?**
   - Pro: Better privacy (no data left on shared devices)
   - Con: Slower re-login (must re-download from server)
   - Recommendation: Make it configurable in settings

4. **Do we need to support offline mode with multiple users?**
   - Current plan: Requires online authentication to determine user_id
   - Offline use cases may be limited
   - Can be addressed in future iteration if needed

---

## Appendix: Files to Modify

### Backend
- ✏️ `ai_therapist_backend/app/api/deps/auth.py` - Modify `_get_or_create_user()`
- ✏️ `ai_therapist_backend/README.md` - Document auth behavior

### Frontend
- ✏️ `ai_therapist_app/lib/data/datasources/local/app_database.dart` - Add migration v9
- ✨ `ai_therapist_app/lib/services/user_context_service.dart` - NEW FILE
- ✏️ `ai_therapist_app/lib/data/repositories/session_repository.dart` - Add user filtering
- ✏️ `ai_therapist_app/lib/data/repositories/message_repository.dart` - Add user filtering
- ✏️ `ai_therapist_app/lib/data/repositories/log_repo.dart` - Add user filtering
- ✏️ `ai_therapist_app/lib/services/auth_service.dart` - Optional data cleanup on logout
- ✏️ `ai_therapist_app/lib/di/service_locator.dart` - Register UserContextService

### Tests
- ✨ `ai_therapist_backend/tests/test_auth_isolation.py` - NEW FILE
- ✨ `ai_therapist_app/test/repositories/session_repository_test.dart` - Add isolation tests

---

**Document Version:** 1.0
**Last Updated:** 2025-10-22
**Author:** Claude Code
**Status:** Ready for Engineering Review
