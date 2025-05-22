import 'package:flutter/material.dart';
import '../../services/onboarding_service.dart';
import 'package:get_it/get_it.dart';
import '../widgets/welcome_feature_card.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final onboardingService = GetIt.instance<OnboardingService>();

    return Scaffold(
      backgroundColor: Colors.white, // Clean white background
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
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87, // Dark for readability
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // Supportive description
                Text(
                  'Your companion for thoughtful conversations and personal growth, always here when you need it.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black54, // Subtle dark shade
                    fontFamily: 'Roboto',
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
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                    fontFamily: 'Roboto',
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
                    backgroundColor: const Color(0xFF4285F4), // Google Blue
                    elevation: 3,
                  ),
                  child: const Text(
                    "Let's Begin",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // White text on button
                      fontFamily: 'Roboto',
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
