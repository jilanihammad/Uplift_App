class UserTask {
  final String id;
  final String text;
  final String sessionId;
  final DateTime dateAdded;
  final bool isCompleted;
  final DateTime? completedDate;

  UserTask({
    required this.id,
    required this.text,
    required this.sessionId,
    required this.dateAdded,
    this.isCompleted = false,
    this.completedDate,
  });

  UserTask copyWith({
    String? id,
    String? text,
    String? sessionId,
    DateTime? dateAdded,
    bool? isCompleted,
    DateTime? completedDate,
  }) {
    return UserTask(
      id: id ?? this.id,
      text: text ?? this.text,
      sessionId: sessionId ?? this.sessionId,
      dateAdded: dateAdded ?? this.dateAdded,
      isCompleted: isCompleted ?? this.isCompleted,
      completedDate: completedDate ?? this.completedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'sessionId': sessionId,
      'dateAdded': dateAdded.toIso8601String(),
      'isCompleted': isCompleted,
      'completedDate': completedDate?.toIso8601String(),
    };
  }

  factory UserTask.fromJson(Map<String, dynamic> json) {
    return UserTask(
      id: json['id'],
      text: json['text'],
      sessionId: json['sessionId'],
      dateAdded: DateTime.parse(json['dateAdded']),
      isCompleted: json['isCompleted'] ?? false,
      completedDate: json['completedDate'] != null 
          ? DateTime.parse(json['completedDate']) 
          : null,
    );
  }
}