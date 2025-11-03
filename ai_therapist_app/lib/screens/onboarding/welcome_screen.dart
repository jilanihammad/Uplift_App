import 'package:flutter/material.dart';

import 'package:ai_therapist_app/config/theme.dart';

import '../../di/dependency_container.dart';
import '../../services/onboarding_service.dart';
import '../widgets/welcome_feature_card.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final onboardingService = DependencyContainer().get<OnboardingService>();
    final theme = Theme.of(context);
    final palette = theme.extension<AppPalette>();

    return Scaffold(
      backgroundColor: palette?.surface ?? theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // High-quality colorful logo
                Center(
                  child: Image.asset(
                    'assets/images/uplift_logo.png', // Replace with your new logo
                    height: 120,
                    width: 120,
                  ),
                ),
                const SizedBox(height: 40),
                // Title with Google-inspired simplicity
                Text(
                  'Welcome to Uplift',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Supportive description
                Text(
                  'Your companion for thoughtful conversations and personal growth, always here when you need it.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color
                        ?.withValues(alpha: 0.72),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                // Feature list with white cards
                ..._buildFeatureItems(context),
                const SizedBox(height: 40),
                // Encouraging message
                Text(
                  "You're taking a positive step towards self-improvement. We're here to support you.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.65),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Vibrant button with white text
                ElevatedButton(
                  onPressed: () {
                    onboardingService.goToNextStep();
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    backgroundColor:
                        palette?.accentPrimary ?? theme.colorScheme.primary,
                    elevation: 3,
                  ),
                  child: Text(
                    "Let's Begin",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ThemeData.estimateBrightnessForColor(
                                  palette?.accentPrimary ??
                                      theme.colorScheme.primary) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFeatureItems(BuildContext context) {
    final features = [
      {
        'icon': Icons.person_outline,
        'title': 'Tailored Support',
        'description': 'We adapt to your needs and preferences.',
      },
      {
        'icon': Icons.chat_bubble_outline,
        'title': 'Thoughtful Conversations',
        'description':
            'Engage in natural, supportive chats using proven techniques.',
      },
      {
        'icon': Icons.track_changes,
        'title': 'Track Your Journey',
        'description': 'See your progress and celebrate milestones.',
      },
    ];

    return features.map((feature) {
      return WelcomeFeatureCard(
        icon: feature['icon'] as IconData,
        title: feature['title'] as String,
        description: feature['description'] as String,
      );
    }).toList();
  }
}
