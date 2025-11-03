import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PayPalService {
  // PayPal Sandbox Credentials (for testing)
  // Get these from: https://developer.paypal.com/developer/applications
  static const String _clientId = 'AXF93VMtb1mck9gTglQNns_Cx-HPSZInn7N_vOoCeKNyc3RyouQKYC8ehqVNkyyNFwKoOEEpKfyAKS2w';
  static const String _secretKey = 'EMfJugmMPqsSAP3bet90VrJ7IYzua4Xx71A7RHsL4L48yWTgKx_eaQq0X1oTxUdjMjuw33Yb67X4nPap';

  // Sandbox URL for testing (use production URL when going live)
  static const String _baseUrl = 'https://api-m.sandbox.paypal.com';
  // Production: 'https://api-m.paypal.com'

  /// Get PayPal Access Token
  static Future<String?> _getAccessToken() async {
    try {
      final credentials = base64Encode(utf8.encode('$_clientId:$_secretKey'));

      final response = await http.post(
        Uri.parse('$_baseUrl/v1/oauth2/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['access_token'];
      } else {
        debugPrint('Token error: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Token exception: $e');
      return null;
    }
  }

  /// Create PayPal Order
  static Future<Map<String, dynamic>> createOrder({
    required double amount,
    required String description,
    required String bookingId,
    required String bookingType,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        return {
          'success': false,
          'error': 'Failed to authenticate with PayPal',
        };
      }

      final orderData = {
        'intent': 'CAPTURE',
        'purchase_units': [
          {
            'reference_id': bookingId,
            'description': description,
            'custom_id': bookingType, // 'court' or 'coach'
            'amount': {
              'currency_code': 'MYR', //  CHANGED FROM USD TO MYR
              'value': amount.toStringAsFixed(2),
            },
          }
        ],
        'application_context': {
          'return_url': 'sportify://payment/success',
          'cancel_url': 'sportify://payment/cancel',
          'brand_name': 'Sportify',
          'user_action': 'PAY_NOW',
        }
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/v2/checkout/orders'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(orderData),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);

        final approvalUrl = (data['links'] as List)
            .firstWhere((link) => link['rel'] == 'approve')['href'];

        debugPrint('PayPal order created: ${data['id']}');

        return {
          'success': true,
          'orderId': data['id'],
          'approvalUrl': approvalUrl,
          'data': data,
        };
      } else {
        debugPrint('Order error: ${response.statusCode} - ${response.body}');
        return {
          'success': false,
          'error': 'Failed to create PayPal order: ${response.body}',
        };
      }
    } catch (e) {
      debugPrint('Order exception: $e');
      return {
        'success': false,
        'error': 'Payment system error: $e',
      };
    }
  }

  /// Capture (Complete) PayPal Payment
  static Future<Map<String, dynamic>> captureOrder(String orderId) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        return {
          'success': false,
          'error': 'Failed to authenticate',
        };
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/v2/checkout/orders/$orderId/capture'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);

        return {
          'success': true,
          'status': data['status'],
          'captureId': data['purchase_units'][0]['payments']['captures'][0]['id'],
          'data': data,
        };
      } else {
        debugPrint('Capture error: ${response.body}');
        return {
          'success': false,
          'error': 'Failed to capture payment',
        };
      }
    } catch (e) {
      debugPrint('Capture exception: $e');
      return {
        'success': false,
        'error': 'Error capturing payment: $e',
      };
    }
  }

  /// Get Order Details
  static Future<Map<String, dynamic>> getOrderDetails(String orderId) async {
    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        return {
          'success': false,
          'error': 'Failed to authenticate',
        };
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/v2/checkout/orders/$orderId'),
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        return {
          'success': true,
          'status': data['status'], // CREATED, APPROVED, COMPLETED
          'data': data,
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to get order details',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Error getting order: $e',
      };
    }
  }

  /// Confirm Payment and Update Booking
  static Future<void> confirmPayment({
    required String bookingId,
    required String bookingType,
    required String orderId,
    required String captureId,
    required double amount,
  }) async {
    try {
      final db = FirebaseFirestore.instance;
      final collectionName = bookingType == 'coach' ? 'coach_appointments' : 'bookings';

      // Update booking status
      await db.collection(collectionName).doc(bookingId).update({
        'status': 'confirmed',
        'paymentStatus': 'completed',
        'paymentMethod': 'paypal',
        'paymentId': captureId,
        'paypalOrderId': orderId,
        'paidAmount': amount,
        'paidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Get booking data for notification
      final bookingDoc = await db.collection(collectionName).doc(bookingId).get();
      final bookingData = bookingDoc.data();

      if (bookingData != null) {
        // Create notification for user
        await db.collection('notifications').add({
          'userId': bookingData['userId'],
          'type': 'payment_success',
          'title': 'Payment Successful',
          'message': bookingType == 'coach'
              ? 'Your coaching session payment has been confirmed. Session with ${bookingData['coachName']} on ${bookingData['date']}.'
              : 'Your court booking payment has been confirmed. ${bookingData['venueName']} on ${bookingData['date']}.',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'metadata': {
            'bookingId': bookingId,
            'bookingType': bookingType,
            'amount': amount,
            'paymentId': captureId,
          },
        });

        // If coach booking, notify coach too
        if (bookingType == 'coach') {
          await db.collection('notifications').add({
            'userId': bookingData['coachId'],
            'type': 'booking_confirmed',
            'title': 'Booking Payment Confirmed',
            'message': 'Payment confirmed for session with ${bookingData['studentName']} on ${bookingData['date']}.',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
            'metadata': {
              'bookingId': bookingId,
              'bookingType': bookingType,
              'amount': amount,
            },
          });
        }
      }

      debugPrint('Payment confirmed successfully');
    } catch (e) {
      debugPrint('Error confirming payment: $e');
      rethrow;
    }
  }

  /// Confirm Tournament Payment and Update Registration
  static Future<void> confirmTournamentPayment({
    required String registrationId,
    required String tournamentId,
    required String orderId,
    required String captureId,
    required double amount,
  }) async {
    try {
      final db = FirebaseFirestore.instance;

      // Update registration status
      await db.collection('tournament_registrations').doc(registrationId).update({
        'status': 'confirmed',
        'paymentStatus': 'completed',
        'paymentMethod': 'paypal',
        'paymentId': captureId,
        'paypalOrderId': orderId,
        'paidAmount': amount,
        'paidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Increment tournament participant count
      await db.collection('tournaments').doc(tournamentId).update({
        'currentParticipants': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Get registration data for notifications
      final registrationDoc = await db.collection('tournament_registrations').doc(registrationId).get();
      final registrationData = registrationDoc.data();

      // Get tournament data
      final tournamentDoc = await db.collection('tournaments').doc(tournamentId).get();
      final tournamentData = tournamentDoc.data();

      if (registrationData != null && tournamentData != null) {
        // Create notification for user
        await db.collection('notifications').add({
          'userId': registrationData['userId'],
          'type': 'payment',
          'title': 'Tournament Payment Successful',
          'message':
          'Your payment for ${tournamentData['name']} has been confirmed. You are now registered!',
          'data': {
            'tournamentId': tournamentId,
            'registrationId': registrationId,
            'action': 'view_tournament',
          },
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'priority': 'high',
        });

        // Create notification for venue owner
        await db.collection('notifications').add({
          'userId': tournamentData['venueOwnerId'],
          'type': 'tournament',
          'title': 'New Tournament Registration',
          'message':
          '${registrationData['userName']} has paid and joined ${tournamentData['name']}',
          'data': {
            'tournamentId': tournamentId,
            'action': 'view_tournament',
          },
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'priority': 'medium',
        });
      }

      debugPrint('Tournament payment confirmed successfully');
    } catch (e) {
      debugPrint('Error confirming tournament payment: $e');
      rethrow;
    }
  }

  /// Poll Payment Status (check if user completed payment)
  static Future<bool> pollPaymentStatus({
    required String orderId,
    required String bookingId,
    required String bookingType,
    int maxAttempts = 60, // 10 minutes
    Duration interval = const Duration(seconds: 10),
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      debugPrint('Checking PayPal payment status... Attempt ${i + 1}/$maxAttempts');

      final orderDetails = await getOrderDetails(orderId);

      if (orderDetails['success']) {
        final status = orderDetails['data']['status'];

        if (status == 'COMPLETED') {
          // Payment successful! Capture it
          final captureResult = await captureOrder(orderId);

          if (captureResult['success']) {
            await confirmPayment(
              bookingId: bookingId,
              bookingType: bookingType,
              orderId: orderId,
              captureId: captureResult['captureId'],
              amount: double.parse(
                  orderDetails['data']['purchase_units'][0]['amount']['value']
              ),
            );
            return true;
          }
        } else if (status == 'APPROVED') {
          // User approved, now capture
          final captureResult = await captureOrder(orderId);

          if (captureResult['success']) {
            await confirmPayment(
              bookingId: bookingId,
              bookingType: bookingType,
              orderId: orderId,
              captureId: captureResult['captureId'],
              amount: double.parse(
                  orderDetails['data']['purchase_units'][0]['amount']['value']
              ),
            );
            return true;
          }
        } else if (status == 'VOIDED' || status == 'EXPIRED') {
          debugPrint('Payment cancelled or expired');

          // Update booking as failed
          final db = FirebaseFirestore.instance;
          final collectionName = bookingType == 'coach' ? 'coach_appointments' : 'bookings';
          await db.collection(collectionName).doc(bookingId).update({
            'status': 'cancelled',
            'paymentStatus': 'failed',
            'updatedAt': FieldValue.serverTimestamp(),
          });

          return false;
        }
      }

      // Wait before next check
      if (i < maxAttempts - 1) {
        await Future.delayed(interval);
      }
    }

    debugPrint('Payment status check timed out');
    return false;
  }
}