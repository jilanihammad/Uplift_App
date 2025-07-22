// lib/services/subscription_manager.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/subscription_tier.dart';
import '../config/api.dart';

/// Manages subscription state and in-app purchases for the AI Therapist app
/// 
/// This service handles:
/// - Google Play Billing integration via in_app_purchase package
/// - Subscription tier caching with encrypted storage
/// - Real-time subscription status updates
/// - Auto-restore on app startup
/// - Purchase flow management
class SubscriptionManager {
  static const String _subscriptionId = 'uplift_sub';
  static const String _cacheKey = 'subscription_status';
  static const String _lastRestoreKey = 'last_restore_date';
  
  final InAppPurchase _iap = InAppPurchase.instance;
  final StreamController<SubscriptionTier> _tierController = 
      StreamController<SubscriptionTier>.broadcast();
  
  // Current subscription state
  SubscriptionStatus _currentStatus = const SubscriptionStatus(
    tier: SubscriptionTier.none,
    isActive: false,
  );
  
  bool _isInitialized = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  
  /// Stream of subscription tier changes for reactive UI updates
  Stream<SubscriptionTier> get tierStream => _tierController.stream;
  
  /// Current subscription tier
  SubscriptionTier get currentTier => _currentStatus.effectiveTier;
  
  /// Current subscription status
  SubscriptionStatus get currentStatus => _currentStatus;
  
  /// Check if voice sessions are allowed for current tier
  bool get allowsVoiceSessions => currentTier.allowsVoiceSessions;
  
  /// Check if chat sessions are allowed for current tier
  bool get allowsChatSessions => currentTier.allowsChatSessions;
  
  /// Initialize the subscription manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      debugPrint('SubscriptionManager: Initializing...');
      
      // Load cached subscription status
      await _loadCachedStatus();
      
      // Check if in-app purchase is available
      final available = await _iap.isAvailable();
      if (!available) {
        debugPrint('SubscriptionManager: In-app purchase not available');
        _isInitialized = true;
        return;
      }
      
