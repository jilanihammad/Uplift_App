// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ai_therapist_app/di/dependency_container.dart';
import 'package:ai_therapist_app/di/interfaces/interfaces.dart';
import 'package:ai_therapist_app/blocs/auth/auth_bloc.dart';
import 'package:ai_therapist_app/blocs/auth/auth_events.dart';
import 'package:ai_therapist_app/blocs/auth/auth_state.dart';
import 'package:ai_therapist_app/models/user_profile.dart';
import 'package:ai_therapist_app/config/llm_config.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatefulWidget {
  final IUserProfileService? userProfileService;
  final IThemeService? themeService;
  final IPreferencesService? preferencesService;

  const ProfileScreen({
    super.key,
    this.userProfileService,
    this.themeService,
    this.preferencesService,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isLoading = true;
  bool _darkModeEnabled = false;

  late IUserProfileService _userProfileService;
  late IThemeService _themeService;
  late IPreferencesService _preferencesService;
  UserProfile? _userProfile;
  late String _selectedVoiceId;

  @override
  void initState() {
    super.initState();
    _userProfileService =
        widget.userProfileService ?? DependencyContainer().userProfile;
    _themeService = widget.themeService ?? DependencyContainer().theme;
    _preferencesService =
        widget.preferencesService ?? DependencyContainer().preferences;
    _loadUserProfile();
    _darkModeEnabled = _themeService.isDarkMode;

    // Initialize voice selection
    _selectedVoiceId = _preferencesService.preferences?.aiVoiceId ??
        LLMConfig.activeTTSVoice;
    if (!LLMConfig.voiceDisplayNames.containsKey(_selectedVoiceId)) {
      if (LLMConfig.availableVoiceIds.isNotEmpty) {
        _selectedVoiceId = LLMConfig.availableVoiceIds.first;
      } else {
        _selectedVoiceId = 'sage'; // fallback
      }
    }
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    // Get the user profile from the service
    _userProfile = _userProfileService.profile;

    if (_userProfile != null) {
      _nameController.text = _userProfile!.name;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _userProfileService.updateProfile(
        name: _nameController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isEditing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          // Navigate to login screen when user is logged out
          context.go('/login');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your Profile'),
          actions: [
            TextButton(
              onPressed: () {
                if (_isEditing) {
                  _saveProfile();
                } else {
                  setState(() {
                    _isEditing = true;
                  });
                }
              },
              child: Text(
                _isEditing ? 'Save' : 'Edit',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _isEditing ? () {} : null,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Change Photo'),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  enabled: _isEditing,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                if (_userProfile != null) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Therapy Information',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _buildProfileInfoCard(
                    'Primary Reason for Therapy',
                    _userProfile!.primaryReason ?? 'Not specified',
                    Icons.healing,
                  ),
                  const SizedBox(height: 12),
                  _buildProfileInfoCard(
                    'Therapy Goals',
                    _userProfile!.goals.isEmpty
                        ? 'No goals specified'
                        : _userProfile!.goals.join(', '),
                    Icons.flag,
                  ),
                ],
                const SizedBox(height: 32),
                const Divider(),
                SwitchListTile(
                  secondary: Icon(
                    _darkModeEnabled ? Icons.dark_mode : Icons.light_mode,
                    color: Theme.of(context).primaryColor,
                  ),
                  title: const Text('Dark Mode'),
                  value: _darkModeEnabled,
                  onChanged: (value) {
                    setState(() {
                      _darkModeEnabled = value;
                    });
                    _themeService
                        .setTheme(value ? ThemeMode.dark : ThemeMode.light);
                  },
                ),
                const Divider(),
                // Voice Selection
                ListTile(
                  leading: Icon(
                    Icons.record_voice_over,
                    color: Theme.of(context).primaryColor,
                  ),
                  title: const Text('AI Voice'),
                  subtitle: Text(LLMConfig.displayNameForVoice(_selectedVoiceId)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: LLMConfig.voiceDisplayNames.length > 1
                      ? _showVoiceSelectionSheet
                      : null,
                ),
                const Divider(),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    BlocProvider.of<AuthBloc>(context).add(LogoutEvent());
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoCard(String title, String content, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(content),
          ],
        ),
      ),
    );
  }

  void _showVoiceSelectionSheet() {
    final voiceEntries = LLMConfig.voiceDisplayNames.entries.toList();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Text(
                    'Choose Voice',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...voiceEntries.map(
                  (entry) => RadioListTile<String>(
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: _selectedVoiceId,
                    onChanged: (value) {
                      if (value != null) {
                        _handleVoiceSelection(value);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleVoiceSelection(String voiceId) async {
    Navigator.of(context).pop();

    try {
      await _preferencesService.setPreferredVoice(voiceId);
      if (!mounted) return;

      setState(() {
        _selectedVoiceId = voiceId;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${LLMConfig.displayNameForVoice(voiceId)} voice selected'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update voice. Please try again.'),
        ),
      );
    }
  }
}
