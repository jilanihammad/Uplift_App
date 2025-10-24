import 'package:flutter/material.dart';

// Enum for different mood states
enum Mood { happy, neutral, sad, anxious, angry, stressed }

// Extension to get emoji for each mood
extension MoodExtension on Mood {
  String get emoji {
    switch (this) {
      case Mood.happy:
        return '😊';
      case Mood.neutral:
        return '😐';
      case Mood.sad:
        return '😢';
      case Mood.anxious:
        return '😰';
      case Mood.angry:
        return '😠';
      case Mood.stressed:
        return '😫';
    }
  }

  String get label {
    switch (this) {
      case Mood.happy:
        return 'Happy';
      case Mood.neutral:
        return 'Neutral';
      case Mood.sad:
        return 'Sad';
      case Mood.anxious:
        return 'Anxious';
      case Mood.angry:
        return 'Angry';
      case Mood.stressed:
        return 'Stressed';
    }
  }

  Color get color {
    switch (this) {
      case Mood.happy:
        return Colors.yellow;
      case Mood.neutral:
        return Colors.grey;
      case Mood.sad:
        return Colors.blue;
      case Mood.anxious:
        return Colors.purple;
      case Mood.angry:
        return Colors.red;
      case Mood.stressed:
        return Colors.orange;
    }
  }
}

class MoodSelector extends StatelessWidget {
  final Function(Mood) onMoodSelected;

  const MoodSelector({super.key, required this.onMoodSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // First row of moods
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMoodButton(Mood.happy, context),
            _buildMoodButton(Mood.neutral, context),
            _buildMoodButton(Mood.sad, context),
          ],
        ),
        const SizedBox(height: 16),
        // Second row of moods
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMoodButton(Mood.anxious, context),
            _buildMoodButton(Mood.angry, context),
            _buildMoodButton(Mood.stressed, context),
          ],
        ),
      ],
    );
  }

  Widget _buildMoodButton(Mood mood, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          Material(
            color: mood.color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onMoodSelected(mood),
              child: Container(
                width: 70,
                height: 70,
                alignment: Alignment.center,
                child: Text(
                  mood.emoji,
                  style: const TextStyle(fontSize: 32),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            mood.label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
