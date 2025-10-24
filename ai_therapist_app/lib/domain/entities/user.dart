import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String name;
  final String email;
  final String? profileImage;
  final String? photoUrl;
  final String? phoneNumber;
  final DateTime createdAt;
  final Map<String, dynamic>? preferences;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.profileImage,
    this.photoUrl,
    this.phoneNumber,
    required this.createdAt,
    this.preferences,
  });

  // Create a copy of this User with updated fields
  User copyWith({
    String? id,
    String? name,
    String? email,
    String? profileImage,
    String? photoUrl,
    String? phoneNumber,
    DateTime? createdAt,
    Map<String, dynamic>? preferences,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profileImage: profileImage ?? this.profileImage,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      preferences: preferences ?? this.preferences,
    );
  }

  // Factory constructor from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      profileImage: json['profile_image'],
      photoUrl: json['photo_url'],
      phoneNumber: json['phone_number'],
      createdAt: DateTime.parse(json['created_at']),
      preferences: json['preferences'],
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profile_image': profileImage,
      'photo_url': photoUrl,
      'phone_number': phoneNumber,
      'created_at': createdAt.toIso8601String(),
      'preferences': preferences,
    };
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        profileImage,
        photoUrl,
        phoneNumber,
        createdAt,
        preferences
      ];
}
