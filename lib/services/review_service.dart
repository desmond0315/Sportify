import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/review_model.dart';
import 'notification_service.dart';

class ReviewService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Check if user can review (appointment must be completed and not already reviewed)
  static Future<bool> canReviewAppointment(String appointmentId, String userId) async {
    try {
      // Check if appointment exists and is completed
      final appointmentDoc = await _firestore
          .collection('coach_appointments')
          .doc(appointmentId)
          .get();

      if (!appointmentDoc.exists) return false;

      final appointmentData = appointmentDoc.data() as Map<String, dynamic>;

      // Must be the student who made the appointment
      if (appointmentData['userId'] != userId) return false;

      // Must be completed (accept both 'completed' and 'complete')
      if (appointmentData['status'] != 'completed' && appointmentData['status'] != 'complete') return false;

      // Check if already reviewed
      final existingReview = await _firestore
          .collection('coach_appointments')
          .doc(appointmentId)
          .collection('reviews')
          .where('studentId', isEqualTo: userId)
          .limit(1)
          .get();

      return existingReview.docs.isEmpty;
    } catch (e) {
      print('Error checking review eligibility: $e');
      return false;
    }
  }

  // Submit a review
  static Future<String?> submitReview({
    required String appointmentId,
    required String coachId,
    required String coachName,
    required String studentId,
    required String studentName,
    required int rating,
    required String comment,
  }) async {
    try {
      // Validate rating
      if (rating < 1 || rating > 5) {
        throw 'Rating must be between 1 and 5';
      }

      // Check if can review
      final canReview = await canReviewAppointment(appointmentId, studentId);
      if (!canReview) {
        throw 'You cannot review this appointment';
      }

      final reviewData = {
        'coachId': coachId,
        'coachName': coachName,
        'studentId': studentId,
        'studentName': studentName,
        'userName': studentName, // For backward compatibility
        'appointmentId': appointmentId,
        'rating': rating,
        'comment': comment.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      };

      // Add review to coach's reviews subcollection
      final reviewRef = await _firestore
          .collection('coaches')
          .doc(coachId)
          .collection('reviews')
          .add(reviewData);

      // Also add to appointment's reviews subcollection
      await _firestore
          .collection('coach_appointments')
          .doc(appointmentId)
          .collection('reviews')
          .doc(reviewRef.id)
          .set(reviewData);

      // Mark appointment as reviewed
      await _firestore
          .collection('coach_appointments')
          .doc(appointmentId)
          .update({
        'hasReview': true,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update coach's rating statistics
      await _updateCoachRating(coachId);

      // Send notification to coach
      await NotificationService.notifyCoachNewReview(
        coachId: coachId,
        studentName: studentName,
        rating: rating,
      );

      return reviewRef.id;
    } catch (e) {
      print('Error submitting review: $e');
      rethrow;
    }
  }

  // Check if user can review venue booking
  static Future<bool> canReviewVenueBooking(String bookingId, String userId) async {
    try {
      // Check if booking exists and is completed
      final bookingDoc = await _firestore
          .collection('bookings')
          .doc(bookingId)
          .get();

      if (!bookingDoc.exists) {
        print('DEBUG: Booking does not exist');
        return false;
      }

      final bookingData = bookingDoc.data() as Map<String, dynamic>;

      // Must be the user who made the booking
      if (bookingData['userId'] != userId) {
        print('DEBUG: User is not the booking owner');
        return false;
      }

      // Check if booking TIME has passed (not just the date)
      final bookingDateStr = bookingData['date'] as String?;
      final endTimeStr = bookingData['endTime'] as String?;

      if (bookingDateStr != null && endTimeStr != null) {
        try {
          // Parse the booking date (YYYY-MM-DD)
          final dateParts = bookingDateStr.split('-');
          final year = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final day = int.parse(dateParts[2]);

          // Parse the end time (HH:MM)
          final timeParts = endTimeStr.split(':');
          final hour = int.parse(timeParts[0]);
          final minute = int.parse(timeParts[1]);

          // Create the booking end datetime
          final bookingEndTime = DateTime(year, month, day, hour, minute);
          final now = DateTime.now();

          // Booking end time must have passed
          if (!now.isAfter(bookingEndTime)) {
            print('DEBUG: Booking end time has not passed yet');
            print('DEBUG: Booking ends at: $bookingEndTime');
            print('DEBUG: Current time: $now');
            return false;
          }

          print('DEBUG: Booking end time has passed');
        } catch (e) {
          print('DEBUG: Error parsing booking date/time: $e');
          return false;
        }
      } else {
        print('DEBUG: Missing date or endTime field');
        return false;
      }

      // Must be confirmed (payment completed) and not cancelled
      final status = bookingData['status'] as String?;
      final paymentStatus = bookingData['paymentStatus'] as String?;

      if (status == 'cancelled') {
        print('DEBUG: Booking is cancelled');
        return false;
      }

      if (paymentStatus != 'completed' && paymentStatus != 'paid' && paymentStatus != 'held_by_admin') {
        print('DEBUG: Payment not completed. Status: $paymentStatus');
        return false;
      }

      // Check if already reviewed
      final existingReview = await _firestore
          .collection('bookings')
          .doc(bookingId)
          .collection('reviews')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (existingReview.docs.isNotEmpty) {
        print('DEBUG: Booking already reviewed');
        return false;
      }

      print('DEBUG: User can review this booking');
      return true;
    } catch (e) {
      print('Error checking venue review eligibility: $e');
      return false;
    }
  }

// Submit a venue review
  static Future<String?> submitVenueReview({
    required String bookingId,
    required String venueId,
    required String venueName,
    required String userId,
    required String userName,
    required int rating,
    required String comment,
  }) async {
    try {
      // Validate rating
      if (rating < 1 || rating > 5) {
        throw 'Rating must be between 1 and 5';
      }

      // Check if can review
      final canReview = await canReviewVenueBooking(bookingId, userId);
      if (!canReview) {
        throw 'You cannot review this booking';
      }

      final reviewData = {
        'venueId': venueId,
        'venueName': venueName,
        'userId': userId,
        'userName': userName,
        'bookingId': bookingId,
        'rating': rating,
        'comment': comment.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      };

      // Add review to venue's reviews subcollection
      final reviewRef = await _firestore
          .collection('venues')
          .doc(venueId)
          .collection('reviews')
          .add(reviewData);

      // Also add to booking's reviews subcollection
      await _firestore
          .collection('bookings')
          .doc(bookingId)
          .collection('reviews')
          .doc(reviewRef.id)
          .set(reviewData);

      // Mark booking as reviewed
      await _firestore
          .collection('bookings')
          .doc(bookingId)
          .update({
        'hasReview': true,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update venue's rating statistics
      await _updateVenueRating(venueId);

      // Send notification to venue owner (optional)
      // You can implement this later if needed

      return reviewRef.id;
    } catch (e) {
      print('Error submitting venue review: $e');
      rethrow;
    }
  }

// Update venue's overall rating
  static Future<void> _updateVenueRating(String venueId) async {
    try {
      // Get all reviews for this venue
      final reviewsSnapshot = await _firestore
          .collection('venues')
          .doc(venueId)
          .collection('reviews')
          .where('isActive', isEqualTo: true)
          .get();

      if (reviewsSnapshot.docs.isEmpty) return;

      // Calculate average rating
      double totalRating = 0;
      int count = 0;

      for (var doc in reviewsSnapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] as int? ?? 0;
        if (rating > 0) {
          totalRating += rating;
          count++;
        }
      }

      final averageRating = count > 0 ? totalRating / count : 0.0;

      // Update venue document
      await _firestore.collection('venues').doc(venueId).update({
        'rating': double.parse(averageRating.toStringAsFixed(1)),
        'totalReviews': count,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating venue rating: $e');
    }
  }

// Check if venue booking has been reviewed
  static Future<bool> hasReviewedVenueBooking(String bookingId, String userId) async {
    try {
      final reviewSnapshot = await _firestore
          .collection('bookings')
          .doc(bookingId)
          .collection('reviews')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      return reviewSnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if reviewed: $e');
      return false;
    }
  }

  // Update coach's overall rating
  static Future<void> _updateCoachRating(String coachId) async {
    try {
      // Get all reviews for this coach
      final reviewsSnapshot = await _firestore
          .collection('coaches')
          .doc(coachId)
          .collection('reviews')
          .where('isActive', isEqualTo: true)
          .get();

      if (reviewsSnapshot.docs.isEmpty) {
        // No reviews yet, set default values
        await _firestore.collection('coaches').doc(coachId).update({
          'rating': 0.0,
          'totalReviews': 0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Calculate average rating
      double totalRating = 0;
      int count = 0;

      for (var doc in reviewsSnapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] as int? ?? 0;
        if (rating > 0) {
          totalRating += rating;
          count++;
        }
      }

      final averageRating = count > 0 ? totalRating / count : 0.0;

      print('DEBUG: Updating coach rating - Total: $totalRating, Count: $count, Average: $averageRating');

      // Update coach document
      await _firestore.collection('coaches').doc(coachId).update({
        'rating': double.parse(averageRating.toStringAsFixed(1)),
        'totalReviews': count,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('DEBUG: Coach rating updated successfully');
    } catch (e) {
      print('Error updating coach rating: $e');
      // Don't throw error - we don't want to fail the review submission if rating update fails
    }
  }

  // Get reviews for a coach
  static Stream<List<ReviewModel>> getCoachReviews(String coachId) {
    return _firestore
        .collection('coaches')
        .doc(coachId)
        .collection('reviews')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ReviewModel.fromFirestore(doc)).toList();
    });
  }

  // Check if appointment has been reviewed
  static Future<bool> hasReviewed(String appointmentId, String userId) async {
    try {
      final reviewSnapshot = await _firestore
          .collection('coach_appointments')
          .doc(appointmentId)
          .collection('reviews')
          .where('studentId', isEqualTo: userId)
          .limit(1)
          .get();

      return reviewSnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking if reviewed: $e');
      return false;
    }
  }

  // Get user's review for an appointment
  static Future<ReviewModel?> getUserReview(String appointmentId, String userId) async {
    try {
      final reviewSnapshot = await _firestore
          .collection('coach_appointments')
          .doc(appointmentId)
          .collection('reviews')
          .where('studentId', isEqualTo: userId)
          .limit(1)
          .get();

      if (reviewSnapshot.docs.isEmpty) return null;

      return ReviewModel.fromFirestore(reviewSnapshot.docs.first);
    } catch (e) {
      print('Error getting user review: $e');
      return null;
    }
  }
}