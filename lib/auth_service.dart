import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password - PLAYER ONLY
  Future<UserCredential?> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    UserCredential? userCredential;

    try {
      print('Creating Firebase Auth account for PLAYER...');

      // Create user account
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      print('Firebase Auth account created: ${userCredential.user?.uid}');

      // Update display name
      await userCredential.user?.updateDisplayName(name);

      // Reload the user to get updated info
      await userCredential.user?.reload();

      print('Starting Firestore document creation...');

      // Create user document in Firestore
      if (userCredential.user != null) {
        await _createUserDocumentWithRetry(userCredential.user!, name, email);
        print('User document created successfully for ${userCredential.user!.uid}');
      }

      // ✅ IMPORTANT: Return the userCredential here
      return userCredential;

    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Exception: ${e.code} - ${e.message}');
      throw _handleAuthException(e);

    } catch (e) {
      print('Unexpected error during signup: $e');

      // Special handling for PigeonUserDetails/ListObject32 error
      if (e.toString().contains('PigeonUserDetails') ||
          e.toString().contains('ListObject32') ||
          e.toString().contains('List<Object?>')) {

        // Check if user was actually created despite the error
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          print('User was created despite error, ensuring Firestore document exists...');

          try {
            // Try to create the user document
            await _createUserDocumentWithRetry(currentUser, name, email);
            print('User document created after error recovery');

            // we'll return null but the signup handler will check currentUser
            return null;

          } catch (firestoreError) {
            print('Failed to create user document after recovery: $firestoreError');
            try {
              await currentUser.delete();
            } catch (deleteError) {
              print('Also failed to clean up auth user: $deleteError');
            }
            throw 'Account creation failed. Please try again.';
          }
        }
      }

      throw 'An unexpected error occurred during signup. Please try again.';
    }
  }

  // Helper method to create user document with retry logic
  Future<void> _createUserDocumentWithRetry(User user, String name, String email, {int maxRetries = 3}) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < maxRetries) {
      try {
        attempts++;
        print('Creating user document, attempt $attempts');

        final userData = {
          'uid': user.uid,
          'name': name,
          'email': email,
          'role': 'player',
          'createdAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'profileImageUrl': null,
          'phoneNumber': null,
          'dateOfBirth': null,
        };

        await _firestore.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));

        // Wait a moment then verify the document was created
        await Future.delayed(Duration(milliseconds: 500));
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          print('User document verified successfully');
          return; // Success!
        } else {
          throw Exception('Document creation verification failed');
        }

      } catch (e) {
        print('User document creation attempt $attempts failed: $e');
        lastError = e as Exception;

        if (attempts < maxRetries) {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 1000 * attempts));
        }
      }
    }

    // If we get here, all retries failed
    throw lastError ?? Exception('Failed to create user document after $maxRetries attempts');
  }

  // Sign in with email and password - PLAYER LOGIN
  Future<UserCredential?> signInPlayerWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      print('Attempting PLAYER login...');

      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Verify this user exists in users collection (not coaches)
      if (userCredential.user != null) {
        final userDoc = await _firestore.collection('users').doc(userCredential.user!.uid).get();

        if (!userDoc.exists) {
          // Check if they're actually a coach
          final coachDoc = await _firestore.collection('coaches').doc(userCredential.user!.uid).get();
          if (coachDoc.exists) {
            await _auth.signOut();
            throw 'This account is registered as a coach. Please use coach login instead.';
          }

          // Create missing user document for regular user - this shouldn't happen but let's handle it
          print('User document missing, creating it now...');
          await ensureUserDocument(userCredential.user!);
        } else {
          // Verify they're not trying to login as player when they're a coach
          final userData = userDoc.data()!;
          if (userData['role'] == 'coach') {
            await _auth.signOut();
            throw 'This account is registered as a coach. Please use coach login instead.';
          }
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw e.toString();
    }
  }

  // Sign in with email and password - COACH LOGIN
  Future<Map<String, dynamic>> signInCoachWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      print('Attempting COACH login...');

      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Check if user exists in coaches collection
        final coachDoc = await _firestore.collection('coaches').doc(userCredential.user!.uid).get();

        if (!coachDoc.exists) {
          await _auth.signOut();
          throw 'Coach profile not found. Please apply to become a coach first.';
        }

        final coachData = coachDoc.data()!;

        // Check coach status
        if (coachData['status'] != 'approved') {
          await _auth.signOut();
          String message = 'Your coach application is still under review.';
          if (coachData['status'] == 'rejected') {
            message = 'Your coach application was rejected. Please contact support.';
          }
          throw message;
        }

        if (coachData['isActive'] != true) {
          await _auth.signOut();
          throw 'Your coach account is inactive. Please contact support.';
        }

        // Return coach data for the app to use
        return {
          'success': true,
          'userCredential': userCredential,
          'coachData': coachData,
        };
      }

      throw 'Authentication failed';
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw e.toString();
    }
  }

  // Updated main sign in method that routes to appropriate login
  Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    // This is for backward compatibility - default to player login
    return await signInPlayerWithEmailAndPassword(
        email: email,
        password: password
    );
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw 'Error signing out. Please try again.';
    }
  }

  // Reset password
  Future<void> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // Ensure user document exists - PLAYERS ONLY
  Future<void> ensureUserDocument(User user) async {
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) {
        // Create missing user document (PLAYER only)
        final userData = {
          'uid': user.uid,
          'name': user.displayName ?? user.email?.split('@')[0] ?? 'User',
          'email': user.email,
          'role': 'player', // Always player
          'createdAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'profileImageUrl': null,
          'phoneNumber': null,
          'dateOfBirth': null,
        };

        await _firestore.collection('users').doc(user.uid).set(userData);
        print('Created missing user document for ${user.email}');
      } else {
        print('User document already exists for ${user.email}');
      }
    } catch (e) {
      print('Error ensuring user document: $e');
      // Don't throw here as this might prevent login
    }
  }

  // Get user data from Firestore (PLAYERS)
  Future<DocumentSnapshot> getUserData(String uid) async {
    try {
      return await _firestore.collection('users').doc(uid).get();
    } catch (e) {
      throw 'Error fetching user data.';
    }
  }

  // Get coach data from Firestore (COACHES)
  Future<DocumentSnapshot> getCoachData(String uid) async {
    try {
      return await _firestore.collection('coaches').doc(uid).get();
    } catch (e) {
      throw 'Error fetching coach data.';
    }
  }

  // Get user data stream for real-time updates (PLAYERS)
  Stream<DocumentSnapshot> getUserDataStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  // Get coach data stream for real-time updates (COACHES)
  Stream<DocumentSnapshot> getCoachDataStream(String uid) {
    return _firestore.collection('coaches').doc(uid).snapshots();
  }

  // Update user profile (PLAYERS)
  Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? phoneNumber,
    String? profileImageUrl,
  }) async {
    try {
      Map<String, dynamic> updateData = {};

      if (name != null) updateData['name'] = name;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (profileImageUrl != null) updateData['profileImageUrl'] = profileImageUrl;

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('users').doc(uid).update(updateData);
    } catch (e) {
      throw 'Error updating user profile: $e';
    }
  }

  // Update coach profile (COACHES)
  Future<void> updateCoachProfile({
    required String uid,
    String? name,
    String? phoneNumber,
    String? bio,
    String? location,
    int? pricePerHour,
  }) async {
    try {
      Map<String, dynamic> updateData = {};

      if (name != null) updateData['name'] = name;
      if (phoneNumber != null) updateData['phone'] = phoneNumber;
      if (bio != null) updateData['bio'] = bio;
      if (location != null) updateData['location'] = location;
      if (pricePerHour != null) updateData['pricePerHour'] = pricePerHour;

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('coaches').doc(uid).update(updateData);
    } catch (e) {
      throw 'Error updating coach profile: $e';
    }
  }

  // Check what type of account this email belongs to
  Future<String> getAccountType(String email) async {
    try {
      // Check users collection first
      final usersQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (usersQuery.docs.isNotEmpty) {
        return 'player';
      }

      // Check coaches collection
      final coachesQuery = await _firestore
          .collection('coaches')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (coachesQuery.docs.isNotEmpty) {
        return 'coach';
      }

      return 'none';
    } catch (e) {
      print('Error checking account type: $e');
      return 'none';
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'invalid-credential':
        return 'Invalid credentials. Please check your email and password.';
      default:
        return 'Authentication error: ${e.message}';
    }
  }
}