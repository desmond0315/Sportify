import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../services/messaging_service.dart';
import 'chat_page.dart';
import 'upload_proof_page.dart';

class CoachRequestsPage extends StatefulWidget {
  const CoachRequestsPage({Key? key}) : super(key: key);

  @override
  State<CoachRequestsPage> createState() => _CoachRequestsPageState();
}

class _CoachRequestsPageState extends State<CoachRequestsPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late TabController _tabController;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _acceptedRequests = [];
  List<Map<String, dynamic>> _processedRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      final querySnapshot = await _firestore
          .collection('coach_appointments')
          .where('coachId', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> pending = [];
      List<Map<String, dynamic>> accepted = [];
      List<Map<String, dynamic>> processed = [];

      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id;

        // Handle reschedule_requested status
        if (data['status'] == 'pending_approval') {
          pending.add(data);
        } else if (data['status'] == 'reschedule_requested') {
          // Put reschedule requests in accepted tab so coach can see and approve
          accepted.add(data);
        } else if (data['status'] == 'accepted' || data['status'] == 'confirmed') {
          accepted.add(data);
        } else if (['rejected', 'completed', 'cancelled', 'awaiting_verification', 'verified'].contains(data['status'])) {
          processed.add(data);
        }
      }

      // Sort in memory
      pending.sort((a, b) {
        final aTime = a['requestedAt'] as Timestamp?;
        final bTime = b['requestedAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      // Sort accepted - put reschedule requests first
      accepted.sort((a, b) {
        // Reschedule requests go first
        if (a['status'] == 'reschedule_requested' && b['status'] != 'reschedule_requested') return -1;
        if (a['status'] != 'reschedule_requested' && b['status'] == 'reschedule_requested') return 1;

        // Then sort by scheduled time
        final aTime = a['scheduledAt'] as Timestamp?;
        final bTime = b['scheduledAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });

      processed.sort((a, b) {
        final aTime = a['requestedAt'] as Timestamp?;
        final bTime = b['requestedAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      setState(() {
        _pendingRequests = pending;
        _acceptedRequests = accepted;
        _processedRequests = processed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error loading requests: $e');
    }
  }

  Future<void> _openChatWithStudent(Map<String, dynamic> request) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final coachDoc = await _firestore.collection('coaches').doc(user.uid).get();
      final coachData = coachDoc.data();
      final coachName = coachData?['name'] ?? 'Coach';

      final chatId = await MessagingService.createOrGetChat(
        coachId: user.uid,
        coachName: coachName,
        studentId: request['userId'],
        studentName: request['studentName'] ?? 'Student',
        appointmentId: request['id'],
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              chatId: chatId,
              otherUserName: request['studentName'] ?? 'Student',
              otherUserId: request['userId'],
              otherUserRole: 'student',
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

  Future<void> _handleRequest(Map<String, dynamic> request, bool accept) async {
    try {
      final newStatus = accept ? 'accepted' : 'rejected';

      // Add paymentStatus field
      Map<String, dynamic> updateData = {
        'status': newStatus,
        'respondedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // If accepting, set payment status to pending
      if (accept) {
        updateData['paymentStatus'] = 'pending';
      }

      await _firestore
          .collection('coach_appointments')
          .doc(request['id'])
          .update(updateData);

      await _sendResponseNotification(request, accept);

      try {
        final user = _auth.currentUser;
        if (user != null) {
          final coachDoc = await _firestore.collection('coaches').doc(user.uid).get();
          final coachData = coachDoc.data();
          final coachName = coachData?['name'] ?? 'Coach';

          final chatId = MessagingService.generateChatId(user.uid, request['userId']);

          await MessagingService.sendAppointmentMessage(
            chatId: chatId,
            senderId: user.uid,
            senderName: coachName,
            senderRole: 'coach',
            receiverId: request['userId'],
            appointmentStatus: newStatus,
            appointmentData: request,
          );
        }
      } catch (chatError) {
        print('Error sending chat message: $chatError');
      }

      await _loadRequests();

      _showSuccessSnackBar(
          accept ? 'Request accepted successfully!' : 'Request rejected.'
      );
    } catch (e) {
      _showErrorSnackBar('Error processing request: $e');
    }
  }

  Future<void> _markAsCompleted(Map<String, dynamic> request) async {
    try {
      await _firestore
          .collection('coach_appointments')
          .doc(request['id'])
          .update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send notification to student to write review
      await NotificationService.notifyStudentToReview(
        studentId: request['userId'],
        studentName: request['studentName'] ?? 'Student',
        coachName: request['coachName'] ?? 'Coach',
        appointmentId: request['id'],
      );

      await _loadRequests();

      _showSuccessSnackBar('Session marked as completed! Student will be notified to leave a review.');
    } catch (e) {
      _showErrorSnackBar('Error marking as completed: $e');
    }
  }

  Future<void> _sendResponseNotification(Map<String, dynamic> request, bool accepted) async {
    final title = accepted ? 'Session Request Accepted!' : 'Session Request Declined';
    final message = accepted
        ? 'Great news! Your coaching session request has been accepted. Check your bookings for details.'
        : 'Your coaching session request has been declined. Feel free to book with another coach or try a different time slot.';

    await NotificationService.createNotification(
      userId: request['userId'],
      type: 'coach',
      title: title,
      message: message,
      data: {
        'appointmentId': request['id'],
        'coachId': request['coachId'],
        'action': 'view_booking',
        'status': accepted ? 'accepted' : 'rejected',
      },
      priority: 'high',
    );
  }

  Future<void> _handleRescheduleRequest(Map<String, dynamic> request, bool approve) async {
    try {
      final rescheduleHistory = List<Map<String, dynamic>>.from(
          request['rescheduleHistory'] ?? []
      );

      if (rescheduleHistory.isEmpty) {
        throw 'No reschedule request found';
      }

      // Get the latest reschedule request
      final latestReschedule = rescheduleHistory.last;

      if (approve) {
        // Update the reschedule entry to approved
        latestReschedule['status'] = 'approved';
        latestReschedule['approvedBy'] = 'coach';
        latestReschedule['approvedAt'] = Timestamp.now();

        // Update appointment with new date/time
        await _firestore
            .collection('coach_appointments')
            .doc(request['id'])
            .update({
          'date': latestReschedule['newDate'],
          'timeSlot': latestReschedule['newTimeSlot'],
          'endTime': latestReschedule['newEndTime'],
          'status': 'confirmed',
          'rescheduleHistory': rescheduleHistory,
          'rescheduleCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
          'scheduledAt': Timestamp.fromDate(
            DateTime(
              int.parse(latestReschedule['newDate'].split('-')[0]),
              int.parse(latestReschedule['newDate'].split('-')[1]),
              int.parse(latestReschedule['newDate'].split('-')[2]),
              int.parse(latestReschedule['newTimeSlot'].split(':')[0]),
              0,
            ),
          ),
        });

        // Send notification to student
        await NotificationService.createNotification(
          userId: request['userId'],
          type: 'coach',
          title: 'Reschedule Approved!',
          message: '${request['coachName']} has approved your reschedule request. '
              'Your session is now on ${latestReschedule['newDate']} at ${latestReschedule['newTimeSlot']}.',
          data: {
            'appointmentId': request['id'],
            'action': 'view_booking',
          },
          priority: 'high',
        );

        // Send chat message
        try {
          final user = _auth.currentUser;
          if (user != null) {
            final coachDoc = await _firestore.collection('coaches').doc(user.uid).get();
            final coachData = coachDoc.data();
            final coachName = coachData?['name'] ?? 'Coach';

            final chatId = MessagingService.generateChatId(user.uid, request['userId']);

            await MessagingService.sendMessage(
              chatId: chatId,
              senderId: user.uid,
              senderName: coachName,
              senderRole: 'coach',
              receiverId: request['userId'],
              message: 'Great! I\'ve approved your reschedule request. See you on ${latestReschedule['newDate']} at ${latestReschedule['newTimeSlot']}! 👍',
              messageType: 'text',
            );
          }
        } catch (e) {
          print('Error sending chat message: $e');
        }

        _showSuccessSnackBar('Reschedule request approved!');
      } else {
        // Update the reschedule entry to rejected
        latestReschedule['status'] = 'rejected';
        latestReschedule['approvedBy'] = 'coach';
        latestReschedule['approvedAt'] = Timestamp.now();

        // Keep original date/time, just update status
        await _firestore
            .collection('coach_appointments')
            .doc(request['id'])
            .update({
          'status': 'confirmed', // Back to confirmed with original time
          'rescheduleHistory': rescheduleHistory,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Send notification to student
        await NotificationService.createNotification(
          userId: request['userId'],
          type: 'coach',
          title: 'Reschedule Request Declined',
          message: '${request['coachName']} has declined your reschedule request. Your session remains on ${request['date']} at ${request['timeSlot']}. Please contact your coach if you need to discuss alternatives.',
          data: {
            'appointmentId': request['id'],
            'action': 'view_booking',
          },
          priority: 'high',
        );

        // Send chat message
        try {
          final user = _auth.currentUser;
          if (user != null) {
            final coachDoc = await _firestore.collection('coaches').doc(user.uid).get();
            final coachData = coachDoc.data();
            final coachName = coachData?['name'] ?? 'Coach';

            final chatId = MessagingService.generateChatId(user.uid, request['userId']);

            await MessagingService.sendMessage(
              chatId: chatId,
              senderId: user.uid,
              senderName: coachName,
              senderRole: 'coach',
              receiverId: request['userId'],
              message: 'I\'m unable to reschedule to the requested time. Your session is still scheduled for ${request['date']} at ${request['timeSlot']}. Let\'s chat if you need to find another time that works!',
              messageType: 'text',
            );
          }
        } catch (e) {
          print('Error sending chat message: $e');
        }

        _showSuccessSnackBar('Reschedule request declined. Original time maintained.');
      }

      await _loadRequests();
    } catch (e) {
      print('Error handling reschedule request: $e');
      _showErrorSnackBar('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoadingState()
          : Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRequestsList(_pendingRequests, type: 'pending'),
                _buildRequestsList(_acceptedRequests, type: 'accepted'),
                _buildRequestsList(_processedRequests, type: 'processed'),
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
        'Session Requests',
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
          onPressed: _loadRequests,
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
            text: 'Pending (${_pendingRequests.length})',
            icon: const Icon(Icons.schedule, size: 18),
          ),
          Tab(
            text: 'Accepted (${_acceptedRequests.length})',
            icon: const Icon(Icons.check_circle_outline, size: 18),
          ),
          Tab(
            text: 'History (${_processedRequests.length})',
            icon: const Icon(Icons.history, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
      ),
    );
  }

  Widget _buildRequestsList(List<Map<String, dynamic>> requests, {required String type}) {
    if (requests.isEmpty) {
      return _buildEmptyState(type);
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: requests.length,
        itemBuilder: (context, index) => _buildRequestCard(requests[index], type),
      ),
    );
  }

  Widget _buildEmptyState(String type) {
    String title, subtitle;
    IconData icon;

    switch (type) {
      case 'pending':
        title = 'No pending requests';
        subtitle = 'New session requests will appear here';
        icon = Icons.inbox_outlined;
        break;
      case 'accepted':
        title = 'No upcoming sessions';
        subtitle = 'Accepted sessions will appear here';
        icon = Icons.event_available;
        break;
      case 'processed':
        title = 'No history';
        subtitle = 'Completed and declined sessions will appear here';
        icon = Icons.history;
        break;
      default:
        title = 'No requests';
        subtitle = 'Requests will appear here';
        icon = Icons.inbox_outlined;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
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
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request, String type) {
    final isPending = type == 'pending';
    final isAccepted = type == 'accepted';
    final isProcessed = type == 'processed';
    final isRescheduleRequested = request['status'] == 'reschedule_requested';

    return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isRescheduleRequested
              ? Border.all(color: Colors.orange, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
          children: [
          Container(
          width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Center(
              child: Text(
                (request['studentName'] ?? 'S')[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF8A50),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['studentName'] ?? 'Student',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                Text(
                  request['userEmail'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: () => _openChatWithStudent(request),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Color(0xFF4CAF50),
                  size: 20,
                ),
              ),
              tooltip: 'Chat with student',
            ),
          ),
          _buildStatusBadge(request['status']),
          ],
        ),

        const SizedBox(height: 16),

        // Show reschedule alert if there's a pending reschedule request
        if (isRescheduleRequested) ...[
    Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: Colors.orange.withOpacity(0.1),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.orange.withOpacity(0.3)),
    ),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Row(
    children: [
    Icon(Icons.schedule_send, color: Colors.orange[700], size: 20),
    const SizedBox(width: 8),
    Text(
    'Reschedule Request',
    style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.orange[700],
    ),
    ),
    ],
    ),
    const SizedBox(height: 8),
    _buildRescheduleDetails(request),
    ],
    ),
    ),
    const SizedBox(height: 16),
    ],

    // Session details
    Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: Colors.grey[50],
    borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
    children: [
    if (isRescheduleRequested) ...[
    // Show current booking details
    Text(
    'Current Booking:',
    style: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.grey[600],
    ),
    ),
    const SizedBox(height: 8),
    ],
    _buildDetailRow(Icons.calendar_today, 'Date', _formatDate(request['date'])),
    _buildDetailRow(Icons.access_time, 'Time', '${request['timeSlot']} - ${request['endTime']}'),
    _buildDetailRow(Icons.schedule, 'Duration', '${request['duration']} hour(s)'),
    _buildDetailRow(Icons.attach_money, 'Payment', 'RM ${request['price']}'),
    if (request['notes'] != null && request['notes'].isNotEmpty)
    _buildDetailRow(Icons.note, 'Notes', request['notes']),
    ],
    ),
    ),

    const SizedBox(height: 16),

    // Action buttons
    if (isPending) ...[
    Row(
    children: [
    Expanded(
    child: OutlinedButton.icon(
    onPressed: () => _showRejectConfirmation(request),
    icon: const Icon(Icons.close, size: 18),
    label: const Text('Decline'),
    style: OutlinedButton.styleFrom(
    foregroundColor: Colors.red,
    side: const BorderSide(color: Colors.red),
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    ),
    ),
    ),
    ),
    const SizedBox(width: 12),
    Expanded(
    child: ElevatedButton.icon(
    onPressed: () => _handleRequest(request, true),
    icon: const Icon(Icons.check, size: 18),
    label: const Text('Accept'),
    style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF4CAF50),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    ),
    ),
    ),
    ),
    ],
    ),
    ] else if (isRescheduleRequested) ...[
    // Reschedule approval buttons
    Row(
    children: [
    Expanded(
    child: OutlinedButton.icon(
    onPressed: () => _showDeclineRescheduleConfirmation(request),
    icon: const Icon(Icons.close, size: 18),
    label: const Text('Decline'),
    style: OutlinedButton.styleFrom(
    foregroundColor: Colors.red,
    side: const BorderSide(color: Colors.red),
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    ),
    ),
    ),
    ),
    const SizedBox(width: 12),
    Expanded(
    child: ElevatedButton.icon(
    onPressed: () => _showApproveRescheduleConfirmation(request),
    icon: const Icon(Icons.check, size: 18),
    label: const Text('Approve'),
    style: ElevatedButton.styleFrom(
    backgroundColor: Colors.orange,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    ),
    ),
    ),
    ),
    ],
    ),
    ] else if (isAccepted && !isRescheduleRequested) ...[
    // Show upload button for accepted/confirmed sessions that haven't been verified yet
    // OR if they were rejected and need to re-upload
    if (request['status'] == 'confirmed' ||
    request['status'] == 'accepted' ||
    request['verificationStatus'] == 'rejected') ...[
    Column(
    children: [
    // Show rejection notice if proof was rejected
    if (request['verificationStatus'] == 'rejected') ...[
    Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
    color: Colors.red.withOpacity(0.1),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.red.withOpacity(0.3)),
    ),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Row(
    children: [
    Icon(Icons.warning, color: Colors.red[700], size: 20),
    const SizedBox(width: 8),
    Text(
    'Proof Rejected - Please Re-upload',
    style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.red[700],
    ),
    ),
    ],
    ),
    if (request['verificationNotes'] != null) ...[
    const SizedBox(height: 8),
    Text(
    'Reason: ${request['verificationNotes']}',
    style: TextStyle(
    fontSize: 13,
    color: Colors.red[900],
    ),
    ),
    ],
    ],
    ),
    ),
    ],
    SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
    onPressed: () {
    Navigator.push(
    context,
    MaterialPageRoute(
    builder: (context) => UploadProofPage(appointment: request),
    ),
    ).then((_) {
    _loadRequests();
    });
    },
    icon: Icon(
    request['verificationStatus'] == 'rejected'
    ? Icons.upload_file
        : Icons.cloud_upload,
    size: 18
    ),
    label: Text(
    request['verificationStatus'] == 'rejected'
    ? 'Re-upload Proof'
        : 'Upload Proof & Complete'
    ),
    style: ElevatedButton.styleFrom(
    backgroundColor: request['verificationStatus'] == 'rejected'
    ? Colors.orange
        : Colors.blue,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(8),
    ),
    ),
    ),
    ),
    ],
    ),
    ] else if (request['status'] == 'awaiting_verification') ...[
    // Show "Awaiting Verification" message
    Container(
    padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty, color: Colors.orange[700], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Awaiting Admin Verification',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your proof is being reviewed by admin',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[900],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    ] else if (request['status'] == 'verified') ...[
      // Show "Verified - Awaiting Payment" message
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verified - Payment Pending',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.green[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Admin will release payment soon',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[900],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
    ],
            ],
          ),
        ),
    );
  }

  // Helper method to show reschedule details
  Widget _buildRescheduleDetails(Map<String, dynamic> request) {
    final rescheduleHistory = List<Map<String, dynamic>>.from(
        request['rescheduleHistory'] ?? []
    );

    if (rescheduleHistory.isEmpty) return const SizedBox.shrink();

    final latestReschedule = rescheduleHistory.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.arrow_forward, size: 16, color: Colors.orange[700]),
            const SizedBox(width: 4),
            Text(
              'Requested new time:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orange[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${latestReschedule['newDate']} at ${latestReschedule['newTimeSlot']} - ${latestReschedule['newEndTime']}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.orange[900],
          ),
        ),
        if (latestReschedule['reason'] != null && latestReschedule['reason'].toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Reason: ${latestReschedule['reason']}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  // Confirmation dialogs
  void _showApproveRescheduleConfirmation(Map<String, dynamic> request) {
    final rescheduleHistory = List<Map<String, dynamic>>.from(
        request['rescheduleHistory'] ?? []
    );
    final latestReschedule = rescheduleHistory.isNotEmpty ? rescheduleHistory.last : null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve Reschedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Approve the reschedule request from ${request['studentName']}?'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_busy, size: 16, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Old: ${request['date']} at ${request['timeSlot']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[700],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.event_available, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Text(
                          'New: ${latestReschedule?['newDate']} at ${latestReschedule?['newTimeSlot']}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleRescheduleRequest(request, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Approve', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showDeclineRescheduleConfirmation(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Decline Reschedule'),
          content: Text(
              'Decline the reschedule request from ${request['studentName']}? '
                  'The session will remain at the original time: ${request['date']} at ${request['timeSlot']}.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleRescheduleRequest(request, false);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Decline', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case 'accepted':
      case 'confirmed':
        color = const Color(0xFF4CAF50);
        text = 'Accepted';
        icon = Icons.check_circle;
        break;
      case 'rejected':
        color = Colors.red;
        text = 'Declined';
        icon = Icons.cancel;
        break;
      case 'completed':
        color = Colors.blue;
        text = 'Completed';
        icon = Icons.check_circle;
        break;
      case 'cancelled':
        color = Colors.orange;
        text = 'Cancelled';
        icon = Icons.cancel;
        break;
      case 'awaiting_verification':
        color = Colors.orange;
        text = 'Awaiting Review';
        icon = Icons.hourglass_empty;
        break;
      case 'verified':
        color = Colors.green;
        text = 'Verified';
        icon = Icons.verified;
        break;
      default:
        color = Colors.orange;
        text = 'Pending';
        icon = Icons.schedule;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
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

  void _showRejectConfirmation(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Decline Request'),
          content: Text('Are you sure you want to decline the session request from ${request['studentName']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleRequest(request, false);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Decline', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showCompleteConfirmation(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Mark as Completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mark the session with ${request['studentName']} as completed?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The student will be notified to leave a review',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _markAsCompleted(request);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Complete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'No date';

    try {
      final parts = dateString.split('-');
      final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}