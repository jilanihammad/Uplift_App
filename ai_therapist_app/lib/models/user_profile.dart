import 'package:flutter/foundation.dart';

enum TherapyExperience {
  none,
  positiveExperience,
  mixedExperience,
  negativeExperience,
  preferNotToSay,
}

enum TypicalCopingStrategy {
  talkToOthers,
  hobbies,
  ignoreIt,
  withdraw,
  relaxationTechniques,
  unhealthyHabits,
  notSure,
}

enum SupportStyle {
  supportiveListener,
  structuredGuidance,
  balancedApproach,
  proactiveCheckins,
  notSure,
}

enum CBTFamiliarity {
  veryFamiliar,
  somewhatFamiliar,
  heardOf,
  notFamiliar,
  useTechniques,
}

class UserProfile {
  final String name;
  final String? email;
  final String? gender;
  final String? primaryReason;
  final List<String> goals;
  final TherapyExperience therapyExperience;
  final List<String> helpfulTherapyElements;
  final String? moodDescription;
  final TypicalCopingStrategy copingStrategy;
  final SupportStyle preferredSupportStyle;
  final List<String> energizers;
  final CBTFamiliarity cbtFamiliarity;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.name,
    this.email,
    this.gender,
    this.primaryReason,
    this.goals = const [],
    this.therapyExperience = TherapyExperience.none,
    this.helpfulTherapyElements = const [],
    this.moodDescription,
    this.copingStrategy = TypicalCopingStrategy.notSure,
    this.preferredSupportStyle = SupportStyle.notSure,
    this.energizers = const [],
    this.cbtFamiliarity = CBTFamiliarity.notFamiliar,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : 
      this.createdAt = createdAt ?? DateTime.now(),
      this.updatedAt = updatedAt ?? DateTime.now();

  UserProfile copyWith({
    String? name,
    String? email,
    String? gender,
    String? primaryReason,
    List<String>? goals,
    TherapyExperience? therapyExperience,
    List<String>? helpfulTherapyElements,
    String? moodDescription,
    TypicalCopingStrategy? copingStrategy,
    SupportStyle? preferredSupportStyle,
    List<String>? energizers,
    CBTFamiliarity? cbtFamiliarity,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      primaryReason: primaryReason ?? this.primaryReason,
      goals: goals ?? this.goals,
      therapyExperience: therapyExperience ?? this.therapyExperience,
      helpfulTherapyElements: helpfulTherapyElements ?? this.helpfulTherapyElements,
      moodDescription: moodDescription ?? this.moodDescription,
      copingStrategy: copingStrategy ?? this.copingStrategy,
      preferredSupportStyle: preferredSupportStyle ?? this.preferredSupportStyle,
      energizers: energizers ?? this.energizers,
      cbtFamiliarity: cbtFamiliarity ?? this.cbtFamiliarity,
      createdAt: this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'gender': gender,
      'primaryReason': primaryReason,
      'goals': goals,
      'therapyExperience': therapyExperience.toString().split('.').last,
      'helpfulTherapyElements': helpfulTherapyElements,
      'moodDescription': moodDescription,
      'copingStrategy': copingStrategy.toString().split('.').last,
      'preferredSupportStyle': preferredSupportStyle.toString().split('.').last,
      'energizers': energizers,
      'cbtFamiliarity': cbtFamiliarity.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] ?? '',
      email: json['email'],
      gender: json['gender'],
      primaryReason: json['primaryReason'],
      goals: json['goals'] != null ? List<String>.from(json['goals']) : [],
      therapyExperience: json['therapyExperience'] != null
          ? TherapyExperience.values.firstWhere(
              (e) => e.toString().split('.').last == json['therapyExperience'],
              orElse: () => TherapyExperience.none)
          : TherapyExperience.none,
      helpfulTherapyElements: json['helpfulTherapyElements'] != null
          ? List<String>.from(json['helpfulTherapyElements'])
          : [],
      moodDescription: json['moodDescription'],
      copingStrategy: json['copingStrategy'] != null
          ? TypicalCopingStrategy.values.firstWhere(
              (e) => e.toString().split('.').last == json['copingStrategy'],
              orElse: () => TypicalCopingStrategy.notSure)
          : TypicalCopingStrategy.notSure,
      preferredSupportStyle: json['preferredSupportStyle'] != null
          ? SupportStyle.values.firstWhere(
              (e) => e.toString().split('.').last == json['preferredSupportStyle'],
              orElse: () => SupportStyle.notSure)
          : SupportStyle.notSure,
      energizers: json['energizers'] != null ? List<String>.from(json['energizers']) : [],
      cbtFamiliarity: json['cbtFamiliarity'] != null
          ? CBTFamiliarity.values.firstWhere(
              (e) => e.toString().split('.').last == json['cbtFamiliarity'],
              orElse: () => CBTFamiliarity.notFamiliar)
          : CBTFamiliarity.notFamiliar,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
    );
  }
} 