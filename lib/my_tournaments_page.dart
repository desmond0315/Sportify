import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tournament_detail_page.dart';
import 'tournament_payment_page.dart';

class MyTournamentsPage extends StatefulWidget {
  const MyTournamentsPage({Key? key}) : super(key: key);

  @override
  State<MyTournamentsPage> createState() => _MyTournamentsPageState();
}

class _MyTournamentsPageState extends State<MyTournamentsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> _myTournaments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMyTournaments();
  }

  Future<void> _fetchMyTournaments() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Get user's registrations
      final registrationsSnapshot = await _firestore
          .collection('tournament_registrations')
          .where('userId', isEqualTo: user.uid)
          .get();

      List<Map<String, dynamic>> tournaments = [];

      // Fetch tournament details for each registration
      for (var regDoc in registrationsSnapshot.docs) {
        final registrationData = regDoc.data();
        registrationData['registrationDocId'] = regDoc.id; // Store the registration doc ID
        final tournamentId = registrationData['tournamentId'];

        if (tournamentId != null) {
          final tournamentDoc =
          await _firestore.collection('tournaments').doc(tournamentId).get();

          if (tournamentDoc.exists) {
            Map<String, dynamic> tournamentData =
            tournamentDoc.data() as Map<String, dynamic>;
            tournamentData['id'] = tournamentDoc.id;
            tournamentData['registrationData'] = registrationData;
            tournaments.add(tournamentData);
          }
        }
      }

      setState(() {
        _myTournaments = tournaments;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching tournaments: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading tournaments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'My Tournaments',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
        ),
      )
          : _myTournaments.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _fetchMyTournaments,
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: _myTournaments.length,
          itemBuilder: (context, index) {
            return _buildTournamentCard(_myTournaments[index]);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Tournaments Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Join tournaments to see them here',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Browse Tournaments',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTournamentCard(Map<String, dynamic> tournament) {
    final startDate = tournament['startDate'] as Timestamp?;
    final status = tournament['status'] as String?;
    final registrationData = tournament['registrationData'] as Map<String, dynamic>?;
    final paymentStatus = registrationData?['paymentStatus'] ?? 'pending';
    final registrationStatus = registrationData?['status'] ?? 'pending_payment';
    final registrationDocId = registrationData?['registrationDocId'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TournamentDetailPage(tournament: tournament),
            ),
          );
          // Refresh if returned from payment
          if (result == true && mounted) {
            _fetchMyTournaments();
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _getStatusGradient(status),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tournament['name'] ?? 'Tournament',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tournament['venueName'] ?? 'Venue',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _getStatusLabel(status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sport and Format
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8A50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tournament['sport'] ?? 'Sport',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFFF8A50),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tournament['format'] ?? 'Format',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Info rows
                  _buildInfoRow(
                    Icons.calendar_today,
                    'Start Date',
                    _formatDate(startDate),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    Icons.payment,
                    'Payment Status',
                    _capitalizeFirst(paymentStatus),
                    valueColor: paymentStatus == 'completed' || paymentStatus == 'paid'
                        ? Colors.green
                        : Colors.orange,
                  ),

                  // Payment Status Badge
                  if (registrationData != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: paymentStatus == 'completed'
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: paymentStatus == 'completed'
                                ? Colors.green
                                : Colors.orange,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              paymentStatus == 'completed'
                                  ? Icons.check_circle
                                  : Icons.pending,
                              size: 18,
                              color: paymentStatus == 'completed'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                paymentStatus == 'completed'
                                    ? 'Registration Confirmed - Payment Completed'
                                    : 'Payment Pending - Complete payment to confirm registration',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: paymentStatus == 'completed'
                                      ? Colors.green[700]
                                      : Colors.orange[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Action Buttons
                  Row(
                    children: [
                      // Pay Now Button (only show if payment is pending)
                      if (paymentStatus == 'pending' && registrationDocId != null)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TournamentPaymentPage(
                                    tournament: tournament,
                                    registrationId: registrationDocId,
                                  ),
                                ),
                              );
                              // Refresh after payment
                              if (result == true && mounted) {
                                _fetchMyTournaments();
                              }
                            },
                            icon: const Icon(Icons.payment, size: 18),
                            label: const Text('Pay Now'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),

                      if (paymentStatus == 'pending' && registrationDocId != null)
                        const SizedBox(width: 8),

                      // View Details Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    TournamentDetailPage(tournament: tournament),
                              ),
                            );
                            if (result == true && mounted) {
                              _fetchMyTournaments();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8A50),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            paymentStatus == 'completed' ? 'View Details' : 'View Details',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor ?? const Color(0xFF2D3748),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  List<Color> _getStatusGradient(String? status) {
    switch (status?.toLowerCase()) {
      case 'upcoming':
        return [const Color(0xFF3b82f6), const Color(0xFF2563eb)];
      case 'ongoing':
        return [const Color(0xFF10b981), const Color(0xFF059669)];
      case 'completed':
        return [const Color(0xFF6b7280), const Color(0xFF4b5563)];
      default:
        return [const Color(0xFFFF8A50), const Color(0xFFE8751A)];
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'upcoming':
        return const Color(0xFF3b82f6);
      case 'ongoing':
        return const Color(0xFF10b981);
      case 'completed':
        return const Color(0xFF6b7280);
      default:
        return const Color(0xFFFF8A50);
    }
  }

  String _getStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'upcoming':
        return 'UPCOMING';
      case 'ongoing':
        return 'ONGOING';
      case 'completed':
        return 'COMPLETED';
      default:
        return 'ACTIVE';
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'TBA';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}