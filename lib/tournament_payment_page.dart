import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/paypal_service.dart';

class TournamentPaymentPage extends StatefulWidget {
  final Map<String, dynamic> tournament;
  final String registrationId;

  const TournamentPaymentPage({
    Key? key,
    required this.tournament,
    required this.registrationId,
  }) : super(key: key);

  @override
  State<TournamentPaymentPage> createState() => _TournamentPaymentPageState();
}

class _TournamentPaymentPageState extends State<TournamentPaymentPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isProcessing = false;
  bool _agreeToTerms = false;
  bool _isPollingPayment = false;

  String? _currentOrderId;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isPollingPayment) {
          final shouldLeave = await _showLeaveConfirmation();
          return shouldLeave ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTournamentSummary(),
                    const SizedBox(height: 24),
                    _buildPayPalInfo(),
                    const SizedBox(height: 24),
                    _buildTournamentPolicy(),
                    const SizedBox(height: 24),
                    _buildTermsCheckbox(),
                    if (_isPollingPayment) ...[
                      const SizedBox(height: 24),
                      _buildPaymentStatusCard(),
                    ],
                  ],
                ),
              ),
            ),
            _buildPaymentButton(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
        onPressed: _isPollingPayment ? null : () => Navigator.pop(context),
      ),
      title: const Text(
        'Complete Payment',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildTournamentSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Color(0xFFFF8A50),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Tournament Registration',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSummaryRow('Tournament', widget.tournament['name'] ?? 'Unknown Tournament'),
          _buildSummaryRow('Venue', widget.tournament['venueName'] ?? 'N/A'),
          _buildSummaryRow('Sport', widget.tournament['sport'] ?? 'N/A'),
          _buildSummaryRow('Format', widget.tournament['format'] ?? 'N/A'),
          _buildSummaryRow('Start Date', _formatDate(widget.tournament['startDate'])),
          const Divider(height: 32),
          _buildSummaryRow(
            'Entry Fee',
            'RM ${_formatRM(widget.tournament['entryFee'] ?? 0)}',
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: isTotal ? const Color(0xFF2D3748) : Colors.grey[600],
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: isTotal ? 18 : 14,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
                color: isTotal ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayPalInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0070BA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.payment,
                  color: Color(0xFF0070BA),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Payment Method',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0070BA), Color(0xFF1546A0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'PayPal',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0070BA),
                      fontFamily: 'Verdana',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Secure Payment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Pay with PayPal, credit card, or debit card',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                'Buyer Protection • Secure Checkout',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTournamentPolicy() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Tournament Policy',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.orange[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPolicyItem('✓ Entry fee is non-refundable once paid'),
          _buildPolicyItem('✓ You will be confirmed as a participant after payment'),
          _buildPolicyItem('✓ Check tournament rules and regulations'),
        ],
      ),
    );
  }

  Widget _buildPolicyItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.orange[800],
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildTermsCheckbox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _agreeToTerms,
            onChanged: (value) => setState(() => _agreeToTerms = value ?? false),
            activeColor: const Color(0xFFFF8A50),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Color(0xFF2D3748)),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Tournament Policy',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                      const TextSpan(text: ' and understand the '),
                      TextSpan(
                        text: 'Entry Fee Policy',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0070BA).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0070BA).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0070BA)),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Checking Payment Status...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we verify your PayPal payment',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'This may take a few moments...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentButton() {
    final canPay = _agreeToTerms && !_isProcessing && !_isPollingPayment;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: canPay ? _handlePayment : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canPay ? const Color(0xFF0070BA) : Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isProcessing
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2.5,
              ),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  'PAY WITH PAYPAL - RM ${_formatRM(widget.tournament['entryFee'] ?? 0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatRM(dynamic amount) {
    final value = (amount is int) ? amount.toDouble() : (amount as double? ?? 0);
    return value.toStringAsFixed(2);
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'TBA';
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    }
    return 'TBA';
  }

  Future<void> _handlePayment() async {
    setState(() => _isProcessing = true);

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'Please login to complete payment';
      }

      final amountRM = (widget.tournament['entryFee'] ?? 0).toDouble();

      final orderResult = await PayPalService.createOrder(
        amount: amountRM,
        description: 'Tournament Entry: ${widget.tournament['name']}',
        bookingId: widget.registrationId,
        bookingType: 'tournament',
      );

      if (orderResult['success']) {
        _currentOrderId = orderResult['orderId'];

        // Update registration with PayPal order ID
        await _firestore
            .collection('tournament_registrations')
            .doc(widget.registrationId)
            .update({
          'paypalOrderId': orderResult['orderId'],
          'paymentMethod': 'paypal',
          'paymentStatus': 'processing',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Open PayPal in external browser
        final Uri paymentUri = Uri.parse(orderResult['approvalUrl']);
        if (await canLaunchUrl(paymentUri)) {
          await launchUrl(paymentUri, mode: LaunchMode.externalApplication);

          if (mounted) {
            setState(() {
              _isProcessing = false;
              _isPollingPayment = true;
            });

            _startPaymentPolling();
          }
        } else {
          throw 'Could not open PayPal payment page';
        }
      } else {
        throw orderResult['error'] ?? 'Failed to create PayPal order';
      }
    } catch (e) {
      print('Payment error: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startPaymentPolling() async {
    if (_currentOrderId == null) return;

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Poll payment status (checking every 10 seconds for up to 10 minutes)
      bool paymentSuccess = false;
      int attempts = 0;
      const maxAttempts = 60; // 10 minutes

      while (attempts < maxAttempts && mounted) {
        attempts++;

        print('Checking payment status... Attempt $attempts/$maxAttempts');

        final orderDetails = await PayPalService.getOrderDetails(_currentOrderId!);

        if (orderDetails['success']) {
          final status = orderDetails['data']['status'];

          if (status == 'COMPLETED' || status == 'APPROVED') {
            // Payment successful! Capture it
            final captureResult = await PayPalService.captureOrder(_currentOrderId!);

            if (captureResult['success']) {
              await _confirmPayment(
                captureId: captureResult['captureId'],
                amount: widget.tournament['entryFee'].toDouble(),
              );
              paymentSuccess = true;
              break;
            }
          } else if (status == 'VOIDED' || status == 'EXPIRED') {
            print('Payment cancelled or expired');
            break;
          }
        }

        // Wait 10 seconds before next check
        await Future.delayed(const Duration(seconds: 10));
      }

      if (mounted) {
        setState(() => _isPollingPayment = false);

        if (paymentSuccess) {
          _showPaymentSuccessDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Payment verification timed out. Please check your tournament registrations.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      print('Error polling payment: $e');
      if (mounted) {
        setState(() => _isPollingPayment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error verifying payment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmPayment({
    required String captureId,
    required double amount,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Update registration status to confirmed
      await _firestore
          .collection('tournament_registrations')
          .doc(widget.registrationId)
          .update({
        'paymentStatus': 'completed',
        'paymentMethod': 'paypal',
        'paymentId': captureId,
        'paypalOrderId': _currentOrderId,
        'paidAmount': amount,
        'paidAt': FieldValue.serverTimestamp(),
        'status': 'confirmed',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Increment tournament participant count
      await _firestore
          .collection('tournaments')
          .doc(widget.tournament['id'])
          .update({
        'currentParticipants': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Get user data for notification
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      // Create notification for user
      await _firestore.collection('notifications').add({
        'userId': user.uid,
        'type': 'payment',
        'title': 'Tournament Payment Successful',
        'message':
        'Your payment for ${widget.tournament['name']} has been confirmed. You are now registered!',
        'data': {
          'tournamentId': widget.tournament['id'],
          'registrationId': widget.registrationId,
          'action': 'view_tournament',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'priority': 'high',
      });

      // Create notification for venue owner
      await _firestore.collection('notifications').add({
        'userId': widget.tournament['venueOwnerId'],
        'type': 'tournament',
        'title': 'New Tournament Registration',
        'message':
        '${userData?['name'] ?? 'A participant'} has paid and joined ${widget.tournament['name']}',
        'data': {
          'tournamentId': widget.tournament['id'],
          'action': 'view_tournament',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'priority': 'medium',
      });

      print('Payment confirmed successfully');
    } catch (e) {
      print('Error confirming payment: $e');
      rethrow;
    }
  }

  Future<bool?> _showLeaveConfirmation() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Payment in Progress'),
        content: const Text(
            'Payment verification is still in progress. Are you sure you want to leave?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showPaymentSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Payment Successful!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'You are now registered for ${widget.tournament['name']}!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Amount Paid:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            'RM ${_formatRM(widget.tournament['entryFee'])}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Payment Method:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            'PayPal',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      Navigator.of(context).pop(true); // Return to My Tournaments with refresh flag
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0070BA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'View My Tournaments',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      Navigator.of(context).pop(); // Go back to detail page
                      Navigator.of(context).pop(); // Go back to tournaments list
                    },
                    child: const Text(
                      'Back to Tournaments',
                      style: TextStyle(
                        color: Color(0xFF2D3748),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}