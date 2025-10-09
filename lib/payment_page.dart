import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/paypal_service.dart';

class PaymentPage extends StatefulWidget {
  final Map<String, dynamic> appointment;

  const PaymentPage({Key? key, required this.appointment}) : super(key: key);

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isProcessing = false;
  bool _agreeToTerms = false;
  bool _isPollingPayment = false;

  String? _currentOrderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app returns from background (after PayPal payment)
    if (state == AppLifecycleState.resumed && _currentOrderId != null && !_isPollingPayment) {
      // Check payment immediately when returning to app
      _checkPaymentStatusNow();
    }
  }

  Future<void> _checkPaymentStatusNow() async {
    if (_currentOrderId == null) return;

    setState(() {
      _isProcessing = true;
      _isPollingPayment = true;
    });

    try {
      // Wait a bit for PayPal to process
      await Future.delayed(const Duration(seconds: 2));

      final orderDetails = await PayPalService.getOrderDetails(_currentOrderId!);

      if (orderDetails['success']) {
        final status = orderDetails['data']['status'];

        if (status == 'COMPLETED' || status == 'APPROVED') {
          final captureResult = await PayPalService.captureOrder(_currentOrderId!);

          if (captureResult['success']) {
            await PayPalService.confirmPayment(
              bookingId: widget.appointment['id'],
              bookingType: 'coach',
              orderId: _currentOrderId!,
              captureId: captureResult['captureId'],
              amount: double.parse(
                  orderDetails['data']['purchase_units'][0]['amount']['value']
              ),
            );

            if (mounted) {
              setState(() {
                _isProcessing = false;
                _isPollingPayment = false;
              });
              _showPaymentSuccessDialog();
            }
            return;
          }
        }
      }
    } catch (e) {
      print('Error checking payment: $e');
    }

    // If not successful immediately, continue polling
    if (mounted) {
      setState(() => _isProcessing = false);
      _startPaymentPolling();
    }
  }

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
                    _buildBookingSummary(),
                    const SizedBox(height: 24),
                    _buildPayPalInfo(),
                    const SizedBox(height: 24),
                    _buildReschedulingPolicy(),
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

  Widget _buildBookingSummary() {
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
                  Icons.receipt_long,
                  color: Color(0xFFFF8A50),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Booking Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSummaryRow('Coach', widget.appointment['coachName'] ?? 'Coach'),
          _buildSummaryRow('Sport', widget.appointment['coachSport'] ?? 'Sport'),
          _buildSummaryRow('Date', widget.appointment['date'] ?? 'N/A'),
          _buildSummaryRow('Time', '${widget.appointment['timeSlot']} - ${widget.appointment['endTime']}'),
          _buildSummaryRow('Duration', '${widget.appointment['duration']} hour(s)'),
          const Divider(height: 32),
          _buildSummaryRow(
            'Total Amount',
            'RM ${_formatRM(widget.appointment['paymentAmount'] ?? widget.appointment['price'] ?? 0)}',
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
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
              color: isTotal ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
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

  Widget _buildReschedulingPolicy() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Rescheduling Policy',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPolicyItem('✓ You can reschedule up to 2 times'),
          _buildPolicyItem('✓ No refunds, but flexible rescheduling'),
          _buildPolicyItem('✓ Must reschedule 24+ hours before session'),
          _buildPolicyItem('✓ Coach must approve new time'),
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
          color: Colors.blue[800],
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
                        text: 'Terms & Conditions',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Rescheduling Policy',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                          decoration: TextDecoration.underline,
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
        ],
      ),
    );
  }

  Widget _buildPaymentButton() {
    final canPay = _agreeToTerms && !_isProcessing && !_isPollingPayment;
    final amount = widget.appointment['paymentAmount'] ?? widget.appointment['price'] ?? 0;

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
                  'PAY WITH PAYPAL - RM ${_formatRM(amount)}',
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

  Future<void> _handlePayment() async {
    setState(() => _isProcessing = true);

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'Please login to complete payment';
      }

      final amountRM = (widget.appointment['paymentAmount'] ?? widget.appointment['price'] ?? 0).toDouble();

      final orderResult = await PayPalService.createOrder(
        amount: amountRM,
        description: 'Coach Booking - ${widget.appointment['coachName']} - ${widget.appointment['date']}',
        bookingId: widget.appointment['id'],
        bookingType: 'coach',
      );

      if (orderResult['success']) {
        _currentOrderId = orderResult['orderId'];

        await _firestore
            .collection('coach_appointments')
            .doc(widget.appointment['id'])
            .update({
          'paypalOrderId': orderResult['orderId'],
          'paymentMethod': 'paypal',
          'paymentStatus': 'processing',
          'updatedAt': FieldValue.serverTimestamp(),
        });

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

    final paymentSuccess = await PayPalService.pollPaymentStatus(
      orderId: _currentOrderId!,
      bookingId: widget.appointment['id'],
      bookingType: 'coach',
      maxAttempts: 60,
      interval: const Duration(seconds: 10),
    );

    if (mounted) {
      setState(() => _isPollingPayment = false);

      if (paymentSuccess) {
        _showPaymentSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment verification timed out. Please check your bookings.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<bool?> _showLeaveConfirmation() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment in Progress'),
        content: const Text('Payment verification is still in progress. Are you sure you want to leave?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
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
                ),
                const SizedBox(height: 12),
                Text(
                  'Your coaching session is now confirmed. You can chat with your coach and reschedule if needed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0070BA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
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