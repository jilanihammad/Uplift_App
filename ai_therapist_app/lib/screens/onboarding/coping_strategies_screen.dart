import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../services/onboarding_service.dart';
import '../../services/user_profile_service.dart';
import '../../models/user_profile.dart';

class CopingStrategiesScreen extends StatefulWidget {
  const CopingStrategiesScreen({Key? key}) : super(key: key);

  @override
  State<CopingStrategiesScreen> createState() => _CopingStrategiesScreenState();
}

class _CopingStrategiesScreenState extends State<CopingStrategiesScreen> {
  final _onboardingService = GetIt.instance<OnboardingService>();
  final _userProfileService = GetIt.instance<UserProfileService>();
  
  TypicalCopingStrategy _selectedCopingStrategy = TypicalCopingStrategy.notSure;
  List<String> _selectedAuxiliaryStrategies = [];
  final _customStrategyController = TextEditingController();
  bool _isLoading = false;
  
  // Primary coping strategies
  final List<Map<String, dynamic>> _primaryStrategies = [
    {
      'value': TypicalCopingStrategy.talkToOthers,
      'name': 'Talk to Others',
      'description': 'I typically reach out to friends or family for support',
    },
    {
      'value': TypicalCopingStrategy.hobbies,
      'name': 'Engage in Hobbies',
      'description': 'I use activities and hobbies to distract myself',
    },
    {
      'value': TypicalCopingStrategy.ignoreIt,
      'name': 'Ignore Problems',
      'description': 'I try not to think about problems and focus elsewhere',
    },
    {
      'value': TypicalCopingStrategy.withdraw, 
      'name': 'Withdraw from Others',
      'description': 'I tend to isolate myself and process alone',
    },
    {
      'value': TypicalCopingStrategy.relaxationTechniques,
      'name': 'Relaxation Techniques',
      'description': 'I use meditation, deep breathing, or other mindfulness practices',
    },
    {
      'value': TypicalCopingStrategy.unhealthyHabits,
      'name': 'Unhealthy Habits',
      'description': 'I sometimes use substances or food to cope',
    },
    {
      'value': TypicalCopingStrategy.notSure,
      'name': 'Not Sure',
      'description': 'I haven\'t thought about how I typically cope',
    },
  ];
  
  // Additional coping strategies
  final List<Map<String, String>> _auxiliaryStrategies = [
    {
      'id': 'deep_breathing',
      'name': 'Deep Breathing',
      'description': 'Slow, controlled breathing to reduce stress',
    },
    {
      'id': 'mindfulness',
      'name': 'Mindfulness Meditation',
      'description': 'Focusing on the present moment',
    },
    {
      'id': 'exercise',
      'name': 'Physical Exercise',
      'description': 'Regular movement to boost mood',
    },
    {
      'id': 'journaling',
      'name': 'Journaling',
      'description': 'Writing down thoughts and feelings',
    },
    {
      'id': 'talking',
      'name': 'Talking to Friends',
      'description': 'Sharing feelings with trusted people',
    },
    {
      'id': 'music',
      'name': 'Listening to Music',
      'description': 'Using music to regulate emotions',
    },
    {
      'id': 'nature',
      'name': 'Spending Time in Nature',
      'description': 'Connecting with the outdoors',
    },
    {
      'id': 'creative',
      'name': 'Creative Activities',
      'description': 'Art, crafts, or other creative outlets',
    },
  ];
  
  @override
  void initState() {
    super.initState();
    // Pre-fill with existing data if available
    if (_userProfileService.profile != null) {
      _selectedCopingStrategy = _userProfileService.profile!.copingStrategy;
      _selectedAuxiliaryStrategies = List.from(_userProfileService.profile!.energizers);
    }
  }
  
  @override
  void dispose() {
    _customStrategyController.dispose();
    super.dispose();
  }
  
  void _toggleAuxiliaryStrategy(String strategyId) {
    setState(() {
      if (_selectedAuxiliaryStrategies.contains(strategyId)) {
        _selectedAuxiliaryStrategies.remove(strategyId);
      } else {
        _selectedAuxiliaryStrategies.add(strategyId);
      }
    });
  }
  
  void _addCustomStrategy() {
    final customStrategy = _customStrategyController.text.trim();
    if (customStrategy.isNotEmpty) {
      setState(() {
        _selectedAuxiliaryStrategies.add('custom:$customStrategy');
        _customStrategyController.clear();
      });
    }
  }
  
  Future<void> _saveAndContinue() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _userProfileService.updateProfile(
        copingStrategy: _selectedCopingStrategy,
        energizers: _selectedAuxiliaryStrategies,
      );
      await _onboardingService.goToNextStep();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving coping strategies: $e')),
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
        title: const Text('Coping Strategies'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _onboardingService.goToStep(OnboardingStep.moodSetup);
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
                'How do you typically cope?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select your primary coping strategy and additional techniques you find helpful.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              
              // Primary coping strategy selection
              const Text(
                'My primary coping approach:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              // Primary strategies
              ...List.generate(_primaryStrategies.length, (index) {
                final strategy = _primaryStrategies[index];
                final isSelected = _selectedCopingStrategy == strategy['value'];
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: RadioListTile<TypicalCopingStrategy>(
                    value: strategy['value'],
                    groupValue: _selectedCopingStrategy,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedCopingStrategy = value;
                        });
                      }
                    },
                    title: Text(
                      strategy['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(strategy['description']),
                    activeColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade300,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                );
              }),
              
              const SizedBox(height: 32),
              
              // Additional strategies heading
              const Text(
                'Additional strategies that help me:',
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              
              // Auxiliary coping strategies list
              ...List.generate(_auxiliaryStrategies.length, (index) {
                final strategy = _auxiliaryStrategies[index];
                final isSelected = _selectedAuxiliaryStrategies.contains(strategy['id']);
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: CheckboxListTile(
                    value: isSelected,
                    onChanged: (_) => _toggleAuxiliaryStrategy(strategy['id']!),
                    title: Text(
                      strategy['name']!,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(strategy['description']!),
                    activeColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade300,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                );
              }),
              
              // Custom strategies from selection
              if (_selectedAuxiliaryStrategies.any((s) => s.startsWith('custom:'))) ...[
                const SizedBox(height: 16),
                const Text(
                  'Your custom coping strategies:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...List.generate(
                  _selectedAuxiliaryStrategies.where((s) => s.startsWith('custom:')).length,
                  (index) {
                    final customStrategy = _selectedAuxiliaryStrategies
                        .where((s) => s.startsWith('custom:'))
                        .elementAt(index)
                        .replaceFirst('custom:', '');
                    
                    return ListTile(
                      title: Text(customStrategy),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedAuxiliaryStrategies.remove('custom:$customStrategy');
                          });
                        },
                      ),
                    );
                  },
                ),
              ],
              
              // Add custom strategy
              const SizedBox(height: 24),
              TextField(
                controller: _customStrategyController,
                decoration: InputDecoration(
                  labelText: 'Add your own coping strategy',
                  hintText: 'E.g., Playing with my pet',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addCustomStrategy,
                  ),
                ),
                onSubmitted: (_) => _addCustomStrategy(),
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
} 