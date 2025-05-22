import 'package:flutter/material.dart';
import 'package:ai_therapist_app/widgets/mood_selector.dart';

class MoodSelectorScreen extends StatelessWidget {
  final Mood? selectedMood;
  final void Function(Mood) onMoodSelected;

  const MoodSelectorScreen({
    Key? key,
    this.selectedMood,
    required this.onMoodSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).primaryColor.withOpacity(0.05),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'How are you feeling today?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MoodSelector(
                  onMoodSelected: onMoodSelected,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
