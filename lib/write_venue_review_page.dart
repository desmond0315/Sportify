import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/review_service.dart';

class WriteVenueReviewPage extends StatefulWidget {
  final String bookingId;
  final String venueId;
  final String venueName;

  const WriteVenueReviewPage({
    Key? key,
    required this.bookingId,
    required this.venueId,
    required this.venueName,
  }) : super(key: key);

  @override
  State<WriteVenueReviewPage> createState() => _WriteVenueReviewPageState();
}

class _WriteVenueReviewPageState extends State<WriteVenueReviewPage> {
  final TextEditingController _commentController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  int _rating = 0;
  bool _isSubmitting = false;
  bool _canReview = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkReviewEligibility();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _checkReviewEligibility() async {
    final user = _auth.currentUser;
    if (user != null) {
      print('DEBUG: Checking review eligibility for booking ${widget.bookingId}');
      final canReview = await ReviewService.canReviewVenueBooking(
        widget.bookingId,
        user.uid,
      );
      print('DEBUG: Can review result: $canReview');

      setState(() {
        _canReview = canReview;
        _isLoading = false;
      });

      // Show debug info in UI if can't review
      if (!canReview) {
        // Fetch booking to see status
        final bookingDoc = await FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .get();

        if (bookingDoc.exists) {
          final data = bookingDoc.data();
          print('DEBUG: Booking status: ${data?['status']}');
          print('DEBUG: Payment status: ${data?['paymentStatus']}');
          print('DEBUG: Booking date: ${data?['date']}');
        }
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF2D3748)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
          ),
        ),
      );
    }

    if (!_canReview) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF2D3748)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                Text(
                  'Cannot Write Review',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You can only review venue bookings after:\n• The booking date has passed\n• Payment is completed\n• You haven\'t already reviewed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: const Text(
                    'Go Back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF2D3748)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Write Review',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Venue info
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8A50).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        size: 40,
                        color: Color(0xFFFF8A50),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.venueName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D3748),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'How was your experience?',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Rating section
              const Text(
                'Your Rating',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _rating = index + 1;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber[600],
                          size: 48,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              if (_rating > 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _getRatingText(_rating),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _getRatingColor(_rating),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 32),

              // Comment section
              const Text(
                'Your Feedback (Optional)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Share your experience to help others',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
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
                  controller: _commentController,
                  maxLines: 6,
                  maxLength: 500,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'How were the facilities? Was the court in good condition?',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    counterStyle: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _rating > 0 && !_isSubmitting ? _submitReview : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rating > 0 ? const Color(0xFFFF8A50) : Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2.5,
                    ),
                  )
                      : Text(
                    'SUBMIT REVIEW',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _rating > 0 ? Colors.white : Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }

  Color _getRatingColor(int rating) {
    if (rating <= 2) return Colors.red;
    if (rating == 3) return Colors.orange;
    return Colors.green;
  }

  Future<void> _submitReview() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to submit a review'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data();
      final userName = userData?['name'] ??
          user.displayName ??
          user.email?.split('@')[0] ??
          'User';

      // Submit review
      await ReviewService.submitVenueReview(
        bookingId: widget.bookingId,
        venueId: widget.venueId,
        venueName: widget.venueName,
        userId: user.uid,
        userName: userName,
        rating: _rating,
        comment: _commentController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context, true);
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting review: $e'),
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
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Review Submitted!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Thank you for your feedback! Your review helps others find great venues.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}