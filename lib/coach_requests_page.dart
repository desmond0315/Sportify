import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../services/messaging_service.dart';
import 'chat_page.dart';

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
  List<Map<String, dynamic>> _processedRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      // Modified query - remove orderBy to avoid compound index requirement
      final querySnapshot = await _firestore
          .collection('coach_appointments')
          .where('coachId', isEqualTo: user.uid)
          .get(); // Removed .orderBy('requestedAt', descending: true)

      List<Map<String, dynamic>> pending = [];
      List<Map<String, dynamic>> processed = [];

      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id;

        if (data['status'] == 'pending_approval') {
          pending.add(data);
        } else if (['accepted', 'rejected'].contains(data['status'])) {
          processed.add(data);
        }
      }

      // Sort in memory instead of using Firestore orderBy
      pending.sort((a, b) {
        final aTime = a['requestedAt'] as Timestamp?;
        final bTime = b['requestedAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // Descending order (most recent first)
      });

      processed.sort((a, b) {
        final aTime = a['requestedAt'] as Timestamp?;
        final bTime = b['requestedAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // Descending order (most recent first)
      });

      setState(() {
        _pendingRequests = pending;
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

      // Get current coach data
      final coachDoc = await _firestore.collection('coaches').doc(user.uid).get();
      final coachData = coachDoc.data();
      final coachName = coachData?['name'] ?? 'Coach';

      // Create or get existing chat
      final chatId = await MessagingService.createOrGetChat(
        coachId: user.uid,
        coachName: coachName,
        studentId: request['userId'],
        studentName: request['studentName'] ?? 'Student',
        appointmentId: request['id'],
      );

      // Navigate to chat page
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

      // Update the appointment in Firestore
      await _firestore
          .collection('coach_appointments')
          .doc(request['id'])
          .update({
        'status': newStatus,
        'respondedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send notification to the student
      await _sendResponseNotification(request, accept);

      // Send message to chat about the decision
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
        // Don't fail the operation if chat message fails
      }

      // Refresh the requests
      await _loadRequests();

      _showSuccessSnackBar(
          accept ? 'Request accepted successfully!' : 'Request rejected.'
      );
    } catch (e) {
      _showErrorSnackBar('Error processing request: $e');
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
                _buildRequestsList(_pendingRequests, isPending: true),
                _buildRequestsList(_processedRequests, isPending: false),
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
            icon: const Icon(Icons.schedule, size: 20),
          ),
          Tab(
            text: 'Processed (${_processedRequests.length})',
            icon: const Icon(Icons.check_circle_outline, size: 20),
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

  Widget _buildRequestsList(List<Map<String, dynamic>> requests, {required bool isPending}) {
    if (requests.isEmpty) {
      return _buildEmptyState(isPending);
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: requests.length,
        itemBuilder: (context, index) => _buildRequestCard(requests[index], isPending),
      ),
    );
  }

  Widget _buildEmptyState(bool isPending) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPending ? Icons.inbox_outlined : Icons.history,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isPending ? 'No pending requests' : 'No processed requests',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPending
                ? 'New session requests will appear here'
                : 'Accepted and rejected requests will appear here',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request, bool isPending) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            // Student info and status
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
                // Chat button
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

            // Session details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildDetailRow(Icons.calendar_today, 'Date', _formatDate(request['date'])),
                  _buildDetailRow(Icons.access_time, 'Time', '${request['timeSlot']} - ${request['endTime']}'),
                  _buildDetailRow(Icons.schedule, 'Duration', '${request['duration']} hour(s)'),
                  _buildDetailRow(Icons.attach_money, 'Payment', 'RM ${request['price']}'),
                  if (request['notes'] != null && request['notes'].isNotEmpty)
                    _buildDetailRow(Icons.note, 'Notes', request['notes']),
                ],
              ),
            ),

            if (isPending) ...[
              const SizedBox(height: 16),
              // Action buttons for pending requests
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
            ] else ...[
              const SizedBox(height: 16),
              // Chat button for processed requests
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openChatWithStudent(request),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Open Chat'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4CAF50),
                    side: const BorderSide(color: Color(0xFF4CAF50)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case 'accepted':
        color = const Color(0xFF4CAF50);
        text = 'Accepted';
        icon = Icons.check_circle;
        break;
      case 'rejected':
        color = Colors.red;
        text = 'Declined';
        icon = Icons.cancel;
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