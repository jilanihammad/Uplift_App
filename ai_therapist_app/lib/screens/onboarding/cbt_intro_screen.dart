import 'package:flutter/material.dart';
import '../../di/dependency_container.dart';
import '../../services/onboarding_service.dart';

class CbtIntroScreen extends StatelessWidget {
  const CbtIntroScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final onboardingService = DependencyContainer().get<OnboardingService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cognitive Behavioral Therapy'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            onboardingService.goToStep(OnboardingStep.moodSetup);
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Understanding CBT',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Cognitive Behavioral Therapy (CBT) is one of the most effective forms of therapy. '
                'Here\'s how it works and how you can benefit from it.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),

              // CBT explanation cards
              _buildInfoCard(
                context,
                title: 'Thoughts → Feelings → Actions',
                content:
                    'CBT focuses on the connection between your thoughts, emotions, and behaviors. Changing negative thought patterns can help improve how you feel and act.',
                icon: Icons.psychology,
              ),

              _buildInfoCard(
                context,
                title: 'Evidence-Based',
                content:
                    'CBT has strong scientific support and has been proven effective for many mental health challenges, including anxiety, depression, and stress.',
                icon: Icons.science,
              ),

              _buildInfoCard(
                context,
                title: 'Practical Skills',
                content:
                    'You\'ll learn practical tools and techniques that you can apply immediately to manage difficult emotions and situations.',
                icon: Icons.build,
              ),

              _buildInfoCard(
                context,
                title: 'Long-Term Benefits',
                content:
                    'The skills you learn through CBT become part of your emotional toolkit, helping you navigate challenges long after therapy ends.',
                icon: Icons.trending_up,
              ),

              const SizedBox(height: 40),

              // Example CBT exercise
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sample CBT Exercise',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Thought Record:\n'
                      '1. Identify a negative thought\n'
                      '2. Rate how strongly you believe it (0-100%)\n'
                      '3. Find evidence that supports and contradicts the thought\n'
                      '4. Create a more balanced alternative thought\n'
                      '5. Rate how you feel now',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // Continue Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => onboardingService.completeOnboarding(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Complete Setup',
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
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String content,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                content,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
