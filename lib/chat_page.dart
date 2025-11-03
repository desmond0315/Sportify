import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../services/messaging_service.dart';
import '../models/message_model.dart';
import '../services/encryption_service.dart';


class ChatPage extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String otherUserRole; // 'coach' or 'student'
  final String? otherUserId;

  const ChatPage({
    Key? key,
    required this.chatId,
    required this.otherUserName,
    required this.otherUserRole,
    this.otherUserId,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late String _currentUserId;
  late String _currentUserName;
  late String _currentUserRole;

  StreamSubscription<List<MessageModel>>? _messagesSubscription;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  // ADDED: Store other user's profile image
  String? _otherUserProfileImage;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _listenToMessages();
    _markMessagesAsRead();
    _loadOtherUserProfile(); // ADDED: Load other user's profile
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    super.dispose();
  }

  void _initializeUser() {
    final user = _auth.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      _currentUserName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
      // Determine user role (you might want to get this from Firestore)
      _currentUserRole = widget.otherUserRole == 'coach' ? 'student' : 'coach';
    }
  }

  // ADDED: Load other user's profile image from Firestore
  Future<void> _loadOtherUserProfile() async {
    if (widget.otherUserId == null || widget.otherUserId!.isEmpty) {
      setState(() => _isLoadingProfile = false);
      return;
    }

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      DocumentSnapshot userDoc;

      // Determine which collection to query based on role
      if (widget.otherUserRole == 'coach') {
        userDoc = await firestore.collection('coaches').doc(widget.otherUserId).get();
      } else if (widget.otherUserRole == 'venue_owner') {
        userDoc = await firestore.collection('venue_owners').doc(widget.otherUserId).get();
      } else {
        userDoc = await firestore.collection('users').doc(widget.otherUserId).get();
      }

      if (userDoc.exists && mounted) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        setState(() {
          _otherUserProfileImage = userData?['profileImageBase64'];
          _isLoadingProfile = false;
        });
      } else {
        setState(() => _isLoadingProfile = false);
      }
    } catch (e) {
      print('Error loading other user profile: $e');
      setState(() => _isLoadingProfile = false);
    }
  }

  void _listenToMessages() {
    _messagesSubscription = MessagingService.getMessagesStream(widget.chatId)
        .listen((messages) {
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        _scrollToBottom();
        _markMessagesAsRead();
      }
    });
  }

  void _markMessagesAsRead() {
    if (_currentUserId.isNotEmpty) {
      MessagingService.markMessagesAsRead(
        widget.chatId,
        _currentUserId,
        _currentUserRole,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      await MessagingService.sendMessage(
        chatId: widget.chatId,
        senderId: _currentUserId,
        senderName: _currentUserName,
        senderRole: _currentUserRole,
        receiverId: widget.otherUserId ?? '',
        message: messageText,
      );

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
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
            child: _isLoading
                ? _buildLoadingState()
                : _buildMessagesList(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          // UPDATED: Show actual profile image or fallback to icon
          _buildOtherUserAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                Text(
                  widget.otherUserRole == 'coach' ? 'Coach' : widget.otherUserRole == 'venue_owner' ? 'Venue Owner' : 'Student',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Color(0xFF2D3748)),
          onPressed: _showChatInfo,
        ),
      ],
    );
  }

  // ADDED: Build avatar for the other user
  Widget _buildOtherUserAvatar() {
    if (_otherUserProfileImage != null && _otherUserProfileImage!.isNotEmpty) {
      try {
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.otherUserRole == 'coach'
                  ? const Color(0xFF4CAF50)
                  : widget.otherUserRole == 'venue_owner'
                  ? const Color(0xFF8B5CF6)
                  : const Color(0xFFFF8A50),
              width: 2,
            ),
          ),
          child: ClipOval(
            child: Image.memory(
              base64Decode(_otherUserProfileImage!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildDefaultOtherUserAvatar();
              },
            ),
          ),
        );
      } catch (e) {
        return _buildDefaultOtherUserAvatar();
      }
    } else {
      return _buildDefaultOtherUserAvatar();
    }
  }

  Widget _buildDefaultOtherUserAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.otherUserRole == 'coach'
            ? const Color(0xFF4CAF50).withOpacity(0.1)
            : widget.otherUserRole == 'venue_owner'
            ? const Color(0xFF8B5CF6).withOpacity(0.1)
            : const Color(0xFFFF8A50).withOpacity(0.1),
      ),
      child: Icon(
        widget.otherUserRole == 'coach'
            ? Icons.school
            : widget.otherUserRole == 'venue_owner'
            ? Icons.business
            : Icons.person,
        color: widget.otherUserRole == 'coach'
            ? const Color(0xFF4CAF50)
            : widget.otherUserRole == 'venue_owner'
            ? const Color(0xFF8B5CF6)
            : const Color(0xFFFF8A50),
        size: 20,
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isMe = message.senderId == _currentUserId;
        final showDate = index == _messages.length - 1 ||
            !_isSameDay(_messages[index].timestamp, _messages[index + 1].timestamp);

        return Column(
          children: [
            if (showDate) _buildDateSeparator(message.timestamp),
            _buildMessageBubble(message, isMe),
          ],
        );
      },
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
            'Start your conversation',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to begin chatting with your ${widget.otherUserRole}',
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

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate == today) {
      dateText = 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      dateText = 'Yesterday';
    } else {
      dateText = '${date.day}/${date.month}/${date.year}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              dateText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe) {
    final isSystem = message.messageType == 'system' || message.senderRole == 'system';

    if (isSystem) {
      return _buildSystemMessage(message);
    }

    // Decrypt user messages (system messages are already plain text)
    final decryptedMessage = message.iv.isNotEmpty
        ? EncryptionService.decryptMessage(message.message, message.iv, widget.chatId)
        : message.message;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.otherUserRole == 'coach'
                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                    : const Color(0xFFFF8A50).withOpacity(0.1),
              ),
              child: Icon(
                widget.otherUserRole == 'coach' ? Icons.school : Icons.person,
                color: widget.otherUserRole == 'coach'
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF8A50),
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFFF8A50) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMe ? 20 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    decryptedMessage,
                    style: TextStyle(
                      fontSize: 16,
                      color: isMe ? Colors.white : const Color(0xFF2D3748),
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatMessageTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
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

  Widget _buildSystemMessage(MessageModel message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Text(
            message.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8A50), Color(0xFFE8751A)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isSending ? null : _sendMessage,
                  borderRadius: BorderRadius.circular(24),
                  child: Center(
                    child: _isSending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatInfo() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Chat Information'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chat with: ${widget.otherUserName}'),
              Text('Role: ${widget.otherUserRole}'),
              Text('Chat ID: ${widget.chatId}'),
              const SizedBox(height: 16),
              const Text(
                'Messages are encrypted and stored securely. Only you and your chat partner can see these messages.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
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

  String _formatMessageTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      // Today - show time only
      final hour = timestamp.hour.toString().padLeft(2, '0');
      final minute = timestamp.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else {
      // Other days - show date and time
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}