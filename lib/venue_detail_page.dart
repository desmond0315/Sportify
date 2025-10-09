import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'court_booking_page.dart';

class VenueDetailPage extends StatefulWidget {
  final Map<String, dynamic> venue;

  const VenueDetailPage({Key? key, required this.venue}) : super(key: key);

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoadingCourts = true;
  bool _isLoadingReviews = true;

  List<Map<String, dynamic>> _courts = [];
  List<Map<String, dynamic>> _reviews = [];

  late TabController _tabController;

  // For photo carousel
  final PageController _pageController = PageController();
  int _currentPhotoIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchVenueCourts();
    _fetchVenueReviews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchVenueCourts() async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('venues')
          .doc(widget.venue['id'])
          .collection('courts')
          .where('isActive', isEqualTo: true)
          .orderBy('courtNumber')
          .get();

      List<Map<String, dynamic>> courts = [];
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> courtData = doc.data() as Map<String, dynamic>;
        courtData['id'] = doc.id;
        courts.add(courtData);
      }

      setState(() {
        _courts = courts;
        _isLoadingCourts = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCourts = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching courts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchVenueReviews() async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('venues')
          .doc(widget.venue['id'])
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      List<Map<String, dynamic>> reviews = [];
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> reviewData = doc.data() as Map<String, dynamic>;
        reviewData['id'] = doc.id;
        reviews.add(reviewData);
      }

      setState(() {
        _reviews = reviews;
        _isLoadingReviews = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingReviews = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching reviews: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Get list of photos from venue
  List<String> _getVenuePhotos() {
    List<String> photos = [];

    // Check if venue has photos array
    if (widget.venue['photos'] != null && widget.venue['photos'] is List) {
      List photosList = widget.venue['photos'] as List;
      for (var photo in photosList) {
        if (photo is Map && photo['data'] != null) {
          photos.add(photo['data']);
        }
      }
    }

    // If no photos array, fall back to imageUrl
    if (photos.isEmpty && widget.venue['imageUrl'] != null) {
      photos.add(widget.venue['imageUrl']);
    }

    return photos;
  }

  Widget _buildPhotoFromData(String imageData) {
    if (imageData.isEmpty) {
      return Container(
        color: Colors.grey[200],
        child: Icon(
          Icons.location_on,
          size: 100,
          color: Colors.grey[500],
        ),
      );
    }

    // Check if it's a base64 data URL
    if (imageData.startsWith('data:image')) {
      try {
        // Extract base64 string
        final base64String = imageData.split(',')[1];
        final bytes = base64Decode(base64String);

        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: Icon(
                Icons.location_on,
                size: 100,
                color: Colors.grey[500],
              ),
            );
          },
        );
      } catch (e) {
        print('Error decoding base64 image: $e');
        return Container(
          color: Colors.grey[200],
          child: Icon(
            Icons.error,
            size: 100,
            color: Colors.grey[500],
          ),
        );
      }
    }

    // Regular network URL
    return Image.network(
      imageData,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: Icon(
            Icons.location_on,
            size: 100,
            color: Colors.grey[500],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildVenueInfo(),
                _buildTabSection(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildBookingFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSliverAppBar() {
    final photos = _getVenuePhotos();

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      // actions property removed - no more favorite and share icons
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Photo PageView for swiping
            photos.isEmpty
                ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.grey[300]!,
                    Colors.grey[200]!,
                  ],
                ),
              ),
              child: Icon(
                Icons.location_on,
                size: 100,
                color: Colors.grey[500],
              ),
            )
                : PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPhotoIndex = index;
                });
              },
              itemCount: photos.length,
              itemBuilder: (context, index) {
                return _buildPhotoFromData(photos[index]);
              },
            ),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
            ),

            // Left Arrow Button (only show if multiple photos and not on first photo)
            if (photos.length > 1 && _currentPhotoIndex > 0)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),

            // Right Arrow Button (only show if multiple photos and not on last photo)
            if (photos.length > 1 && _currentPhotoIndex < photos.length - 1)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),

            // Photo indicator dots (only show if multiple photos)
            if (photos.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(photos.length, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPhotoIndex == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPhotoIndex == index
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

            // Photo counter (top right)
            if (photos.length > 1)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_currentPhotoIndex + 1}/${photos.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueInfo() {
    List<String> sports = [];
    if (widget.venue['sports'] is List) {
      sports = List<String>.from(widget.venue['sports']);
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.venue['name'] ?? 'Unknown Venue',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D3748),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      color: Colors.amber[700],
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.venue['rating'] ?? 0.0}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                color: Colors.grey[600],
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.venue['location'] ?? 'Location not specified',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (sports.isNotEmpty) ...[
            const Text(
              'Available Sports',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sports.map((sport) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8A50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFF8A50).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    sport,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFFF8A50),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          Row(
            children: [
              _buildStatCard(
                icon: Icons.sports_tennis,
                label: 'Courts',
                value: '${widget.venue['totalCourts'] ?? 0}',
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.access_time,
                label: 'Open Hours',
                value: _getTodayOpeningHours(),
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.attach_money,
                label: 'From',
                value: 'RM ${widget.venue['pricePerHour'] ?? 0}/hr',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: const Color(0xFFFF8A50),
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3748),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _getTodayOpeningHours() {
    if (widget.venue['operatingHours'] == null) return 'Not set';

    final now = DateTime.now();
    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final today = days[now.weekday - 1];

    final todayHours = widget.venue['operatingHours'][today];

    if (todayHours == null) return 'Closed';

    if (todayHours['closed'] == true) {
      return 'Closed';
    }

    final open = todayHours['open'] ?? '';
    final close = todayHours['close'] ?? '';

    if (open.isEmpty || close.isEmpty) {
      return 'Closed';
    }

    return '$open-$close';
  }

  Widget _buildTabSection() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFFFF8A50),
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: const Color(0xFFFF8A50),
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Courts'),
              Tab(text: 'Reviews'),
            ],
          ),
        ),
        SizedBox(
          height: 400,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildCourtsTab(),
              _buildReviewsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    // Get facilities and rules from venue data
    List<String> facilities = [];
    if (widget.venue['facilities'] is List) {
      facilities = List<String>.from(widget.venue['facilities']);
    }

    List<String> rules = [];
    if (widget.venue['rules'] is List) {
      rules = List<String>.from(widget.venue['rules']);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About this venue',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.venue['description'] ?? 'No description available.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),

          // Only show Facilities section if there are facilities
          if (facilities.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Facilities',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 12),
            _buildFacilitiesList(facilities),
          ],

          // Only show Rules section if there are rules
          if (rules.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Rules & Policies',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 12),
            _buildRulesList(rules),
          ],
        ],
      ),
    );
  }

  Widget _buildFacilitiesList(List<String> facilities) {
    return Column(
      children: facilities.map((facility) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF4CAF50),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  facility,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRulesList(List<String> rules) {
    return Column(
      children: rules.map((rule) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey[500],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rule,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCourtsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: _isLoadingCourts
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
        ),
      )
          : _courts.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_tennis,
              size: 60,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No courts available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Courts (${_courts.length})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _courts.length,
              itemBuilder: (context, index) {
                return _buildCourtCard(_courts[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtCard(Map<String, dynamic> court) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
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
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _getCourtTypeColor(court['type']).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getCourtTypeIcon(court['type']),
              color: _getCourtTypeColor(court['type']),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  court['courtName'] ?? 'Court ${court['courtNumber'] ?? 'N/A'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getCourtTypeColor(court['type']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        court['type'] ?? 'Standard Court',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getCourtTypeColor(court['type']),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: (court['isAvailable'] ?? true)
                            ? const Color(0xFF4CAF50)
                            : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (court['isAvailable'] ?? true) ? 'Available' : 'Occupied',
                      style: TextStyle(
                        fontSize: 12,
                        color: (court['isAvailable'] ?? true)
                            ? const Color(0xFF4CAF50)
                            : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            'RM ${court['pricePerHour'] ?? widget.venue['pricePerHour'] ?? 0}/hr',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFF8A50),
            ),
          ),
        ],
      ),
    );
  }

  Color _getCourtTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'indoor':
        return const Color(0xFF3B82F6);
      case 'outdoor':
        return const Color(0xFFF59E0B);
      case 'covered':
        return const Color(0xFF10B981);
      case 'semi-indoor':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getCourtTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'indoor':
        return Icons.home;
      case 'outdoor':
        return Icons.wb_sunny;
      case 'covered':
        return Icons.roofing;
      case 'semi-indoor':
        return Icons.deck;
      default:
        return Icons.sports_tennis;
    }
  }

  Widget _buildReviewsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: _isLoadingReviews
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
        ),
      )
          : _reviews.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.rate_review,
              size: 60,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No reviews yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to leave a review!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reviews (${_reviews.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Navigate to all reviews page
                },
                child: const Text(
                  'View all',
                  style: TextStyle(
                    color: Color(0xFFFF8A50),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _reviews.length,
              itemBuilder: (context, index) {
                return _buildReviewCard(_reviews[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFF8A50),
                child: Text(
                  (review['userName'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['userName'] ?? 'Anonymous',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    Row(
                      children: [
                        Row(
                          children: List.generate(5, (index) {
                            return Icon(
                              index < (review['rating'] ?? 0) ? Icons.star : Icons.star_border,
                              color: Colors.amber[600],
                              size: 16,
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(review['createdAt']),
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
          const SizedBox(height: 12),
          Text(
            review['comment'] ?? '',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Recently';

    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else {
        return 'Recently';
      }

      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} days ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hours ago';
      } else {
        return 'Recently';
      }
    } catch (e) {
      return 'Recently';
    }
  }

  Widget _buildBookingFAB() {
    return Container(
      width: MediaQuery.of(context).size.width - 40,
      height: 56,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFFF8A50),
            Color(0xFFFF6B35),
            Color(0xFFE8751A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A50).withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _handleBookVenue,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'BOOK NOW',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  void _handleBookVenue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourtBookingPage(
          venue: widget.venue,
          courts: _courts,
        ),
      ),
    );
  }
}