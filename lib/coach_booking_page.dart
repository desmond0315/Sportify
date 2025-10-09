// Updated coach_booking_page.dart with Malaysia timezone support

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'my_bookings_page.dart';
import '../services/messaging_service.dart';
import 'services/notification_service.dart';
import '../utils/timezone_helper.dart'; // Add this import

class CoachBookingPage extends StatefulWidget {
  final Map<String, dynamic> coach;
  final List<Map<String, dynamic>> packages;

  const CoachBookingPage({
    Key? key,
    required this.coach,
    required this.packages,
  }) : super(key: key);

  @override
  State<CoachBookingPage> createState() => _CoachBookingPageState();
}

class _CoachBookingPageState extends State<CoachBookingPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedStartTime;
  String? _selectedEndTime;
  Map<String, dynamic>? _selectedPackage;
  String _bookingType = 'hourly'; // 'hourly' or 'package'
  bool _isLoading = false;

  Map<String, dynamic>? _currentUserData;
  Map<String, bool> _timeSlotAvailability = {};

  final List<String> _timeSlots = [
    '08:00', '09:00', '10:00', '11:00', '12:00', '13:00',
    '14:00', '15:00', '16:00', '17:00', '18:00', '19:00',
    '20:00', '21:00', '22:00',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize with Malaysia current date
    final malaysiaTime = TimezoneHelper.getMalaysiaTime();
    _selectedDate = DateTime(malaysiaTime.year, malaysiaTime.month, malaysiaTime.day);

    _loadCurrentUserData();
    _checkTimeSlotAvailability();
    if (widget.packages.isNotEmpty) {
      _selectedPackage = widget.packages[0];
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
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
          .collection('coach_appointments')
          .where('coachId', isEqualTo: widget.coach['id'])
          .where('date', isEqualTo: dateStr)
          .where('status', whereIn: ['confirmed', 'pending']).get();

      Map<String, bool> availability = {};
      for (String slot in _timeSlots) {
        availability[slot] = true;
      }

      for (var doc in bookingsSnapshot.docs) {
        final bookingData = doc.data() as Map<String, dynamic>;
        final startTime = bookingData['timeSlot'];
        final endTime = bookingData['endTime'];

        if (startTime != null && endTime != null) {
          // Mark all time slots between start and end as unavailable
          final startHour = int.parse(startTime.split(':')[0]);
          final endHour = int.parse(endTime.split(':')[0]);

          for (int hour = startHour; hour < endHour; hour++) {
            final timeSlot = '${hour.toString().padLeft(2, '0')}:00';
            if (availability.containsKey(timeSlot)) {
              availability[timeSlot] = false;
            }
          }
        }
      }

      // Mark past time slots as unavailable using Malaysia timezone
      for (String slot in _timeSlots) {
        if (TimezoneHelper.isTimeSlotInPast(_selectedDate, slot)) {
          availability[slot] = false;
        }
      }

      setState(() {
        _timeSlotAvailability = availability;
      });
    } catch (e) {
      print('Error checking coach availability: $e');
    }
  }

  bool _isTimeRangeAvailable(String startTime, String endTime) {
    final startHour = int.parse(startTime.split(':')[0]);
    final endHour = int.parse(endTime.split(':')[0]);

    for (int hour = startHour; hour < endHour; hour++) {
      final timeSlot = '${hour.toString().padLeft(2, '0')}:00';
      if (_timeSlotAvailability[timeSlot] == false ||
          TimezoneHelper.isTimeSlotInPast(_selectedDate, timeSlot)) {
        return false;
      }
    }
    return true;
  }

  int _calculateDuration() {
    if (_selectedStartTime == null || _selectedEndTime == null) return 0;

    final startHour = int.parse(_selectedStartTime!.split(':')[0]);
    final endHour = int.parse(_selectedEndTime!.split(':')[0]);

    return endHour - startHour;
  }

  double _calculateTotalPrice() {
    final duration = _calculateDuration();
    if (duration <= 0) return 0;

    if (_bookingType == 'hourly') {
      return (widget.coach['pricePerHour'] ?? 0) * duration.toDouble();
    } else {
      return (_selectedPackage?['price'] ?? 0) * duration.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildCoachHeader(),
                  _buildBookingTypeSelection(),
                  _buildDateSelection(),
                  _buildTimeSelection(),
                  if (_bookingType == 'package')
                    _buildPackageSelection(),
                  _buildNotesSection(),
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
        'Book Coach',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      actions: [
        // Add current Malaysia time display
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

  Widget _buildCoachHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[200],
            ),
            child: ClipOval(
              child: widget.coach['imageUrl'] != null
                  ? Image.network(
                widget.coach['imageUrl'],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person,
                    size: 35,
                    color: Colors.grey[500],
                  );
                },
              )
                  : Icon(
                Icons.person,
                size: 35,
                color: Colors.grey[500],
              ),
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
                        widget.coach['name'] ?? 'Unknown Coach',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                    ),
                    if (widget.coach['isVerified'] == true)
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
                Text(
                  '${widget.coach['sport'] ?? 'Sport'} • ${widget.coach['experience'] ?? 'Experience'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber[600], size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.coach['rating'] ?? 0.0}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'RM ${widget.coach['pricePerHour'] ?? 0}/hr',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF8A50),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingTypeSelection() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Type',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildBookingTypeCard(
                  'hourly',
                  'Hourly Session',
                  'Book by the hour',
                  Icons.access_time,
                ),
              ),
              const SizedBox(width: 12),
              if (widget.packages.isNotEmpty)
                Expanded(
                  child: _buildBookingTypeCard(
                    'package',
                    'Training Package',
                    'Package rates',
                    Icons.card_giftcard,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingTypeCard(String type, String title, String subtitle, IconData icon) {
    final isSelected = _bookingType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _bookingType = type;
          _selectedStartTime = null;
          _selectedEndTime = null;
          if (type == 'package' && widget.packages.isNotEmpty) {
            _selectedPackage = widget.packages[0];
          }
        });
        _checkTimeSlotAvailability();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF8A50).withOpacity(0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF8A50) : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFF8A50) : Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
          const Text(
            'Select Date',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              itemBuilder: (context, index) {
                // Use Malaysia timezone for date calculation
                final availableDates = TimezoneHelper.getAvailableBookingDates();
                final date = availableDates[index];

                final isSelected = _selectedDate.day == date.day &&
                    _selectedDate.month == date.month &&
                    _selectedDate.year == date.year;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                      _selectedStartTime = null;
                      _selectedEndTime = null;
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

  Widget _buildTimeSelection() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Select Time',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
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

          // Start Time Selection
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Time',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _timeSlots.length - 1, // Exclude last slot for start time
                        itemBuilder: (context, index) {
                          final timeSlot = _timeSlots[index];
                          final isAvailable = _timeSlotAvailability[timeSlot] ?? true;
                          final isSelected = _selectedStartTime == timeSlot;
                          final isPastTime = TimezoneHelper.isTimeSlotInPast(_selectedDate, timeSlot);

                          return GestureDetector(
                            onTap: isAvailable && !isPastTime
                                ? () {
                              setState(() {
                                _selectedStartTime = timeSlot;
                                _selectedEndTime = null; // Reset end time
                              });
                            }
                                : null,
                            child: Container(
                              width: 70,
                              margin: const EdgeInsets.only(right: 8),
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
                                        fontSize: 12,
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
                                          size: 8,
                                        ),
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
              ),
            ],
          ),

          const SizedBox(height: 16),

          // End Time Selection
          if (_selectedStartTime != null)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'End Time',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 48,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _getAvailableEndTimes().length,
                          itemBuilder: (context, index) {
                            final timeSlot = _getAvailableEndTimes()[index];
                            final isSelected = _selectedEndTime == timeSlot;
                            final canSelect = _canSelectEndTime(timeSlot);

                            return GestureDetector(
                              onTap: canSelect
                                  ? () {
                                setState(() {
                                  _selectedEndTime = timeSlot;
                                });
                              }
                                  : null,
                              child: Container(
                                width: 70,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: !canSelect
                                      ? Colors.grey[200]
                                      : isSelected
                                      ? const Color(0xFFFF8A50)
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: !canSelect
                                        ? Colors.grey[300]!
                                        : isSelected
                                        ? const Color(0xFFFF8A50)
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    timeSlot,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: !canSelect
                                          ? Colors.grey[500]
                                          : isSelected
                                          ? Colors.white
                                          : const Color(0xFF2D3748),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

          // Duration Display and Malaysia Time Info
          if (_selectedStartTime != null && _selectedEndTime != null)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF8A50).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        color: const Color(0xFFFF8A50),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Duration: ${_calculateDuration()} hour${_calculateDuration() > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF8A50),
                        ),
                      ),
                    ],
                  ),
                  if (TimezoneHelper.isToday(_selectedDate))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Booking in Malaysia Time. Current time: ${TimezoneHelper.formatMalaysiaTime(DateTime.now())}',
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
            ),
        ],
      ),
    );
  }

  List<String> _getAvailableEndTimes() {
    if (_selectedStartTime == null) return [];

    final startIndex = _timeSlots.indexOf(_selectedStartTime!);
    return _timeSlots.sublist(startIndex + 1);
  }

  bool _canSelectEndTime(String endTime) {
    if (_selectedStartTime == null) return false;

    return _isTimeRangeAvailable(_selectedStartTime!, endTime);
  }

  Widget _buildPackageSelection() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Package',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          Column(
            children: widget.packages.map((package) {
              final isSelected = _selectedPackage?['id'] == package['id'];

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedPackage = package;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  package['name'] ?? 'Package',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? const Color(0xFFFF8A50) : const Color(0xFF2D3748),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'RM ${package['price'] ?? 0}/hour',
                                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (package['description'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          package['description'],
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ],
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

  Widget _buildNotesSection() {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Additional Notes (Optional)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: TextField(
              controller: _notesController,
              maxLines: 3,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Any specific requirements or goals for your training session?',
                hintStyle: TextStyle(color: Colors.grey[500]),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingSummary() {
    if (_selectedStartTime == null || _selectedEndTime == null ||
        (_bookingType == 'package' && _selectedPackage == null)) {
      return const SizedBox.shrink();
    }

    final duration = _calculateDuration();
    final totalPrice = _calculateTotalPrice();

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
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
                _buildSummaryRow('Coach', widget.coach['name'] ?? 'Unknown'),
                _buildSummaryRow('Sport', widget.coach['sport'] ?? 'Sport'),
                _buildSummaryRow('Date', _formatDate(_selectedDate)),
                _buildSummaryRow('Time', '$_selectedStartTime - $_selectedEndTime (Malaysia)'),
                _buildSummaryRow('Duration', '$duration hour${duration > 1 ? 's' : ''}'),
                if (_bookingType == 'package') ...[
                  _buildSummaryRow('Package', _selectedPackage?['name'] ?? 'Package'),
                  _buildSummaryRow('Rate', 'RM ${_selectedPackage?['price'] ?? 0}/hour'),
                ] else ...[
                  _buildSummaryRow('Rate', 'RM ${widget.coach['pricePerHour'] ?? 0}/hour'),
                ],
                const Divider(height: 24),
                _buildSummaryRow('Total', 'RM ${totalPrice.toStringAsFixed(0)}', isTotal: true),
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

  Widget _buildBookingButton() {
    final canBook = _selectedStartTime != null && _selectedEndTime != null &&
        (_bookingType == 'hourly' || (_bookingType == 'package' && _selectedPackage != null));

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
            canBook ? 'CONFIRM BOOKING' : 'SELECT START & END TIME',
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

  Future<void> _handleBooking() async {
    // Double-check if the selected time range is still valid before booking
    if (_selectedStartTime != null &&
        TimezoneHelper.isTimeSlotInPast(_selectedDate, _selectedStartTime!)) {
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

      if (_currentUserData == null) {
        await _loadCurrentUserData();
      }

      final duration = _calculateDuration();
      final totalPrice = _calculateTotalPrice();

      DateTime appointmentDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        int.parse(_selectedStartTime!.split(':')[0]),
        0,
      );

      final malaysiaTime = TimezoneHelper.getMalaysiaTime();

      // ==================== SIMPLIFIED DATA STRUCTURE ====================
      Map<String, dynamic> appointmentData = {
        // EXISTING BASIC FIELDS
        'userId': user.uid,
        'studentName': _currentUserData?['name'] ?? user.displayName ?? user.email?.split('@')[0] ?? 'User',
        'userEmail': user.email ?? '',
        'userPhone': _currentUserData?['phoneNumber'] ?? '',
        'coachId': widget.coach['id'],
        'coachName': widget.coach['name'] ?? 'Unknown Coach',
        'coachSport': widget.coach['sport'] ?? 'Sport',
        'coachLocation': widget.coach['location'] ?? '',
        'appointmentType': _bookingType,
        'price': totalPrice.toInt(),
        'status': 'pending_approval',
        'requestedAt': FieldValue.serverTimestamp(),
        'respondedAt': null,
        'responseMessage': null,
        'notes': _notesController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'scheduledAt': Timestamp.fromDate(appointmentDateTime),
        'date': "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
        'timeSlot': _selectedStartTime,
        'endTime': _selectedEndTime,
        'duration': duration,
        'bookedInTimezone': 'Asia/Kuala_Lumpur',
        'bookedAtMalaysiaTime': TimezoneHelper.formatMalaysiaTime(malaysiaTime, format: 'dd/MM/yyyy HH:mm'),

        // PAYMENT FIELDS (SIMPLIFIED)
        'paymentStatus': 'not_required_yet',
        'paymentAmount': totalPrice.toDouble(),
        'paymentMethod': '',
        'paymentId': '',
        'paidAt': null,

        // PROOF FIELDS
        'proofPhotoUrl': '',
        'proofUploadedAt': null,

        // VERIFICATION FIELDS
        'verificationStatus': 'pending',
        'verifiedBy': '',
        'verifiedAt': null,
        'verificationNotes': '',

        // RESCHEDULING FIELDS (NEW!)
        'rescheduleCount': 0,
        'maxReschedules': 2,
        'canReschedule': true,
        'rescheduleHistory': [],

        // CANCELLATION FIELDS (SIMPLIFIED - admin only)
        'cancelledBy': '',
        'cancelledAt': null,
        'cancellationReason': '',
        'isCancelled': false,

        // PAYMENT RELEASE FIELDS
        'paymentReleasedToCoach': false,
        'paymentReleasedAt': null,
        'coachEarnings': 0.0,
      };

      // Add package-specific fields
      if (_bookingType == 'hourly') {
        appointmentData['pricePerHour'] = widget.coach['pricePerHour'] ?? 0;
      } else {
        appointmentData.addAll({
          'packageId': _selectedPackage?['id'],
          'packageName': _selectedPackage?['name'],
          'packagePrice': _selectedPackage?['price'],
        });
      }

      print('Creating coach appointment with SIMPLIFIED STRUCTURE: $appointmentData');

      final docRef = await _firestore.collection('coach_appointments').add(appointmentData);
      appointmentData['id'] = docRef.id;
      print('Coach appointment created with ID: ${docRef.id}');

      // Create chat (existing code - keep as is)
      try {
        final chatId = await MessagingService.createOrGetChat(
          coachId: widget.coach['id'],
          coachName: widget.coach['name'] ?? 'Coach',
          studentId: user.uid,
          studentName: _currentUserData?['name'] ?? user.displayName ?? 'Student',
          appointmentId: docRef.id,
        );

        await MessagingService.sendMessage(
          chatId: chatId,
          senderId: 'system',
          senderName: 'Sportify',
          senderRole: 'system',
          receiverId: widget.coach['id'],
          message: 'New session request from ${appointmentData['studentName']} for ${appointmentData['date']} at ${appointmentData['timeSlot']} (Malaysia Time). You can discuss details here while you decide whether to accept.',
          messageType: 'system',
          metadata: {
            'appointmentId': docRef.id,
            'appointmentData': appointmentData,
          },
        );

        print('Chat created successfully with ID: $chatId');
      } catch (chatError) {
        print('Error creating chat: $chatError');
      }

      // Send notification to coach (existing code)
      try {
        await NotificationService.notifyCoachNewRequest(
          coachId: widget.coach['id'],
          studentName: appointmentData['studentName'],
          appointmentData: appointmentData,
        );
      } catch (notificationError) {
        print('Error sending notification: $notificationError');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showBookingSuccessDialog();
      }
    } catch (e) {
      print('Coach appointment error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Appointment booking failed: $e'),
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF8A50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.schedule, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Request Sent!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your coaching session request has been sent to ${widget.coach['name']}. The session is scheduled for ${_formatDate(_selectedDate)} at $_selectedStartTime - $_selectedEndTime (Malaysia Time). You\'ll receive a notification once they respond to your request.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                        },
                        child: const Text(
                          'Back to Coaches',
                          style: TextStyle(
                            color: Color(0xFF2D3748),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MyBookingsPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8A50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'View Requests',
                          style: TextStyle(
                            color: Colors.white,
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
        );
      },
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

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}