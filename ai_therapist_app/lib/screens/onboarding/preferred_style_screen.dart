import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../services/onboarding_service.dart';
import '../../services/preferences_service.dart';
import '../../models/therapist_style.dart';

class PreferredStyleScreen extends StatefulWidget {
  const PreferredStyleScreen({Key? key}) : super(key: key);

  @override
  State<PreferredStyleScreen> createState() => _PreferredStyleScreenState();
}

class _PreferredStyleScreenState extends State<PreferredStyleScreen> {
  final _onboardingService = GetIt.instance<OnboardingService>();
  final _preferencesService = GetIt.instance<PreferencesService>();
  
  String? _selectedStyleId;
  bool _isLoading = false;
  
  List<TherapistStyle> _therapistStyles = [];
  
  @override
  void initState() {
    super.initState();
    // Get available styles
    _therapistStyles = TherapistStyle.availableStyles;
    // Pre-fill with existing data if available
    _selectedStyleId = _preferencesService.getCurrentTherapistStyle().id;
  }
  
  Future<void> _saveAndContinue() async {
    if (_selectedStyleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a therapy style')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _preferencesService.updateSinglePreference(
        therapistStyleId: _selectedStyleId,
      );
      await _onboardingService.goToNextStep();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving preference: $e')),
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
        title: const Text('Therapy Approach'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _onboardingService.goToStep(OnboardingStep.profileExperience);
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
                'Choose your therapy approach',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select a therapeutic approach that aligns with your preferences. You can change this later in settings.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              
              // Style options
              ..._buildStyleOptions(),
              
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
  
  List<Widget> _buildStyleOptions() {
    return _therapistStyles.map((style) {
      final isSelected = _selectedStyleId == style.id;
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedStyleId = style.id;
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
                    Expanded(
                      child: Text(
                        style.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      style.icon,
                      color: style.color,
                    ),
                  ],
                ),
                if (style.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 36.0, top: 8.0),
                    child: Text(
                      style.description,
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