import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:convert';
import 'coach_profile_update_page.dart';
import 'coach_requests_page.dart';
import 'services/messaging_service.dart';
import 'services/notification_service.dart';
import 'chats_list_page.dart';
import 'notifications_page.dart';

class CoachDashboardPage extends StatefulWidget {
  final Map<String, dynamic> coachData;

  const CoachDashboardPage({Key? key, required this.coachData}) : super(key: key);

  @override
  State<CoachDashboardPage> createState() => _CoachDashboardPageState();
}

class _CoachDashboardPageState extends State<CoachDashboardPage> {
  int _selectedIndex = 0;
  StreamSubscription<DocumentSnapshot>? _coachSubscription;
  StreamSubscription<QuerySnapshot>? _appointmentsSubscription;
  StreamSubscription<QuerySnapshot>? _reviewsSubscription;
  StreamSubscription<QuerySnapshot>? _pendingRequestsSubscription;
  StreamSubscription<int>? _messageCountSubscription;
  StreamSubscription<int>? _notificationCountSubscription;

  Map<String, dynamic> _currentCoachData = {};
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _reviews = [];

  // Stats
  int _totalStudents = 0;
  int _monthlyAppointments = 0;
  double _averageRating = 0.0;
  double _monthlyRevenue = 0.0;
  int _pendingRequestsCount = 0;
  int _unreadMessageCount = 0;
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    _currentCoachData = widget.coachData;
    _listenToRealTimeData();
    _listenToMessageCount();
    _listenToNotificationCount();
  }

  @override
  void dispose() {
    _coachSubscription?.cancel();
    _appointmentsSubscription?.cancel();
    _reviewsSubscription?.cancel();
    _pendingRequestsSubscription?.cancel();
    _messageCountSubscription?.cancel();
    _notificationCountSubscription?.cancel();
    super.dispose();
  }

  void _listenToRealTimeData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Listen to coach data changes
      _coachSubscription = FirebaseFirestore.instance
          .collection('coaches')
          .doc(user.uid)
          .snapshots()
          .listen((docSnapshot) {
        if (docSnapshot.exists && mounted) {
          setState(() {
            _currentCoachData = docSnapshot.data() as Map<String, dynamic>;
          });
        }
      });

      // Listen to appointments
      _appointmentsSubscription = FirebaseFirestore.instance
          .collection('coach_appointments')
          .where('coachId', isEqualTo: user.uid)
          .limit(50)
          .snapshots()
          .listen((querySnapshot) {
        if (mounted) {
          setState(() {
            _appointments = querySnapshot.docs.map((doc) {
              Map<String, dynamic> data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();
            // Sort in memory instead of using Firestore orderBy
            _appointments.sort((a, b) {
              final aTime = a['scheduledAt'] as Timestamp?;
              final bTime = b['scheduledAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            _calculateStats();
          });
        }
      });

      // Listen to reviews
      _reviewsSubscription = FirebaseFirestore.instance
          .collection('coaches')
          .doc(user.uid)
          .collection('reviews')
          .limit(20)
          .snapshots()
          .listen((querySnapshot) {
        if (mounted) {
          setState(() {
            _reviews = querySnapshot.docs.map((doc) {
              Map<String, dynamic> data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();
            // Sort in memory
            _reviews.sort((a, b) {
              final aTime = a['createdAt'] as Timestamp?;
              final bTime = b['createdAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            _calculateStats();
          });
        }
      });

      // Listen to pending requests count
      _pendingRequestsSubscription = FirebaseFirestore.instance
          .collection('coach_appointments')
          .where('coachId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending_approval')
          .snapshots()
          .listen((querySnapshot) {
        if (mounted) {
          setState(() {
            _pendingRequestsCount = querySnapshot.docs.length;
          });
        }
      });
    }
  }

  void _listenToMessageCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _messageCountSubscription =
          MessagingService.getUnreadMessagesCount(user.uid, 'coach')
              .listen((count) {
            if (mounted) {
              setState(() {
                _unreadMessageCount = count;
              });
            }
          });
    }
  }

  void _listenToNotificationCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _notificationCountSubscription =
          NotificationService.getUnreadCount(user.uid)
              .listen((count) {
            if (mounted) {
              setState(() {
                _unreadNotificationCount = count;
              });
            }
          });
    }
  }

  void _calculateStats() {
    // Calculate unique students (only from accepted/confirmed appointments)
    Set<String> uniqueStudents = {};
    for (var appointment in _appointments) {
      if (appointment['userId'] != null &&
          ['accepted', 'confirmed', 'completed'].contains(
              appointment['status'])) {
        uniqueStudents.add(appointment['userId']);
      }
    }
    _totalStudents = uniqueStudents.length;

    // Calculate monthly appointments and revenue (only confirmed/completed)
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    _monthlyAppointments = _appointments.where((appointment) {
      if (appointment['scheduledAt'] != null &&
          ['accepted', 'confirmed', 'completed'].contains(
              appointment['status'])) {
        DateTime appointmentDate = (appointment['scheduledAt'] as Timestamp)
            .toDate();
        return appointmentDate.isAfter(startOfMonth);
      }
      return false;
    }).length;

    // Calculate monthly revenue
    _monthlyRevenue = _appointments.where((appointment) {
      if (appointment['scheduledAt'] != null &&
          appointment['status'] == 'completed') {
        DateTime appointmentDate = (appointment['scheduledAt'] as Timestamp)
            .toDate();
        return appointmentDate.isAfter(startOfMonth);
      }
      return false;
    }).fold(0.0, (sum, appointment) {
      return sum + (appointment['price']?.toDouble() ??
          _currentCoachData['pricePerHour']?.toDouble() ?? 0.0);
    });

    // Calculate average rating
    if (_reviews.isNotEmpty) {
      double totalRating = _reviews.fold(0.0, (sum, review) {
        return sum + (review['rating']?.toDouble() ?? 0.0);
      });
      _averageRating = totalRating / _reviews.length;
    } else {
      _averageRating = _currentCoachData['rating']?.toDouble() ?? 0.0;
    }
  }

  // Navigate to update profile page
  void _navigateToUpdateProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CoachProfileUpdatePage(coachData: _currentCoachData),
      ),
    );

    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _getSelectedPage()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A50), Color(0xFFE8751A)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A50).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Profile Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
              border: Border.all(
                  color: Colors.white.withOpacity(0.3), width: 2),
            ),
            child: ClipOval(
              child: _currentCoachData['profileImageBase64'] != null
                  ? Image.memory(
                base64Decode(_currentCoachData['profileImageBase64']),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                      Icons.person, color: Colors.white, size: 30);
                },
              )
                  : const Icon(Icons.person, color: Colors.white, size: 30),
            ),
          ),

          const SizedBox(width: 16),

          // Coach Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _currentCoachData['name'] ?? 'Coach',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_currentCoachData['sport']} Coach',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Notifications badge
          if (_unreadNotificationCount > 0)
            GestureDetector(
              onTap: () =>
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationsPage(),
                    ),
                  ),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    const Icon(
                        Icons.notifications_outlined, color: Colors.white,
                        size: 20),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _unreadNotificationCount > 9
                              ? '9+'
                              : '$_unreadNotificationCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Messages badge
          if (_unreadMessageCount > 0)
            GestureDetector(
              onTap: () =>
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChatsListPage(),
                    ),
                  ),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Colors.white,
                        size: 20),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _unreadMessageCount > 9
                              ? '9+'
                              : '$_unreadMessageCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Requests badge
          if (_pendingRequestsCount > 0)
            GestureDetector(
              onTap: () =>
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CoachRequestsPage(),
                    ),
                  ),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    const Icon(Icons.schedule, color: Colors.white, size: 20),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _pendingRequestsCount > 9
                              ? '9+'
                              : '$_pendingRequestsCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Logout Button
          GestureDetector(
            onTap: _showLogoutDialog,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.logout, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return _buildDashboardOverview();
      case 1:
        return _buildAppointmentsPage();
      case 2:
      // Navigate to update profile page when Profile tab is selected
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _navigateToUpdateProfile();
            // Reset to dashboard after navigation
            setState(() => _selectedIndex = 0);
          }
        });
        return _buildDashboardOverview();
      default:
        return _buildDashboardOverview();
    }
  }

  Widget _buildDashboardOverview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard Overview',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),

          const SizedBox(height: 20),

          // Stats Cards - Updated with pending requests
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Pending Requests',
                  value: '$_pendingRequestsCount',
                  icon: Icons.schedule,
                  color: Colors.orange,
                  onTap: () =>
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CoachRequestsPage(),
                        ),
                      ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  title: 'Total Students',
                  value: '$_totalStudents',
                  icon: Icons.people,
                  color: Colors.blue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'This Month',
                  value: '$_monthlyAppointments',
                  icon: Icons.calendar_month,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  title: 'Rating',
                  value: '${_averageRating.toStringAsFixed(1)}',
                  icon: Icons.star,
                  color: Colors.amber,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Revenue',
                  value: 'RM ${_monthlyRevenue.toStringAsFixed(0)}',
                  icon: Icons.attach_money,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(), // Empty space for balance
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Recent Activity from real data
          _buildRecentActivity(),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    // Get recent appointments and reviews for activity feed
    List<Map<String, dynamic>> recentActivity = [];

    // Add recent appointments
    for (var appointment in _appointments.take(3)) {
      recentActivity.add({
        'type': 'appointment',
        'title': appointment['status'] == 'completed'
            ? 'Training session completed'
            : appointment['status'] == 'pending_approval'
            ? 'New session request received'
            : 'Session ${appointment['status']}',
        'subtitle': '${appointment['studentName'] ?? 'Student'} - ${_formatDate(
            appointment['scheduledAt'])}',
        'icon': appointment['status'] == 'completed'
            ? Icons.check_circle
            : appointment['status'] == 'pending_approval'
            ? Icons.schedule
            : Icons.event,
        'color': appointment['status'] == 'completed'
            ? Colors.green
            : appointment['status'] == 'pending_approval'
            ? Colors.orange
            : Colors.blue,
        'time': appointment['scheduledAt'],
      });
    }

    // Add recent reviews
    for (var review in _reviews.take(2)) {
      recentActivity.add({
        'type': 'review',
        'title': 'New review received',
        'subtitle': '${review['rating']} stars from ${review['studentName'] ??
            'Student'}',
        'icon': Icons.star,
        'color': Colors.amber,
        'time': review['createdAt'],
      });
    }

    // Sort by time
    recentActivity.sort((a, b) {
      if (a['time'] == null || b['time'] == null) return 0;
      return (b['time'] as Timestamp).compareTo(a['time'] as Timestamp);
    });

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
          const Text(
            'Recent Activity',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),

          if (recentActivity.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.inbox, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    'No recent activity',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your requests and reviews will appear here',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ...recentActivity.take(5).map((activity) =>
                _buildActivityItem(
                  activity['title'],
                  activity['subtitle'],
                  activity['icon'],
                  activity['color'],
                )),
        ],
      ),
    );
  }

  Widget _buildAppointmentsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Appointments',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 20),

          if (_appointments.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.calendar_today, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No Appointments Yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your appointments and requests will appear here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          else
            ..._appointments.map((appointment) =>
                _buildAppointmentCard(appointment)),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _getStatusColor(appointment['status']).withOpacity(0.1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Icon(
              _getStatusIcon(appointment['status']),
              color: _getStatusColor(appointment['status']),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment['studentName'] ?? 'Student',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(appointment['scheduledAt']),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(appointment['status']).withOpacity(
                        0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusDisplayText(appointment['status']),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(appointment['status']),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'RM ${appointment['price'] ?? _currentCoachData['pricePerHour'] ??
                0}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF8A50),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'accepted':
      case 'confirmed':
        return Colors.blue;
      case 'cancelled':
      case 'rejected':
        return Colors.red;
      case 'pending_approval':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'accepted':
      case 'confirmed':
        return Icons.event;
      case 'cancelled':
      case 'rejected':
        return Icons.cancel;
      case 'pending_approval':
        return Icons.schedule;
      default:
        return Icons.help_outline;
    }
  }

  String _getStatusDisplayText(String? status) {
    switch (status) {
      case 'pending_approval':
        return 'AWAITING RESPONSE';
      case 'accepted':
        return 'ACCEPTED';
      case 'rejected':
        return 'DECLINED';
      case 'confirmed':
        return 'CONFIRMED';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status?.toUpperCase() ?? 'UNKNOWN';
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'No date';
    try {
      DateTime date = (timestamp as Timestamp).toDate();
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute
          .toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
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
          border: onTap != null ? Border.all(
            color: color.withOpacity(0.3),
            width: 1,
          ) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios, color: color, size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool showBadge = false,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFF8A50).withOpacity(0.1),
              const Color(0xFFE8751A).withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFF8A50).withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    Icon(icon, color: const Color(0xFFFF8A50), size: 24),
                    if (showBadge && badgeCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            badgeCount > 9 ? '9+' : '$badgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_ios,
                    color: const Color(0xFFFF8A50),
                    size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String title, String subtitle, IconData icon,
      Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFFF8A50),
        unselectedItemColor: Colors.grey[500],
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await FirebaseAuth.instance.signOut();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}