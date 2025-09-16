// Updated court_booking_page.dart with new flow: Date -> Time -> Duration -> Available Courts

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'my_bookings_page.dart';
import 'services/notification_service.dart';
import '../utils/timezone_helper.dart';

class CourtBookingPage extends StatefulWidget {
  final Map<String, dynamic> venue;
  final List<Map<String, dynamic>> courts;

  const CourtBookingPage({
    Key? key,
    required this.venue,
    required this.courts,
  }) : super(key: key);

  @override
  State<CourtBookingPage> createState() => _CourtBookingPageState();
}

class _CourtBookingPageState extends State<CourtBookingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DateTime _selectedDate = DateTime.now();
  String? _selectedTimeSlot;
  int _selectedDuration = 1; // Default 1 hour
  Map<String, dynamic>? _selectedCourt;
  bool _isLoading = false;

  Map<String, bool> _timeSlotAvailability = {};
  Map<String, int> _maxDurationPerSlot = {}; // Max consecutive hours available from each slot
  List<Map<String, dynamic>> _availableCourts = [];
  Map<String, dynamic>? _currentUserData;

  final List<String> _timeSlots = [
    '06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
    '12:00', '13:00', '14:00', '15:00', '16:00', '17:00',
    '18:00', '19:00', '20:00', '21:00', '22:00',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize with Malaysia current date
    final malaysiaTime = TimezoneHelper.getMalaysiaTime();
    _selectedDate = DateTime(malaysiaTime.year, malaysiaTime.month, malaysiaTime.day);

    _checkTimeSlotAvailability();
    _loadCurrentUserData();
  }

  Future<void> _loadCurrentUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          setState(() {
            _currentUserData = userDoc.data();
          });
        } else {
          // Create user document if it doesn't exist
          final userData = {
            'uid': user.uid,
            'name': user.displayName ?? user.email?.split('@')[0] ?? 'User',
            'email': user.email,
            'role': 'player',
            'createdAt': FieldValue.serverTimestamp(),
            'isActive': true,
          };

          await _firestore.collection('users').doc(user.uid).set(userData);
          setState(() {
            _currentUserData = userData;
          });
          print('Created user document for booking: ${user.uid}');
        }
      } catch (e) {
        print('Error loading user data: $e');
        // Fallback user data
        setState(() {
          _currentUserData = {
            'uid': user.uid,
            'name': user.displayName ?? user.email?.split('@')[0] ?? 'User',
            'email': user.email,
            'role': 'player',
          };
        });
      }
    }
  }

  Future<void> _checkTimeSlotAvailability() async {
    try {
      final dateStr = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

      // Get all bookings for this venue and date
      QuerySnapshot bookingsSnapshot = await _firestore
          .collection('bookings')
          .where('venueId', isEqualTo: widget.venue['id'])
          .where('date', isEqualTo: dateStr)
          .where('status', whereIn: ['confirmed', 'pending']).get();

      Map<String, bool> availability = {};
      Map<String, int> maxDuration = {};

      // Initialize all slots as available
      for (String slot in _timeSlots) {
        availability[slot] = true;
        maxDuration[slot] = 0;
      }

      // Count bookings per time slot to determine availability
      Map<String, int> slotBookingCount = {};
      for (var doc in bookingsSnapshot.docs) {
        final bookingData = doc.data() as Map<String, dynamic>;
        final timeSlot = bookingData['timeSlot'];
        final duration = bookingData['duration'] ?? 1;

        if (timeSlot != null) {
          final startIndex = _timeSlots.indexOf(timeSlot);
          if (startIndex != -1) {
            // Mark all slots covered by this booking as unavailable
            for (int i = 0; i < duration && (startIndex + i) < _timeSlots.length; i++) {
              final slot = _timeSlots[startIndex + i];
              slotBookingCount[slot] = (slotBookingCount[slot] ?? 0) + 1;
            }
          }
        }
      }

      // Mark slots as unavailable if all courts are booked
      for (String slot in _timeSlots) {
        final bookedCourts = slotBookingCount[slot] ?? 0;
        if (bookedCourts >= widget.courts.length) {
          availability[slot] = false;
        }
      }

      // Calculate maximum consecutive duration for each slot
      for (int i = 0; i < _timeSlots.length; i++) {
        final slot = _timeSlots[i];
        if ((availability[slot] ?? false) && !TimezoneHelper.isTimeSlotInPast(_selectedDate, slot)) {
          int consecutiveHours = 0;
          // Check how many consecutive hours are available from this slot
          for (int j = i; j < _timeSlots.length; j++) {
            final checkSlot = _timeSlots[j];
            if ((availability[checkSlot] ?? false) && !TimezoneHelper.isTimeSlotInPast(_selectedDate, checkSlot)) {
              consecutiveHours++;
            } else {
              break;
            }
          }
          maxDuration[slot] = consecutiveHours;
        } else {
          maxDuration[slot] = 0;
          availability[slot] = false;
        }
      }

      // Mark past time slots as unavailable using Malaysia timezone
      for (String slot in _timeSlots) {
        if (TimezoneHelper.isTimeSlotInPast(_selectedDate, slot)) {
          availability[slot] = false;
          maxDuration[slot] = 0;
        }
      }

      setState(() {
        _timeSlotAvailability = availability;
        _maxDurationPerSlot = maxDuration;
      });
    } catch (e) {
      print('Error checking time slot availability: $e');
    }
  }

  Future<void> _checkAvailableCourts() async {
    if (_selectedTimeSlot == null) return;

    try {
      final dateStr = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      final startTimeIndex = _timeSlots.indexOf(_selectedTimeSlot!);

      if (startTimeIndex == -1) return;

      // Get all time slots that would be covered by the selected duration
      List<String> requiredTimeSlots = [];
      for (int i = 0; i < _selectedDuration; i++) {
        if (startTimeIndex + i < _timeSlots.length) {
          requiredTimeSlots.add(_timeSlots[startTimeIndex + i]);
        }
      }

      // Get bookings for all required time slots
      List<String> bookedCourtIds = [];
      for (String timeSlot in requiredTimeSlots) {
        QuerySnapshot bookingsSnapshot = await _firestore
            .collection('bookings')
            .where('venueId', isEqualTo: widget.venue['id'])
            .where('date', isEqualTo: dateStr)
            .where('timeSlot', isEqualTo: timeSlot)
            .where('status', whereIn: ['confirmed', 'pending']).get();

        for (var doc in bookingsSnapshot.docs) {
          final bookingData = doc.data() as Map<String, dynamic>;
          final courtId = bookingData['courtId'];
          if (courtId != null) {
            bookedCourtIds.add(courtId);
          }
        }
      }

      // Also check for bookings that overlap with our desired time range
      QuerySnapshot overlappingBookings = await _firestore
          .collection('bookings')
          .where('venueId', isEqualTo: widget.venue['id'])
          .where('date', isEqualTo: dateStr)
          .where('status', whereIn: ['confirmed', 'pending']).get();

      for (var doc in overlappingBookings.docs) {
        final bookingData = doc.data() as Map<String, dynamic>;
        final bookingStartTime = bookingData['timeSlot'];
        final bookingDuration = bookingData['duration'] ?? 1;
        final courtId = bookingData['courtId'];

        if (bookingStartTime != null && courtId != null) {
          final bookingStartIndex = _timeSlots.indexOf(bookingStartTime);
          if (bookingStartIndex != -1) {
            final bookingEndIndex = bookingStartIndex + bookingDuration;
            final ourEndIndex = startTimeIndex + _selectedDuration;

            // Check if there's any overlap
            if (!(ourEndIndex <= bookingStartIndex || startTimeIndex >= bookingEndIndex)) {
              bookedCourtIds.add(courtId);
            }
          }
        }
      }

      // Convert to Set to remove duplicates, then back to List
      final uniqueBookedCourtIds = bookedCourtIds.toSet();

      // Filter available courts
      List<Map<String, dynamic>> availableCourts = widget.courts.where((court) {
        return !uniqueBookedCourtIds.contains(court['id']) && (court['isActive'] ?? true);
      }).toList();

      setState(() {
        _availableCourts = availableCourts;
        // Reset selected court if it's no longer available
        if (_selectedCourt != null && !availableCourts.any((court) => court['id'] == _selectedCourt!['id'])) {
          _selectedCourt = null;
        }
      });
    } catch (e) {
      print('Error checking available courts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: widget.courts.isEmpty
          ? _buildNoCourtsState()
          : Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildVenueHeader(),
                  _buildDateSelection(),
                  _buildTimeSlotSelection(),
                  if (_selectedTimeSlot != null) _buildDurationSelection(),
                  if (_selectedTimeSlot != null) _buildCourtSelection(),
                  _buildBookingSummary(),
                ],
              ),
            ),
          ),
          _buildBookingButton(),
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
        'Book Court',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Malaysia Time',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  TimezoneHelper.formatMalaysiaTime(DateTime.now()),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoCourtsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sports_tennis, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No Courts Available',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'This venue currently has no courts for booking',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: widget.venue['imageUrl'] != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.venue['imageUrl'],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.location_on, color: Colors.grey[500], size: 30);
                },
              ),
            )
                : Icon(Icons.location_on, color: Colors.grey[500], size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.venue['name'] ?? 'Unknown Venue',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2D3748)),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.venue['location'] ?? 'Location not specified',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelection() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Date', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2D3748))),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              itemBuilder: (context, index) {
                final availableDates = TimezoneHelper.getAvailableBookingDates();
                final date = availableDates[index];

                final isSelected = _selectedDate.day == date.day &&
                    _selectedDate.month == date.month &&
                    _selectedDate.year == date.year;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                      _selectedTimeSlot = null;
                      _selectedDuration = 1; // Reset duration
                      _selectedCourt = null;
                      _availableCourts = [];
                    });
                    _checkTimeSlotAvailability();
                  },
                  child: Container(
                    width: 70,
                    margin: EdgeInsets.only(right: index == 13 ? 0 : 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFF8A50) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getWeekdayName(date.weekday),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.white : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : const Color(0xFF2D3748),
                          ),
                        ),
                        Text(
                          _getMonthName(date.month),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? Colors.white : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getWeekdayName(int weekday) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildTimeSlotSelection() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Available Time Slots', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2D3748))),
              const Spacer(),
              if (TimezoneHelper.isToday(_selectedDate))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
            ),
            itemCount: _timeSlots.length,
            itemBuilder: (context, index) {
              final timeSlot = _timeSlots[index];
              final isAvailable = _timeSlotAvailability[timeSlot] ?? true;
              final isSelected = _selectedTimeSlot == timeSlot;
              final isPastTime = TimezoneHelper.isTimeSlotInPast(_selectedDate, timeSlot);

              return GestureDetector(
                onTap: isAvailable && !isPastTime
                    ? () {
                  setState(() {
                    _selectedTimeSlot = timeSlot;
                    _selectedDuration = 1; // Reset duration to 1 hour
                    _selectedCourt = null; // Reset court selection
                  });
                  _checkAvailableCourts();
                }
                    : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: !isAvailable || isPastTime
                        ? Colors.grey[200]
                        : isSelected
                        ? const Color(0xFFFF8A50)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: !isAvailable || isPastTime
                          ? Colors.grey[300]!
                          : isSelected
                          ? const Color(0xFFFF8A50)
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          timeSlot,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: !isAvailable || isPastTime
                                ? Colors.grey[500]
                                : isSelected
                                ? Colors.white
                                : const Color(0xFF2D3748),
                          ),
                        ),
                      ),
                      if (isPastTime && TimezoneHelper.isToday(_selectedDate))
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.access_time,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (TimezoneHelper.isToday(_selectedDate))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Past time slots are disabled. Current Malaysia time: ${TimezoneHelper.formatMalaysiaTime(DateTime.now())}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
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

  Widget _buildDurationSelection() {
    final maxDuration = _maxDurationPerSlot[_selectedTimeSlot] ?? 1;

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Select Duration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2D3748))
          ),
          const SizedBox(height: 16),

          // Duration slider
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_selectedDuration hour${_selectedDuration > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF8A50),
                    ),
                  ),
                  Text(
                    'Max: $maxDuration hour${maxDuration > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFFFF8A50),
                  inactiveTrackColor: Colors.grey[300],
                  thumbColor: const Color(0xFFFF8A50),
                  overlayColor: const Color(0xFFFF8A50).withOpacity(0.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _selectedDuration.toDouble(),
                  min: 1,
                  max: maxDuration.toDouble(),
                  divisions: maxDuration - 1 > 0 ? maxDuration - 1 : null,
                  onChanged: (value) {
                    setState(() {
                      _selectedDuration = value.round();
                      _selectedCourt = null; // Reset court selection when duration changes
                    });
                    _checkAvailableCourts();
                  },
                ),
              ),

              // Duration options chips
              const SizedBox(height: 16),
              Row(
                children: [
                  for (int i = 1; i <= maxDuration && i <= 6; i++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i == maxDuration || i == 6 ? 0 : 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDuration = i;
                              _selectedCourt = null;
                            });
                            _checkAvailableCourts();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedDuration == i
                                  ? const Color(0xFFFF8A50)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedDuration == i
                                    ? const Color(0xFFFF8A50)
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              '${i}h',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _selectedDuration == i
                                    ? Colors.white
                                    : const Color(0xFF2D3748),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Time range display
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF8A50).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  color: Color(0xFFFF8A50),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Booking time: $_selectedTimeSlot - ${_getEndTimeForDuration(_selectedTimeSlot!, _selectedDuration)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF8A50),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtSelection() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Courts (${_availableCourts.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2D3748)),
          ),
          const SizedBox(height: 16),
          if (_availableCourts.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Icon(Icons.sports_tennis, size: 40, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'No courts available',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All courts are booked for this time slot',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _availableCourts.map((court) {
                final isSelected = _selectedCourt?['id'] == court['id'];

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCourt = court;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFF8A50).withOpacity(0.1) : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFF8A50) : Colors.grey[200]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFF8A50) : Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.sports_tennis,
                            color: isSelected ? Colors.white : Colors.grey[600],
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Court ${court['courtNumber'] ?? 'N/A'}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                court['type'] ?? 'Standard Court',
                                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'RM ${court['pricePerHour'] ?? widget.venue['pricePerHour'] ?? 0}/hr',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBookingSummary() {
    if (_selectedTimeSlot == null || _selectedCourt == null) {
      return const SizedBox.shrink();
    }

    final pricePerHour = _selectedCourt!['pricePerHour'] ?? widget.venue['pricePerHour'] ?? 0;
    final totalPrice = pricePerHour * _selectedDuration;

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Booking Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2D3748))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _buildSummaryRow('Venue', widget.venue['name'] ?? 'Unknown'),
                _buildSummaryRow('Court', 'Court ${_selectedCourt!['courtNumber'] ?? 'N/A'}'),
                _buildSummaryRow('Date', _formatDate(_selectedDate)),
                _buildSummaryRow('Time', '$_selectedTimeSlot - ${_getEndTimeForDuration(_selectedTimeSlot!, _selectedDuration)}'),
                _buildSummaryRow('Duration', '$_selectedDuration hour${_selectedDuration > 1 ? 's' : ''}'),
                _buildSummaryRow('Rate', 'RM $pricePerHour/hour'),
                const Divider(height: 24),
                _buildSummaryRow('Total', 'RM $totalPrice', isTotal: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: isTotal ? const Color(0xFF2D3748) : Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: isTotal ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _getEndTime(String startTime) {
    final hour = int.parse(startTime.split(':')[0]);
    final endHour = (hour + 1) % 24;
    return '${endHour.toString().padLeft(2, '0')}:00';
  }

  String _getEndTimeForDuration(String startTime, int duration) {
    final hour = int.parse(startTime.split(':')[0]);
    final endHour = (hour + duration) % 24;
    return '${endHour.toString().padLeft(2, '0')}:00';
  }

  Widget _buildBookingButton() {
    final canBook = _selectedTimeSlot != null && _selectedCourt != null;

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: canBook
              ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFF8A50), Color(0xFFFF6B35), Color(0xFFE8751A)],
          )
              : null,
          color: canBook ? null : Colors.grey[300],
        ),
        child: ElevatedButton(
          onPressed: canBook && !_isLoading ? _handleBooking : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isLoading
              ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 2.5,
            ),
          )
              : Text(
            canBook ? 'CONFIRM BOOKING' : _getButtonText(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: canBook ? Colors.white : Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  String _getButtonText() {
    if (_selectedTimeSlot == null) {
      return 'SELECT DATE & TIME';
    } else if (_selectedCourt == null) {
      return 'SELECT COURT';
    }
    return 'CONFIRM BOOKING';
  }

  Future<void> _handleBooking() async {
    if (_selectedCourt == null || _selectedTimeSlot == null) return;

    // Double-check if the selected time is still valid before booking
    if (TimezoneHelper.isTimeSlotInPast(_selectedDate, _selectedTimeSlot!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This time slot is no longer available. Please select a different time.'),
          backgroundColor: Colors.red,
        ),
      );
      // Refresh availability
      _checkTimeSlotAvailability();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'Please log in to make a booking';
      }

      // Ensure we have current user data
      if (_currentUserData == null) {
        await _loadCurrentUserData();
      }

      final dateStr = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      final pricePerHour = _selectedCourt!['pricePerHour'] ?? widget.venue['pricePerHour'] ?? 0;
      final totalPrice = pricePerHour * _selectedDuration;

      // Create booking datetime in Malaysia timezone for accurate scheduling
      final malaysiaTime = TimezoneHelper.getMalaysiaTime();
      final timeParts = _selectedTimeSlot!.split(':');
      final bookingDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );

      final bookingData = {
        'userId': user.uid,
        'userName': _currentUserData?['name'] ?? user.displayName ?? user.email?.split('@')[0] ?? 'User',
        'userEmail': user.email ?? '',
        'userPhone': _currentUserData?['phoneNumber'] ?? '',
        'venueId': widget.venue['id'],
        'venueName': widget.venue['name'] ?? 'Unknown Venue',
        'venueLocation': widget.venue['location'] ?? '',
        'courtId': _selectedCourt!['id'],
        'courtNumber': _selectedCourt!['courtNumber'] ?? 'N/A',
        'courtType': _selectedCourt!['type'] ?? 'Standard Court',
        'date': dateStr,
        'timeSlot': _selectedTimeSlot,
        'endTime': _getEndTimeForDuration(_selectedTimeSlot!, _selectedDuration),
        'duration': _selectedDuration,
        'pricePerHour': pricePerHour,
        'totalPrice': totalPrice,
        'status': 'confirmed',
        'paymentStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'bookingType': 'court',
        'notes': '',
        'isActive': true,
        'bookedInTimezone': 'Asia/Kuala_Lumpur',
        'bookedAtMalaysiaTime': TimezoneHelper.formatMalaysiaTime(malaysiaTime, format: 'dd/MM/yyyy HH:mm'),
      };

      print('Creating booking with data: $bookingData');

      final docRef = await _firestore.collection('bookings').add(bookingData);
      print('Booking created with ID: ${docRef.id}');

      // Create notification for successful booking
      await NotificationService.createBookingNotification(
        userId: user.uid,
        bookingType: 'court',
        title: 'Booking Confirmed!',
        message: 'Your court booking at ${widget.venue['name']} for ${_formatDate(_selectedDate)} at $_selectedTimeSlot has been confirmed.',
        bookingData: {
          'bookingId': docRef.id,
          'venueName': widget.venue['name'],
          'courtNumber': _selectedCourt!['courtNumber'],
          'date': dateStr,
          'timeSlot': _selectedTimeSlot,
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showBookingSuccessDialog();
      }
    } catch (e) {
      print('Booking error: $e');

      // Create notification for failed booking
      final user = _auth.currentUser;
      if (user != null) {
        await NotificationService.createNotification(
          userId: user.uid,
          type: 'booking',
          title: 'Booking Failed',
          message: 'There was an issue with your booking. Please try again or contact support.',
          priority: 'high',
        );
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showBookingSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                  child: const Icon(Icons.check, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Booking Confirmed!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF2D3748)),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your court has been successfully booked for ${_formatDate(_selectedDate)} from $_selectedTimeSlot to ${_getEndTimeForDuration(_selectedTimeSlot!, _selectedDuration)} ($_selectedDuration hour${_selectedDuration > 1 ? 's' : ''}) (Malaysia Time).',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close dialog
                          Navigator.of(context).pop(); // Go back to venue detail
                          Navigator.of(context).pop(); // Go back to venues list
                        },
                        child: const Text('Back to Venues', style: TextStyle(color: Color(0xFF2D3748), fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // Close dialog
                          Navigator.of(context).pop(); // Go back to venue detail
                          Navigator.of(context).pop(); // Go back to venues list
                          Navigator.of(context).pop(); // Go back to home
                          // Navigate to My Bookings
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MyBookingsPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8A50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('View Booking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}