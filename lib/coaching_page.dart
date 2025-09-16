import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'coach_detail_page.dart';
import 'services/messaging_service.dart';
import 'chat_page.dart';

class CoachingPage extends StatefulWidget {
  const CoachingPage({Key? key}) : super(key: key);

  @override
  State<CoachingPage> createState() => _CoachingPageState();
}

class _CoachingPageState extends State<CoachingPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _selectedSport = 'All Sports';
  String _selectedExperience = 'All Levels';

  List<Map<String, dynamic>> _allCoaches = [];
  List<Map<String, dynamic>> _filteredCoaches = [];
  bool _isLoading = true;

  final List<String> _sports = ['All Sports', 'Badminton', 'Football', 'Basketball', 'Pickleball', 'Hockey'];
  final List<String> _experienceLevels = ['All Levels', '1-3 years', '4-7 years', '8+ years'];

  @override
  void initState() {
    super.initState();
    _fetchCoaches();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCoaches() async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot querySnapshot = await _firestore
          .collection('coaches')
          .where('isActive', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> coaches = [];
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> coachData = doc.data() as Map<String, dynamic>;
        coachData['id'] = doc.id;
        coaches.add(coachData);
      }

      setState(() {
        _allCoaches = coaches;
        _filteredCoaches = coaches;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching coaches: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterCoaches() {
    setState(() {
      _filteredCoaches = _allCoaches.where((coach) {
        // Search filter
        final searchQuery = _searchController.text.toLowerCase();
        final matchesSearch = searchQuery.isEmpty ||
            (coach['name']?.toLowerCase().contains(searchQuery) ?? false) ||
            (coach['sport']?.toLowerCase().contains(searchQuery) ?? false) ||
            (coach['location']?.toLowerCase().contains(searchQuery) ?? false);

        // Sport filter
        final matchesSport = _selectedSport == 'All Sports' ||
            coach['sport'] == _selectedSport;

        // Experience filter
        bool matchesExperience = true;
        if (_selectedExperience != 'All Levels' && coach['experience'] != null) {
          final experienceText = coach['experience'].toString();
          final experienceMatch = RegExp(r'(\d+)').firstMatch(experienceText);

          if (experienceMatch != null) {
            final experience = int.tryParse(experienceMatch.group(1)!) ?? 0;
            switch (_selectedExperience) {
              case '1-3 years':
                matchesExperience = experience >= 1 && experience <= 3;
                break;
              case '4-7 years':
                matchesExperience = experience >= 4 && experience <= 7;
                break;
              case '8+ years':
                matchesExperience = experience >= 8;
                break;
            }
          }
        }

        return matchesSearch && matchesSport && matchesExperience;
      }).toList();
    });
  }

  Widget _getCoachProfileImage(Map<String, dynamic> coach) {
    if (coach['profileImageBase64'] != null) {
      try {
        return Image.memory(
          base64Decode(coach['profileImageBase64']),
          fit: BoxFit.cover,
          width: 80,
          height: 80,
        );
      } catch (e) {
        return Icon(Icons.person, size: 40, color: Colors.grey[500]);
      }
    }
    return Icon(Icons.person, size: 40, color: Colors.grey[500]);
  }

  Future<void> _startChatWithCoach(Map<String, dynamic> coach) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to chat with coaches'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
          ),
        ),
      );

      // Get current user data
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final studentName = userData?['name'] ??
          user.displayName ??
          user.email?.split('@')[0] ??
          'Student';

      // Create or get existing chat
      final chatId = await MessagingService.createOrGetChat(
        coachId: coach['id'],
        coachName: coach['name'] ?? 'Coach',
        studentId: user.uid,
        studentName: studentName,
      );

      // Hide loading
      if (mounted) {
        Navigator.pop(context);

        // Navigate to chat page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              chatId: chatId,
              otherUserName: coach['name'] ?? 'Coach',
              otherUserId: coach['id'],
              otherUserRole: 'coach',
            ),
          ),
        );
      }
    } catch (e) {
      // Hide loading if still showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting chat: $e'),
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
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Search and filters
          _buildSearchAndFilters(),

          // Results header
          _buildResultsHeader(),

          // Coach list
          Expanded(
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
              ),
            )
                : _filteredCoaches.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _fetchCoaches,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _filteredCoaches.length,
                itemBuilder: (context, index) {
                  return _buildCoachCard(_filteredCoaches[index]);
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
        'Find a Coach',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
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
                hintText: 'Search coaches, sports, locations...',
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              onChanged: (value) => _filterCoaches(),
            ),
          ),

          const SizedBox(height: 16),

          // Filter chips
          Row(
            children: [
              Expanded(
                child: _buildFilterChip(
                  'Sport',
                  _selectedSport,
                  _sports,
                      (value) {
                    setState(() {
                      _selectedSport = value;
                      _filterCoaches();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterChip(
                  'Experience',
                  _selectedExperience,
                  _experienceLevels,
                      (value) {
                    setState(() {
                      _selectedExperience = value;
                      _filterCoaches();
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String selected, List<String> options, Function(String) onSelected) {
    return GestureDetector(
      onTap: () => _showFilterDialog(label, options, selected, onSelected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected != options[0] ? const Color(0xFFFF8A50).withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected != options[0] ? const Color(0xFFFF8A50) : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                selected,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected != options[0] ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down,
              color: selected != options[0] ? const Color(0xFFFF8A50) : Colors.grey[600],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog(String title, List<String> options, String selected, Function(String) onSelected) {
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
            '${_filteredCoaches.length} coaches found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showSortDialog,
            child: Row(
              children: [
                Icon(Icons.sort, color: Colors.grey[600], size: 20),
                const SizedBox(width: 4),
                Text(
                  'Sort',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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

  void _showSortDialog() {
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
                const Text(
                  'Sort by',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Highest Rating'),
                  leading: const Icon(Icons.star, color: Color(0xFFFF8A50)),
                  onTap: () {
                    _sortCoaches('rating');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Lowest Price'),
                  leading: const Icon(Icons.attach_money, color: Color(0xFFFF8A50)),
                  onTap: () {
                    _sortCoaches('price');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Most Reviews'),
                  leading: const Icon(Icons.reviews, color: Color(0xFFFF8A50)),
                  onTap: () {
                    _sortCoaches('reviews');
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _sortCoaches(String sortBy) {
    setState(() {
      switch (sortBy) {
        case 'rating':
          _filteredCoaches.sort((a, b) => (b['rating'] ?? 0.0).compareTo(a['rating'] ?? 0.0));
          break;
        case 'price':
          _filteredCoaches.sort((a, b) => (a['pricePerHour'] ?? 0).compareTo(b['pricePerHour'] ?? 0));
          break;
        case 'reviews':
          _filteredCoaches.sort((a, b) => (b['totalReviews'] ?? 0).compareTo(a['totalReviews'] ?? 0));
          break;
      }
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No coaches found',
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
            onPressed: _fetchCoaches,
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

  Widget _buildCoachCard(Map<String, dynamic> coach) {
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
      child: Column(
        children: [
          // Main coach info (tappable)
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => _navigateToCoachDetail(coach),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Coach image
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                    ),
                    child: ClipOval(
                      child: _getCoachProfileImage(coach),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Coach details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name and verification
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                coach['name'] ?? 'Unknown Coach',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2D3748),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (coach['isVerified'] == true)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4CAF50),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // Sport and experience
                        Text(
                          '${coach['sport'] ?? 'Sport'} • ${coach['experience'] ?? 'Experience'} experience',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Rating and reviews
                        Row(
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.amber[600],
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${coach['rating'] ?? 0.0}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${coach['totalReviews'] ?? 0} reviews)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'RM ${coach['pricePerHour'] ?? 0}/hr',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFF8A50),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Location
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              coach['location'] ?? 'Location not specified',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
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
          ),

          // Action buttons section
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                // Message button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _startChatWithCoach(coach),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Message'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4CAF50),
                      side: const BorderSide(color: Color(0xFF4CAF50)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Book Now button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToCoachDetail(coach),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: const Text('Book Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A50),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCoachDetail(Map<String, dynamic> coach) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoachDetailPage(coach: coach),
      ),
    );
  }
}