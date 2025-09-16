import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'coaching_page.dart';
import 'venues_page.dart';
import 'my_bookings_page.dart';
import 'profile_page.dart';
import 'search_results_page.dart';
import 'notifications_page.dart';
import 'services/notification_service.dart';
import 'services/messaging_service.dart';
import 'chats_list_page.dart';
import 'search_results_page.dart';

class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({Key? key, required this.userName}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _currentUserRole = 'player';

  // Add these for real-time user data
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  StreamSubscription<int>? _notificationCountSubscription;
  StreamSubscription<int>? _messageCountSubscription;
  String _currentUserName = '';
  String _currentUserEmail = '';
  int _unreadNotificationCount = 0;
  int _unreadMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _currentUserName = widget.userName;
    _listenToUserChanges();
    _listenToNotificationCount();
    _listenToMessageCount();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _notificationCountSubscription?.cancel();
    _messageCountSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToUserChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserEmail = user.email ?? '';
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((docSnapshot) {
        if (docSnapshot.exists && mounted) {
          final userData = docSnapshot.data();
          setState(() {
            _currentUserName = userData?['name'] ??
                user.displayName ??
                user.email?.split('@')[0] ??
                'User';
            _currentUserRole = userData?['role'] ?? 'player';
          });
        }
      });
    }
  }

  void _listenToNotificationCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _notificationCountSubscription = NotificationService.getUnreadCount(user.uid)
          .listen((count) {
        if (mounted) {
          setState(() {
            _unreadNotificationCount = count;
          });
        }
      });
    }
  }

  void _listenToMessageCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _messageCountSubscription = MessagingService.getUnreadMessagesCount(
          user.uid,
          _currentUserRole
      ).listen((count) {
        if (mounted) {
          setState(() {
            _unreadMessageCount = count;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with profile and notification
                    _buildHeader(),

                    const SizedBox(height: 30),

                    // Search bar
                    _buildSearchBar(),

                    const SizedBox(height: 35),

                    // Sports categories
                    _buildSportsCategories(),

                    const SizedBox(height: 40),

                    // Main action buttons (Coaching, Booking, Tournament)
                    _buildMainActionButtons(),

                    const SizedBox(height: 40),

                    // Venues near you section
                    _buildVenuesSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }


  Widget _buildHeader() {
    return Row(
      children: [
        // Profile circle (tappable for profile/logout menu)
        GestureDetector(
          onTap: _showProfileMenu,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF8A50).withOpacity(0.2),
                  const Color(0xFFE8751A).withOpacity(0.1),
                ],
              ),
              border: Border.all(
                color: const Color(0xFFFF8A50).withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8A50).withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.person,
              color: Color(0xFFFF8A50),
              size: 24,
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Greeting text - now uses real-time data
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, $_currentUserName!',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              Text(
                'Ready to get active?',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Notification bell with badge
        GestureDetector(
          onTap: _handleNotificationTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(
                    Icons.notifications_outlined,
                    color: Color(0xFF2D3748),
                    size: 20,
                  ),
                ),
                // Badge for unread notifications
                if (_unreadNotificationCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8A50),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8A50).withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        _unreadNotificationCount > 99
                            ? '99+'
                            : _unreadNotificationCount.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search sports & venues...',
          hintStyle: TextStyle(
            color: Colors.grey[500],
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8A50), Color(0xFFE8751A)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.search,
              color: Colors.white,
              size: 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SearchResultsPage(initialQuery: value.trim()),
              ),
            );
          }
        },
        onTap: () {
          // Alternative: Navigate to search page when tapped
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SearchResultsPage(initialQuery: ''),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSportsCategories() {
    final sports = [
      {'name': 'Badminton', 'icon': Icons.sports_tennis, 'color': const Color(0xFF4CAF50)},
      {'name': 'Football', 'icon': Icons.sports_soccer, 'color': const Color(0xFF2196F3)},
      {'name': 'Basketball', 'icon': Icons.sports_basketball, 'color': const Color(0xFFFF9800)},
      {'name': 'Pickleball', 'icon': Icons.sports_baseball, 'color': const Color(0xFF9C27B0)},
      {'name': 'Hockey', 'icon': Icons.sports_hockey, 'color': const Color(0xFFE91E63)},
    ];

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sports.length,
        itemBuilder: (context, index) {
          final sport = sports[index];
          return Container(
            margin: EdgeInsets.only(right: index == sports.length - 1 ? 0 : 16),
            child: GestureDetector(
              onTap: () => _handleSportTap(sport['name'] as String),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (sport['color'] as Color).withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      sport['icon'] as IconData,
                      color: sport['color'] as Color,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sport['name'] as String,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainActionButtons() {
    final actions = [
      {
        'title': 'Find Coach',
        'subtitle': 'Book training',
        'icon': Icons.school_outlined,
        'gradient': [const Color(0xFF4CAF50), const Color(0xFF66BB6A)],
      },
      {
        'title': 'Book Venue',
        'subtitle': 'Reserve courts',
        'icon': Icons.place_outlined,
        'gradient': [const Color(0xFF2196F3), const Color(0xFF42A5F5)],
      },
      {
        'title': 'Tournaments',
        'subtitle': 'Join events',
        'icon': Icons.emoji_events_outlined,
        'gradient': [const Color(0xFFFF9800), const Color(0xFFFFB74D)],
      },
    ];

    return Row(
      children: actions.map((action) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: _buildActionCard(
              title: action['title'] as String,
              subtitle: action['subtitle'] as String,
              icon: action['icon'] as IconData,
              gradient: action['gradient'] as List<Color>,
              onTap: () => _handleActionTap(action['title'] as String),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenuesSection() {
    return Column(
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Popular Venues',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3748),
              ),
            ),
            GestureDetector(
              onTap: _handleShowMoreVenues,
              child: const Text(
                'View all',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFFF8A50),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Show sample venues message
        Container(
          height: 260,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_on,
                  size: 60,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Popular Venues Coming Soon',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap "Book Venue" above to explore all available venues',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _handleActionTap('Book Venue'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Browse Venues',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
        onTap: _onBottomNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFFF8A50),
        unselectedItemColor: Colors.grey[500],
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.chat_bubble_outline),
                if (_unreadMessageCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF8A50),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _unreadMessageCount > 99 ? '99+' : _unreadMessageCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: Stack(
              children: [
                const Icon(Icons.chat_bubble),
                if (_unreadMessageCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF8A50),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _unreadMessageCount > 99 ? '99+' : _unreadMessageCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Bookings',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // Event handlers
  void _handleSearch(String query) {
    if (query.trim().isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SearchResultsPage(initialQuery: query.trim()),
        ),
      );
    }
  }

  void _handleSportTap(String sport) {
    print('Tapped on sport: $sport');
    // Navigate to search page with the selected sport as query
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchResultsPage(initialQuery: sport.toLowerCase()),
      ),
    );
  }

  void _handleActionTap(String actionType) {
    switch (actionType) {
      case 'Find Coach':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CoachingPage(),
          ),
        );
        break;
      case 'Book Venue':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const VenuesPage(),
          ),
        );
        break;
      case 'Tournaments':
        print('Navigate to Tournaments');
        // TODO: Navigate to tournaments page
        break;
    }
  }

  void _handleShowMoreVenues() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VenuesPage(),
      ),
    );
  }

  void _handleVenueTap(String venueName) {
    print('Tapped on venue: $venueName');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VenuesPage(),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
      // Already on Home
        break;
      case 1:
      // Navigate to Search
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SearchResultsPage(initialQuery: ''),
          ),
        );
        break;
      case 2:
      // Navigate to Messages
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ChatsListPage(),
          ),
        );
        break;
      case 3:
      // Navigate to My Bookings
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const MyBookingsPage(),
          ),
        );
        break;
      case 4:
        _showProfileMenu();
        break;
    }
  }

  void _handleNotificationTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationsPage(),
      ),
    );
  }

  void _showProfileMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5, // Fixed height instead of DraggableScrollableSheet
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 20),

              // User info section (fixed at top)
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFF8A50).withOpacity(0.2),
                          const Color(0xFFE8751A).withOpacity(0.1),
                        ],
                      ),
                    ),
                    child: Icon(
                      _currentUserRole == 'coach' ? Icons.school : Icons.person,
                      color: const Color(0xFFFF8A50),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _currentUserName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2D3748),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _currentUserRole == 'coach'
                                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _currentUserRole == 'coach' ? 'Coach' : 'Player',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _currentUserRole == 'coach'
                                      ? const Color(0xFF4CAF50)
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          _currentUserEmail,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // Menu options - using Column instead of ListView for better control
              Expanded(
                child: Column(
                  children: [
                    _buildMenuOption(
                      icon: Icons.calendar_today,
                      title: 'My Bookings',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MyBookingsPage(),
                          ),
                        );
                      },
                    ),

                    _buildMenuOption(
                      icon: Icons.notifications,
                      title: 'Notifications',
                      subtitle: _unreadNotificationCount > 0 ? '$_unreadNotificationCount unread' : null,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotificationsPage(),
                          ),
                        );
                      },
                      isHighlighted: _unreadNotificationCount > 0,
                    ),

                    _buildMenuOption(
                      icon: Icons.chat_bubble_outline,
                      title: 'Messages',
                      subtitle: _unreadMessageCount > 0 ? '$_unreadMessageCount unread' : null,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ChatsListPage(),
                          ),
                        );
                      },
                      isHighlighted: _unreadMessageCount > 0,
                    ),

                    _buildMenuOption(
                      icon: Icons.person_outline,
                      title: 'Edit Profile',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ProfilePage(),
                          ),
                        );
                      },
                    ),

                    // Show coach-specific options for coaches only
                    if (_currentUserRole == 'coach')
                      _buildMenuOption(
                        icon: Icons.dashboard_outlined,
                        title: 'Coach Dashboard',
                        subtitle: 'Manage your coaching',
                        onTap: () {
                          Navigator.pop(context);
                          print('Coach Dashboard');
                        },
                        isHighlighted: true,
                      ),


                    // Logout button - same styling as other menu items
                    _buildMenuOption(
                      icon: Icons.logout,
                      title: 'Logout',
                      onTap: () {
                        Navigator.pop(context);
                        _handleLogout();
                      },
                      isDestructive: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool isHighlighted = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isHighlighted ? const Color(0xFFFF8A50).withOpacity(0.05) : null,
        border: isHighlighted ? Border.all(color: const Color(0xFFFF8A50).withOpacity(0.2)) : null,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDestructive
              ? Colors.red
              : isHighlighted
              ? const Color(0xFFFF8A50)
              : const Color(0xFF2D3748),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDestructive
                ? Colors.red
                : isHighlighted
                ? const Color(0xFFFF8A50)
                : const Color(0xFF2D3748),
            fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: isHighlighted ? const Color(0xFFFF8A50) : Colors.grey[600],
          ),
        )
            : null,
        trailing: isHighlighted
            ? Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Color(0xFFFF8A50),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_forward,
            color: Colors.white,
            size: 16,
          ),
        )
            : null,
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error logging out: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}