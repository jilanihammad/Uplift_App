import 'package:ai_therapist_app/services/langchain/custom_langchain.dart';

/// Provides reusable prompt templates for the therapy application
class TherapyPromptTemplates {
  // System prompt template for the therapist
  static final therapistSystemPrompt = PromptTemplate.fromTemplate(
    '''You are an AI therapist named Uplift, designed to provide mental health support. 
Your approach is: {therapist_style}

Current session context:
- Session phase: {session_phase}
- Main topic: {topic}
- Identified issues: {issues}
- User's mood: {mood}

Instructions for this response:
{specific_instructions}

Remember to be empathetic, non-judgmental, and focus on the user's needs. Ask thoughtful questions and provide evidence-based therapeutic insights.
'''
  );
  
  // Therapeutic stance options
  static const Map<String, String> therapistStances = {
    'cbt': 'Cognitive Behavioral Therapy focused. You help identify negative thought patterns and develop coping strategies to change them.',
    'psychodynamic': 'Psychodynamic focused. You explore unconscious processes and how past experiences influence current behavior.',
    'humanistic': 'Humanistic and person-centered. You focus on the whole person and their potential for growth and self-actualization.',
    'solution_focused': 'Solution-focused. You focus on the present and future, helping identify goals and build solutions rather than analyzing problems.',
    'mindfulness': 'Mindfulness-based. You incorporate mindfulness principles to help users develop greater awareness and acceptance.',
    'eclectic': 'Eclectic and integrative. You draw from multiple therapeutic approaches based on what might be most helpful for the specific situation.',
  };
  
  // Template for summarizing a therapy session
  static final sessionSummaryPrompt = PromptTemplate.fromTemplate(
    '''Review the following therapy conversation and create a concise, helpful summary with these components:
1. Main concerns or issues discussed
2. Key insights or realizations
3. Therapeutic approaches suggested
4. Action items or homework agreed upon
5. Overall progress and themes

The summary should be in bullet point format, balanced between being concise and capturing important details.

Conversation:
{conversation_text}
'''
  );
  
  // Template for generating personalized coping strategies
  static final copingStrategiesPrompt = PromptTemplate.fromTemplate(
    '''Based on the user's situation:
{situation_description}

And their specific challenges:
{challenges}

Generate 3-5 personalized coping strategies that are:
1. Evidence-based and effective for their situation
2. Realistic and achievable given their circumstances 
3. Specific and actionable
4. Supportive of their overall wellbeing

Format each strategy with a title and brief explanation.
'''
  );
  
  // Template for guided reflection exercises
  static final reflectionExercisePrompt = PromptTemplate.fromTemplate(
    '''Create a brief guided reflection exercise for the user based on:
- Their current concern: {current_concern}
- Their emotional state: {emotional_state}
- Their therapeutic goals: {therapeutic_goals}

The exercise should:
1. Help them gain insight into their situation
2. Be completable in 5-10 minutes
3. Include 3-5 specific reflection questions
4. Provide clear but gentle guidance

Structure the exercise with a brief introduction, the reflection questions, and a closing note.
'''
  );
  
  // Template for mental health education
  static final psychoeducationPrompt = PromptTemplate.fromTemplate(
    '''Provide concise, accurate psychoeducation about: {topic}

The explanation should:
1. Help the user understand {topic} in an accessible way
2. Include 2-3 key scientific insights without jargon
3. Normalize their experience when appropriate
4. Connect the information to their personal situation: {user_situation}
5. Be encouraging without minimizing challenges

Keep the tone supportive and the language clear. Aim for understanding rather than overwhelming with information.
'''
  );
  
  // Format the prompt for a particular therapeutic stance
  static String formatTherapistPrompt({
    required String therapistStyle,
    required String sessionPhase,
    String topic = '',
    String issues = '',
    String mood = '',
    required String specificInstructions,
  }) {
    try {
      final stance = therapistStances[therapistStyle] ?? therapistStances['eclectic']!;
      
      return therapistSystemPrompt.format({
        'therapist_style': stance,
        'session_phase': sessionPhase,
        'topic': topic.isEmpty ? 'Not yet identified' : topic,
        'issues': issues.isEmpty ? 'Not yet identified' : issues,
        'mood': mood.isEmpty ? 'Not specified' : mood,
        'specific_instructions': specificInstructions,
      });
    } catch (e) {
      // Fallback prompt if formatting fails
      return '''You are an empathetic AI therapist named Uplift. Respond thoughtfully to the user's message.
      
Instructions: $specificInstructions''';
    }
  }
  
  // Format a session summary prompt
  static String formatSessionSummaryPrompt(String conversationText) {
    try {
      return sessionSummaryPrompt.format({
        'conversation_text': conversationText,
      });
    } catch (e) {
      // Fallback prompt if formatting fails
      return 'Summarize the therapy session conversation in a few bullet points.';
    }
  }
  
  // Format a coping strategies prompt
  static String formatCopingStrategiesPrompt({
    required String situationDescription,
    required String challenges,
  }) {
    try {
      return copingStrategiesPrompt.format({
        'situation_description': situationDescription,
        'challenges': challenges,
      });
    } catch (e) {
      // Fallback prompt if formatting fails
      return 'Suggest 3-5 coping strategies for the user based on their situation.';
    }
  }
} 