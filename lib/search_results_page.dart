import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'venue_detail_page.dart';

class SearchResultsPage extends StatefulWidget {
  final String initialQuery;

  const SearchResultsPage({Key? key, required this.initialQuery}) : super(key: key);

  @override
  State<SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<SearchResultsPage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    _currentQuery = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      _performSearch(widget.initialQuery);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _currentQuery = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _currentQuery = query;
    });

    try {
      // Get all active venues first
      QuerySnapshot venuesSnapshot = await _firestore
          .collection('venues')
          .where('isActive', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> allVenues = [];
      for (var doc in venuesSnapshot.docs) {
        Map<String, dynamic> venueData = doc.data() as Map<String, dynamic>;
        venueData['id'] = doc.id;
        allVenues.add(venueData);
      }

      // Filter venues based on search query
      List<Map<String, dynamic>> filteredVenues = _filterVenues(allVenues, query.toLowerCase());

      setState(() {
        _searchResults = filteredVenues;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterVenues(List<Map<String, dynamic>> venues, String query) {
    return venues.where((venue) {
      // Search in venue name
      final name = (venue['name'] ?? '').toString().toLowerCase();
      if (name.contains(query)) return true;

      // Search in location
      final location = (venue['location'] ?? '').toString().toLowerCase();
      if (location.contains(query)) return true;

      // Search in description
      final description = (venue['description'] ?? '').toString().toLowerCase();
      if (description.contains(query)) return true;

      // Search in sports array
      if (venue['sports'] is List) {
        List<String> sports = List<String>.from(venue['sports']);
        for (String sport in sports) {
          if (sport.toLowerCase().contains(query)) return true;
        }
      }

      return false;
    }).toList();
  }

  Widget _buildVenueImage(String? imageUrl, {double? height, double? width}) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        height: height,
        width: width,
        color: Colors.grey[200],
        child: Icon(
          Icons.location_on,
          size: 50,
          color: Colors.grey[500],
        ),
      );
    }

    // Check if it's a base64 data URL
    if (imageUrl.startsWith('data:image')) {
      try {
        // Extract base64 string
        final base64String = imageUrl.split(',')[1];
        final bytes = base64Decode(base64String);

        return Image.memory(
          bytes,
          height: height,
          width: width,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: height,
              width: width,
              color: Colors.grey[200],
              child: Icon(
                Icons.location_on,
                size: 50,
                color: Colors.grey[500],
              ),
            );
          },
        );
      } catch (e) {
        print('Error decoding base64 image: $e');
        return Container(
          height: height,
          width: width,
          color: Colors.grey[200],
          child: Icon(
            Icons.error,
            size: 50,
            color: Colors.grey[500],
          ),
        );
      }
    }

    // Regular network URL
    return Image.network(
      imageUrl,
      height: height,
      width: width,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: height,
          width: width,
          color: Colors.grey[200],
          child: Icon(
            Icons.location_on,
            size: 50,
            color: Colors.grey[500],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildResultsHeader(),
          Expanded(
            child: _buildSearchResults(),
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
        'Search Venues',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search venues, locations, sports...',
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
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear, color: Colors.grey),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          onSubmitted: _performSearch,
          onChanged: (value) {
            // Debounce search - only search when user stops typing for 500ms
            setState(() {});
            Future.delayed(const Duration(milliseconds: 500), () {
              if (value == _searchController.text) {
                _performSearch(value);
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildResultsHeader() {
    if (_currentQuery.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _isSearching
                  ? 'Searching...'
                  : '${_searchResults.length} results for "$_currentQuery"',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          if (_searchResults.isNotEmpty)
            GestureDetector(
              onTap: _showSortOptions,
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

  Widget _buildSearchResults() {
    if (_currentQuery.isEmpty) {
      return _buildSearchSuggestions();
    }

    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return _buildNoResults();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        return _buildVenueCard(_searchResults[index]);
      },
    );
  }

  Widget _buildSearchSuggestions() {
    final suggestions = [
      {'title': 'Badminton Courts', 'icon': Icons.sports_tennis, 'query': 'badminton'},
      {'title': 'Football Fields', 'icon': Icons.sports_soccer, 'query': 'football'},
      {'title': 'Basketball Courts', 'icon': Icons.sports_basketball, 'query': 'basketball'},
      {'title': 'Georgetown Area', 'icon': Icons.location_on, 'query': 'georgetown'},
      {'title': 'Bayan Lepas', 'icon': Icons.location_on, 'query': 'bayan lepas'},
      {'title': 'Indoor Facilities', 'icon': Icons.home, 'query': 'indoor'},
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Popular Searches',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          ...suggestions.map((suggestion) => _buildSuggestionTile(
            title: suggestion['title'] as String,
            icon: suggestion['icon'] as IconData,
            onTap: () {
              _searchController.text = suggestion['query'] as String;
              _performSearch(suggestion['query'] as String);
            },
          )),
        ],
      ),
    );
  }

  Widget _buildSuggestionTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFF8A50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: const Color(0xFFFF8A50),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2D3748),
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.grey,
          size: 16,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tileColor: Colors.white,
      ),
    );
  }

  Widget _buildNoResults() {
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
            'Try different keywords or check spelling',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              _searchController.clear();
              _performSearch('');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Clear Search',
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
            // Venue image - UPDATED
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
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: _buildVenueImage(venue['imageUrl'], height: 180, width: double.infinity),
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
                        final isHighlighted = sport.toLowerCase().contains(_currentQuery.toLowerCase());
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? const Color(0xFFFF8A50).withOpacity(0.2)
                                : const Color(0xFFFF8A50).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: isHighlighted
                                ? Border.all(color: const Color(0xFFFF8A50))
                                : null,
                          ),
                          child: Text(
                            sport,
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFFFF8A50),
                              fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
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

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
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
                leading: const Icon(Icons.star, color: Color(0xFFFF8A50)),
                title: const Text('Highest Rating'),
                onTap: () {
                  Navigator.pop(context);
                  _sortResults('rating');
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_money, color: Color(0xFFFF8A50)),
                title: const Text('Lowest Price'),
                onTap: () {
                  Navigator.pop(context);
                  _sortResults('price');
                },
              ),
              ListTile(
                leading: const Icon(Icons.location_on, color: Color(0xFFFF8A50)),
                title: const Text('Name A-Z'),
                onTap: () {
                  Navigator.pop(context);
                  _sortResults('name');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _sortResults(String sortBy) {
    setState(() {
      switch (sortBy) {
        case 'rating':
          _searchResults.sort((a, b) => (b['rating'] ?? 0.0).compareTo(a['rating'] ?? 0.0));
          break;
        case 'price':
          _searchResults.sort((a, b) => (a['pricePerHour'] ?? 0).compareTo(b['pricePerHour'] ?? 0));
          break;
        case 'name':
          _searchResults.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
          break;
      }
    });
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