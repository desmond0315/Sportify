// Create this file as: lib/models/message_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String senderRole; // 'coach' or 'student'
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? messageType; // 'text', 'image', 'system'
  final Map<String, dynamic>? metadata; // For additional data

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.messageType = 'text',
    this.metadata,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    return MessageModel(
      id: id,
      chatId: map['chatId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      senderRole: map['senderRole'] ?? '',
      receiverId: map['receiverId'] ?? '',
      message: map['message'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: map['isRead'] ?? false,
      messageType: map['messageType'] ?? 'text',
      metadata: map['metadata'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'receiverId': receiverId,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
      'messageType': messageType,
      'metadata': metadata,
    };
  }
}

class ChatModel {
  final String id;
  final String coachId;
  final String coachName;
  final String studentId;
  final String studentName;
  final String? appointmentId; // Optional link to appointment
  final DateTime lastMessageTime;
  final String lastMessage;
  final String lastMessageSender;
  final int unreadCountForCoach;
  final int unreadCountForStudent;
  final bool isActive;
  final DateTime createdAt;

  ChatModel({
    required this.id,
    required this.coachId,
    required this.coachName,
    required this.studentId,
    required this.studentName,
    this.appointmentId,
    required this.lastMessageTime,
    required this.lastMessage,
    required this.lastMessageSender,
    this.unreadCountForCoach = 0,
    this.unreadCountForStudent = 0,
    this.isActive = true,
    required this.createdAt,
  });

  factory ChatModel.fromMap(Map<String, dynamic> map, String id) {
    return ChatModel(
      id: id,
      coachId: map['coachId'] ?? '',
      coachName: map['coachName'] ?? '',
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      appointmentId: map['appointmentId'],
      lastMessageTime: (map['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageSender: map['lastMessageSender'] ?? '',
      unreadCountForCoach: map['unreadCountForCoach'] ?? 0,
      unreadCountForStudent: map['unreadCountForStudent'] ?? 0,
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'coachId': coachId,
      'coachName': coachName,
      'studentId': studentId,
      'studentName': studentName,
      'appointmentId': appointmentId,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'lastMessage': lastMessage,
      'lastMessageSender': lastMessageSender,
      'unreadCountForCoach': unreadCountForCoach,
      'unreadCountForStudent': unreadCountForStudent,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}