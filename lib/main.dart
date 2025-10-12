import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'coach_dashboard_page.dart';
import 'auth_service.dart';
import 'utils/timezone_helper.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await TimezoneHelper.initialize();


  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sportify',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF9A56)),
        useMaterial3: true,
      ),
      home: AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          return FutureBuilder<Map<String, dynamic>>(
            future: _getUserTypeAndData(snapshot.data!.uid),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Loading your profile...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF2D3748),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Handle errors in user data loading
              if (userSnapshot.hasError) {
                print('Error loading user data: ${userSnapshot.error}');
                // If there's an error loading user data, sign out and go to login
                FirebaseAuth.instance.signOut();
                return const LoginPage();
              }

              if (!userSnapshot.hasData || userSnapshot.data!['type'] == 'none') {
                FirebaseAuth.instance.signOut();
                return const LoginPage();
              }

              final userType = userSnapshot.data!['type'];
              final userData = userSnapshot.data!['data'];

              // Check if coach and not approved
              if (userType == 'coach' && userData['isActive'] != true) {
                return const PendingApprovalPage();
              }

              // Route approved coaches to coach dashboard
              if (userType == 'coach' && userData['isActive'] == true) {
                return CoachDashboardPage(coachData: userData);
              }

              // Regular players go to HomePage
              String userName = userData['name'] ??
                  snapshot.data?.displayName ??
                  snapshot.data?.email?.split('@')[0] ??
                  'User';

              return HomePage(userName: userName);
            },
          );
        }

        return const LoginPage();
      },
    );
  }

  Future<Map<String, dynamic>> _getUserTypeAndData(String uid) async {
    final firestore = FirebaseFirestore.instance;

    try {
      // Check users collection first
      final userDoc = await firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        return {'type': 'player', 'data': userDoc.data()!};
      }

      // Check coaches collection
      final coachDoc = await firestore.collection('coaches').doc(uid).get();
      if (coachDoc.exists) {
        return {'type': 'coach', 'data': coachDoc.data()!};
      }

      return {'type': 'none', 'data': {}};
    } catch (e) {
      print('Error fetching user data: $e');

      // Handle the PigeonUserDetails error here too
      if (e.toString().contains('PigeonUserDetails') ||
          e.toString().contains('ListObject32')) {
        print('PigeonUserDetails error in user data fetch, retrying...');

        // Wait a moment and retry
        await Future.delayed(Duration(milliseconds: 1000));

        try {
          final userDoc = await firestore.collection('users').doc(uid).get();
          if (userDoc.exists) {
            return {'type': 'player', 'data': userDoc.data()!};
          }

          final coachDoc = await firestore.collection('coaches').doc(uid).get();
          if (coachDoc.exists) {
            return {'type': 'coach', 'data': coachDoc.data()!};
          }
        } catch (retryError) {
          print('Retry also failed: $retryError');
        }
      }

      return {'type': 'none', 'data': {}};
    }
  }

  Future<void> _ensureUserDocumentExists(User user) async {
    try {
      final authService = AuthService();
      await authService.ensureUserDocument(user);
    } catch (e) {
      print('Error ensuring user document in AuthWrapper: $e');
    }
  }
}

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.orange[100]!,
                      Colors.orange[200]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.schedule,
                  size: 60,
                  color: Colors.orange[600],
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                'Application Under Review',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              Text(
                'Thank you for applying to become a coach! Your application is currently being reviewed by our admin team.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.orange[200]!,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange[600],
                      size: 24,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'What happens next?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Our team will review your documents\n• We\'ll verify your credentials\n• You\'ll receive an email with the decision\n• Approval typically takes 24-48 hours',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFF8A50),
                    width: 2,
                  ),
                ),
                child: ElevatedButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'SIGN OUT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF8A50),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Need help? Contact us at support@sportify.com',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}