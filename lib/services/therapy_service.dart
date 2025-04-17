// Process user message without voice
Future<String> processUserMessage(String userMessage) async {
  try {
    print('DEBUG: Processing user message: "${userMessage.substring(0, min(20, userMessage.length))}..."');
    print('DEBUG: Using LLM API endpoint: ${serviceLocator<ConfigService>().llmApiEndpoint}');
    
    // Detect conversation state and analyze user message
    final graphResult = await _conversationGraph.analyzeMessage(userMessage);
    
    // Check cache for existing response
    if (_responseCache.containsKey(userMessage)) {
      print('DEBUG: Cache hit! Using cached response.');
      return _responseCache[userMessage]!;
    }
    
    // Build the request payload
    final systemPrompt = _buildSystemPrompt(graphResult);
    final payload = {
      'message': userMessage,
      'system_prompt': systemPrompt,
    };
    
    print('DEBUG: Sending API request to /ai/response with system prompt length: ${systemPrompt.length}');
    
    // Make the API call
    try {
      final apiClient = serviceLocator<ApiClient>();
      print('DEBUG: ApiClient baseUrl: ${apiClient.baseUrl}');
      
      final response = await apiClient.post('/ai/response', body: payload);
      
      print('DEBUG: Received response from API: ${response != null ? "OK" : "NULL"}');
      
      if (response != null && response.containsKey('response')) {
        // Process insights and save to memory in background
        _processInsightsAndSaveMemory(
          userMessage, 
          response, 
          graphResult
        );
        
        // Cache the response for future use
        _responseCache[userMessage] = response['response'];
        
        // Limit cache size to avoid memory issues
        if (_responseCache.length > 100) {
          // Remove oldest entries when cache gets too large
          final oldestKey = _responseCache.keys.first;
          _responseCache.remove(oldestKey);
        }
        
        return response['response'];
      } else {
        print('DEBUG: Invalid response format. Keys: ${response?.keys.toList() ?? "null"}');
      }
    } catch (e) {
      print('DEBUG: API Error: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      if (e is ApiException) {
        print('DEBUG: API Exception status code: ${e.statusCode}, message: ${e.message}');
      }
      print('DEBUG: Falling back to template-based response');
    }
    
    // Generate fallback response in background
    print('DEBUG: Generating fallback response');
    final fallbackResponse = await compute(
      _generateFallbackResponse, 
      {'message': userMessage, 'templates': _responseTemplates}
    );
    
    // Cache fallback response too
    _responseCache[userMessage] = fallbackResponse;
    
    return fallbackResponse;
  } catch (e) {
    print('DEBUG: Error processing user message: $e');
    
    return "I'm sorry, I'm having trouble processing that right now. Could you try expressing that differently?";
  }
} 