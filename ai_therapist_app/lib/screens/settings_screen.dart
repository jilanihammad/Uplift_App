// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/services/notification_service.dart';
import 'package:ai_therapist_app/config/routes.dart';
import 'package:ai_therapist_app/models/therapist_style.dart';

class SettingsScreen extends StatefulWidget {
  final IPreferencesService? preferencesService;
  final NotificationService? notificationService;
  final IThemeService? themeService;
  final IUserProfileService? userProfileService;
  
  const SettingsScreen({
    super.key,
    this.preferencesService,
    this.notificationService,
    this.themeService,
    this.userProfileService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late IPreferencesService _preferencesService;
  late NotificationService _notificationService;
  late IThemeService _themeService;
  late IUserProfileService _userProfileService;
  bool _darkModeEnabled = false;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  String _selectedLanguage = 'English';
  late String _therapistStyleId;
  late bool _useVoiceByDefault;
  TimeOfDay? _dailyCheckInTime;
  bool _dailyCheckInEnabled = false;

  @override
  void initState() {
    super.initState();
    _preferencesService = widget.preferencesService ?? DependencyContainer().preferences;
    _notificationService = widget.notificationService ?? DependencyContainer().get<NotificationService>();
    _themeService = widget.themeService ?? DependencyContainer().theme;
    _userProfileService = widget.userProfileService ?? DependencyContainer().userProfile;

    // Load preferences
    _therapistStyleId =
        _preferencesService.preferences?.therapistStyleId ?? 'cbt';
    _useVoiceByDefault =
        _preferencesService.preferences?.useVoiceByDefault ?? false;
    _dailyCheckInTime = _preferencesService.preferences?.dailyCheckInTime;
    _dailyCheckInEnabled = _dailyCheckInTime != null;
    _darkModeEnabled = _themeService.isDarkMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // User Profile Section
          _buildUserProfileSection(),
          
          _buildSection(
            title: 'Therapy Experience',
            children: [
              ListTile(
                title: const Text('Therapist Style'),
                subtitle: Text(TherapistStyle.getById(_therapistStyleId).name),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  context.push('/settings/therapist_style');
                },
              ),
              SwitchListTile(
                title: const Text('Use Voice by Default'),
                subtitle:
                    const Text('Enable voice input and output by default'),
                value: _useVoiceByDefault,
                onChanged: (value) {
                  setState(() {
                    _useVoiceByDefault = value;
                  });
                  _preferencesService.setUseVoiceByDefault(value);
                },
              ),
            ],
          ),
          _buildSection(
            title: 'Daily Check-in',
            children: [
              SwitchListTile(
                title: const Text('Enable Daily Check-in'),
                subtitle:
                    const Text('Get a reminder to log your mood each day'),
                value: _dailyCheckInEnabled,
                onChanged: (value) {
                  setState(() {
                    _dailyCheckInEnabled = value;
                    if (value && _dailyCheckInTime == null) {
                      // Default to 9:00 AM if not set
                      _dailyCheckInTime = const TimeOfDay(hour: 9, minute: 0);
                    }
                  });

                  if (value) {
                    _preferencesService.setDailyCheckInTime(_dailyCheckInTime);
                    _scheduleDailyCheckIn();
                  } else {
                    _preferencesService.setDailyCheckInTime(null);
                    _cancelDailyCheckIn();
                  }
                },
              ),
              ListTile(
                title: const Text('Check-in Time'),
                subtitle: _dailyCheckInTime != null
                    ? Text(_formatTimeOfDay(_dailyCheckInTime!))
                    : const Text('Not set'),
                trailing: const Icon(Icons.arrow_forward_ios),
                enabled: _dailyCheckInEnabled,
                onTap: _dailyCheckInEnabled ? _selectCheckInTime : null,
              ),
            ],
          ),
          _buildSection(
            title: 'Appearance',
            children: [
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Enable dark theme'),
                value: _darkModeEnabled,
                onChanged: (value) {
                  setState(() {
                    _darkModeEnabled = value;
                  });
                  _themeService
                      .setTheme(value ? ThemeMode.dark : ThemeMode.light);
                },
              ),
              ListTile(
                title: const Text('Language'),
                subtitle: Text(_selectedLanguage),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  _showLanguageDialog();
                },
              ),
              ListTile(
                title: const Text('Text Size'),
                subtitle: const Text('Medium'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // Show text size options
                },
              ),
            ],
          ),
          _buildSection(
            title: 'Notifications',
            children: [
              SwitchListTile(
                title: const Text('Enable Notifications'),
                subtitle: const Text('Receive reminders and updates'),
                value: _notificationsEnabled,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Sounds'),
                subtitle: const Text('Play sounds for notifications'),
                value: _soundEnabled,
                onChanged: _notificationsEnabled
                    ? (value) {
                        setState(() {
                          _soundEnabled = value;
                        });
                      }
                    : null,
              ),
            ],
          ),
          _buildSection(
            title: 'Privacy & Security',
            children: [
              ListTile(
                title: const Text('Data Privacy'),
                subtitle: const Text('Manage your data and privacy settings'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // Navigate to privacy settings
                },
              ),
              ListTile(
                title: const Text('Security'),
                subtitle: const Text('Change password and security options'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // Navigate to security settings
                },
              ),
            ],
          ),
          _buildSection(
            title: 'Developer Tools',
            children: [
              ListTile(
                title: const Text('Diagnostics'),
                subtitle: const Text('Test TTS and LLM functionality'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  context.push(AppRouter.diagnostic);
                },
              ),
            ],
          ),
          _buildSection(
            title: 'About',
            children: [
              const ListTile(
                title: Text('Version'),
                subtitle: Text('1.0.0 (Beta)'),
              ),
              ListTile(
                title: const Text('Terms of Service'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // Show terms of service
                },
              ),
              ListTile(
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  // Show privacy policy
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfileSection() {
    final userProfile = _userProfileService.profile;
    final userName = userProfile?.displayName ?? 'User';
    final userEmail = userProfile?.email;
    
    return _buildSection(
      title: 'Profile',
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: const Text('Your Name'),
          subtitle: Text(
            userProfile?.firstName ?? userProfile?.displayName ?? 'Not set',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          trailing: const Icon(Icons.edit),
          onTap: () => _showEditNameDialog(),
        ),
        if (userEmail != null && userEmail.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(
              userEmail,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              context.push('/profile');
            },
          ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLanguageOption('English'),
              _buildLanguageOption('Spanish'),
              _buildLanguageOption('French'),
              _buildLanguageOption('German'),
              _buildLanguageOption('Chinese'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLanguageOption(String language) {
    return RadioListTile<String>(
      title: Text(language),
      value: language,
      groupValue: _selectedLanguage,
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedLanguage = value;
          });
          Navigator.of(context).pop();
        }
      },
    );
  }

  Future<void> _selectCheckInTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _dailyCheckInTime ?? const TimeOfDay(hour: 9, minute: 0),
    );

    if (picked != null && picked != _dailyCheckInTime) {
      setState(() {
        _dailyCheckInTime = picked;
      });

      _preferencesService.setDailyCheckInTime(picked);
      _scheduleDailyCheckIn();
    }
  }

  void _scheduleDailyCheckIn() {
    if (_dailyCheckInTime != null) {
      _notificationService.scheduleDailyNotification(
        id: 1,
        title: 'Daily Check-in',
        body: 'How are you feeling today? Tap to log your mood.',
        hour: _dailyCheckInTime!.hour,
        minute: _dailyCheckInTime!.minute,
      );
    }
  }

  void _cancelDailyCheckIn() {
    _notificationService.cancelNotification(1);
  }

  String _formatTimeOfDay(TimeOfDay timeOfDay) {
    return timeOfDay.format(context);
  }

  Future<void> _showEditNameDialog() async {
    final currentFirstName = _userProfileService.profile?.firstName ?? 
                             _userProfileService.profile?.displayName ?? '';
    
    final controller = TextEditingController(text: currentFirstName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Your Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('What would you like to be called?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'First name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.of(context).pop(newName);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      try {
        // Update firstName in the service
        await _userProfileService.updateProfile(firstName: result);
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Name updated to "$result"'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
          // Refresh the UI
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating name: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
    
    controller.dispose();
  }
}
