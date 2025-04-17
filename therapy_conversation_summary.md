# AI Therapist Conversation Summarization Flow

## Overview
The AI Therapist application uses a structured approach to summarize therapy sessions, providing valuable insights and action items for the user. This process integrates both the client-side Flutter application and the server-side Python backend.

## Client-Side (Flutter)
### End Session Flow
1. The user ends a therapy session by tapping the end session button in the `ChatScreen`
2. A confirmation dialog is shown to confirm the user wants to end the session
3. When confirmed, the app calls `_therapyService.endSession(messageList)` with all conversation messages

### TherapyService Implementation
```dart
Future<Map<String, dynamic>> endSession(List<Map<String, dynamic>> messages) async {
  // Format messages for the API
  final cleanedMessages = messages.map((msg) => {
    'content': msg['content'] ?? '',
    'isUser': msg['isUser'] ?? false,
    'timestamp': msg['timestamp'] ?? DateTime.now().toIso8601String(),
  }).toList();
  
  // Prepare payload with therapeutic context
  final payload = {
    'messages': cleanedMessages,
    'system_prompt': _systemPrompt,
    'memory_context': memoryContext,
    'therapeutic_approach': _therapeuticApproach.toString().split('.').last,
    'visited_nodes': _conversationGraph.currentState?.metadata['visited_nodes'] ?? [],
  };
  
  // Make API call using ApiClient
  try {
    final response = await apiClient.post('/therapy/end_session', body: payload);
    
    // Process response and update memory with insights
    if (response != null) {
      // Extract and store therapeutic goals
      if (response.containsKey('goals') && response['goals'] is List) {
        await _memoryService.updateTherapeuticGoals(List<String>.from(response['goals']));
      }
      
      // Save significant insights for future sessions
      if (response.containsKey('insights') && response['insights'] is List) {
        for (final insight in response['insights']) {
          await _memoryService.addInsight(insight, 'session_summary');
        }
      }
      
      return {
        'summary': response['summary'] ?? "Session summary not available.",
        'actionItems': response.containsKey('action_items') && response['action_items'] is List
            ? List<String>.from(response['action_items'])
            : [],
        'insights': response.containsKey('insights') && response['insights'] is List
            ? List<String>.from(response['insights'])
            : []
      };
    }
  } catch (e) {
    // Fall back to template-based summary if API call fails
  }
}
```

## Server-Side (Python)
### Backend Endpoint
The server exposes a `/therapy/end_session` endpoint that processes the therapy conversation.

```python
@app.post("/therapy/end_session")
async def end_session(request: EndSessionRequest):
    """Generate therapy session summary using Groq's LLM."""
    # Format conversation for prompt
    conversation_text = ""
    for msg in request.messages:
        role = "User" if msg.get("isUser", False) else "Therapist"
        conversation_text += f"{role}: {msg.get('content', '')}\n\n"
    
    # Create structured summarization prompt
    summary_prompt = f"""
    You are a skilled AI therapist assistant. Based on the conversation below, please provide:
    1. A concise summary of the key points discussed
    2. 3-5 actionable suggestions for the client
    3. 2-3 insights about patterns or progress noticed
    
    Therapeutic approach: {request.therapeutic_approach}
    
    CONVERSATION:
    {conversation_text}
    
    Please format your response as JSON with the following structure:
    {{
        "summary": "Summary of the session",
        "action_items": ["Action 1", "Action 2", ...],
        "insights": ["Insight 1", "Insight 2", ...]
    }}
    """
    
    # Send to Groq LLM API and parse response
    async with httpx.AsyncClient() as client:
        # Send prompt to Groq API for generation
        # Parse JSON response and extract structured data
        
        # Return structured summary with action items and insights
        return {
            "summary": session_summary,
            "action_items": action_items,
            "insights": insights
        }
```

## Data Flow
1. User ends the therapy session in the Flutter app
2. App collects all conversation messages and context
3. Data is sent to the backend's `/therapy/end_session` endpoint
4. Backend formats the conversation for the LLM
5. LLM generates a structured summary, action items, and insights
6. Backend returns the structured data to the app
7. App displays the summary to the user and stores insights in memory
8. Session details are saved to local database and synchronized with backend

## Error Handling
- If the API call fails, the app falls back to template-based summaries
- The backend also has fallback templates if the LLM call fails
- Direct HTTP calls are attempted for debugging in development environments

## Response Format
```json
{
  "summary": "Concise summary of the session's key points",
  "action_items": [
    "Specific action for the user to take",
    "Another practical suggestion"
  ],
  "insights": [
    "Observation about patterns or progress",
    "Another therapeutic insight"
  ]
}
``` 