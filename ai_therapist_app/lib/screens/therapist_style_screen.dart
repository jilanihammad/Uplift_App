import 'package:flutter/material.dart';
import 'package:ai_therapist_app/di/service_locator.dart';
import 'package:ai_therapist_app/models/therapist_style.dart';
import 'package:ai_therapist_app/services/preferences_service.dart';
import 'package:ai_therapist_app/services/therapy_service.dart';

class TherapistStyleScreen extends StatefulWidget {
  const TherapistStyleScreen({Key? key}) : super(key: key);

  @override
  State<TherapistStyleScreen> createState() => _TherapistStyleScreenState();
}

class _TherapistStyleScreenState extends State<TherapistStyleScreen> {
  late PreferencesService _preferencesService;
  late TherapyService _therapyService;
  String _selectedStyleId = '';
  
  @override
  void initState() {
    super.initState();
    _preferencesService = serviceLocator<PreferencesService>();
    _therapyService = serviceLocator<TherapyService>();
    _selectedStyleId = _preferencesService.preferences?.therapistStyleId ?? 'cbt';
  }
  
  Future<void> _selectTherapistStyle(String styleId) async {
    setState(() {
      _selectedStyleId = styleId;
    });
    
    // Update preferences
    await _preferencesService.setTherapistStyle(styleId);
    
    // Update therapy service with the new style
    final style = TherapistStyle.getById(styleId);
    _therapyService.setTherapistStyle(style.systemPrompt);
    
    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Therapist style updated to: ${style.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Therapist Style'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose your preferred therapy approach',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This will personalize how the AI therapist interacts with you',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: TherapistStyle.availableStyles.length,
                itemBuilder: (context, index) {
                  final style = TherapistStyle.availableStyles[index];
                  final isSelected = style.id == _selectedStyleId;
                  
                  return Card(
                    elevation: isSelected ? 4 : 1,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isSelected 
                          ? BorderSide(color: style.color, width: 2) 
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      onTap: () => _selectTherapistStyle(style.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: style.color.withOpacity(0.2),
                              child: Icon(style.icon, color: style.color),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    style.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    style.description,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: style.color,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
} 