import 'package:cloud_firestore/cloud_firestore.dart';

// Chat Model - represents a conversation
class ChatModel {
  final String id;
  final String coachId;
  final String coachName;
  final String studentId;
  final String studentName;
  final String? appointmentId;
  final DateTime lastMessageTime;
  final String lastMessage;
  final String lastMessageSender;
  final DateTime createdAt;
  final bool isActive;
  final int unreadCountForCoach;
  final int unreadCountForStudent;

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
    required this.createdAt,
    this.isActive = true,
    this.unreadCountForCoach = 0,
    this.unreadCountForStudent = 0,
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
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: map['isActive'] ?? true,
      unreadCountForCoach: map['unreadCountForCoach'] ?? 0,
      unreadCountForStudent: map['unreadCountForStudent'] ?? 0,
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
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'unreadCountForCoach': unreadCountForCoach,
      'unreadCountForStudent': unreadCountForStudent,
    };
  }
}

// Message Model - represents individual messages
class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String receiverId;
  final String message; // This will be encrypted
  final String iv; // Initialization Vector for decryption
  final DateTime timestamp;
  final bool isRead;
  final String messageType;
  final Map<String, dynamic>? metadata;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.receiverId,
    required this.message,
    this.iv = '',
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
      iv: map['iv'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: map['isRead'] ?? false,
      messageType: map['messageType'] ?? 'text',
      metadata: map['metadata'] as Map<String, dynamic>?,
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
      'iv': iv,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
      'messageType': messageType,
      'metadata': metadata,
    };
  }
}