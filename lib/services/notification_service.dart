import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create notification
  static Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    Map<String, dynamic>? data,
    String? imageUrl,
    String priority = 'medium',
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'imageUrl': imageUrl,
        'priority': priority,
      });
      print('Notification created for user $userId: $title');
    } catch (e) {
      print('Error creating notification: $e');
    }
  }

  // Get user notifications stream with better error handling
  static Stream<List<NotificationModel>> getUserNotifications(String userId) {
    print('Setting up notifications stream for user: $userId');

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .handleError((error) {
      print('Firestore stream error: $error');
    })
        .map((snapshot) {
      print('Received snapshot with ${snapshot.docs.length} documents');

      return snapshot.docs.map((doc) {
        try {
          final data = doc.data();
          print('Processing notification: ${doc.id} - ${data['title']}');
          return NotificationModel.fromMap(data, doc.id);
        } catch (e) {
          print('Error processing notification ${doc.id}: $e');
          // Return a default notification for corrupted data
          return NotificationModel(
            id: doc.id,
            userId: userId,
            type: 'system',
            title: 'Error loading notification',
            message: 'There was an error loading this notification.',
            createdAt: DateTime.now(),
          );
        }
      }).toList();
    });
  }

  // Mark notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      print('Notification $notificationId marked as read');
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // Mark all notifications as read for user
  static Future<void> markAllAsRead(String userId) async {
    try {
      final batch = _firestore.batch();
      final notifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in notifications.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      print('All notifications marked as read for user $userId');
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  // Delete notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).delete();
      print('Notification $notificationId deleted');
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  // Get unread count
  static Stream<int> getUnreadCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .handleError((error) {
      print('Error getting unread count: $error');
    })
        .map((snapshot) => snapshot.docs.length);
  }

  // Create booking-related notifications
  static Future<void> createBookingNotification({
    required String userId,
    required String bookingType, // 'court' or 'coach'
    required String title,
    required String message,
    Map<String, dynamic>? bookingData,
  }) async {
    await createNotification(
      userId: userId,
      type: 'booking',
      title: title,
      message: message,
      data: {
        'bookingType': bookingType,
        'bookingData': bookingData,
        'action': 'view_booking',
      },
      priority: 'high',
    );
  }

  // Create coach-related notifications
  static Future<void> createCoachNotification({
    required String userId,
    required String title,
    required String message,
    Map<String, dynamic>? coachData,
    String action = 'view_coaches',
  }) async {
    await createNotification(
      userId: userId,
      type: 'coach',
      title: title,
      message: message,
      data: {
        'coachData': coachData,
        'action': action,
      },
      priority: 'medium',
    );
  }

  // Create system notifications (for all users or specific groups)
  static Future<void> createSystemNotification({
    List<String>? userIds, // If null, creates for all users
    required String title,
    required String message,
    String? imageUrl,
  }) async {
    try {
      if (userIds == null) {
        // Get all users
        final usersSnapshot = await _firestore.collection('users').get();
        userIds = usersSnapshot.docs.map((doc) => doc.id).toList();
      }

      final batch = _firestore.batch();

      for (String userId in userIds) {
        final notificationRef = _firestore.collection('notifications').doc();
        batch.set(notificationRef, {
          'userId': userId,
          'type': 'system',
          'title': title,
          'message': message,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'imageUrl': imageUrl,
          'priority': 'high',
        });
      }

      await batch.commit();
      print('System notification created for ${userIds.length} users');
    } catch (e) {
      print('Error creating system notification: $e');
    }
  }

  // Payment related notifications
  static Future<void> createPaymentNotification({
    required String userId,
    required String title,
    required String message,
    Map<String, dynamic>? paymentData,
    String priority = 'high',
  }) async {
    await createNotification(
      userId: userId,
      type: 'payment',
      title: title,
      message: message,
      data: {
        'paymentData': paymentData,
        'action': 'view_booking',
      },
      priority: priority,
    );
  }

  // Clean up old notifications (call this periodically)
  static Future<void> cleanupOldNotifications({int daysToKeep = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));

      final oldNotifications = await _firestore
          .collection('notifications')
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();

      final batch = _firestore.batch();
      for (var doc in oldNotifications.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('Cleaned up ${oldNotifications.docs.length} old notifications');
    } catch (e) {
      print('Error cleaning up old notifications: $e');
    }
  }

  // Test function to create a sample notification
  static Future<void> createTestNotification(String userId) async {
    try {
      await createNotification(
        userId: userId,
        type: 'system',
        title: 'Welcome to Sportify!',
        message: 'This is a test notification to verify your notifications are working correctly.',
        priority: 'medium',
      );
      print('Test notification created for user: $userId');
    } catch (e) {
      print('Error creating test notification: $e');
    }
  }

  // Notify coach about new session request
  static Future<void> notifyCoachNewRequest({
    required String coachId,
    required String studentName,
    required Map<String, dynamic> appointmentData,
  }) async {
    await NotificationService.createNotification(
      userId: coachId,
      type: 'coach',
      title: 'New Session Request',
      message: '$studentName has requested a coaching session on ${appointmentData['date']} at ${appointmentData['timeSlot']}.',
      data: {
        'appointmentId': appointmentData['id'],
        'studentId': appointmentData['userId'],
        'action': 'view_requests',
      },
      priority: 'high',
    );
  }

  // Notify student about request acceptance
  static Future<void> notifyStudentRequestAccepted({
    required String studentId,
    required String coachName,
    required Map<String, dynamic> appointmentData,
  }) async {
    await NotificationService.createNotification(
      userId: studentId,
      type: 'coach',
      title: 'Session Request Accepted!',
      message: 'Great news! $coachName has accepted your session request for ${appointmentData['date']} at ${appointmentData['timeSlot']}.',
      data: {
        'appointmentId': appointmentData['id'],
        'coachId': appointmentData['coachId'],
        'action': 'view_booking',
        'status': 'accepted',
      },
      priority: 'high',
    );
  }

  // Notify student about request rejection
  static Future<void> notifyStudentRequestRejected({
    required String studentId,
    required String coachName,
    required Map<String, dynamic> appointmentData,
  }) async {
    await NotificationService.createNotification(
      userId: studentId,
      type: 'coach',
      title: 'Session Request Declined',
      message: '$coachName has declined your session request for ${appointmentData['date']} at ${appointmentData['timeSlot']}. Feel free to book with another coach or try a different time slot.',
      data: {
        'appointmentId': appointmentData['id'],
        'coachId': appointmentData['coachId'],
        'action': 'view_coaches',
        'status': 'rejected',
      },
      priority: 'medium',
    );
  }
}

