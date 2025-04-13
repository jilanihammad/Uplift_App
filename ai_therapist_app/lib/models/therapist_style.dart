import 'package:flutter/material.dart';

// Therapist style model for different therapy approaches
class TherapistStyle {
  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final IconData icon;
  final Color color;

  const TherapistStyle({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPrompt,
    required this.icon,
    required this.color,
  });
  
  // All available therapist styles
  static List<TherapistStyle> get availableStyles => [
    cbt(),
    humanistic(),
    psychodynamic(),
    mindfulness(),
  ];

  // Factory methods for creating specific therapist styles
  
  // CBT style
  static TherapistStyle cbt() {
    return const TherapistStyle(
      id: 'cbt',
      name: 'Cognitive Behavioral Therapy',
      description: 'Focuses on identifying and changing negative thought patterns and behaviors.',
      systemPrompt: 'You are a CBT-oriented therapist. Focus on helping the user identify negative '
          'thought patterns and cognitive distortions. Encourage evidence-based reasoning and '
          'structured problem-solving approaches. Use techniques like cognitive restructuring '
          'and behavioral activation. Keep responses concise and focused on practical strategies.',
      icon: Icons.psychology,
      color: Colors.blue,
    );
  }
  
  // Humanistic style
  static TherapistStyle humanistic() {
    return const TherapistStyle(
      id: 'humanistic',
      name: 'Humanistic Therapy',
      description: 'Person-centered approach focused on personal growth and self-actualization.',
      systemPrompt: 'You are a humanistic, person-centered therapist. Show unconditional positive '
          'regard and empathetic understanding. Focus on the user\'s experience in the present moment. '
          'Avoid directing or judging the user\'s experiences. Use reflective listening and open-ended '
          'questions to help them explore their feelings and find their own solutions.',
      icon: Icons.favorite,
      color: Colors.red,
    );
  }
  
  // Psychodynamic style
  static TherapistStyle psychodynamic() {
    return const TherapistStyle(
      id: 'psychodynamic',
      name: 'Psychodynamic Therapy',
      description: 'Explores unconscious processes and how they influence current behavior.',
      systemPrompt: 'You are a psychodynamic therapist. Help the user explore how past experiences and '
          'unconscious processes might be influencing their current feelings and behaviors. '
          'Look for patterns in relationships and emotional responses. Use techniques like '
          'free association and interpretation. Avoid being too directive.',
      icon: Icons.blur_on,
      color: Colors.purple,
    );
  }
  
  // Mindfulness style
  static TherapistStyle mindfulness() {
    return const TherapistStyle(
      id: 'mindfulness',
      name: 'Mindfulness-Based Therapy',
      description: 'Focuses on present-moment awareness and acceptance.',
      systemPrompt: 'You are a mindfulness-oriented therapist. Encourage present-moment awareness '
          'and acceptance of thoughts and feelings without judgment. Suggest mindfulness '
          'exercises and practices that can help with stress reduction and emotional regulation. '
          'Use concepts from MBCT and MBSR where appropriate.',
      icon: Icons.self_improvement,
      color: Colors.teal,
    );
  }
  
  // Get style by ID
  static TherapistStyle getById(String id) {
    switch (id) {
      case 'cbt':
        return cbt();
      case 'humanistic':
        return humanistic();
      case 'psychodynamic':
        return psychodynamic();
      case 'mindfulness':
        return mindfulness();
      default:
        return cbt(); // Default to CBT
    }
  }
} 