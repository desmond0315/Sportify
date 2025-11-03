import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class TimezoneHelper {
  static late tz.Location _malaysiaLocation;
  static bool _initialized = false;

  // Initialize timezone data (call this in main.dart)
  static Future<void> initialize() async {
    if (!_initialized) {
      tz.initializeTimeZones();
      _malaysiaLocation = tz.getLocation('Asia/Kuala_Lumpur');
      _initialized = true;
    }
  }

  // Get current Malaysia time
  static tz.TZDateTime getMalaysiaTime() {
    if (!_initialized) {
      throw StateError('TimezoneHelper not initialized. Call initialize() first.');
    }
    return tz.TZDateTime.now(_malaysiaLocation);
  }

  // Convert any DateTime to Malaysia timezone
  static tz.TZDateTime toMalaysiaTime(DateTime dateTime) {
    if (!_initialized) {
      throw StateError('TimezoneHelper not initialized. Call initialize() first.');
    }
    return tz.TZDateTime.from(dateTime, _malaysiaLocation);
  }

  // Check if a time slot is in the past (Malaysia time)
  static bool isTimeSlotInPast(DateTime selectedDate, String timeSlot) {
    if (!_initialized) {
      throw StateError('TimezoneHelper not initialized. Call initialize() first.');
    }

    try {
      final now = getMalaysiaTime();

      // Parse the time slot (format: "HH:mm")
      final timeParts = timeSlot.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;

      // Create the slot datetime in Malaysia timezone
      final slotDateTime = tz.TZDateTime(
        _malaysiaLocation,
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        hour,
        minute,
      );

      // Check if slot is in the past (with 15-minute buffer)
      final bufferTime = now.add(const Duration(minutes: 15));
      return slotDateTime.isBefore(bufferTime);

    } catch (e) {
      print('Error checking time slot: $e');
      return true; // Default to unavailable if error occurs
    }
  }

  // Check if selected date is today (Malaysia time)
  static bool isToday(DateTime selectedDate) {
    if (!_initialized) {
      throw StateError('TimezoneHelper not initialized. Call initialize() first.');
    }

    final now = getMalaysiaTime();
    return selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
  }

  // Format Malaysia time for display
  static String formatMalaysiaTime(DateTime dateTime, {String format = 'HH:mm'}) {
    final malaysiaTime = toMalaysiaTime(dateTime);

    switch (format) {
      case 'HH:mm':
        return '${malaysiaTime.hour.toString().padLeft(2, '0')}:${malaysiaTime.minute.toString().padLeft(2, '0')}';
      case 'dd/MM/yyyy HH:mm':
        return '${malaysiaTime.day}/${malaysiaTime.month}/${malaysiaTime.year} ${malaysiaTime.hour.toString().padLeft(2, '0')}:${malaysiaTime.minute.toString().padLeft(2, '0')}';
      case 'dd MMM yyyy':
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${malaysiaTime.day} ${months[malaysiaTime.month - 1]} ${malaysiaTime.year}';
      default:
        return malaysiaTime.toString();
    }
  }

  // Get available dates for booking (next 14 days from Malaysia time)
  static List<DateTime> getAvailableBookingDates({int daysAhead = 14}) {
    final now = getMalaysiaTime();
    final today = DateTime(now.year, now.month, now.day);

    return List.generate(daysAhead, (index) {
      return today.add(Duration(days: index));
    });
  }

  // Debug: Get timezone info
  static Map<String, dynamic> getTimezoneInfo() {
    final now = getMalaysiaTime();
    return {
      'current_malaysia_time': now.toString(),
      'timezone': now.timeZoneName,
      'offset': now.timeZoneOffset.toString(),
      'is_dst': now.timeZoneOffset != const Duration(hours: 8),
    };
  }
}