import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../services/onboarding_service.dart';
import '../../services/user_profile_service.dart';

class ProfileGoalsScreen extends StatefulWidget {
  const ProfileGoalsScreen({Key? key}) : super(key: key);

  @override
  State<ProfileGoalsScreen> createState() => _ProfileGoalsScreenState();
}

class _ProfileGoalsScreenState extends State<ProfileGoalsScreen> {
  final _onboardingService = GetIt.instance<OnboardingService>();
  final _userProfileService = GetIt.instance<UserProfileService>();
  
  final _otherGoalController = TextEditingController();
  bool _isLoading = false;
  
  // Common therapy goals
  final List<String> _commonGoals = [
    'Reduce anxiety',
    'Improve mood',
    'Manage stress better',
    'Build confidence',
    'Improve relationships',
    'Process trauma',
    'Develop coping skills',
    'Improve sleep',
    'Find purpose/meaning',
    'Work-life balance',
  ];
  
  // Selected goals
  final Set<String> _selectedGoals = {};
  
  @override
  void initState() {
    super.initState();
    // Pre-fill with existing data if available
    if (_userProfileService.profile != null && 
        _userProfileService.profile!.goals.isNotEmpty) {
      for (final goal in _userProfileService.profile!.goals) {
        if (_commonGoals.contains(goal)) {
          _selectedGoals.add(goal);
        } else {
          _otherGoalController.text = goal;
        }
      }
    }
  }
  
  @override
  void dispose() {
    _otherGoalController.dispose();
    super.dispose();
  }
  
  void _toggleGoal(String goal) {
    setState(() {
      if (_selectedGoals.contains(goal)) {
        _selectedGoals.remove(goal);
      } else {
        _selectedGoals.add(goal);
      }
    });
  }
  
  Future<void> _saveAndContinue() async {
    if (_selectedGoals.isEmpty && _otherGoalController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one goal')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final goals = _selectedGoals.toList();
      
      // Add custom goal if provided
      if (_otherGoalController.text.trim().isNotEmpty) {
        goals.add(_otherGoalController.text.trim());
      }
      
      await _userProfileService.updateProfile(
        goals: goals,
      );
      
      // Show a success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goals saved successfully')),
        );
      }
      
      // Continue to the next step in the onboarding flow
      await _onboardingService.goToNextStep();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving goals: $e')),
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
        title: const Text('Your Therapy Goals'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _onboardingService.goToStep(OnboardingStep.profileReason);
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
                'What are your goals?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select the goals you hope to achieve through therapy. Choose all that apply.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              
              // Goal selection
              ..._buildGoalOptions(),
              
              // Custom goal entry
              const SizedBox(height: 16),
              Text(
                'Add a custom goal (optional)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _otherGoalController,
                decoration: InputDecoration(
                  labelText: 'Your goal',
                  hintText: 'Enter a specific goal not listed above',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              
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
  
  List<Widget> _buildGoalOptions() {
    return _commonGoals.map((goal) {
      final isSelected = _selectedGoals.contains(goal);
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: InkWell(
          onTap: () => _toggleGoal(goal),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
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
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    goal,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
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