      // Listen to purchase updates
      _purchaseSubscription = _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (error) {
          debugPrint('SubscriptionManager: Purchase stream error: $error');
        },
      );
      
      // Auto-restore purchases on startup (adds ~5ms, worth it for UX)
      await _autoRestoreOnStartup();
      
      // Sync with backend for latest subscription status (skip if backend not ready)
      try {
        await syncWithBackend();
      } catch (e) {
        debugPrint('SubscriptionManager: Backend sync failed, continuing with local state: $e');
        // Continue with default/cached state if backend is not ready
      }
      
      _isInitialized = true;
      debugPrint('SubscriptionManager: Initialized successfully');
      
    } catch (e) {
      debugPrint('SubscriptionManager: Initialization failed: $e');
      _isInitialized = false;
      rethrow;
    }
  }
  
  /// Dispose resources
  void dispose() {
    _purchaseSubscription?.cancel();
    _tierController.close();
  }
  
  /// Check current subscription status and update cached data
  Future<void> checkSubscriptionStatus() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      debugPrint('SubscriptionManager: Checking subscription status...');
      
      // Query current purchases from Google Play
      await _queryPurchases();
      
    } catch (e) {
      debugPrint('SubscriptionManager: Error checking subscription status: $e');
    }
  }
  
  /// Purchase a subscription plan
  Future<bool> purchaseSubscription(String planId) async {
    if (!_isInitialized) {
      throw StateError('SubscriptionManager not initialized');
    }
    
    try {
      debugPrint('SubscriptionManager: Starting purchase for plan: $planId');
      
      // Get available products
      final Set<String> productIds = {planId};
      final ProductDetailsResponse response = 
          await _iap.queryProductDetails(productIds);
      
      if (response.error != null) {
        debugPrint('SubscriptionManager: Error querying products: ${response.error}');
        return false;
      }
      
      if (response.productDetails.isEmpty) {
        debugPrint('SubscriptionManager: No products found for ID: $planId');
        return false;
      }
      
      final ProductDetails productDetails = response.productDetails.first;
      
      // Create purchase param
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );
      
      // Start the purchase flow (use buyNonConsumable for subscriptions)
      final bool success = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      
      debugPrint('SubscriptionManager: Purchase initiated: $success');
      return success;
      
    } catch (e) {
      debugPrint('SubscriptionManager: Purchase failed: $e');
      return false;
    }
  }
  
  /// Start a 7-day free trial
  Future<bool> startFreeTrial() async {
    if (!_isInitialized) {
      throw StateError('SubscriptionManager not initialized');
    }
    
    try {
      debugPrint('SubscriptionManager: Starting 7-day free trial...');
      
      // Calculate trial expiration (7 days from now)
      final trialExpiresAt = DateTime.now().add(const Duration(days: 7));
      
      // Create trial subscription status
      final trialStatus = SubscriptionStatus(
        tier: SubscriptionTier.trial,
        planId: 'free_trial',
        isActive: true,
        expiresAt: trialExpiresAt,
        lastUpdated: DateTime.now(),
      );
      
      // Update local status first
      _updateSubscriptionStatus(trialStatus);
      
      // Try to sync with backend (optional - if backend isn't ready, trial still works locally)
      try {
        await _storeFreeTrialStart(trialExpiresAt);
      } catch (e) {
        debugPrint('SubscriptionManager: Backend sync for trial failed (continuing locally): $e');
        // Continue with local trial even if backend sync fails
      }
      
      debugPrint('SubscriptionManager: Free trial started successfully');
      return true;
      
    } catch (e) {
      debugPrint('SubscriptionManager: Failed to start free trial: $e');
      return false;
    }
  }

  /// Check if user has already used their free trial
  Future<bool> hasUsedFreeTrial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('has_used_free_trial') ?? false;
    } catch (e) {
      debugPrint('SubscriptionManager: Error checking trial usage: $e');
      return false;
    }
  }

  /// Mark free trial as used (prevents multiple trials)
  Future<void> _markTrialAsUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_used_free_trial', true);
    } catch (e) {
      debugPrint('SubscriptionManager: Error marking trial as used: $e');
    }
  }

  /// Store free trial start in backend
  Future<void> _storeFreeTrialStart(DateTime expiresAt) async {
    try {
      final response = await _authenticatedRequest((token) => http.post(
        Uri.parse('${ApiConfig.baseUrl}/subscriptions/start-trial'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'trial_expires_at': expiresAt.toIso8601String(),
        }),
      ));
      
      if (response.statusCode == 200) {
        debugPrint('SubscriptionManager: Free trial stored in backend');
        await _markTrialAsUsed();
      }
    } catch (e) {
      debugPrint('SubscriptionManager: Error storing trial in backend: $e');
      // Still mark as used locally to prevent multiple local trials
      await _markTrialAsUsed();
      rethrow;
    }
  }

  /// Manually restore purchases (for user-initiated restore)
  Future<void> restorePurchases() async {
    if (!_isInitialized) {
      throw StateError('SubscriptionManager not initialized');
    }
    
    try {
      debugPrint('SubscriptionManager: Manually restoring purchases...');
      
      await _queryPurchases();
      await _updateLastRestoreDate();
      
      debugPrint('SubscriptionManager: Manual restore completed');
      
    } catch (e) {
      debugPrint('SubscriptionManager: Manual restore failed: $e');
      rethrow;
    }
  }
  
  /// Sync subscription status from backend
  Future<void> syncWithBackend() async {
    try {
      final response = await _authenticatedRequest((token) => http.get(
        Uri.parse('${ApiConfig.baseUrl}/subscriptions/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Map backend tier to Flutter enum
        final tierMap = {
          'none': SubscriptionTier.none,
          'basic': SubscriptionTier.basic,
          'premium': SubscriptionTier.premium,
        };
        
        final tier = tierMap[data['subscription_tier']] ?? SubscriptionTier.none;
        final expiresAt = data['subscription_expires_at'] != null 
          ? DateTime.parse(data['subscription_expires_at'])
          : null;
        
        final newStatus = SubscriptionStatus(
          tier: tier,
          planId: data['subscription_plan_id'],
          isActive: tier != SubscriptionTier.none,
          expiresAt: expiresAt,
          lastUpdated: DateTime.now(),
        );
        
        _updateSubscriptionStatus(newStatus);
        debugPrint('SubscriptionManager: Synced with backend: $tier');
      }
    } catch (e) {
      // Surface to UI for real failures
      debugPrint('SubscriptionManager: Backend sync error: $e');
      // For now, don't rethrow to allow app to continue working without backend
      // rethrow;
    }
  }

  /// Open Google Play Store subscription management
  void openManageSubscriptions() {
    // This will deep link to Play Store subscription management
    // Implementation depends on url_launcher or similar package
    debugPrint('SubscriptionManager: Opening subscription management...');
    // TODO: Implement deep link to Play Store
  }
  
  /// Auto-restore purchases on cold start
  Future<void> _autoRestoreOnStartup() async {
    try {
      // Check if we need to restore (avoid too frequent calls)
      final prefs = await SharedPreferences.getInstance();
      final lastRestore = prefs.getString(_lastRestoreKey);
      
      if (lastRestore != null) {
        final lastRestoreDate = DateTime.parse(lastRestore);
        final hoursSinceRestore = DateTime.now().difference(lastRestoreDate).inHours;
        
        // Only auto-restore if it's been more than 24 hours
        if (hoursSinceRestore < 24) {
          debugPrint('SubscriptionManager: Skipping auto-restore (recent restore)');
          return;
        }
      }
      
      debugPrint('SubscriptionManager: Auto-restoring purchases...');
      await _queryPurchases();
      await _updateLastRestoreDate();
      
    } catch (e) {
      debugPrint('SubscriptionManager: Auto-restore failed: $e');
    }
  }
  
  /// Query current purchases from Google Play
  Future<void> _queryPurchases() async {
    try {
      // Query all past purchases
      await _iap.restorePurchases();
      
    } catch (e) {
      debugPrint('SubscriptionManager: Error querying purchases: $e');
    }
  }
  
  /// Handle purchase stream updates
  void _handlePurchaseUpdates(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      debugPrint('SubscriptionManager: Processing purchase: ${purchaseDetails.productID}');
      
      if (purchaseDetails.status == PurchaseStatus.purchased) {
        _processPurchase(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        debugPrint('SubscriptionManager: Purchase error: ${purchaseDetails.error}');
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        debugPrint('SubscriptionManager: Purchase canceled');
      }
      
      // Acknowledge purchase if needed
      if (purchaseDetails.pendingCompletePurchase) {
        _iap.completePurchase(purchaseDetails);
      }
    }
  }
  
  /// Process a successful purchase
  void _processPurchase(PurchaseDetails purchaseDetails) async {
    debugPrint('SubscriptionManager: Processing successful purchase: ${purchaseDetails.productID}');
    
    // Determine tier from product ID
    final plan = SubscriptionPlan.getPlanById(purchaseDetails.productID);
    if (plan == null) {
      debugPrint('SubscriptionManager: Unknown product ID: ${purchaseDetails.productID}');
      return;
    }
    
    // Store purchase token in backend for webhook processing
    await _storePurchaseToken(purchaseDetails, plan);
    
    // Update subscription status
    final newStatus = SubscriptionStatus(
      tier: plan.tier,
      planId: plan.planId,
      isActive: true,
      expiresAt: null, // Will be updated by RTDN webhook
      lastUpdated: DateTime.now(),
    );
    
    _updateSubscriptionStatus(newStatus);
  }
  
  /// Get Firebase auth token with proper error handling
  Future<String?> _getAuthToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      
      // Force refresh to ensure token isn't expired
      return await user.getIdToken(true);
    } catch (e) {
      debugPrint('Failed to get auth token: $e');
      return null;
    }
  }
  
  /// Make authenticated request with retry logic
  Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function(String token) request,
  ) async {
    // First attempt
    var token = await _getAuthToken();
    if (token == null) {
      throw Exception('Not authenticated - please sign in');
    }
    
    var response = await request(token);
    
    // Retry once on 401
    if (response.statusCode == 401) {
      debugPrint('Token expired, refreshing...');
      token = await _getAuthToken();
      if (token != null) {
        response = await request(token);
      }
    }
    
    // Surface non-401 errors to UI
    if (response.statusCode >= 400 && response.statusCode != 401) {
      final errorBody = jsonDecode(response.body);
      final errorMessage = errorBody['detail'] ?? 'Request failed';
      throw Exception('Server error (${response.statusCode}): $errorMessage');
    }
    
    return response;
  }
  
  /// Store purchase token in backend for webhook processing
  Future<void> _storePurchaseToken(PurchaseDetails purchaseDetails, SubscriptionPlan plan) async {
    try {
      // Map Flutter product IDs to backend subscription IDs
      final subscriptionId = plan.tier == SubscriptionTier.basic ? 'basic_chat' : 'premium_voice_chat';
      
      final response = await _authenticatedRequest((token) => http.post(
        Uri.parse('${ApiConfig.baseUrl}/subscriptions/store-purchase-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'purchase_token': purchaseDetails.purchaseID ?? '',
          'subscription_id': subscriptionId,
        }),
      ));
      
      if (response.statusCode == 200) {
        debugPrint('SubscriptionManager: Purchase token stored successfully');
      }
    } catch (e) {
      // Log error but don't fail the purchase flow
      debugPrint('SubscriptionManager: Error storing purchase token: $e');
      // Could show a non-blocking notification to user
    }
  }
  
  /// Update subscription status and notify listeners
  void _updateSubscriptionStatus(SubscriptionStatus newStatus) {
    final oldTier = _currentStatus.effectiveTier;
    _currentStatus = newStatus;
    
    // Cache the new status
    _cacheSubscriptionStatus(newStatus);
    
    // Notify listeners if tier changed
    final newTier = newStatus.effectiveTier;
    if (oldTier != newTier) {
      debugPrint('SubscriptionManager: Tier changed from $oldTier to $newTier');
      _tierController.add(newTier);
    }
  }
  
  /// Load cached subscription status
  Future<void> _loadCachedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cacheKey);
      
      if (cachedData != null) {
        final Map<String, dynamic> data = jsonDecode(cachedData);
        _currentStatus = SubscriptionStatus.fromCache(data);
        
        debugPrint('SubscriptionManager: Loaded cached tier: ${_currentStatus.tier}');
        
        // Emit current tier for any listeners
        _tierController.add(_currentStatus.effectiveTier);
      }
      
    } catch (e) {
      debugPrint('SubscriptionManager: Error loading cached status: $e');
    }
  }
  
  /// Cache subscription status to encrypted storage
  Future<void> _cacheSubscriptionStatus(SubscriptionStatus status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(status.toCache());
      await prefs.setString(_cacheKey, data);
      
      debugPrint('SubscriptionManager: Cached subscription status');
      
    } catch (e) {
      debugPrint('SubscriptionManager: Error caching status: $e');
    }
  }
  
  /// Update last restore date
  Future<void> _updateLastRestoreDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRestoreKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('SubscriptionManager: Error updating restore date: $e');
    }
  }
  
  /// Get user-friendly error message from PlatformException
  String _getErrorMessage(PlatformException error) {
    switch (error.code) {
      case 'billing_unavailable':
        return 'Billing service is unavailable. Please try again later.';
      case 'item_unavailable':
        return 'This subscription is currently unavailable.';
      case 'user_canceled':
        return 'Purchase was canceled.';
      case 'service_unavailable':
        return 'Network connection is required for purchases.';
      default:
        return 'An error occurred during purchase. Please try again.';
    }
  }
}