import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:convert';
import '../services/messaging_service.dart';
import '../models/message_model.dart';
import 'chat_page.dart';

class ChatsListPage extends StatefulWidget {
  const ChatsListPage({Key? key}) : super(key: key);

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends State<ChatsListPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<List<ChatModel>>? _chatsSubscription;
  List<ChatModel> _chats = [];
  bool _isLoading = true;
  String _currentUserId = '';
  String _currentUserRole = '';

  // Cache for user profile data
  Map<String, Map<String, dynamic>> _userProfileCache = {};

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      _currentUserId = user.uid;

      // Determine user role by checking which collection they exist in
      try {
        final coachDoc = await _firestore.collection('coaches').doc(user.uid).get();
        if (coachDoc.exists) {
          _currentUserRole = 'coach';
        } else {
          _currentUserRole = 'student';
        }

        _listenToChats();
      } catch (e) {
        print('Error determining user role: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _listenToChats() {
    _chatsSubscription = MessagingService.getUserChatsStream(_currentUserId, _currentUserRole)
        .listen((chats) {
      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoading = false;
        });
        // Preload user profile data for all chats
        _preloadUserProfiles();
      }
    });
  }

  Future<void> _preloadUserProfiles() async {
    for (ChatModel chat in _chats) {
      final isCoach = _currentUserRole == 'coach';
      final otherUserId = isCoach ? chat.studentId : chat.coachId;
      final otherUserRole = isCoach ? 'student' : 'coach';

      // Only fetch if not already cached
      if (!_userProfileCache.containsKey(otherUserId)) {
        await _fetchUserProfile(otherUserId, otherUserRole);
      }
    }
  }

  Future<void> _fetchUserProfile(String userId, String userRole) async {
    try {
      DocumentSnapshot userDoc;
      if (userRole == 'coach') {
        userDoc = await _firestore.collection('coaches').doc(userId).get();
      } else {
        userDoc = await _firestore.collection('users').doc(userId).get();
      }

      if (userDoc.exists && mounted) {
        setState(() {
          _userProfileCache[userId] = userDoc.data() as Map<String, dynamic>;
        });
      }
    } catch (e) {
      print('Error fetching user profile for $userId: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: _isLoading
          ? _buildLoadingState()
          : _chats.isEmpty
          ? _buildEmptyState()
          : _buildChatsList(),
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
        'Messages',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Color(0xFF2D3748)),
          onPressed: _showSearchDialog,
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currentUserRole == 'coach'
                ? 'Start chatting with your students when they book sessions'
                : 'Start chatting with coaches when you book sessions',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList() {
    return RefreshIndicator(
      onRefresh: () async {
        // Clear cache and reload
        _userProfileCache.clear();
        await _preloadUserProfiles();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          return _buildChatCard(_chats[index]);
        },
      ),
    );
  }

  Widget _buildChatCard(ChatModel chat) {
    final isCoach = _currentUserRole == 'coach';
    final otherUserName = isCoach ? chat.studentName : chat.coachName;
    final otherUserId = isCoach ? chat.studentId : chat.coachId;
    final otherUserRole = isCoach ? 'student' : 'coach';
    final unreadCount = isCoach ? chat.unreadCountForCoach : chat.unreadCountForStudent;
    final isLastMessageFromMe = chat.lastMessageSender == _currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Stack(
          children: [
            _buildProfileAvatar(otherUserId, otherUserRole, otherUserName),
            // Online indicator (you can implement online status later)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                otherUserName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                  color: const Color(0xFF2D3748),
                ),
              ),
            ),
            Text(
              _formatChatTime(chat.lastMessageTime),
              style: TextStyle(
                fontSize: 12,
                color: unreadCount > 0 ? const Color(0xFFFF8A50) : Colors.grey[500],
                fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            if (isLastMessageFromMe) ...[
              Icon(
                Icons.done_all,
                size: 16,
                color: Colors.grey[500],
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                chat.lastMessage,  // This now shows actual message preview
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: unreadCount > 0 ? const Color(0xFF2D3748) : Colors.grey[600],
                  fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8A50),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        onTap: () => _openChat(chat, otherUserName, otherUserId, otherUserRole),
        onLongPress: () => _showChatOptions(chat),
      ),
    );
  }

  Widget _buildProfileAvatar(String userId, String userRole, String userName) {
    // Get cached user profile data
    final userProfile = _userProfileCache[userId];
    final profileImageBase64 = userProfile?['profileImageBase64'] as String?;

    if (profileImageBase64 != null && profileImageBase64.isNotEmpty) {
      // Show actual profile picture from base64
      try {
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: userRole == 'coach'
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFFF8A50),
              width: 2,
            ),
          ),
          child: ClipOval(
            child: Image.memory(
              base64Decode(profileImageBase64),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to initials if image fails to load
                return _buildFallbackAvatar(userRole, userName);
              },
            ),
          ),
        );
      } catch (e) {
        // Fallback to initials if base64 decode fails
        return _buildFallbackAvatar(userRole, userName);
      }
    } else {
      // Fallback to initials or icon
      return _buildFallbackAvatar(userRole, userName);
    }
  }

  Widget _buildFallbackAvatar(String userRole, String userName) {
    // Get initials from name
    String initials = '';
    if (userName.isNotEmpty) {
      List<String> nameParts = userName.split(' ');
      initials = nameParts.length >= 2
          ? '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase()
          : userName[0].toUpperCase();
    }

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: userRole == 'coach'
              ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
              : [const Color(0xFFFF8A50), const Color(0xFFFFAB40)],
        ),
        border: Border.all(
          color: userRole == 'coach'
              ? const Color(0xFF4CAF50)
              : const Color(0xFFFF8A50),
          width: 2,
        ),
      ),
      child: initials.isNotEmpty
          ? Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      )
          : Icon(
        userRole == 'coach' ? Icons.school : Icons.person,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  void _openChat(ChatModel chat, String otherUserName, String otherUserId, String otherUserRole) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatId: chat.id,
          otherUserName: otherUserName,
          otherUserId: otherUserId,
          otherUserRole: otherUserRole,
        ),
      ),
    );
  }

  void _showChatOptions(ChatModel chat) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Chat with ${_currentUserRole == 'coach' ? chat.studentName : chat.coachName}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.mark_chat_read, color: Color(0xFF2D3748)),
                title: const Text('Mark as Read'),
                onTap: () {
                  Navigator.pop(context);
                  _markChatAsRead(chat);
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive, color: Color(0xFF2D3748)),
                title: const Text('Archive Chat'),
                onTap: () {
                  Navigator.pop(context);
                  _showArchiveConfirmation(chat);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Color(0xFF2D3748)),
                title: const Text('Chat Info'),
                onTap: () {
                  Navigator.pop(context);
                  _showChatInfo(chat);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _markChatAsRead(ChatModel chat) async {
    try {
      await MessagingService.markMessagesAsRead(chat.id, _currentUserId, _currentUserRole);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as read')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _showArchiveConfirmation(ChatModel chat) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Archive Chat'),
          content: Text('Archive conversation with ${_currentUserRole == 'coach' ? chat.studentName : chat.coachName}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await MessagingService.archiveChat(chat.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat archived')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error archiving chat: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );
  }

  void _showChatInfo(ChatModel chat) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Chat Information'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coach: ${chat.coachName}'),
              Text('Student: ${chat.studentName}'),
              if (chat.appointmentId != null)
                Text('Related to appointment: ${chat.appointmentId}'),
              Text('Created: ${_formatDate(chat.createdAt)}'),
              Text('Last message: ${_formatDate(chat.lastMessageTime)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final searchController = TextEditingController();
        return AlertDialog(
          title: const Text('Search Chats'),
          content: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              hintText: 'Search for people or messages...',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // TODO: Implement search functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Search functionality coming soon!')),
                );
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  String _formatChatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      // Today - show time
      final hour = timestamp.hour.toString().padLeft(2, '0');
      final minute = timestamp.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (messageDate == yesterday) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(timestamp).inDays < 7) {
      // This week - show day name
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[timestamp.weekday - 1];
    } else {
      // Older - show date
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}