// Helper class for admin and system notifications
class AdminNotificationHelpers {

  // Welcome new users
  static Future<void> sendWelcomeNotification(String userId, String userName) async {
    await NotificationService.createNotification(
      userId: userId,
      type: 'system',
      title: 'Welcome to Sportify!',
      message: 'Hi $userName! Welcome to Sportify. Start by booking a court or finding a coach to begin your fitness journey.',
      data: {
        'action': 'explore_app',
      },
      priority: 'medium',
    );
  }

  // Coach application status updates
  static Future<void> notifyCoachApplicationApproved(String userId, String coachName) async {
    await NotificationService.createNotification(
      userId: userId,
      type: 'system',
      title: 'Coach Application Approved!',
      message: 'Congratulations! Your application to become a coach has been approved. You can now start accepting students.',
      data: {
        'action': 'coach_dashboard',
      },
      priority: 'high',
    );
  }

  static Future<void> notifyCoachApplicationRejected(String userId, String reason) async {
    await NotificationService.createNotification(
      userId: userId,
      type: 'system',
      title: 'Coach Application Update',
      message: 'Unfortunately, your coach application was not approved. Reason: $reason. You can reapply after addressing the feedback.',
      priority: 'high',
    );
  }

  // New feature announcements
  static Future<void> announceNewFeature(String title, String message) async {
    await NotificationService.createSystemNotification(
      title: title,
      message: message,
    );
  }

