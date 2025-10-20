// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ai_therapist_app/config/app_config.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/services/notification_service.dart';
import 'package:ai_therapist_app/services/remote_config_service.dart';
import 'package:ai_therapist_app/utils/feature_flags.dart';
import 'package:ai_therapist_app/config/routes.dart';

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

class _CrisisResource {
  final String region;
  final String description;
  final String contact;
  final bool isLink;

  const _CrisisResource({
    required this.region,
    required this.description,
    required this.contact,
    this.isLink = false,
  });
}

class _SettingsScreenState extends State<SettingsScreen> {
  late IPreferencesService _preferencesService;
  late NotificationService _notificationService;
  late IThemeService _themeService;
  late IUserProfileService _userProfileService;
  final AppConfig _appConfig = AppConfig();
  bool _darkModeEnabled = false;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  String _selectedLanguage = 'English';
  late bool _useVoiceByDefault;
  TimeOfDay? _dailyCheckInTime;
  bool _dailyCheckInEnabled = false;

  @override
  void initState() {
    super.initState();
    _preferencesService =
        widget.preferencesService ?? DependencyContainer().preferences;
    _notificationService = widget.notificationService ??
        DependencyContainer().get<NotificationService>();
    _themeService = widget.themeService ?? DependencyContainer().theme;
    _userProfileService =
        widget.userProfileService ?? DependencyContainer().userProfile;

    // Load preferences
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
          // Notifications section intentionally hidden until backend wiring is ready.
          _buildSection(
            title: 'Privacy & Security',
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Data Privacy'),
                subtitle: const Text('Review how we handle your information'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  _launchExternalUri(Uri.parse(_appConfig.privacyPolicyUrl));
                },
              ),
              ListTile(
                leading: const Icon(Icons.psychology_alt_outlined),
                title: const Text('AI-Assisted Care Disclosure'),
                subtitle:
                    const Text('Understand Maya\'s role and usage guidelines'),
                trailing: const Icon(Icons.info_outline),
                onTap: _showAiDisclosureDialog,
              ),
              ListTile(
                leading: const Icon(Icons.health_and_safety_outlined),
                title: const Text('Crisis Support Resources'),
                subtitle: const Text(
                    'Find immediate help if you or someone else is at risk'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _showCrisisSupportSheet,
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Request Account Deletion'),
                subtitle: const Text('Remove your account and personal data'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: _confirmAccountDeletion,
              ),
            ],
          ),
          // Help & Support section will be added in a future release when backend support is ready.
          if (kDebugMode)
            _buildSection(
              title: 'Debug Tools',
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('Refresh Remote Config'),
                  subtitle: const Text('Fetch latest feature flags from Firebase'),
                  trailing: const Icon(Icons.refresh),
                  onTap: _refreshRemoteConfig,
                ),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Show Feature Flags'),
                  subtitle: const Text('View current feature flag values'),
                  trailing: const Icon(Icons.info_outline),
                  onTap: _showFeatureFlags,
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
                  _launchExternalUri(Uri.parse(_appConfig.termsOfServiceUrl));
                },
              ),
              ListTile(
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  _launchExternalUri(Uri.parse(_appConfig.privacyPolicyUrl));
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
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.8),
            ),
          ),
          trailing: const Icon(Icons.edit),
          onTap: () => _showEditNameDialog(),
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

  Future<bool> _launchExternalUri(Uri uri,
      {LaunchMode mode = LaunchMode.externalApplication}) async {
    try {
      final launched = await launchUrl(uri, mode: mode);
      if (!launched && mounted) {
        _showSnack('Unable to open ${uri.toString()}');
      }
      return launched;
    } catch (e) {
      if (mounted) {
        _showSnack('Unable to open ${uri.toString()}');
      }
      return false;
    }
  }

  void _showAiDisclosureDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI-Assisted Care'),
        content: const Text(
          'Maya provides AI-assisted emotional support and should not replace professional care. '
          'If you are in crisis or facing an emergency, please contact emergency services or a licensed mental health professional immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCrisisSupportSheet() {
    final resources = [
      const _CrisisResource(
        region: 'United States & Canada',
        description: '988 Suicide & Crisis Lifeline',
        contact: '988',
      ),
      const _CrisisResource(
        region: 'United Kingdom & Ireland',
        description: 'Samaritans (24/7)',
        contact: '+44-116-123',
      ),
      const _CrisisResource(
        region: 'Australia',
        description: 'Lifeline (24/7)',
        contact: '13 11 14',
      ),
      const _CrisisResource(
        region: 'International',
        description: 'Find helplines worldwide',
        contact: 'https://www.opencounseling.com/suicide-hotlines',
        isLink: true,
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'If you or someone else is in danger, please contact local emergency services immediately.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              ...resources.map((resource) => ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: Text(resource.region),
                    subtitle: Text(resource.description),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () async {
                      final Uri uri = resource.isLink
                          ? Uri.parse(resource.contact)
                          : Uri(
                              scheme: 'tel',
                              path: resource.contact
                                  .replaceAll(RegExp(r'[^0-9+]'), ''),
                            );
                      final launched = await _launchExternalUri(uri,
                          mode: resource.isLink
                              ? LaunchMode.externalApplication
                              : LaunchMode.platformDefault);
                      if (launched && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAccountDeletion() async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Deleting your account will remove your profile, session history, and stored memories. '
          'This action is permanent. Would you like to continue to the deletion request form?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('CONTINUE'),
          ),
        ],
      ),
    );

    if (shouldProceed == true) {
      final launched = await _launchExternalUri(
        Uri.parse(_appConfig.accountDeletionUrl),
      );
      if (launched && mounted) {
        _showSnack('Opening account deletion request in your browser...');
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
        _userProfileService.profile?.displayName ??
        '';

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

  /// Manually refresh Firebase Remote Config (debug mode only)
  Future<void> _refreshRemoteConfig() async {
    try {
      _showSnack('Fetching latest remote config...');
      await RemoteConfigService().refresh();
      if (mounted) {
        _showSnack('Remote config refreshed! Memory persistence: ${FeatureFlags.isMemoryPersistenceEnabled}');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to refresh remote config: $e');
      }
    }
  }

  /// Show current feature flag values (debug mode only)
  void _showFeatureFlags() {
    final flags = FeatureFlags.getAllFlags();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feature Flags'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in flags.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    Icon(
                      entry.value ? Icons.check_circle : Icons.cancel,
                      color: entry.value ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
