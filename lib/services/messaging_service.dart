import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/message_model.dart';
import '../services/encryption_service.dart';


class MessagingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Generate chat ID from two user IDs (works for coach, student, venue owner)
  static String generateChatId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  // Create or get existing chat between student and coach
  static Future<String> createOrGetChat({
    required String coachId,
    required String coachName,
    required String studentId,
    required String studentName,
    String? appointmentId,
  }) async {
    try {
      final chatId = generateChatId(coachId, studentId);
      final chatRef = _firestore.collection('chats').doc(chatId);

      final chatDoc = await chatRef.get();

      if (!chatDoc.exists) {
        // Create new chat
        final chatData = ChatModel(
          id: chatId,
          coachId: coachId,
          coachName: coachName,
          studentId: studentId,
          studentName: studentName,
          appointmentId: appointmentId,
          lastMessageTime: DateTime.now(),
          lastMessage: 'Chat created',
          lastMessageSender: 'system',
          createdAt: DateTime.now(),
          chatType: 'coach_student', // NEW: Specify chat type
        );

        await chatRef.set(chatData.toMap());

        // Send welcome message
        await sendMessage(
          chatId: chatId,
          senderId: 'system',
          senderName: 'Sportify',
          senderRole: 'system',
          receiverId: studentId,
          message: 'You can now chat with your coach about your training session.',
          messageType: 'system',
        );
      }

      return chatId;
    } catch (e) {
      print('Error creating/getting chat: $e');
      throw Exception('Failed to create chat');
    }
  }

  // NEW: Create or get chat between student and venue owner
  static Future<String> createOrGetVenueChat({
    required String venueId,
    required String venueOwnerId,
    required String venueOwnerName,
    required String venueName,
    required String studentId,
    required String studentName,
    String? bookingId,
  }) async {
    try {
      final chatId = generateChatId(venueOwnerId, studentId);
      final chatRef = _firestore.collection('chats').doc(chatId);

      final chatDoc = await chatRef.get();

      if (!chatDoc.exists) {
        // Create new venue chat
        final chatData = VenueChatModel(
          id: chatId,
          venueId: venueId,
          venueOwnerId: venueOwnerId,
          venueOwnerName: venueOwnerName,
          venueName: venueName,
          studentId: studentId,
          studentName: studentName,
          bookingId: bookingId,
          lastMessageTime: DateTime.now(),
          lastMessage: 'Chat created',
          lastMessageSender: 'system',
          createdAt: DateTime.now(),
          chatType: 'venue_student',
        );

        await chatRef.set(chatData.toMap());

        // Send welcome message
        await sendMessage(
          chatId: chatId,
          senderId: 'system',
          senderName: 'Sportify',
          senderRole: 'system',
          receiverId: studentId,
          message: 'You can now chat with $venueName about your booking.',
          messageType: 'system',
        );
      }

      return chatId;
    } catch (e) {
      print('Error creating/getting venue chat: $e');
      throw Exception('Failed to create venue chat');
    }
  }

  // Send a message
  static Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String receiverId,
    required String message,
    String messageType = 'text',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      String messageToStore;
      String iv;
      String lastMessagePreview;

      // DON'T encrypt system messages
      if (messageType == 'system' || senderRole == 'system' || senderId == 'system') {
        messageToStore = message;
        iv = '';
        lastMessagePreview = message.length > 100
            ? '${message.substring(0, 100)}...'
            : message;
      } else {
        // ONLY encrypt regular user messages
        final encryptionResult = EncryptionService.encryptMessage(message, chatId);
        messageToStore = encryptionResult['encrypted']!;
        iv = encryptionResult['iv']!;

        lastMessagePreview = message.length > 100
            ? '${message.substring(0, 100)}...'
            : message;
      }

      final messageData = MessageModel(
        id: '',
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        receiverId: receiverId,
        message: messageToStore,
        iv: iv,
        timestamp: DateTime.now(),
        messageType: messageType,
        metadata: metadata,
      );

      // Add message to messages collection
      await _firestore.collection('messages').add(messageData.toMap());

      // Update chat with preview
      await _updateChatLastMessage(
        chatId: chatId,
        lastMessage: lastMessagePreview,
        lastMessageSender: senderId,
        senderRole: senderRole,
      );

      print('Message sent successfully');
    } catch (e) {
      print('Error sending message: $e');
      throw Exception('Failed to send message');
    }
  }

  // Update chat's last message and unread counts
  static Future<void> _updateChatLastMessage({
    required String chatId,
    required String lastMessage,
    required String lastMessageSender,
    required String senderRole,
  }) async {
    try {
      final chatRef = _firestore.collection('chats').doc(chatId);
      final chatDoc = await chatRef.get();

      if (!chatDoc.exists) return;

      final chatData = chatDoc.data()!;
      final chatType = chatData['chatType'] ?? 'coach_student';

      Map<String, dynamic> updateData = {
        'lastMessage': lastMessage.length > 100 ? '${lastMessage.substring(0, 100)}...' : lastMessage,
        'lastMessageSender': lastMessageSender,
        'lastMessageTime': FieldValue.serverTimestamp(),
      };

      // Increment unread count based on chat type
      if (chatType == 'coach_student') {
        if (senderRole == 'coach') {
          updateData['unreadCountForStudent'] = FieldValue.increment(1);
        } else if (senderRole == 'student') {
          updateData['unreadCountForCoach'] = FieldValue.increment(1);
        }
      } else if (chatType == 'venue_student') {
        if (senderRole == 'venue_owner') {
          updateData['unreadCountForStudent'] = FieldValue.increment(1);
        } else if (senderRole == 'student') {
          updateData['unreadCountForVenueOwner'] = FieldValue.increment(1);
        }
      }

      await chatRef.update(updateData);
    } catch (e) {
      print('Error updating chat last message: $e');
    }
  }

  // Get messages stream for a chat
  static Stream<List<MessageModel>> getMessagesStream(String chatId) {
    return _firestore
        .collection('messages')
        .where('chatId', isEqualTo: chatId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return MessageModel.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // Get user's chats stream (supports all chat types)
  static Stream<List<dynamic>> getUserChatsStream(String userId, String userRole) {
    if (userRole == 'coach') {
      return _firestore
          .collection('chats')
          .where('coachId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .orderBy('lastMessageTime', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          return ChatModel.fromMap(doc.data(), doc.id);
        }).toList();
      });
    } else if (userRole == 'venue_owner') {
      return _firestore
          .collection('chats')
          .where('venueOwnerId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .orderBy('lastMessageTime', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          return VenueChatModel.fromMap(doc.data(), doc.id);
        }).toList();
      });
    } else {
      // Student - get both coach and venue chats
      return _firestore
          .collection('chats')
          .where('studentId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .orderBy('lastMessageTime', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          final chatType = data['chatType'] ?? 'coach_student';

          if (chatType == 'venue_student') {
            return VenueChatModel.fromMap(data, doc.id);
          } else {
            return ChatModel.fromMap(data, doc.id);
          }
        }).toList();
      });
    }
  }

  // Mark messages as read
  static Future<void> markMessagesAsRead(String chatId, String userId, String userRole) async {
    try {
      final chatRef = _firestore.collection('chats').doc(chatId);
      final chatDoc = await chatRef.get();

      if (!chatDoc.exists) return;

      final chatData = chatDoc.data()!;
      final chatType = chatData['chatType'] ?? 'coach_student';

      String unreadField;
      if (chatType == 'coach_student') {
        unreadField = userRole == 'coach' ? 'unreadCountForCoach' : 'unreadCountForStudent';
      } else {
        unreadField = userRole == 'venue_owner' ? 'unreadCountForVenueOwner' : 'unreadCountForStudent';
      }

      await chatRef.update({unreadField: 0});

      // Mark individual messages as read
      final messagesQuery = await _firestore
          .collection('messages')
          .where('chatId', isEqualTo: chatId)
          .where('receiverId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in messagesQuery.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Get total unread messages count for user
  static Stream<int> getUnreadMessagesCount(String userId, String userRole) {
    if (userRole == 'coach') {
      return _firestore
          .collection('chats')
          .where('coachId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .map((snapshot) {
        int totalUnread = 0;
        for (var doc in snapshot.docs) {
          final data = doc.data();
          totalUnread += (data['unreadCountForCoach'] as int? ?? 0);
        }
        return totalUnread;
      });
    } else if (userRole == 'venue_owner') {
      return _firestore
          .collection('chats')
          .where('venueOwnerId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .map((snapshot) {
        int totalUnread = 0;
        for (var doc in snapshot.docs) {
          final data = doc.data();
          totalUnread += (data['unreadCountForVenueOwner'] as int? ?? 0);
        }
        return totalUnread;
      });
    } else {
      return _firestore
          .collection('chats')
          .where('studentId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .map((snapshot) {
        int totalUnread = 0;
        for (var doc in snapshot.docs) {
          final data = doc.data();
          totalUnread += (data['unreadCountForStudent'] as int? ?? 0);
        }
        return totalUnread;
      });
    }
  }

  // Delete a message (soft delete)
  static Future<void> deleteMessage(String messageId) async {
    try {
      await _firestore.collection('messages').doc(messageId).update({
        'message': 'This message was deleted',
        'messageType': 'deleted',
        'isDeleted': true,
      });
    } catch (e) {
      print('Error deleting message: $e');
    }
  }

  // Archive a chat
  static Future<void> archiveChat(String chatId) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'isActive': false,
        'archivedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error archiving chat: $e');
    }
  }

  // Create chat from booking (for venue)
  static Future<String> createChatFromBooking(Map<String, dynamic> bookingData) async {
    try {
      return await createOrGetVenueChat(
        venueId: bookingData['venueId'],
        venueOwnerId: bookingData['venueOwnerId'],
        venueOwnerName: bookingData['venueOwnerName'] ?? 'Venue Owner',
        venueName: bookingData['venueName'] ?? 'Venue',
        studentId: bookingData['userId'],
        studentName: bookingData['userName'] ?? 'User',
        bookingId: bookingData['id'],
      );
    } catch (e) {
      print('Error creating chat from booking: $e');
      rethrow;
    }
  }

  // Send booking-related message
  static Future<void> sendBookingMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String receiverId,
    required String bookingStatus,
    required Map<String, dynamic> bookingData,
  }) async {
    String message;
    switch (bookingStatus) {
      case 'confirmed':
        message = 'Your booking has been confirmed! 🎉\nBooking: ${bookingData['date']} at ${bookingData['startTime']}';
        break;
      case 'rejected':
        message = 'Your booking request has been declined. Feel free to book another time slot.';
        break;
      case 'cancelled':
        message = 'The booking scheduled for ${bookingData['date']} at ${bookingData['startTime']} has been cancelled.';
        break;
      default:
        message = 'Booking status updated: $bookingStatus';
    }

    await sendMessage(
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      receiverId: receiverId,
      message: message,
      messageType: 'system',
      metadata: {
        'bookingId': bookingData['id'],
        'bookingStatus': bookingStatus,
        'bookingData': bookingData,
      },
    );
  }

  // Create chat from appointment booking (for coach)
  static Future<String> createChatFromAppointment(Map<String, dynamic> appointmentData) async {
    try {
      return await createOrGetChat(
        coachId: appointmentData['coachId'],
        coachName: appointmentData['coachName'] ?? 'Coach',
        studentId: appointmentData['userId'],
        studentName: appointmentData['studentName'] ?? 'Student',
        appointmentId: appointmentData['id'],
      );
    } catch (e) {
      print('Error creating chat from appointment: $e');
      rethrow;
    }
  }

  // Send appointment-related message
  static Future<void> sendAppointmentMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String receiverId,
    required String appointmentStatus,
    required Map<String, dynamic> appointmentData,
  }) async {
    String message;
    switch (appointmentStatus) {
      case 'accepted':
        message = 'Your session request has been accepted! 🎉\nSession: ${appointmentData['date']} at ${appointmentData['timeSlot']}';
        break;
      case 'rejected':
        message = 'Your session request has been declined. Feel free to ask about alternative times or discuss your training needs.';
        break;
      case 'cancelled':
        message = 'The session scheduled for ${appointmentData['date']} at ${appointmentData['timeSlot']} has been cancelled.';
        break;
      default:
        message = 'Session status updated: $appointmentStatus';
    }

    await sendMessage(
      chatId: chatId,
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      receiverId: receiverId,
      message: message,
      messageType: 'system',
      metadata: {
        'appointmentId': appointmentData['id'],
        'appointmentStatus': appointmentStatus,
        'appointmentData': appointmentData,
      },
    );
  }
}