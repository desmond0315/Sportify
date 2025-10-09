import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/timezone_helper.dart';
import '../services/notification_service.dart';
import '../services/messaging_service.dart';

class RescheduleRequestPage extends StatefulWidget {
  final Map<String, dynamic> appointment;

  const RescheduleRequestPage({Key? key, required this.appointment}) : super(key: key);

  @override
  State<RescheduleRequestPage> createState() => _RescheduleRequestPageState();
}

class _RescheduleRequestPageState extends State<RescheduleRequestPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _reasonController = TextEditingController();

  DateTime? _selectedDate;
  String? _selectedStartTime;
  String? _selectedEndTime;
  Map<String, bool> _timeSlotAvailability = {};
  bool _isLoading = false;
  bool _isCheckingAvailability = false;

  final List<String> _timeSlots = [
    '08:00', '09:00', '10:00', '11:00', '12:00', '13:00',
    '14:00', '15:00', '16:00', '17:00', '18:00', '19:00',
    '20:00', '21:00', '22:00',
  ];

  @override
  void initState() {
    super.initState();
    _checkRescheduleEligibility();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _checkRescheduleEligibility() {
    final rescheduleCount = widget.appointment['rescheduleCount'] ?? 0;
    final maxReschedules = widget.appointment['maxReschedules'] ?? 2;
    final canReschedule = widget.appointment['canReschedule'] ?? true;

    if (!canReschedule || rescheduleCount >= maxReschedules) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRescheduleNotAllowedDialog();
      });
    }

    // Check if session is within 24 hours
    final scheduledAt = widget.appointment['scheduledAt'] as Timestamp?;
    if (scheduledAt != null) {
      final sessionTime = scheduledAt.toDate();
      final now = TimezoneHelper.getMalaysiaTime();
      final hoursUntilSession = sessionTime.difference(now).inHours;

      if (hoursUntilSession < 24) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTooLateDialog();
        });
      }
    }
  }

  Future<void> _checkTimeSlotAvailability() async {
    if (_selectedDate == null) return;

    setState(() => _isCheckingAvailability = true);

    try {
      final dateStr = "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";

      QuerySnapshot bookingsSnapshot = await _firestore
          .collection('coach_appointments')
          .where('coachId', isEqualTo: widget.appointment['coachId'])
          .where('date', isEqualTo: dateStr)
          .where('status', whereIn: ['confirmed', 'accepted']).get();

      Map<String, bool> availability = {};
      for (String slot in _timeSlots) {
        availability[slot] = true;
      }

      for (var doc in bookingsSnapshot.docs) {
        final bookingData = doc.data() as Map<String, dynamic>;
        final startTime = bookingData['timeSlot'];
        final endTime = bookingData['endTime'];

        if (startTime != null && endTime != null) {
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

      // Mark past time slots as unavailable
      for (String slot in _timeSlots) {
        if (TimezoneHelper.isTimeSlotInPast(_selectedDate!, slot)) {
          availability[slot] = false;
        }
      }

      setState(() {
        _timeSlotAvailability = availability;
        _isCheckingAvailability = false;
      });
    } catch (e) {
      print('Error checking availability: $e');
      setState(() => _isCheckingAvailability = false);
    }
  }

  int _calculateDuration() {
    // Duration is now fixed to original booking duration
    return widget.appointment['duration'] ?? 1;
  }

  bool _isTimeRangeAvailable(String startTime, String endTime) {
    final startHour = int.parse(startTime.split(':')[0]);
    final endHour = int.parse(endTime.split(':')[0]);

    for (int hour = startHour; hour < endHour; hour++) {
      final timeSlot = '${hour.toString().padLeft(2, '0')}:00';
      if (_timeSlotAvailability[timeSlot] == false ||
          TimezoneHelper.isTimeSlotInPast(_selectedDate!, timeSlot)) {
        return false;
      }
    }
    return true;
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCurrentBookingInfo(),
                  const SizedBox(height: 24),
                  _buildRescheduleInfo(),
                  const SizedBox(height: 24),
                  _buildDateSelection(),
                  const SizedBox(height: 24),
                  if (_selectedDate != null) _buildTimeSelection(),
                  const SizedBox(height: 24),
                  _buildReasonInput(),
                ],
              ),
            ),
          ),
          _buildSubmitButton(),
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
        'Request Reschedule',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildCurrentBookingInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event, color: Colors.grey[600], size: 20),
              const SizedBox(width: 8),
              const Text(
                'Current Booking',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Coach', widget.appointment['coachName'] ?? 'Coach'),
          _buildInfoRow('Date', widget.appointment['date'] ?? 'N/A'),
          _buildInfoRow('Time', '${widget.appointment['timeSlot']} - ${widget.appointment['endTime']}'),
          _buildInfoRow('Duration', '${widget.appointment['duration']} hour(s)'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3748),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRescheduleInfo() {
    final rescheduleCount = widget.appointment['rescheduleCount'] ?? 0;
    final maxReschedules = widget.appointment['maxReschedules'] ?? 2;
    final remaining = maxReschedules - rescheduleCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Reschedule Rules',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• You have $remaining reschedule${remaining != 1 ? 's' : ''} remaining',
            style: TextStyle(fontSize: 14, color: Colors.blue[800]),
          ),
          const SizedBox(height: 4),
          Text(
            '• ⏰ Can only reschedule to LATER dates/times',
            style: TextStyle(fontSize: 14, color: Colors.blue[800], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '• 🔒 Duration must stay ${widget.appointment['duration']} hour(s)',
            style: TextStyle(fontSize: 14, color: Colors.blue[800], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '• Coach must approve the new time',
            style: TextStyle(fontSize: 14, color: Colors.blue[800]),
          ),
          const SizedBox(height: 4),
          Text(
            '• New time must be 24+ hours from now',
            style: TextStyle(fontSize: 14, color: Colors.blue[800]),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select New Date',
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
              final availableDates = TimezoneHelper.getAvailableBookingDates();
              final date = availableDates[index];

              // ✅ NEW: Get original booking date
              final originalDate = _getOriginalBookingDate();

              // ✅ NEW: Disable dates that are earlier than original booking
              final isBeforeOriginal = originalDate != null && date.isBefore(originalDate);

              final isSelected = _selectedDate != null &&
                  _selectedDate!.day == date.day &&
                  _selectedDate!.month == date.month &&
                  _selectedDate!.year == date.year;

              return GestureDetector(
                onTap: isBeforeOriginal ? null : () {
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
                    color: isBeforeOriginal
                        ? Colors.grey[200]
                        : isSelected
                        ? const Color(0xFFFF8A50)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isBeforeOriginal
                          ? Colors.grey[300]!
                          : isSelected
                          ? const Color(0xFFFF8A50)
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _getWeekdayName(date.weekday),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isBeforeOriginal
                              ? Colors.grey[400]
                              : isSelected
                              ? Colors.white
                              : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isBeforeOriginal
                              ? Colors.grey[400]
                              : isSelected
                              ? Colors.white
                              : const Color(0xFF2D3748),
                        ),
                      ),
                      Text(
                        _getMonthName(date.month),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isBeforeOriginal
                              ? Colors.grey[400]
                              : isSelected
                              ? Colors.white
                              : Colors.grey[600],
                        ),
                      ),
                      if (isBeforeOriginal)
                        Icon(
                          Icons.lock,
                          size: 12,
                          color: Colors.grey[400],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

// ✅ NEW: Add this helper method to get original booking date
  DateTime? _getOriginalBookingDate() {
    try {
      final dateStr = widget.appointment['date'];
      if (dateStr == null) return null;

      final parts = dateStr.split('-');
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (e) {
      print('Error parsing original date: $e');
      return null;
    }
  }

// ✅ UPDATED: Replace the entire _buildTimeSelection method with this:
  Widget _buildTimeSelection() {
    if (_isCheckingAvailability) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
        ),
      );
    }

    // ✅ NEW: Get original booking date and time for comparison
    final originalDate = _getOriginalBookingDate();
    final originalStartTime = widget.appointment['timeSlot'] as String?;
    final isSameDay = originalDate != null &&
        _selectedDate != null &&
        originalDate.year == _selectedDate!.year &&
        originalDate.month == _selectedDate!.month &&
        originalDate.day == _selectedDate!.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Select New Time',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3748),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_clock, size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                  Text(
                    'Must be ${widget.appointment['duration']}h',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Start Time
        const Text(
          'Start Time',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _timeSlots.length - 1,
            itemBuilder: (context, index) {
              final timeSlot = _timeSlots[index];
              final isAvailable = _timeSlotAvailability[timeSlot] ?? true;
              final isSelected = _selectedStartTime == timeSlot;

              // ✅ NEW: Check if time slot is before original booking time
              final isBeforeOriginal = isSameDay &&
                  originalStartTime != null &&
                  _isTimeSlotBeforeOriginal(timeSlot, originalStartTime);

              return GestureDetector(
                onTap: (isAvailable && !isBeforeOriginal)
                    ? () {
                  setState(() {
                    _selectedStartTime = timeSlot;
                    // ✅ AUTO-CALCULATE end time based on original duration
                    _selectedEndTime = _calculateEndTimeFromDuration(timeSlot);
                  });
                }
                    : null,
                child: Container(
                  width: 70,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: (!isAvailable || isBeforeOriginal)
                        ? Colors.grey[200]
                        : isSelected
                        ? const Color(0xFFFF8A50)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (!isAvailable || isBeforeOriginal)
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
                            color: (!isAvailable || isBeforeOriginal)
                                ? Colors.grey[500]
                                : isSelected
                                ? Colors.white
                                : const Color(0xFF2D3748),
                          ),
                        ),
                      ),
                      if (isBeforeOriginal)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock,
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

        const SizedBox(height: 16),

        // ✅ NEW: Show auto-calculated end time (read-only)
        if (_selectedStartTime != null) ...[
          const Text(
            'End Time (Auto-calculated)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Time: $_selectedStartTime - $_selectedEndTime',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.green[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Duration: ${widget.appointment['duration']} hour(s) (same as original)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ✅ NEW: Helper method to check if time slot is before original
  bool _isTimeSlotBeforeOriginal(String newTime, String originalTime) {
    final newHour = int.parse(newTime.split(':')[0]);
    final originalHour = int.parse(originalTime.split(':')[0]);
    return newHour < originalHour;
  }

// ✅ NEW: Helper method to auto-calculate end time based on duration
  String? _calculateEndTimeFromDuration(String startTime) {
    final startHour = int.parse(startTime.split(':')[0]);
    final duration = widget.appointment['duration'] ?? 1;
    final endHour = startHour + duration;

    // Make sure end time doesn't exceed available hours
    if (endHour > 23) return null;

    return '${endHour.toString().padLeft(2, '0')}:00';
  }


  List<String> _getAvailableEndTimes() {
    if (_selectedStartTime == null) return [];
    final startIndex = _timeSlots.indexOf(_selectedStartTime!);
    return _timeSlots.sublist(startIndex + 1);
  }

  bool _canSelectEndTime(String endTime) {
    if (_selectedStartTime == null || _selectedDate == null) return false;
    return _isTimeRangeAvailable(_selectedStartTime!, endTime);
  }

  Widget _buildReasonInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reason for Rescheduling (Optional)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextField(
            controller: _reasonController,
            maxLines: 3,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'e.g., Family emergency, schedule conflict...',
              hintStyle: TextStyle(color: Colors.grey[500]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    final canSubmit = _selectedDate != null &&
        _selectedStartTime != null &&
        _selectedEndTime != null &&
        !_isLoading;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: canSubmit ? _handleSubmitReschedule : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canSubmit ? const Color(0xFFFF8A50) : Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2.5,
              ),
            )
                : const Text(
              'SEND RESCHEDULE REQUEST',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmitReschedule() async {
    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw 'User not logged in';

      final newDateStr = "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";

      DateTime newScheduledAt = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        int.parse(_selectedStartTime!.split(':')[0]),
        0,
      );

      // ✅ FIXED: Create reschedule history entry with Timestamp.now()
      Map<String, dynamic> rescheduleEntry = {
        'oldDate': widget.appointment['date'],
        'oldTimeSlot': widget.appointment['timeSlot'],
        'oldEndTime': widget.appointment['endTime'],
        'newDate': newDateStr,
        'newTimeSlot': _selectedStartTime,
        'newEndTime': _selectedEndTime,
        'requestedBy': 'student',
        'requestedAt': Timestamp.now(),  // ✅ FIXED
        'reason': _reasonController.text.trim(),
        'status': 'pending',
        'approvedBy': '',
        'approvedAt': null,
      };

      // Get current reschedule history
      List<dynamic> rescheduleHistory = List.from(widget.appointment['rescheduleHistory'] ?? []);
      rescheduleHistory.add(rescheduleEntry);

      // Update appointment with reschedule request
      await _firestore
          .collection('coach_appointments')
          .doc(widget.appointment['id'])
          .update({
        'rescheduleHistory': rescheduleHistory,
        'status': 'reschedule_requested',
        'updatedAt': FieldValue.serverTimestamp(),  // ✅ This is OK at top level
      });

      // Send notification to coach
      await NotificationService.createNotification(
        userId: widget.appointment['coachId'],
        type: 'coach',
        title: 'Reschedule Request',
        message: '${widget.appointment['studentName']} wants to reschedule from ${widget.appointment['date']} to $newDateStr at $_selectedStartTime.',
        data: {
          'appointmentId': widget.appointment['id'],
          'action': 'view_reschedule_request',
        },
        priority: 'high',
      );

      // Send chat message
      try {
        final chatId = MessagingService.generateChatId(
          widget.appointment['coachId'],
          user.uid,
        );

        await MessagingService.sendMessage(
          chatId: chatId,
          senderId: user.uid,
          senderName: widget.appointment['studentName'],
          senderRole: 'student',
          receiverId: widget.appointment['coachId'],
          message: 'Hi! I need to reschedule our session from ${widget.appointment['date']} at ${widget.appointment['timeSlot']} to $newDateStr at $_selectedStartTime. ${_reasonController.text.trim().isNotEmpty ? 'Reason: ${_reasonController.text.trim()}' : ''}',
          messageType: 'text',
        );
      } catch (e) {
        print('Error sending chat message: $e');
      }

      if (mounted) {
        setState(() => _isLoading = false);
        _showSuccessDialog();
      }
    } catch (e) {
      print('Error submitting reschedule: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Sent!'),
        content: const Text(
          'Your reschedule request has been sent to the coach. You\'ll receive a notification once they respond.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close reschedule page
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showRescheduleNotAllowedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cannot Reschedule'),
        content: const Text(
          'You have reached the maximum number of reschedules for this booking. Please contact the coach directly if you need to make changes.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close reschedule page
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTooLateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Too Late to Reschedule'),
        content: const Text(
          'Your session is within 24 hours. You cannot reschedule at this time. Please contact the coach directly.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close reschedule page
            },
            child: const Text('OK'),
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
}