import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/messaging_service.dart';
import '../services/review_service.dart';
import 'chat_page.dart';
import 'services/notification_service.dart';
import 'write_review_page.dart';
import 'write_venue_review_page.dart';
import 'payment_page.dart';
import 'payment_page.dart';
import 'reschedule_request_page.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({Key? key}) : super(key: key);

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late TabController _tabController;
  bool _isLoading = true;

  List<Map<String, dynamic>> _upcomingBookings = [];
  List<Map<String, dynamic>> _pastBookings = [];
  List<Map<String, dynamic>> _cancelledBookings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchBookings() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch court bookings from 'bookings' collection
      final courtBookingsSnapshot = await _firestore
          .collection('bookings')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      // Fetch coach appointments from 'coach_appointments' collection
      final coachAppointmentsSnapshot = await _firestore
          .collection('coach_appointments')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> allBookings = [];

      // Process court bookings
      for (var doc in courtBookingsSnapshot.docs) {
        Map<String, dynamic> booking = doc.data() as Map<String, dynamic>;
        booking['id'] = doc.id;
        booking['bookingType'] = 'court';
        allBookings.add(booking);
      }

      // Process coach appointments
      for (var doc in coachAppointmentsSnapshot.docs) {
        Map<String, dynamic> appointment = doc.data() as Map<String, dynamic>;
        appointment['id'] = doc.id;
        appointment['bookingType'] = 'coach';
        allBookings.add(appointment);
      }

      // Sort all bookings by creation date
      allBookings.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      List<Map<String, dynamic>> upcoming = [];
      List<Map<String, dynamic>> past = [];
      List<Map<String, dynamic>> cancelled = [];

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (var booking in allBookings) {
        DateTime? bookingDate;
        if (booking['date'] != null) {
          try {
            final dateParts = booking['date'].split('-');
            bookingDate = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
            );
          } catch (e) {
            print('Error parsing date: ${booking['date']}');
            continue;
          }
        }

        if (booking['status'] == 'cancelled') {
          cancelled.add(booking);
        } else if (bookingDate != null) {
          if (bookingDate.isAfter(today) || bookingDate.isAtSameMomentAs(today)) {
            upcoming.add(booking);
          } else {
            past.add(booking);
          }
        }
      }

      setState(() {
        _upcomingBookings = upcoming;
        _pastBookings = past;
        _cancelledBookings = cancelled;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching bookings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Add this method after _fetchBookings() method
  bool _canRequestRefund(Map<String, dynamic> booking) {
    if (booking['bookingType'] != 'court') return false;

    try {
      final dateParts = booking['date'].split('-');
      final timeParts = booking['timeSlot'].split(':');

      final bookingDateTime = DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );

      final now = DateTime.now();
      final hoursUntilBooking = bookingDateTime.difference(now).inHours;

      return hoursUntilBooking >= 24;
    } catch (e) {
      print('Error calculating refund eligibility: $e');
      return false;
    }
  }

// Add this method right after _canRequestRefund()
  Future<void> _requestCancelAndRefund(Map<String, dynamic> booking) async {
    // Check if eligible for refund
    if (!_canRequestRefund(booking)) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 28),
                SizedBox(width: 12),
                Text('Refund Not Available'),
              ],
            ),
            content: Text(
              'Sorry, refunds are only available for bookings that are at least 24 hours away. Your booking is within 24 hours.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK', style: TextStyle(fontSize: 16)),
              ),
            ],
          );
        },
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Request Cancellation & Refund?')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to cancel this booking and request a refund?',
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                        SizedBox(width: 8),
                        Text(
                          'Refund Information',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Amount: RM ${booking['totalPrice']}\n'
                          '• Processing time: 5-7 working days\n'
                          '• Refund will be sent to your PayPal account',
                      style: TextStyle(fontSize: 13, color: Colors.blue.shade800, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Keep Booking', style: TextStyle(fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Cancel & Refund', style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // Process the cancellation and refund request
    try {
      final collection = booking['bookingType'] == 'coach' ? 'coach_appointments' : 'bookings';

      await _firestore.collection(collection).doc(booking['id']).update({
        'status': 'refund_requested',
        'refundRequestedAt': FieldValue.serverTimestamp(),
        'refundRequestedBy': _auth.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Create notification for admin
      await _firestore.collection('notifications').add({
        'userId': 'admin',
        'type': 'payment',
        'title': 'Refund Request',
        'message': '${booking['userName']} has requested a refund for booking at ${booking['venueName']} on ${booking['date']}. Amount: RM ${booking['totalPrice']}',
        'data': {
          'bookingId': booking['id'],
          'amount': booking['totalPrice'],
          'action': 'process_refund',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'priority': 'high',
      });

      if (mounted) {
        // Show success dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check, color: Colors.white, size: 30),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Refund Request Submitted',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Your refund request has been submitted successfully. The admin will review and process your refund.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Refund of RM ${booking['totalPrice']} will be processed within 5-7 working days after approval.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _fetchBookings();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF8A50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'OK',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting refund request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Add this method to _MyBookingsPageState
  Future<bool> _canReviewVenue(String bookingId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return await ReviewService.canReviewVenueBooking(bookingId, user.uid);
  }

  Future<bool> _canReview(String appointmentId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    return await ReviewService.canReviewAppointment(appointmentId, user.uid);
  }

  String _getBookingPrice(Map<String, dynamic> booking) {
    final bookingType = booking['bookingType'] ?? 'court';

    if (bookingType == 'coach') {
      // For coach appointments, try different price fields
      final price = booking['price'] ?? booking['packagePrice'] ?? booking['pricePerHour'] ?? 0;
      return price.toString();
    } else {
      // For court bookings, use totalPrice
      final price = booking['totalPrice'] ?? 0;
      return price.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
        ),
      )
          : Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBookingsList(_upcomingBookings, 'upcoming'),
                _buildBookingsList(_pastBookings, 'past'),
                _buildBookingsList(_cancelledBookings, 'cancelled'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'My Bookings',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF2D3748)),
          onPressed: _fetchBookings,
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFFFF8A50),
        unselectedLabelColor: Colors.grey[600],
        indicatorColor: const Color(0xFFFF8A50),
        indicatorWeight: 3,
        tabs: [
          Tab(
            text: 'Upcoming (${_upcomingBookings.length})',
          ),
          Tab(
            text: 'Past (${_pastBookings.length})',
          ),
          Tab(
            text: 'Cancelled (${_cancelledBookings.length})',
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsList(List<Map<String, dynamic>> bookings, String type) {
    if (bookings.isEmpty) {
      return _buildEmptyState(type);
    }

    return RefreshIndicator(
      onRefresh: _fetchBookings,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: bookings.length,
        itemBuilder: (context, index) {
          return _buildBookingCard(bookings[index], type);
        },
      ),
    );
  }

  Widget _buildEmptyState(String type) {
    String title, subtitle;
    IconData icon;

    switch (type) {
      case 'upcoming':
        title = 'No Upcoming Bookings';
        subtitle = 'Book a court or coach to get started';
        icon = Icons.event_available;
        break;
      case 'past':
        title = 'No Past Bookings';
        subtitle = 'Your completed bookings will appear here';
        icon = Icons.history;
        break;
      case 'cancelled':
        title = 'No Cancelled Bookings';
        subtitle = 'Cancelled bookings will appear here';
        icon = Icons.cancel_outlined;
        break;
      default:
        title = 'No Bookings';
        subtitle = 'Start booking to see your history';
        icon = Icons.bookmark_border;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking, String type) {
    final bookingType = booking['bookingType'] ?? 'court';
    final isCoachBooking = bookingType == 'coach';
    final isUpcoming = type == 'upcoming';
    final isPast = type == 'past';
    final isCancelled = type == 'cancelled';
    final isCompleted = booking['status'] == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isCancelled
            ? Border.all(color: Colors.red.withOpacity(0.3), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with status
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCoachBooking
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : const Color(0xFFFF8A50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isCoachBooking ? Icons.school : Icons.sports_tennis,
                    color: isCoachBooking ? const Color(0xFF4CAF50) : const Color(0xFFFF8A50),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCoachBooking
                            ? (booking['coachName'] ?? 'Coach Session')
                            : (booking['venueName'] ?? 'Venue Booking'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      Text(
                        isCoachBooking
                            ? 'Coaching Session'
                            : 'Court ${booking['courtNumber'] ?? 'N/A'} - ${booking['courtType'] ?? 'Court'}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(booking['status'] ?? 'confirmed', isCancelled),
              ],
            ),

            const SizedBox(height: 16),

            // Booking details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildDetailRow(Icons.calendar_today, 'Date', _formatBookingDate(booking['date'])),
                  _buildDetailRow(Icons.access_time, 'Time', '${booking['timeSlot'] ?? 'N/A'} - ${booking['endTime'] ?? 'N/A'}'),
                  if (!isCoachBooking)
                    _buildDetailRow(Icons.location_on, 'Venue', booking['venueLocation'] ?? 'Location not specified'),
                  _buildDetailRow(Icons.attach_money, 'Total', 'RM ${_getBookingPrice(booking)}'),
                  if (booking['paymentStatus'] != null)
                    _buildDetailRow(Icons.payment, 'Payment', _capitalizeFirst(booking['paymentStatus'])),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                // Show "Pay Now" button if payment is pending
                if (isUpcoming &&
                    !isCancelled &&
                    bookingType == 'coach' &&
                    booking['status'] == 'accepted' &&
                    booking['paymentStatus'] == 'pending')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PaymentPage(appointment: booking),
                          ),
                        );
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Pay Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                // Show "Request Reschedule" button for confirmed bookings
                if (isUpcoming &&
                    !isCancelled &&
                    bookingType == 'coach' &&
                    booking['status'] == 'confirmed' &&
                    (booking['canReschedule'] ?? true))
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RescheduleRequestPage(appointment: booking),
                          ),
                        );
                      },
                      icon: const Icon(Icons.schedule, size: 18),
                      label: const Text('Reschedule'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                // Show "Cancel & Refund" button for court bookings with completed payment
                if (isUpcoming && !isCancelled && bookingType == 'court' &&
                    (booking['paymentStatus'] == 'completed' ||
                        booking['paymentStatus'] == 'paid' ||
                        booking['paymentStatus'] == 'held_by_admin'))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _requestCancelAndRefund(booking),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel & Refund'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _canRequestRefund(booking) ? Colors.red : Colors.grey,
                        side: BorderSide(
                          color: _canRequestRefund(booking) ? Colors.red : Colors.grey,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),

                if (isUpcoming && !isCancelled)
                  const SizedBox(width: 12),

                // View Details button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showBookingDetails(booking),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isUpcoming ? 'View Details' : 'View Receipt',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),

// Show 24-hour notice if refund is not available (OUTSIDE THE ROW)
            if (isUpcoming && !isCancelled && bookingType == 'court' &&
                !_canRequestRefund(booking) &&
                (booking['paymentStatus'] == 'completed' ||
                    booking['paymentStatus'] == 'paid' ||
                    booking['paymentStatus'] == 'held_by_admin'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Refunds are only available 24+ hours before booking',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

// Show refund status badge if refund was requested (OUTSIDE THE ROW)
            if (booking['status'] == 'refund_requested')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pending_actions, size: 18, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Refund Request Pending Admin Review',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // In _buildBookingCard method, after the "View Details" button
            // Write Venue Review Button - UPDATED VERSION
            if (type == 'past' && !isCancelled && bookingType == 'court')
              FutureBuilder<bool>(
                future: _canReviewVenue(booking['id']),
                builder: (context, snapshot) {
                  // Show loading while checking
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }

                  // Show write review button if eligible
                  if (snapshot.data == true) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WriteVenueReviewPage(
                                  bookingId: booking['id'],
                                  venueId: booking['venueId'],
                                  venueName: booking['venueName'] ?? 'Venue',
                                ),
                              ),
                            );

                            if (result == true && mounted) {
                              setState(() {}); // Refresh to hide button
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Thank you for your review!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.star_outline, size: 18),
                          label: const Text('Write Venue Review'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8A50),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    );
                  }

                  // Show "Already Reviewed" badge if not eligible (already reviewed)
                  if (snapshot.data == false) {
                    // Double check if it's because they already reviewed
                    return FutureBuilder<bool>(
                      future: ReviewService.hasReviewedVenueBooking(booking['id'], _auth.currentUser!.uid),
                      builder: (context, hasReviewedSnapshot) {
                        if (hasReviewedSnapshot.data == true) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Review Submitted',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),

            // Write Review Button (only for completed coach appointments)
            if (isCoachBooking && isCompleted && isPast)
              FutureBuilder<bool>(
                future: _canReview(booking['id']),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }

                  if (snapshot.data == true) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WriteReviewPage(
                                  appointmentId: booking['id'],
                                  coachId: booking['coachId'],
                                  coachName: booking['coachName'] ?? 'Coach',
                                ),
                              ),
                            );

                            if (result == true && mounted) {
                              setState(() {}); // Refresh to hide button
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Thank you for your review!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.star_outline, size: 18),
                          label: const Text('Write Review'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber[600],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  // Show "Review Submitted" if already reviewed
                  if (snapshot.data == false && isCompleted) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Review Submitted',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, bool isCancelled) {
    Color backgroundColor;
    Color textColor;
    String displayText;
    IconData icon;

    if (isCancelled) {
      backgroundColor = Colors.red.withOpacity(0.1);
      textColor = Colors.red;
      displayText = 'Cancelled';
      icon = Icons.cancel;
    } else {
      switch (status.toLowerCase()) {
        case 'pending_approval':
          backgroundColor = Colors.orange.withOpacity(0.1);
          textColor = Colors.orange;
          displayText = 'Awaiting Response';
          icon = Icons.schedule;
          break;
        case 'accepted':
        case 'confirmed':
          backgroundColor = const Color(0xFF4CAF50).withOpacity(0.1);
          textColor = const Color(0xFF4CAF50);
          displayText = 'Confirmed';
          icon = Icons.check_circle;
          break;
        case 'rejected':
          backgroundColor = Colors.red.withOpacity(0.1);
          textColor = Colors.red;
          displayText = 'Declined';
          icon = Icons.cancel;
          break;
        case 'pending':
          backgroundColor = Colors.blue.withOpacity(0.1);
          textColor = Colors.blue;
          displayText = 'Pending';
          icon = Icons.hourglass_empty;
          break;
        case 'completed':
          backgroundColor = Colors.blue.withOpacity(0.1);
          textColor = Colors.blue;
          displayText = 'Completed';
          icon = Icons.check_circle;
          break;
        default:
          backgroundColor = Colors.grey.withOpacity(0.1);
          textColor = Colors.grey[600]!;
          displayText = _capitalizeFirst(status);
          icon = Icons.info;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 14),
          const SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2D3748),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBookingDate(String? dateString) {
    if (dateString == null) return 'Date not available';

    try {
      final parts = dateString.split('-');
      final date = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];

      const weekdays = [
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
      ];

      return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  void _showCancelDialog(Map<String, dynamic> booking) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Cancel Booking'),
          content: const Text(
            'Are you sure you want to cancel this booking? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Keep Booking'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _cancelBooking(booking);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text(
                'Cancel Booking',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    try {
      // Determine which collection to update based on booking type
      final collection = booking['bookingType'] == 'coach'
          ? 'coach_appointments'
          : 'bookings';

      await _firestore
          .collection(collection)
          .doc(booking['id'])
          .update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send notification to coach if it's a coach appointment
      if (booking['bookingType'] == 'coach' && booking['coachId'] != null) {
        try {
          await NotificationService.createNotification(
            userId: booking['coachId'],
            type: 'coach',
            title: 'Session Cancelled',
            message: '${booking['studentName'] ?? 'A student'} has cancelled their coaching session scheduled for ${_formatBookingDate(booking['date'])} at ${booking['timeSlot']}.',
            data: {
              'appointmentId': booking['id'],
              'action': 'view_requests',
              'studentName': booking['studentName'],
              'date': booking['date'],
              'timeSlot': booking['timeSlot'],
            },
            priority: 'high',
          );
        } catch (notificationError) {
          print('Error sending notification to coach: $notificationError');
          // Don't fail the cancellation if notification fails
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _fetchBookings(); // Refresh the list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openChatWithCoach(Map<String, dynamic> booking) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Get current user data
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final studentName = userData?['name'] ?? user.displayName ?? 'Student';

      // Create or get existing chat
      final chatId = await MessagingService.createOrGetChat(
        coachId: booking['coachId'],
        coachName: booking['coachName'] ?? 'Coach',
        studentId: user.uid,
        studentName: studentName,
        appointmentId: booking['id'],
      );

      // Navigate to chat page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              chatId: chatId,
              otherUserName: booking['coachName'] ?? 'Coach',
              otherUserId: booking['coachId'],
              otherUserRole: 'coach',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showBookingDetails(Map<String, dynamic> booking) {
    final bookingType = booking['bookingType'] ?? 'court';
    final isCoachBooking = bookingType == 'coach';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Booking Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailItem('Booking ID', booking['id'] ?? 'N/A'),

                // Show venue/location/court ONLY for COURT bookings
                if (!isCoachBooking) ...[
                  _buildDetailItem('Venue', booking['venueName'] ?? 'N/A'),
                  _buildDetailItem('Location', booking['venueLocation'] ?? 'N/A'),
                  _buildDetailItem('Court', 'Court ${booking['courtNumber']} - ${booking['courtType']}'),
                ],

                _buildDetailItem('Date', _formatBookingDate(booking['date'])),
                _buildDetailItem('Time', '${booking['timeSlot']} - ${booking['endTime']}'),
                _buildDetailItem('Duration', '${booking['duration'] ?? 1} hour(s)'),
                _buildDetailItem('Total Price', 'RM ${_getBookingPrice(booking)}'),
                _buildDetailItem('Payment Status', _capitalizeFirst(booking['paymentStatus'] ?? 'pending')),
                _buildDetailItem('Status', _capitalizeFirst(booking['status'] ?? 'confirmed')),

                // Show coach name for coach bookings
                if (isCoachBooking && booking['coachName'] != null)
                  _buildDetailItem('Coach', booking['coachName']),

                if (booking['notes'] != null && booking['notes'].isNotEmpty)
                  _buildDetailItem('Notes', booking['notes']),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(color: Colors.white),
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

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2D3748),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}