  // Maintenance notifications
  static Future<void> notifyMaintenance(DateTime scheduledTime, String duration) async {
    await NotificationService.createSystemNotification(
      title: 'Scheduled Maintenance',
      message: 'Sportify will be under maintenance on ${scheduledTime.day}/${scheduledTime.month} for $duration. We apologize for any inconvenience.',
    );
  }
}

// Helper class for booking-related notifications
class BookingNotificationHelpers {

  // When a coach confirms an appointment
  static Future<void> notifyCoachAppointmentConfirmed(String userId, Map<String, dynamic> appointmentData) async {
    await NotificationService.createNotification(
      userId: userId,
      type: 'coach',
      title: 'Coach Session Confirmed!',
      message: '${appointmentData['coachName']} has confirmed your session for ${appointmentData['date']} at ${appointmentData['timeSlot']}.',
      data: {
        'appointmentId': appointmentData['id'],
        'action': 'view_booking',
      },
      priority: 'high',
    );
  }

  // When a booking is cancelled
  static Future<void> notifyBookingCancelled(String userId, String bookingType, Map<String, dynamic> bookingData) async {
    String title = bookingType == 'coach' ? 'Coach Session Cancelled' : 'Court Booking Cancelled';
    String message = bookingType == 'coach'
        ? 'Your session with ${bookingData['coachName']} has been cancelled.'
        : 'Your court booking at ${bookingData['venueName']} has been cancelled.';

    await NotificationService.createNotification(
      userId: userId,
      type: 'booking',
      title: title,
      message: message,
      data: {
        'bookingId': bookingData['id'],
        'action': 'view_booking',
      },
      priority: 'high',
    );
  }

  // Payment related notifications
  static Future<void> notifyPaymentDue(String userId, Map<String, dynamic> bookingData) async {
    await NotificationService.createPaymentNotification(
      userId: userId,
      title: 'Payment Reminder',
      message: 'Payment is due for your upcoming booking. Please complete payment to confirm your reservation.',
      paymentData: {
        'bookingId': bookingData['id'],
        'amount': bookingData['totalPrice'],
      },
    );
  }

  static Future<void> notifyPaymentCompleted(String userId, Map<String, dynamic> bookingData) async {
    await NotificationService.createPaymentNotification(
      userId: userId,
      title: 'Payment Confirmed',
      message: 'Your payment has been processed successfully. Your booking is now confirmed.',
      paymentData: {
        'bookingId': bookingData['id'],
        'amount': bookingData['totalPrice'],
      },
      priority: 'medium',
    );
  }

  // Reminder notifications (you can set up Cloud Functions to trigger these)
  static Future<void> notifyUpcomingBooking(String userId, Map<String, dynamic> bookingData) async {
    String message = bookingData['bookingType'] == 'coach'
        ? 'Your session with ${bookingData['coachName']} is tomorrow at ${bookingData['timeSlot']}'
        : 'Your court booking at ${bookingData['venueName']} is tomorrow at ${bookingData['timeSlot']}';

    await NotificationService.createNotification(
      userId: userId,
      type: 'booking',
      title: 'Upcoming Booking Reminder',
      message: message,
      data: {
        'bookingId': bookingData['id'],
        'action': 'view_booking',
      },
      priority: 'medium',
    );
  }

  // When a booking status changes
  static Future<void> notifyBookingStatusChange(String userId, String status, Map<String, dynamic> bookingData) async {
    String title = 'Booking Status Updated';
    String message = 'Your booking status has been updated to: ${status.toUpperCase()}';

    switch (status.toLowerCase()) {
      case 'confirmed':
        title = 'Booking Confirmed';
        message = 'Your booking has been confirmed and is ready for your visit.';
        break;
      case 'cancelled':
        title = 'Booking Cancelled';
        message = 'Your booking has been cancelled. If you have any questions, please contact support.';
        break;
      case 'completed':
        title = 'Session Completed';
        message = 'Thank you for using Sportify! How was your experience?';
        break;
    }

    await NotificationService.createNotification(
      userId: userId,
      type: 'booking',
      title: title,
      message: message,
      data: {
        'bookingId': bookingData['id'],
        'action': 'view_booking',
        'status': status,
      },
      priority: status == 'cancelled' ? 'high' : 'medium',
    );
  }
}