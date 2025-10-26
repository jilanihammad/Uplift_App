// lib/widgets/debug_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../utils/feature_flags.dart';

/// Debug drawer for development and testing features
/// Only shown in debug builds or with special access in release builds
class DebugDrawer extends StatefulWidget {
  const DebugDrawer({super.key});

  @override
  State<DebugDrawer> createState() => _DebugDrawerState();
}

class _DebugDrawerState extends State<DebugDrawer> {
  Map<String, bool> _flags = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFlags();
  }

  void _loadFlags() {
    setState(() {
      _flags = FeatureFlags.getAllFlags();
      _loading = false;
    });
  }

  Future<void> _toggleFlag(String flagKey) async {
    final currentValue = _flags[flagKey] ?? false;
    await FeatureFlags.setEnabled(flagKey, !currentValue);
    _loadFlags();

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$flagKey ${!currentValue ? 'ENABLED' : 'DISABLED'}\n'
            '⚠️ Restart app to apply changes',
          ),
          backgroundColor: !currentValue ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _resetAllFlags() async {
    await FeatureFlags.resetToDefaults();
    _loadFlags();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'All flags reset to defaults\n⚠️ Restart app to apply changes'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.red,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🚧 DEBUG DRAWER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    kDebugMode ? 'Debug Build' : 'Release Build',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Feature Flags Section
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Feature Flags',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Voice Pipeline Flag
                        Card(
                          child: ListTile(
                            title: const Text('Refactored Voice Pipeline'),
                            subtitle: Text(
                              _flags[FeatureFlags.useRefactoredVoicePipeline] ==
                                      true
                                  ? '✅ Using NEW voice services'
                                  : '🔄 Using LEGACY VoiceService',
                            ),
                            trailing: Switch(
                              value: _flags[FeatureFlags
                                      .useRefactoredVoicePipeline] ??
                                  false,
                              onChanged: (_) => _toggleFlag(
                                  FeatureFlags.useRefactoredVoicePipeline),
                            ),
                            onTap: () => _toggleFlag(
                                FeatureFlags.useRefactoredVoicePipeline),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Reset Button
                        ElevatedButton.icon(
                          onPressed: _resetAllFlags,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reset All Flags'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Warning
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.yellow.shade100,
                            border: Border.all(color: Colors.orange),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '⚠️ Important',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Feature flag changes require app restart to take effect. '
                                'Close the app completely and reopen it.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),

                        if (kDebugMode) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const Text(
                            'Debug Info',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Current Flag Values:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  ..._flags.entries.map((entry) => Text(
                                        '${entry.key}: ${entry.value}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
