// lib/models/subscription_tier.dart

/// Represents the subscription tier levels for the AI Therapist app
enum SubscriptionTier {
  /// No active subscription - limited access
  none,
  
  /// Free trial (7 days) - Full access to test features
  trial,
  
  /// Basic tier ($1/month) - Chat-only therapy sessions
  basic,
  
  /// Premium tier ($10/month) - Voice + chat therapy sessions
  premium;

  /// Get display name for the subscription tier
  String get displayName {
    switch (this) {
      case SubscriptionTier.none:
        return 'Free';
      case SubscriptionTier.trial:
        return 'Free Trial';
      case SubscriptionTier.basic:
        return 'Basic';
      case SubscriptionTier.premium:
        return 'Premium';
    }
  }

  /// Get description for the subscription tier
  String get description {
    switch (this) {
      case SubscriptionTier.none:
        return 'Limited access to basic features';
      case SubscriptionTier.trial:
        return '7 days free access to all features';
      case SubscriptionTier.basic:
        return 'Unlimited chat therapy sessions';
      case SubscriptionTier.premium:
        return 'Voice + chat therapy sessions with full features';
    }
  }

  /// Get price per month for the subscription tier
  String get pricePerMonth {
    switch (this) {
      case SubscriptionTier.none:
        return 'Free';
      case SubscriptionTier.trial:
        return 'Free for 7 days';
      case SubscriptionTier.basic:
        return '\$1/month';
      case SubscriptionTier.premium:
        return '\$10/month';
    }
  }

  /// Get the features available for this tier
  List<String> get features {
    switch (this) {
      case SubscriptionTier.none:
        return [
          'Limited chat access',
          'Basic therapy conversations',
        ];
      case SubscriptionTier.trial:
        return [
          'FREE for 7 days',
          'Unlimited voice therapy sessions',
          'Unlimited chat therapy sessions',
          'Voice-based AI therapist conversations',
          'Real-time voice processing',
          'Advanced mood tracking',
          'Session history and insights',
          'Premium support',
        ];
      case SubscriptionTier.basic:
        return [
          'Unlimited chat therapy sessions',
          'Text-based AI therapist conversations',
          'Mood tracking',
          'Session history',
        ];
      case SubscriptionTier.premium:
        return [
          'Unlimited voice therapy sessions',
          'Unlimited chat therapy sessions',
          'Voice-based AI therapist conversations',
          'Real-time voice processing',
          'Advanced mood tracking',
          'Session history and insights',
          'Premium support',
        ];
    }
  }

  /// Check if this tier allows voice sessions
  bool get allowsVoiceSessions {
    return this == SubscriptionTier.trial || this == SubscriptionTier.premium;
  }

  /// Check if this tier allows chat sessions
  bool get allowsChatSessions {
    return this != SubscriptionTier.none;
  }

  /// Check if this tier is a paid subscription
  bool get isPaidTier {
    return this == SubscriptionTier.basic || this == SubscriptionTier.premium;
  }

  /// Check if this tier is a trial
  bool get isTrialTier {
    return this == SubscriptionTier.trial;
  }

  /// Convert from string representation
  static SubscriptionTier fromString(String value) {
    switch (value.toLowerCase()) {
      case 'trial':
        return SubscriptionTier.trial;
      case 'basic':
        return SubscriptionTier.basic;
      case 'premium':
        return SubscriptionTier.premium;
      case 'none':
      default:
        return SubscriptionTier.none;
    }
  }

  /// Convert to string representation for storage
  @override
  String toString() {
    return name;
  }
}

/// Subscription plan configuration for Google Play billing
class SubscriptionPlan {
  final String planId;
  final SubscriptionTier tier;
  final String title;
  final String description;
  final double monthlyPriceUsd;

  const SubscriptionPlan({
    required this.planId,
    required this.tier,
    required this.title,
    required this.description,
    required this.monthlyPriceUsd,
  });

  /// Available subscription plans
  static const List<SubscriptionPlan> availablePlans = [
    SubscriptionPlan(
      planId: 'basic_chat',
      tier: SubscriptionTier.basic,
      title: 'Basic Plan',
      description: 'Unlimited chat therapy sessions',
      monthlyPriceUsd: 1.0,
    ),
    SubscriptionPlan(
      planId: 'premium_voice_chat',
      tier: SubscriptionTier.premium,
      title: 'Premium Plan',
      description: 'Voice + chat therapy sessions with full features',
      monthlyPriceUsd: 10.0,
    ),
  ];

  /// Get plan by tier
  static SubscriptionPlan? getPlanForTier(SubscriptionTier tier) {
    return availablePlans.where((plan) => plan.tier == tier).firstOrNull;
  }

  /// Get plan by ID
  static SubscriptionPlan? getPlanById(String planId) {
    return availablePlans.where((plan) => plan.planId == planId).firstOrNull;
  }
}

/// Subscription status information
class SubscriptionStatus {
  final SubscriptionTier tier;
  final String? planId;
  final DateTime? expiresAt;
  final bool isActive;
  final DateTime? lastUpdated;

  const SubscriptionStatus({
    required this.tier,
    this.planId,
    this.expiresAt,
    required this.isActive,
    this.lastUpdated,
  });

  /// Create from cached data
  factory SubscriptionStatus.fromCache(Map<String, dynamic> data) {
    return SubscriptionStatus(
      tier: SubscriptionTier.fromString(data['tier'] ?? 'none'),
      planId: data['planId'],
      expiresAt: data['expiresAt'] != null 
          ? DateTime.parse(data['expiresAt']) 
          : null,
      isActive: data['isActive'] ?? false,
      lastUpdated: data['lastUpdated'] != null 
          ? DateTime.parse(data['lastUpdated']) 
          : null,
    );
  }

  /// Convert to map for caching
  Map<String, dynamic> toCache() {
    return {
      'tier': tier.toString(),
      'planId': planId,
      'expiresAt': expiresAt?.toIso8601String(),
      'isActive': isActive,
      'lastUpdated': (lastUpdated ?? DateTime.now()).toIso8601String(),
    };
  }

  /// Check if subscription is currently valid
  bool get isValid {
    if (!isActive) return false;
    if (tier == SubscriptionTier.none) return true;
    if (expiresAt == null) return true;
    return DateTime.now().isBefore(expiresAt!);
  }

  /// Get effective tier considering expiration
  SubscriptionTier get effectiveTier {
    return isValid ? tier : SubscriptionTier.none;
  }

  SubscriptionStatus copyWith({
    SubscriptionTier? tier,
    String? planId,
    DateTime? expiresAt,
    bool? isActive,
    DateTime? lastUpdated,
  }) {
    return SubscriptionStatus(
      tier: tier ?? this.tier,
      planId: planId ?? this.planId,
      expiresAt: expiresAt ?? this.expiresAt,
      isActive: isActive ?? this.isActive,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}