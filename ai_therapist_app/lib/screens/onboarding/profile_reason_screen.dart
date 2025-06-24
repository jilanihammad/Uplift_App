import 'package:flutter/material.dart';
import '../../di/dependency_container.dart';
import '../../services/onboarding_service.dart';
import '../../services/user_profile_service.dart';

class ProfileReasonScreen extends StatefulWidget {
  const ProfileReasonScreen({Key? key}) : super(key: key);

  @override
  State<ProfileReasonScreen> createState() => _ProfileReasonScreenState();
}

class _ProfileReasonScreenState extends State<ProfileReasonScreen> {
  final _onboardingService = DependencyContainer().get<OnboardingService>();
  final _userProfileService = DependencyContainer().get<UserProfileService>();
  
  String? _selectedReason;
  final _otherReasonController = TextEditingController();
  bool _isLoading = false;
  
  // Common therapy reasons
  final List<String> _commonReasons = [
    'Anxiety',
    'Depression',
    'Stress management',
    //'Relationship issues',
    //'Self-esteem',
    //'Life changes',
    //'Trauma',
    'Sleep problems',
    'Other',
  ];
  
  @override
  void initState() {
    super.initState();
    // Pre-fill with existing data if available
    if (_userProfileService.profile != null && 
        _userProfileService.profile!.primaryReason != null) {
      final reason = _userProfileService.profile!.primaryReason!;
      if (_commonReasons.contains(reason)) {
        _selectedReason = reason;
      } else {
        _selectedReason = 'Other';
        _otherReasonController.text = reason;
      }
    }
  }
  
  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }
  
  Future<void> _saveAndContinue() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason for therapy')),
      );
      return;
    }
    
    if (_selectedReason == 'Other' && _otherReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your reason for therapy')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _userProfileService.updateProfile(
        primaryReason: _selectedReason == 'Other' 
            ? _otherReasonController.text.trim() 
            : _selectedReason,
      );
      
      await _onboardingService.goToNextStep();
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
        title: const Text('Your Therapy Goals'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _onboardingService.goToStep(OnboardingStep.profileName);
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
                'What brings you here today?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select your primary reason for seeking therapy. This helps us tailor our approach to your needs.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              
              // Reason selection
              ..._buildReasonOptions(),
              
              // Other reason text field
              if (_selectedReason == 'Other') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _otherReasonController,
                  decoration: InputDecoration(
                    labelText: 'Please specify',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              
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
  
  List<Widget> _buildReasonOptions() {
    return _commonReasons.map((reason) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedReason = reason;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedReason == reason
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade300,
                width: 2,
              ),
              color: _selectedReason == reason
                  ? Theme.of(context).primaryColor.withOpacity(0.1)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  _selectedReason == reason
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _selectedReason == reason
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
                ),
                const SizedBox(width: 16),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: _selectedReason == reason
                        ? FontWeight.bold
                        : FontWeight.normal,
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