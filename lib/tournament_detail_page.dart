import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tournament_payment_page.dart';

class TournamentDetailPage extends StatefulWidget {
  final Map<String, dynamic> tournament;

  const TournamentDetailPage({Key? key, required this.tournament})
      : super(key: key);

  @override
  State<TournamentDetailPage> createState() => _TournamentDetailPageState();
}

class _TournamentDetailPageState extends State<TournamentDetailPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isRegistered = false;
  bool _isLoading = true;
  bool _isRegistering = false;
  String? _registrationId;
  bool _isWithdrawing = false;
  bool _isTournamentActive() {
    final status = widget.tournament['status']?.toLowerCase() ?? '';
    final registrationDeadline =
    widget.tournament['registrationDeadline'] as Timestamp?;

    // If cancelled or completed → not active
    if (status == 'cancelled' || status == 'completed') return false;

    // If registration deadline exists and is already past → not active
    if (registrationDeadline != null &&
        registrationDeadline.toDate().isBefore(DateTime.now())) {
      return false;
    }

    // Otherwise → active
    return true;
  }



  @override
  void initState() {
    super.initState();
    _checkRegistrationStatus();
  }

  Future<void> _checkRegistrationStatus() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final registrationQuery = await _firestore
          .collection('tournament_registrations')
          .where('tournamentId', isEqualTo: widget.tournament['id'])
          .where('userId', isEqualTo: user.uid)
          .get();

      setState(() {
        _isRegistered = registrationQuery.docs.isNotEmpty;
        // Store the registration ID so we can delete it later
        if (_isRegistered) {
          _registrationId = registrationQuery.docs.first.id;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinTournament() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to join tournaments'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if registration deadline has passed
    final registrationDeadline =
    widget.tournament['registrationDeadline'] as Timestamp?;
    if (registrationDeadline != null &&
        registrationDeadline.toDate().isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration deadline has passed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check if tournament is full
    final currentParticipants = widget.tournament['currentParticipants'] ?? 0;
    final maxParticipants = widget.tournament['maxParticipants'] ?? 0;
    if (currentParticipants >= maxParticipants) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tournament is full'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Join Tournament'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Join ${widget.tournament['name']}?'),
              const SizedBox(height: 16),
              if (widget.tournament['entryFee'] > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Entry fee: RM ${widget.tournament['entryFee']}\nYou will proceed to payment after registration.',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isRegistering = true;
    });

    try {
      // Get user data
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      // Create registration with PENDING payment status
      final registrationRef =
      await _firestore.collection('tournament_registrations').add({
        'tournamentId': widget.tournament['id'],
        'tournamentName': widget.tournament['name'],
        'userId': user.uid,
        'userName': userData?['name'] ?? user.displayName ?? 'User',
        'userEmail': user.email ?? '',
        'userPhone': userData?['phone'] ?? '',
        'registeredAt': FieldValue.serverTimestamp(),
        'paymentStatus': widget.tournament['entryFee'] > 0 ? 'pending' : 'completed',
        'paymentAmount': widget.tournament['entryFee'] ?? 0,
        'status': widget.tournament['entryFee'] > 0 ? 'pending_payment' : 'confirmed',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final registrationId = registrationRef.id;

      // If FREE tournament, confirm immediately
      if (widget.tournament['entryFee'] == 0) {
        // Increment participant count for free tournaments
        await _firestore
            .collection('tournaments')
            .doc(widget.tournament['id'])
            .update({
          'currentParticipants': FieldValue.increment(1),
        });

        // Create notification for venue owner
        await _firestore.collection('notifications').add({
          'userId': widget.tournament['venueOwnerId'],
          'type': 'tournament',
          'title': 'New Tournament Registration',
          'message':
          '${userData?['name'] ?? 'A user'} has joined ${widget.tournament['name']}',
          'data': {
            'tournamentId': widget.tournament['id'],
            'action': 'view_tournament',
          },
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'priority': 'medium',
        });

        setState(() {
          _isRegistered = true;
          _registrationId = registrationId;
          _isRegistering = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully joined the tournament!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // For PAID tournaments, navigate to payment page
        setState(() {
          _isRegistering = false;
        });

        if (mounted) {
          // Navigate to payment page
          final paymentResult = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TournamentPaymentPage(
                tournament: widget.tournament,
                registrationId: registrationId,
              ),
            ),
          );

          // Refresh registration status after returning from payment
          await _checkRegistrationStatus();
        }
      }
    } catch (e) {
      setState(() {
        _isRegistering = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error joining tournament: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _withdrawFromTournament() async {
    final user = _auth.currentUser;
    if (user == null || _registrationId == null) {
      return;
    }

    // Check if tournament has already started
    final startDate = widget.tournament['startDate'] as Timestamp?;
    if (startDate != null && startDate.toDate().isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot withdraw from a tournament that has already started'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Withdraw from Tournament?')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to withdraw from ${widget.tournament['name']}?',
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              SizedBox(height: 16),
              if (widget.tournament['entryFee'] > 0)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Entry fee are non-refundable as stated in the tournament policy',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[800],
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
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Withdraw',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isWithdrawing = true;
    });

    try {
      // Get user data for notification
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      // Delete the registration document
      await _firestore
          .collection('tournament_registrations')
          .doc(_registrationId)
          .delete();

      // CRITICAL: Decrement the tournament participant count
      await _firestore
          .collection('tournaments')
          .doc(widget.tournament['id'])
          .update({
        'currentParticipants': FieldValue.increment(-1),
      });

      // Create notification for venue owner
      await _firestore.collection('notifications').add({
        'userId': widget.tournament['venueOwnerId'],
        'type': 'tournament',
        'title': 'Tournament Withdrawal',
        'message':
        '${userData?['name'] ?? 'A participant'} has withdrawn from ${widget.tournament['name']}',
        'data': {
          'tournamentId': widget.tournament['id'],
          'action': 'view_tournament',
        },
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
        'priority': 'medium',
      });

      setState(() {
        _isRegistered = false;
        _registrationId = null;
        _isWithdrawing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully withdrawn from tournament'),
            backgroundColor: Colors.green,
          ),
        );

        // Optionally go back to tournaments list
        // Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isWithdrawing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error withdrawing from tournament: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final startDate = widget.tournament['startDate'] as Timestamp?;
    final endDate = widget.tournament['endDate'] as Timestamp?;
    final registrationDeadline =
    widget.tournament['registrationDeadline'] as Timestamp?;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFFFF8A50),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _getStatusGradient(widget.tournament['status']),
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Text(
                            _getStatusLabel(widget.tournament['status']),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.tournament['name'] ?? 'Tournament',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              widget.tournament['venueName'] ?? 'Venue',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: _isLoading
                ? Container(
              padding: const EdgeInsets.all(40),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
                ),
              ),
            )
                : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Info Cards
                Container(
                  margin: const EdgeInsets.all(20),
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
                  child: Column(
                    children: [
                      _buildInfoRow(
                        Icons.sports,
                        'Sport & Format',
                        '${widget.tournament['sport']} - ${widget.tournament['format']}',
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        Icons.calendar_today,
                        'Start Date',
                        _formatDate(startDate),
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        Icons.event,
                        'End Date',
                        _formatDate(endDate),
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        Icons.timer,
                        'Registration Deadline',
                        _formatDate(registrationDeadline),
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        Icons.people,
                        'Participants',
                        '${widget.tournament['currentParticipants'] ?? 0}/${widget.tournament['maxParticipants'] ?? 0}',
                      ),
                      _buildDivider(),
                      _buildInfoRow(
                        Icons.attach_money,
                        'Entry Fee',
                        widget.tournament['entryFee'] == 0
                            ? 'FREE'
                            : 'RM ${widget.tournament['entryFee']}',
                        valueColor: widget.tournament['entryFee'] == 0
                            ? Colors.green
                            : const Color(0xFFFF8A50),
                      ),
                      if (widget.tournament['prizePool'] != null &&
                          widget.tournament['prizePool'].isNotEmpty) ...[
                        _buildDivider(),
                        _buildInfoRow(
                          Icons.emoji_events,
                          'Prize Pool',
                          widget.tournament['prizePool'],
                          valueColor: Colors.amber[700],
                        ),
                      ],
                    ],
                  ),
                ),

                // Description Section
                if (widget.tournament['description'] != null &&
                    widget.tournament['description'].isNotEmpty)
                  _buildSection(
                    'About Tournament',
                    widget.tournament['description'],
                    Icons.info_outline,
                  ),

                // Rules Section
                if (widget.tournament['rules'] != null &&
                    widget.tournament['rules'].isNotEmpty)
                  _buildSection(
                    'Rules & Regulations',
                    widget.tournament['rules'],
                    Icons.rule,
                  ),

                // Requirements Section
                if (widget.tournament['requirements'] != null &&
                    widget.tournament['requirements'].isNotEmpty)
                  _buildSection(
                    'Requirements',
                    widget.tournament['requirements'],
                    Icons.checklist,
                  ),

                // Location Section
                _buildSection(
                  'Location',
                  widget.tournament['location'] ?? 'Location not specified',
                  Icons.location_on,
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),

      // Bottom action button
      bottomNavigationBar: _isLoading
          ? null
          : Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: !_isTournamentActive()
              ? Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, color: Colors.grey, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Registration closed',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          )
              : _isRegistered
              ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Already Registered Badge
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 24),
                    const SizedBox(width: 12),
                    const Text(
                      'You are registered for this tournament',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Withdraw Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isWithdrawing
                      ? null
                      : _withdrawFromTournament,
                  icon: _isWithdrawing
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(
                          Colors.red),
                    ),
                  )
                      : const Icon(Icons.logout, size: 20),
                  label: Text(
                    _isWithdrawing
                        ? 'Withdrawing...'
                        : 'Withdraw from Tournament',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(
                        color: Colors.red, width: 2),
                    padding:
                    const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          )
              : ElevatedButton(
            onPressed:
            _isRegistering ? null : _joinTournament,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A50),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isRegistering
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                AlwaysStoppedAnimation<Color>(
                    Colors.white),
              ),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emoji_events,
                    color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Text(
                  widget.tournament['entryFee'] > 0
                      ? 'Join Tournament (RM ${widget.tournament['entryFee']})'
                      : 'Join Tournament (FREE)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFF8A50),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? const Color(0xFF2D3748),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.grey[200]);
  }

  Widget _buildSection(String title, String content, IconData icon) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFF8A50), size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
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
      case 'cancelled':
        return [const Color(0xffd12020), const Color(0xffa81a1a)];
      default:
        return [const Color(0xFFFF8A50), const Color(0xFFE8751A)];
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
      case 'cancelled':
        return 'CANCELLED';
      default:
        return 'OPEN';
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'TBA';
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
}