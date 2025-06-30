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
  
  const SettingsScreen({
    Key? key,
    this.preferencesService,
    this.notificationService,
    this.themeService,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late IPreferencesService _preferencesService;
  late NotificationService _notificationService;
  late IThemeService _themeService;
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
              ListTile(
                title: const Text('Version'),
                subtitle: const Text('1.0.0 (Beta)'),
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
    final now = DateTime.now();
    final dateTime = DateTime(
      now.year,
      now.month,
      now.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
    return '${timeOfDay.format(context)}';
  }
}
