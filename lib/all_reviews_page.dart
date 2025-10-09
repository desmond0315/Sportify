import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AllReviewsPage extends StatefulWidget {
  final String coachId;
  final String coachName;

  const AllReviewsPage({
    Key? key,
    required this.coachId,
    required this.coachName,
  }) : super(key: key);

  @override
  State<AllReviewsPage> createState() => _AllReviewsPageState();
}

class _AllReviewsPageState extends State<AllReviewsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  double _averageRating = 0.0;
  Map<int, int> _ratingDistribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

  @override
  void initState() {
    super.initState();
    _fetchAllReviews();
  }

  Future<void> _fetchAllReviews() async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot querySnapshot = await _firestore
          .collection('coaches')
          .doc(widget.coachId)
          .collection('reviews')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> reviews = [];
      double totalRating = 0.0;
      Map<int, int> distribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> reviewData = doc.data() as Map<String, dynamic>;
        reviewData['id'] = doc.id;
        reviews.add(reviewData);

        final rating = reviewData['rating'] as int? ?? 0;
        if (rating > 0) {
          totalRating += rating;
          distribution[rating] = (distribution[rating] ?? 0) + 1;
        }
      }

      setState(() {
        _reviews = reviews;
        _averageRating = reviews.isNotEmpty ? totalRating / reviews.length : 0.0;
        _ratingDistribution = distribution;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.coachName}\'s Reviews',
          style: const TextStyle(
            color: Color(0xFF2D3748),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
        ),
      )
          : RefreshIndicator(
        onRefresh: _fetchAllReviews,
        color: const Color(0xFFFF8A50),
        child: CustomScrollView(
          slivers: [
            // Rating Summary Section
            SliverToBoxAdapter(
              child: _buildRatingSummary(),
            ),

            // Reviews List
            if (_reviews.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return _buildReviewCard(_reviews[index]);
                    },
                    childCount: _reviews.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSummary() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Average Rating Display
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Text(
                      _averageRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return Icon(
                          index < _averageRating.round() ? Icons.star : Icons.star_border,
                          color: Colors.amber[600],
                          size: 24,
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_reviews.length} review${_reviews.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 24),

              // Rating Distribution
              Expanded(
                flex: 3,
                child: Column(
                  children: [5, 4, 3, 2, 1].map((rating) {
                    final count = _ratingDistribution[rating] ?? 0;
                    final percentage = _reviews.isNotEmpty
                        ? (count / _reviews.length * 100)
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '$rating',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star,
                            color: Colors.amber[600],
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percentage / 100,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.amber[600]!,
                                ),
                                minHeight: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 35,
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // User Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFFF8A50),
                child: Text(
                  (review['studentName'] ?? review['userName'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['studentName'] ?? review['userName'] ?? 'Anonymous',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D3748),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(review['createdAt']),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Rating Stars
          Row(
            children: List.generate(5, (index) {
              return Icon(
                index < (review['rating'] ?? 0) ? Icons.star : Icons.star_border,
                color: Colors.amber[600],
                size: 20,
              );
            }),
          ),

          const SizedBox(height: 12),

          // Review Comment
          if (review['comment'] != null && review['comment'].toString().trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                review['comment'],
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'No comment provided',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.rate_review_outlined,
              size: 60,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No reviews yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to leave a review for this coach!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
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

      if (difference.inDays > 30) {
        return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() != 1 ? 's' : ''} ago';
      } else if (difference.inDays > 7) {
        return '${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() != 1 ? 's' : ''} ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} day${difference.inDays != 1 ? 's' : ''} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hour${difference.inHours != 1 ? 's' : ''} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minute${difference.inMinutes != 1 ? 's' : ''} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Recently';
    }
  }
}