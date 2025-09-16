import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String type; // 'booking', 'coach', 'system', 'payment'
  final String title;
  final String message;
  final Map<String, dynamic>? data; // Additional data for navigation
  final DateTime createdAt;
  final bool isRead;
  final String? imageUrl;
  final String priority; // 'high', 'medium', 'low'
  final DateTime? readAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.data,
    required this.createdAt,
    this.isRead = false,
    this.imageUrl,
    this.priority = 'medium',
    this.readAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map, String id) {
    return NotificationModel(
      id: id,
      userId: map['userId'] ?? '',
      type: map['type'] ?? '',
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      data: map['data'],
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      isRead: map['isRead'] ?? false,
      imageUrl: map['imageUrl'],
      priority: map['priority'] ?? 'medium',
      readAt: map['readAt']?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'title': title,
      'message': message,
      'data': data,
      'createdAt': createdAt,
      'isRead': isRead,
      'imageUrl': imageUrl,
      'priority': priority,
      'readAt': readAt,
    };
  }
}