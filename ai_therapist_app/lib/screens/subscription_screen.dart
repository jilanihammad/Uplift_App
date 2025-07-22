// lib/screens/subscription_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/subscription_manager.dart';
import '../models/subscription_tier.dart';
import '../di/dependency_container.dart';

/// Modern subscription screen inspired by premium app designs
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late SubscriptionManager _subscriptionManager;
  bool _isLoading = false;
  String? _errorMessage;
  SubscriptionTier _currentTier = SubscriptionTier.none;
  String _selectedPlanId = 'basic_monthly'; // Default selection

  @override
  void initState() {
    super.initState();
    _subscriptionManager = DependencyContainer().subscriptionManager;
    _currentTier = _subscriptionManager.currentTier;
    
    // Listen for subscription changes
    _subscriptionManager.tierStream.listen(_onTierChanged);
    
  }


  void _onTierChanged(SubscriptionTier newTier) {
    if (mounted) {
      setState(() {
        _currentTier = newTier;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // Dark background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            // Try to pop first (if pushed via Navigator)
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              // Otherwise, use GoRouter to go home
              context.go('/home');
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              children: [
                // Header section
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App icon/logo
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.psychology,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Title
                    const Text(
                      'Upgrade to get advanced\ncapabilities and more usage',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Features list
                    Column(
                      children: [
                        _buildFeature('Unlimited therapy chat sessions'),
                        _buildFeature('Advanced conversation memory'),
                        _buildFeature('Voice therapy sessions', badge: 'PREMIUM'),
                        _buildFeature('Detailed session insights'),
                        _buildFeature('Progress tracking & analytics'),
                        _buildFeature('Priority support'),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Free trial info banner
                if (_currentTier != SubscriptionTier.trial && _currentTier != SubscriptionTier.basic && _currentTier != SubscriptionTier.premium) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.withValues(alpha: 0.3), Colors.blue.withValues(alpha: 0.3)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 32),
                        const SizedBox(height: 8),
                        const Text(
                          '7-Day Free Trial Included',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Start any plan below and get 7 days free',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Cancel anytime in Google Play',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Trial status message
                if (_currentTier == SubscriptionTier.trial) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.timer, color: Colors.green, size: 24),
                        const SizedBox(height: 8),
                        const Text(
                          'Free Trial Active',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getTrialRemainingText(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // Plans section
                Column(
                  children: [
                    
                    // Plan options
                    _buildPlanOption(
                      id: 'basic_monthly',
                      title: 'Basic Chat',
                      price: '\$1/month',
                      subtitle: 'Unlimited text therapy',
                      isPopular: true,
                    ),
                    const SizedBox(height: 12),
                    _buildPlanOption(
                      id: 'premium_monthly',
                      title: 'Premium Voice + Chat',
                      price: '\$10/month',
                      subtitle: 'Voice & text therapy',
                    ),
                    const SizedBox(height: 24),
                    
                    // Upgrade button (secondary action)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _upgradeNow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: Text(
                          _currentTier == SubscriptionTier.none ? 'Start Free Trial' : 'Change Plan',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Footer links
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () {
                            // Handle terms
                          },
                          child: const Text(
                            'Terms',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // Handle privacy
                          },
                          child: const Text(
                            'Privacy',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        TextButton(
                          onPressed: _restorePurchases,
                          child: const Text(
                            'Restore',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(String text, {String? badge}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanOption({
    required String id,
    required String title,
    required String price,
    String? subtitle,
    bool isPopular = false,
  }) {
    final isSelected = _selectedPlanId == id;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlanId = id;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // Radio button
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.white38,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            
            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Popular badge
            if (isPopular)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Popular',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            
            // Price
            Text(
              price,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTrialRemainingText() {
    final status = _subscriptionManager.currentStatus;
    if (status.expiresAt != null) {
      final remaining = status.expiresAt!.difference(DateTime.now()).inDays;
      if (remaining > 1) {
        return '$remaining days remaining';
      } else if (remaining == 1) {
        return '1 day remaining';
      } else {
        return 'Trial ends today';
      }
    }
    return 'Trial active';
  }


  Future<void> _upgradeNow() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Map selected plan ID to Google Play product ID
      final productId = _selectedPlanId == 'premium_monthly' 
          ? 'premium_voice_chat' 
          : 'basic_chat';

      final success = await _subscriptionManager.purchaseSubscription(productId);
      
      if (success) {
        // Success feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully upgraded to ${_selectedPlanId.toUpperCase()}!'),
              backgroundColor: Colors.green,
            ),
          );
          // Delay navigation to avoid Navigator lock issues
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              // Try to pop first (if pushed via Navigator)
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                // Otherwise, use GoRouter to go home
                context.go('/home');
              }
            }
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Purchase failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _restorePurchases() async {
    try {
      await _subscriptionManager.restorePurchases();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchases restored successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore purchases: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}