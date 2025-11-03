import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tournament_detail_page.dart';
import 'my_tournaments_page.dart';

class TournamentsPage extends StatefulWidget {
  const TournamentsPage({Key? key}) : super(key: key);

  @override
  State<TournamentsPage> createState() => _TournamentsPageState();
}

class _TournamentsPageState extends State<TournamentsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _selectedSport = 'All Sports';
  String _selectedStatus = 'All';
  String _selectedFormat = 'All';

  List<Map<String, dynamic>> _allTournaments = [];
  List<Map<String, dynamic>> _filteredTournaments = [];
  bool _isLoading = true;

  final List<String> _sports = [
    'All Sports',
    'Badminton',
    'Football',
    'Basketball',
    'Pickleball',
    'Hockey'
  ];
  final List<String> _statuses = ['All', 'Upcoming', 'Ongoing', 'Completed', 'Cancelled'];
  final List<String> _formats = ['All', 'Singles', 'Doubles', 'Team'];

  @override
  void initState() {
    super.initState();
    _fetchTournaments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTournaments() async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot querySnapshot = await _firestore
          .collection('tournaments')
          .where('isActive', isEqualTo: true)
          .orderBy('startDate', descending: false)
          .get();

      List<Map<String, dynamic>> tournaments = [];
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> tournamentData = doc.data() as Map<String, dynamic>;
        tournamentData['id'] = doc.id;
        tournaments.add(tournamentData);
      }

      setState(() {
        _allTournaments = tournaments;
        _filteredTournaments = tournaments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching tournaments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterTournaments() {
    setState(() {
      _filteredTournaments = _allTournaments.where((tournament) {
        // Search filter
        final searchQuery = _searchController.text.toLowerCase();
        final matchesSearch = searchQuery.isEmpty ||
            (tournament['name']?.toLowerCase().contains(searchQuery) ?? false) ||
            (tournament['venueName']?.toLowerCase().contains(searchQuery) ?? false) ||
            (tournament['description']?.toLowerCase().contains(searchQuery) ?? false);

        // Sport filter
        final matchesSport = _selectedSport == 'All Sports' ||
            tournament['sport'] == _selectedSport;

        // Status filter
        final matchesStatus = _selectedStatus == 'All' ||
            tournament['status'] == _selectedStatus.toLowerCase();

        // Format filter
        final matchesFormat = _selectedFormat == 'All' ||
            tournament['format'] == _selectedFormat;

        return matchesSearch && matchesSport && matchesStatus && matchesFormat;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          _buildResultsHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(
                valueColor:
                AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
              ),
            )
                : _filteredTournaments.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _fetchTournaments,
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _filteredTournaments.length,
                itemBuilder: (context, index) {
                  return _buildTournamentCard(
                      _filteredTournaments[index]);
                },
              ),
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
        'Tournaments',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      // Trophy icon button in AppBar
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.emoji_events,
              color: Color(0xFFFF8A50),
              size: 20,
            ),
          ),
          tooltip: 'My Tournaments',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MyTournamentsPage(),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search tournaments, venues...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A50), Color(0xFFE8751A)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.search, color: Colors.white, size: 20),
                ),
                border: InputBorder.none,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              onChanged: (value) => _filterTournaments(),
            ),
          ),

          const SizedBox(height: 16),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  'Sport',
                  _selectedSport,
                  _sports,
                      (value) {
                    setState(() {
                      _selectedSport = value;
                      _filterTournaments();
                    });
                  },
                ),
                const SizedBox(width: 12),
                _buildFilterChip(
                  'Status',
                  _selectedStatus,
                  _statuses,
                      (value) {
                    setState(() {
                      _selectedStatus = value;
                      _filterTournaments();
                    });
                  },
                ),
                const SizedBox(width: 12),
                _buildFilterChip(
                  'Format',
                  _selectedFormat,
                  _formats,
                      (value) {
                    setState(() {
                      _selectedFormat = value;
                      _filterTournaments();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String selected, List<String> options,
      Function(String) onSelected) {
    return GestureDetector(
      onTap: () => _showFilterDialog(label, options, selected, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected != options[0]
              ? const Color(0xFFFF8A50).withOpacity(0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected != options[0]
                ? const Color(0xFFFF8A50)
                : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: selected != options[0]
                    ? const Color(0xFFFF8A50)
                    : const Color(0xFF2D3748),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down,
              color: selected != options[0]
                  ? const Color(0xFFFF8A50)
                  : Colors.grey[600],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog(String title, List<String> options, String selected,
      Function(String) onSelected) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select $title',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 16),
                ...options.map((option) => ListTile(
                  title: Text(option),
                  leading: Radio<String>(
                    value: option,
                    groupValue: selected,
                    activeColor: const Color(0xFFFF8A50),
                    onChanged: (value) {
                      onSelected(value!);
                      Navigator.pop(context);
                    },
                  ),
                )),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultsHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Text(
            '${_filteredTournaments.length} tournaments found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ],
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
            'No tournaments found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchTournaments,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Refresh',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTournamentCard(Map<String, dynamic> tournament) {
    final startDate = tournament['startDate'] as Timestamp?;
    final registrationDeadline =
    tournament['registrationDeadline'] as Timestamp?;
    final now = DateTime.now();
    final isRegistrationOpen = registrationDeadline != null &&
        registrationDeadline.toDate().isAfter(now);
    final spotsLeft = (tournament['maxParticipants'] ?? 0) -
        (tournament['currentParticipants'] ?? 0);

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
        onTap: () => _navigateToTournamentDetail(tournament),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tournament header with status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _getStatusGradient(tournament['status']),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.emoji_events,
                      color: Colors.white,
                      size: 28,
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
                            fontSize: 18,
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
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getStatusLabel(tournament['status']),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _getStatusColor(tournament['status']),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tournament details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sport and Format tags
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8A50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tournament['sport'] ?? 'Sport',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFF8A50),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tournament['format'] ?? 'Format',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Date and participants info
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(
                                  'Start Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(startDate),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.people,
                                    size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 6),
                                Text(
                                  'Participants',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${tournament['currentParticipants'] ?? 0}/${tournament['maxParticipants'] ?? 0}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Entry fee and registration status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Entry Fee',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tournament['entryFee'] == 0
                                ? 'FREE'
                                : 'RM ${tournament['entryFee']}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tournament['entryFee'] == 0
                                  ? Colors.green
                                  : const Color(0xFFFF8A50),
                            ),
                          ),
                        ],
                      ),
                      if (isRegistrationOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: spotsLeft > 0
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: spotsLeft > 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                          child: Text(
                            spotsLeft > 0
                                ? '$spotsLeft spots left'
                                : 'FULL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: spotsLeft > 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // View details button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _navigateToTournamentDetail(tournament),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A50),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'View Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'upcoming':
        return const Color(0xFF3b82f6);
      case 'ongoing':
        return const Color(0xFF10b981);
      case 'completed':
        return const Color(0xFF6b7280);
      case 'cancelled':
        return const Color(0xffd12020);
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
      case 'cancelled':
        return 'CANCELLED';
      default:
        return 'OPEN';
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'TBA';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }

  void _navigateToTournamentDetail(Map<String, dynamic> tournament) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TournamentDetailPage(tournament: tournament),
      ),
    );
  }
}