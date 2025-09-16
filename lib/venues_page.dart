import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'venue_detail_page.dart';

class VenuesPage extends StatefulWidget {
  const VenuesPage({Key? key}) : super(key: key);

  @override
  State<VenuesPage> createState() => _VenuesPageState();
}

class _VenuesPageState extends State<VenuesPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _selectedSport = 'All Sports';
  String _selectedLocation = 'All Areas';

  List<Map<String, dynamic>> _allVenues = [];
  List<Map<String, dynamic>> _filteredVenues = [];
  bool _isLoading = true;

  final List<String> _sports = ['All Sports', 'Badminton', 'Football', 'Basketball', 'Pickleball', 'Hockey', 'Multi-sport'];
  final List<String> _locations = ['All Areas', 'Georgetown', 'Bayan Lepas', 'Tanjung Bungah', 'Jelutong', 'Butterworth'];

  @override
  void initState() {
    super.initState();
    _fetchVenues();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchVenues() async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot querySnapshot = await _firestore
          .collection('venues')
          .where('isActive', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> venues = [];
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> venueData = doc.data() as Map<String, dynamic>;
        venueData['id'] = doc.id;
        venues.add(venueData);
      }

      setState(() {
        _allVenues = venues;
        _filteredVenues = venues;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching venues: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterVenues() {
    setState(() {
      _filteredVenues = _allVenues.where((venue) {
        // Search filter
        final searchQuery = _searchController.text.toLowerCase();
        final matchesSearch = searchQuery.isEmpty ||
            (venue['name']?.toLowerCase().contains(searchQuery) ?? false) ||
            (venue['location']?.toLowerCase().contains(searchQuery) ?? false) ||
            (venue['description']?.toLowerCase().contains(searchQuery) ?? false);

        // Sport filter
        bool matchesSport = _selectedSport == 'All Sports';
        if (!matchesSport && venue['sports'] is List) {
          List<String> venueSports = List<String>.from(venue['sports']);
          matchesSport = venueSports.contains(_selectedSport) ||
              (venueSports.contains('Multi-sport') && _selectedSport != 'All Sports');
        }

        // Location filter
        final matchesLocation = _selectedLocation == 'All Areas' ||
            (venue['location']?.contains(_selectedLocation) ?? false);

        return matchesSearch && matchesSport && matchesLocation;
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
          // Search and filters
          _buildSearchAndFilters(),

          // Results header
          _buildResultsHeader(),

          // Venue list
          Expanded(
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
              ),
            )
                : _filteredVenues.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _fetchVenues,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _filteredVenues.length,
                itemBuilder: (context, index) {
                  return _buildVenueCard(_filteredVenues[index]);
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
        'Find Venues',
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
                hintText: 'Search venues, locations...',
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
              onChanged: (value) => _filterVenues(),
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
                      _filterVenues();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterChip(
                  'Location',
                  _selectedLocation,
                  _locations,
                      (value) {
                    setState(() {
                      _selectedLocation = value;
                      _filterVenues();
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
            '${_filteredVenues.length} venues found',
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
                    _sortVenues('rating');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Lowest Price'),
                  leading: const Icon(Icons.attach_money, color: Color(0xFFFF8A50)),
                  onTap: () {
                    _sortVenues('price');
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  title: const Text('Distance'),
                  leading: const Icon(Icons.location_on, color: Color(0xFFFF8A50)),
                  onTap: () {
                    _sortVenues('distance');
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

  void _sortVenues(String sortBy) {
    setState(() {
      switch (sortBy) {
        case 'rating':
          _filteredVenues.sort((a, b) => (b['rating'] ?? 0.0).compareTo(a['rating'] ?? 0.0));
          break;
        case 'price':
          _filteredVenues.sort((a, b) => (a['pricePerHour'] ?? 0).compareTo(b['pricePerHour'] ?? 0));
          break;
        case 'distance':
        // For now, just sort by name - you'd implement actual distance calculation
          _filteredVenues.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
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
            'No venues found',
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
            onPressed: _fetchVenues,
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

  Widget _buildVenueCard(Map<String, dynamic> venue) {
    List<String> sports = [];
    if (venue['sports'] is List) {
      sports = List<String>.from(venue['sports']);
    }

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
        onTap: () => _navigateToVenueDetail(venue),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Venue image
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.grey[200]!,
                    Colors.grey[300]!,
                  ],
                ),
              ),
              child: venue['imageUrl'] != null
                  ? ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.network(
                  venue['imageUrl'],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(
                        Icons.location_on,
                        size: 50,
                        color: Colors.grey[500],
                      ),
                    );
                  },
                ),
              )
                  : Center(
                child: Icon(
                  Icons.location_on,
                  size: 50,
                  color: Colors.grey[500],
                ),
              ),
            ),

            // Venue details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rating and price
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.amber[700],
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${venue['rating'] ?? 0.0}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'RM ${venue['pricePerHour'] ?? 0}/hr',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF8A50),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Venue name
                  Text(
                    venue['name'] ?? 'Unknown Venue',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D3748),
                    ),
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
                      Expanded(
                        child: Text(
                          venue['location'] ?? 'Location not specified',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Sports tags
                  if (sports.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: sports.take(3).map((sport) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8A50).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            sport,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFFF8A50),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 12),

                  // Courts available
                  Text(
                    '${venue['totalCourts'] ?? 0} courts available',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
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

  void _navigateToVenueDetail(Map<String, dynamic> venue) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VenueDetailPage(venue: venue),
      ),
    );
  }
}