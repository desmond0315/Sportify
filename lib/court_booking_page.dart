import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'my_bookings_page.dart';
import 'services/notification_service.dart';
import '../utils/timezone_helper.dart';
import 'venue_payment_page.dart';

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
  int _selectedDuration = 1;
  Map<String, dynamic>? _selectedCourt;
  bool _isLoading = false;

  Map<String, bool> _timeSlotAvailability = {};
  Map<String, int> _maxDurationPerSlot = {};
  List<Map<String, dynamic>> _availableCourts = [];
  Map<String, dynamic>? _currentUserData;

  List<String> _timeSlots = [];

  @override
  void initState() {
    super.initState();
    final malaysiaTime = TimezoneHelper.getMalaysiaTime();
    _selectedDate = DateTime(malaysiaTime.year, malaysiaTime.month, malaysiaTime.day);

    _timeSlots = _generateTimeSlotsFromOperatingHours();

    _checkTimeSlotAvailability();
    _loadCurrentUserData();
  }

  List<String> _generateTimeSlotsFromOperatingHours() {
    if (widget.venue['operatingHours'] == null) {
      return [
        '06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
        '12:00', '13:00', '14:00', '15:00', '16:00', '17:00',
        '18:00', '19:00', '20:00', '21:00', '22:00',
      ];
    }

    final days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final today = days[_selectedDate.weekday - 1];
    final todayHours = widget.venue['operatingHours'][today];

    if (todayHours == null || todayHours['closed'] == true) {
      return [];
    }

    final openTime = todayHours['open'] ?? '';
    final closeTime = todayHours['close'] ?? '';

    if (openTime.isEmpty || closeTime.isEmpty) {
      return [];
    }

    final openHour = int.parse(openTime.split(':')[0]);
    final closeHour = int.parse(closeTime.split(':')[0]);

    List<String> slots = [];
    for (int hour = openHour; hour < closeHour; hour++) {
      slots.add('${hour.toString().padLeft(2, '0')}:00');
    }

    return slots;
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
        }
      } catch (e) {
        print('Error loading user data: $e');
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

      QuerySnapshot bookingsSnapshot = await _firestore
          .collection('bookings')
          .where('venueId', isEqualTo: widget.venue['id'])
          .where('date', isEqualTo: dateStr)
          .where('status', whereIn: ['confirmed', 'pending']).get();

      print('Found ${bookingsSnapshot.docs.length} bookings');

      // Get blocked time slots
      QuerySnapshot blockedSlotsSnapshot = await _firestore
          .collection('blockedTimeSlots')
          .where('venueId', isEqualTo: widget.venue['id'])
          .where('date', isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .get();

      // DEBUG: Print each blocked slot
      for (var doc in blockedSlotsSnapshot.docs) {
        final blockData = doc.data() as Map<String, dynamic>;
        print('BLOCKED: Court "${blockData['courtId']}", Time: '
            '${blockData['timeSlot']}, Duration: ${blockData['duration']}h, Reason: ${blockData['reason']}');
      }

      Map<String, bool> availability = {};
      Map<String, int> maxDuration = {};

      for (String slot in _timeSlots) {
        availability[slot] = true;
        maxDuration[slot] = 0;
      }

      // Process blocked time slots
      Map<String, Set<String>> blockedCourtsPerSlot = {};

      for (var doc in blockedSlotsSnapshot.docs) {
        final blockData = doc.data() as Map<String, dynamic>;
        final timeSlot = blockData['timeSlot'];
        final duration = blockData['duration'] ?? 1;
        final courtId = blockData['courtId'];

        if (timeSlot != null && courtId != null) {
          final startIndex = _timeSlots.indexOf(timeSlot);
          if (startIndex != -1) {
            for (int i = 0; i < duration && (startIndex + i) < _timeSlots.length; i++) {
              final slot = _timeSlots[startIndex + i];
              if (!blockedCourtsPerSlot.containsKey(slot)) {
                blockedCourtsPerSlot[slot] = {};
              }
              blockedCourtsPerSlot[slot]!.add(courtId);
              print('Slot $slot: Blocked court "$courtId"');
            }
          }
        }
      }

      Map<String, int> slotBookingCount = {};
      for (var doc in bookingsSnapshot.docs) {
        final bookingData = doc.data() as Map<String, dynamic>;
        final timeSlot = bookingData['timeSlot'];
        final duration = bookingData['duration'] ?? 1;

        if (timeSlot != null) {
          final startIndex = _timeSlots.indexOf(timeSlot);
          if (startIndex != -1) {
            for (int i = 0; i < duration && (startIndex + i) < _timeSlots.length; i++) {
              final slot = _timeSlots[startIndex + i];
              slotBookingCount[slot] = (slotBookingCount[slot] ?? 0) + 1;
            }
          }
        }
      }

      for (String slot in _timeSlots) {
        final bookedCourts = slotBookingCount[slot] ?? 0;
        final blockedCourts = blockedCourtsPerSlot[slot]?.length ?? 0;
        final totalUnavailable = bookedCourts + blockedCourts;

        if (totalUnavailable >= widget.courts.length) {
          availability[slot] = false;
          print('Slot $slot: UNAVAILABLE (Booked: $bookedCourts, Blocked: $blockedCourts, Total courts: ${widget.courts.length})');
        }
      }

      for (int i = 0; i < _timeSlots.length; i++) {
        final slot = _timeSlots[i];
        if ((availability[slot] ?? false) && !TimezoneHelper.isTimeSlotInPast(_selectedDate, slot)) {
          int consecutiveHours = 0;
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

      List<String> requiredTimeSlots = [];
      for (int i = 0; i < _selectedDuration; i++) {
        if (startTimeIndex + i < _timeSlots.length) {
          requiredTimeSlots.add(_timeSlots[startTimeIndex + i]);
        }
      }

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

      // Get blocked courts
      List<String> blockedCourtIds = [];
      for (String timeSlot in requiredTimeSlots) {
        QuerySnapshot blockedSnapshot = await _firestore
            .collection('blockedTimeSlots')
            .where('venueId', isEqualTo: widget.venue['id'])
            .where('date', isEqualTo: dateStr)
            .where('timeSlot', isEqualTo: timeSlot)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in blockedSnapshot.docs) {
          final blockData = doc.data() as Map<String, dynamic>;
          final courtId = blockData['courtId'];
          if (courtId != null) {
            blockedCourtIds.add(courtId);
            print('Found blocked court: "$courtId"');
          }
        }
      }

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

            if (!(ourEndIndex <= bookingStartIndex || startTimeIndex >= bookingEndIndex)) {
              bookedCourtIds.add(courtId);
            }
          }
        }
      }

      QuerySnapshot overlappingBlocks = await _firestore
          .collection('blockedTimeSlots')
          .where('venueId', isEqualTo: widget.venue['id'])
          .where('date', isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in overlappingBlocks.docs) {
        final blockData = doc.data() as Map<String, dynamic>;
        final blockStartTime = blockData['timeSlot'];
        final blockDuration = blockData['duration'] ?? 1;
        final courtId = blockData['courtId'];

        if (blockStartTime != null && courtId != null) {
          final blockStartIndex = _timeSlots.indexOf(blockStartTime);
          if (blockStartIndex != -1) {
            final blockEndIndex = blockStartIndex + blockDuration;
            final ourEndIndex = startTimeIndex + _selectedDuration;

            if (!(ourEndIndex <= blockStartIndex || startTimeIndex >= blockEndIndex)) {
              blockedCourtIds.add(courtId);
            }
          }
        }
      }

      final allUnavailableCourtIds = [...bookedCourtIds, ...blockedCourtIds].toSet();


      List<Map<String, dynamic>> availableCourts = widget.courts.where((court) {
        final isUnavailable = allUnavailableCourtIds.contains(court['id']);
        final isActive = court['isActive'] ?? true;

        if (isUnavailable) {
          print('Court "${court['id']}" is UNAVAILABLE');
        } else if (isActive) {
          print('Court "${court['id']}" is AVAILABLE');
        }

        return !isUnavailable && isActive;
      }).toList();


      setState(() {
        _availableCourts = availableCourts;
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
                      // Regenerate time slots for the new date
                      _timeSlots = _generateTimeSlotsFromOperatingHours();
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

          // Show closed message OR time slots grid
          if (_timeSlots.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.red[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Venue is closed on this day',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
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
                      _selectedDuration = 1;
                      _selectedCourt = null;
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

          if (TimezoneHelper.isToday(_selectedDate) && _timeSlots.isNotEmpty)
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

                // Get court name - use courtName if available, otherwise fallback to Court + number
                final courtName = court['courtName'] ?? 'Court ${court['courtNumber'] ?? 'N/A'}';

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
                                courtName,  // FIXED: Now uses actual court name
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

    // Get court name properly
    final courtName = _selectedCourt!['courtName'] ?? 'Court ${_selectedCourt!['courtNumber'] ?? 'N/A'}';

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
                _buildSummaryRow('Court', courtName),  // FIXED: Now shows actual court name
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

      // Get court name properly
      final courtName = _selectedCourt!['courtName'] ?? 'Court ${_selectedCourt!['courtNumber'] ?? 'N/A'}';

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
        'courtName': courtName,
        'courtType': _selectedCourt!['type'] ?? 'Standard Court',
        'date': dateStr,
        'timeSlot': _selectedTimeSlot,
        'endTime': _getEndTimeForDuration(_selectedTimeSlot!, _selectedDuration),
        'duration': _selectedDuration,
        'pricePerHour': pricePerHour,
        'totalPrice': totalPrice,
        'status': 'pending_payment', // Changed from 'confirmed' to 'pending_payment'
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
      bookingData['id'] = docRef.id;
      print('Booking created with ID: ${docRef.id}');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Navigate to payment page instead of showing success
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VenuePaymentPage(booking: bookingData),
          ),
        );
      }
    } catch (e) {
      print('Booking error: $e');

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