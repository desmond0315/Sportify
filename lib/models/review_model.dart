import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;
  final String coachId;
  final String coachName;
  final String studentId;
  final String studentName;
  final String appointmentId;
  final int rating;
  final String comment;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  ReviewModel({
    required this.id,
    required this.coachId,
    required this.coachName,
    required this.studentId,
    required this.studentName,
    required this.appointmentId,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReviewModel(
      id: doc.id,
      coachId: data['coachId'] ?? '',
      coachName: data['coachName'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      appointmentId: data['appointmentId'] ?? '',
      rating: data['rating'] ?? 0,
      comment: data['comment'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'coachId': coachId,
      'coachName': coachName,
      'studentId': studentId,
      'studentName': studentName,
      'appointmentId': appointmentId,
      'rating': rating,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isActive': isActive,
    };
  }
}