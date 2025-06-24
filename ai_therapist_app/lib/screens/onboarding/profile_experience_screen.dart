import 'package:flutter/material.dart';
import '../../di/dependency_container.dart';
import '../../services/onboarding_service.dart';
import '../../services/user_profile_service.dart';
import '../../models/user_profile.dart';

class ProfileExperienceScreen extends StatefulWidget {
  const ProfileExperienceScreen({Key? key}) : super(key: key);

  @override
  State<ProfileExperienceScreen> createState() => _ProfileExperienceScreenState();
}

class _ProfileExperienceScreenState extends State<ProfileExperienceScreen> {
  final _onboardingService = DependencyContainer().get<OnboardingService>();
  final _userProfileService = DependencyContainer().get<UserProfileService>();
  
  TherapyExperience? _selectedExperience;
  bool _isLoading = false;
  
  // Therapy experience options with descriptions
  final List<Map<String, dynamic>> _experienceOptions = [
    {
      'value': TherapyExperience.none,
      'title': 'No prior experience',
      'description': 'This is my first time trying therapy',
    },
    {
      'value': TherapyExperience.positiveExperience,
      'title': 'Positive experience',
      'description': 'I\'ve had therapy before and found it helpful',
    },
    {
      'value': TherapyExperience.mixedExperience,
      'title': 'Mixed experience',
      'description': 'I\'ve had some good and some not-so-good experiences',
    },
    {
      'value': TherapyExperience.negativeExperience,
      'title': 'Negative experience',
      'description': 'I didn\'t find therapy helpful in the past',
    },
    {
      'value': TherapyExperience.preferNotToSay,
      'title': 'Prefer not to say',
      'description': 'I\'d rather not share my experience',
    },
  ];
  
  @override
  void initState() {
    super.initState();
    // Pre-fill with existing data if available
    if (_userProfileService.profile != null) {
      _selectedExperience = _userProfileService.profile!.therapyExperience;
    }
  }
  
  Future<void> _saveAndContinue() async {
    if (_selectedExperience == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your therapy experience')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _userProfileService.updateProfile(
        therapyExperience: _selectedExperience,
      );
      await _onboardingService.goToStep(OnboardingStep.moodSetup);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e')),
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
        title: const Text('Your Experience'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _onboardingService.goToStep(OnboardingStep.profileGoals);
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
                'Tell us about your therapy experience',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This helps us tailor our approach to your familiarity with therapeutic concepts.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              
              // Experience options
              ..._buildExperienceOptions(),
              
              const SizedBox(height: 48),
              
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
      ),
    );
  }
  
  List<Widget> _buildExperienceOptions() {
    return _experienceOptions.map((option) {
      final isSelected = _selectedExperience == option['value'];
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedExperience = option['value'];
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade300,
                width: 2,
              ),
              color: isSelected
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      option['title'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (option['description'] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 36.0, top: 8.0),
                    child: Text(
                      option['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
} 