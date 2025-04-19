import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../services/onboarding_service.dart';
import '../../services/progress_service.dart';
import '../../widgets/mood_selector.dart';

class MoodSetupScreen extends StatefulWidget {
  const MoodSetupScreen({Key? key}) : super(key: key);

  @override
  State<MoodSetupScreen> createState() => _MoodSetupScreenState();
}

class _MoodSetupScreenState extends State<MoodSetupScreen> {
  final _onboardingService = GetIt.instance<OnboardingService>();
  final _progressService = GetIt.instance<ProgressService>();

  Mood? _selectedMood;
  bool _isLoading = false;

  Future<void> _saveAndContinue() async {
    if (_selectedMood == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your current mood')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Log the initial mood
      await _progressService.logMood(
          _selectedMood!, "Initial mood during setup");
      await _onboardingService.goToNextStep();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving mood: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Current Mood'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _onboardingService.goToStep(OnboardingStep.profileExperience);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'How are you feeling right now?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Tracking your mood helps us understand your emotional patterns and provide better support.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Mood selector
            MoodSelector(
              onMoodSelected: (mood) {
                setState(() {
                  _selectedMood = mood;
                });
              },
            ),

            if (_selectedMood != null) ...[
              const SizedBox(height: 32),
              Text(
                'You selected: ${_selectedMood!.label}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],

            const Spacer(),

            // Continue Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveAndContinue,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
