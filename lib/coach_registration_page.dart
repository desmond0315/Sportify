import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

class CoachRegistrationPage extends StatefulWidget {
  const CoachRegistrationPage({Key? key}) : super(key: key);

  @override
  State<CoachRegistrationPage> createState() => _CoachRegistrationPageState();
}

class _CoachRegistrationPageState extends State<CoachRegistrationPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _experienceController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingUserData = true;
  bool _hasExistingAccount = false;
  String _selectedSport = 'Badminton';
  List<String> _selectedSpecialties = [];

  // File uploads
  File? _profileImageFile;
  String? _profileImageBase64;
  File? _licenseFile;
  String? _licenseBase64;
  String? _licenseFileName;
  File? _certificateFile;
  String? _certificateBase64;
  String? _certificateFileName;

  final List<String> _sports = [
    'Badminton',
    'Football',
    'Basketball',
    'Pickleball',
    'Hockey',
    'Tennis',
    'Volleyball',
    'Swimming',
  ];

  final List<String> _specialtyOptions = [
    'Beginner Training',
    'Advanced Techniques',
    'Competition Prep',
    'Youth Training',
    'Adult Training',
    'Fitness Conditioning',
    'Injury Recovery',
    'Team Strategy',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    setState(() => _isLoadingUserData = true);

    try {
      if (user == null) {
        // No user logged in - this is coming from signup page
        setState(() {
          _hasExistingAccount = false;
          _isLoadingUserData = false;
        });
        return;
      }

      // User is logged in
      setState(() => _hasExistingAccount = true);

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        setState(() {
          _nameController.text = userData['name'] ?? '';
          _emailController.text = userData['email'] ?? user.email ?? '';
          _phoneController.text = userData['phoneNumber'] ?? '';
        });
      } else {
        // Fallback to auth data
        setState(() {
          _nameController.text = user.displayName ?? '';
          _emailController.text = user.email ?? '';
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() => _isLoadingUserData = false);
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        final File imageFile = File(image.path);
        final Uint8List imageBytes = await imageFile.readAsBytes();
        final String base64String = base64Encode(imageBytes);

        setState(() {
          _profileImageFile = imageFile;
          _profileImageBase64 = base64String;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile image selected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickLicenseFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final File file = File(result.files.single.path!);
        final Uint8List fileBytes = await file.readAsBytes();
        final String base64String = base64Encode(fileBytes);

        setState(() {
          _licenseFile = file;
          _licenseBase64 = base64String;
          _licenseFileName = result.files.single.name;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('License document selected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting license: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickCertificateFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final File file = File(result.files.single.path!);
        final Uint8List fileBytes = await file.readAsBytes();
        final String base64String = base64Encode(fileBytes);

        setState(() {
          _certificateFile = file;
          _certificateBase64 = base64String;
          _certificateFileName = result.files.single.name;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Certificate selected successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting certificate: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;

    // Validation checks
    if (_selectedSpecialties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one specialty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_licenseBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload your coaching license'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_profileImageBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a profile picture'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? userUid;
      bool accountCreated = false;

      // If user doesn't have an account, create Firebase Auth account
      if (!_hasExistingAccount) {
        print('Creating Firebase Auth account for new coach...');

        try {
          final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: 'TempPassword123!', // Temporary password
          );

          userUid = userCredential.user?.uid;
          accountCreated = true;
          print('Firebase Auth account created: $userUid');

          // Update display name
          await userCredential.user?.updateDisplayName(_nameController.text.trim());

        } catch (authError) {
          print('Firebase Auth error: $authError');

          // Handle the PigeonUserDetails/ListObject32 error
          if (authError.toString().contains('PigeonUserDetails') ||
              authError.toString().contains('ListObject32')) {

            print('PigeonUserDetails error during coach registration, checking if user was created...');

            // Wait a moment and check if user was actually created
            await Future.delayed(Duration(seconds: 1));

            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null && currentUser.email == _emailController.text.trim()) {
              userUid = currentUser.uid;
              accountCreated = true;
              print('User was created despite error: $userUid');

              try {
                // Update display name
                await currentUser.updateDisplayName(_nameController.text.trim());
              } catch (updateError) {
                print('Error updating display name: $updateError');
              }
            } else {
              throw 'Account creation failed. Please try again.';
            }
          } else {
            throw authError;
          }
        }

        // Send password reset email if account was created successfully
        if (accountCreated && userUid != null) {
          try {
            await FirebaseAuth.instance.sendPasswordResetEmail(
                email: _emailController.text.trim()
            );
            print('Password reset email sent to coach');
          } catch (emailError) {
            print('Error sending password reset email: $emailError');
            // Don't fail the whole process if email fails
          }
        }
      } else {
        // Use existing user's UID
        userUid = _auth.currentUser?.uid;
        accountCreated = true;
      }

      if (!accountCreated || userUid == null) {
        throw 'Failed to create or verify user account';
      }

      // Generate a unique application ID
      final applicationId = _firestore.collection('coach_applications').doc().id;

      // Save to coach_applications collection
      final applicationData = {
        'id': applicationId,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'sport': _selectedSport,
        'location': _locationController.text.trim(),
        'bio': _bioController.text.trim(),
        'experience': _experienceController.text.trim(),
        'specialties': _selectedSpecialties,
        'pricePerHour': int.parse(_priceController.text),

        // File uploads
        'profileImageBase64': _profileImageBase64,
        'licenseBase64': _licenseBase64,
        'licenseFileName': _licenseFileName,
        'certificateBase64': _certificateBase64,
        'certificateFileName': _certificateFileName,

        'status': 'pending',
        'isVerified': false,
        'isActive': false,
        'hasAccount': true,
        'userId': userUid, // Store the Firebase Auth UID

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Save application with retry logic
      await _saveApplicationWithRetry(applicationId, applicationData);

      if (mounted) {
        setState(() => _isLoading = false);
        _showSuccessDialog();
      }

    } catch (e) {
      setState(() => _isLoading = false);
      print('Application submission error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Application failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

// Helper method to save application with retry logic
  Future<void> _saveApplicationWithRetry(String applicationId, Map<String, dynamic> applicationData, {int maxRetries = 3}) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < maxRetries) {
      try {
        attempts++;
        print('Saving application, attempt $attempts');

        await _firestore.collection('coach_applications').doc(applicationId).set(applicationData);

        // Verify the document was created
        await Future.delayed(Duration(milliseconds: 500));
        final doc = await _firestore.collection('coach_applications').doc(applicationId).get();
        if (doc.exists) {
          print('Application saved successfully');
          return; // Success!
        } else {
          throw Exception('Application save verification failed');
        }

      } catch (e) {
        print('Application save attempt $attempts failed: $e');
        lastError = e as Exception;

        if (attempts < maxRetries) {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 1000 * attempts));
        }
      }
    }

    // If we get here, all retries failed
    throw lastError ?? Exception('Failed to save application after $maxRetries attempts');
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
                  'Application Submitted!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _hasExistingAccount
                      ? 'Your coach application has been submitted successfully. Our admin team will review your application within 24-48 hours. You will receive an email with further instructions once approved.'
                      : 'Your coach application has been submitted successfully! We\'ve created your account and sent a password reset email to ${_emailController.text.trim()}. Please check your email to set your password. Our admin team will review your application within 24-48 hours.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      Navigator.of(context).pop(); // Go back to previous screen
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8A50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserData) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: _buildAppBar(),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8A50)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderSection(),
              const SizedBox(height: 32),
              _buildUserInfoSection(),
              const SizedBox(height: 24),
              _buildProfileImageSection(),
              const SizedBox(height: 24),
              _buildBasicInfoSection(),
              const SizedBox(height: 24),
              _buildExperienceSection(),
              const SizedBox(height: 24),
              _buildDocumentsSection(),
              const SizedBox(height: 24),
              _buildSpecialtiesSection(),
              const SizedBox(height: 24),
              _buildPricingSection(),
              const SizedBox(height: 32),
              _buildSubmitButton(),
            ],
          ),
        ),
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
        'Register as Coach',
        style: TextStyle(
          color: Color(0xFF2D3748),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8A50), Color(0xFFE8751A)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school,
              color: Color(0xFFFF8A50),
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Become a Coach',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Share your expertise and help others improve their game',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
              const Icon(Icons.info_outline, color: Color(0xFFFF8A50)),
              const SizedBox(width: 8),
              const Text(
                'Your Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Name Field
          _buildTextField(
            controller: _nameController,
            label: 'Full Name',
            icon: Icons.person_outline,
            hintText: 'Enter your full name',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your full name';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Email Field
          _buildTextField(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            hintText: 'Enter your email address',
            keyboardType: TextInputType.emailAddress,
            enabled: !_hasExistingAccount, // Disable if user is already logged in
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email address';
              }
              if (!RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(value)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Phone Field
          _buildTextField(
            controller: _phoneController,
            label: 'Phone Number',
            icon: Icons.phone_outlined,
            hintText: 'Enter your phone number',
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your phone number';
              }
              return null;
            },
          ),

          const SizedBox(height: 12),
          Text(
            _hasExistingAccount
                ? 'This information will be used for your coach profile.'
                : 'This information will be used to create your account and coach profile.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileImageSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Picture',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFF8A50).withOpacity(0.3),
                      width: 2,
                    ),
                    color: Colors.grey[100],
                  ),
                  child: _profileImageFile != null
                      ? ClipOval(
                    child: Image.file(
                      _profileImageFile!,
                      fit: BoxFit.cover,
                    ),
                  )
                      : Icon(
                    Icons.camera_alt,
                    size: 40,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _pickProfileImage,
                  icon: const Icon(Icons.upload, size: 18),
                  label: Text(_profileImageFile != null ? 'Change Photo' : 'Upload Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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

  Widget _buildBasicInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Coaching Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 20),
          _buildDropdown(
            label: 'Primary Sport',
            value: _selectedSport,
            items: _sports,
            onChanged: (value) {
              setState(() {
                _selectedSport = value!;
              });
            },
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _locationController,
            label: 'Training Location',
            icon: Icons.location_on_outlined,
            hintText: 'Mainland or Island',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your training location';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _bioController,
            label: 'About You',
            icon: Icons.person_outline,
            maxLines: 4,
            hintText: 'Tell us about your coaching philosophy, achievements, and what makes you unique...',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please tell us about yourself';
              }
              if (value.length < 50) {
                return 'Please provide at least 50 characters';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Experience & Qualifications',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _experienceController,
            label: 'Years of Experience',
            icon: Icons.timeline_outlined,
            hintText: 'e.g., "5 years" or "3+ years"',
            keyboardType: TextInputType.text,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your experience';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Required Documents',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload your coaching license and certificates (PDF or Image)',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),

          // License Upload
          _buildFileUploadCard(
            title: 'Coaching License',
            subtitle: 'Required - Upload your coaching license',
            fileName: _licenseFileName,
            onTap: _pickLicenseFile,
            isRequired: true,
          ),

          const SizedBox(height: 16),

          // Certificate Upload
          _buildFileUploadCard(
            title: 'Certificates',
            subtitle: 'Upload relevant certificates or qualifications',
            fileName: _certificateFileName,
            onTap: _pickCertificateFile,
            isRequired: false,
          ),
        ],
      ),
    );
  }

  Widget _buildFileUploadCard({
    required String title,
    required String subtitle,
    required String? fileName,
    required VoidCallback onTap,
    required bool isRequired,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: fileName != null ? const Color(0xFF4CAF50) : Colors.grey[300]!,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: fileName != null
                ? const Color(0xFF4CAF50).withOpacity(0.1)
                : const Color(0xFFFF8A50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            fileName != null ? Icons.check_circle : Icons.upload_file,
            color: fileName != null ? const Color(0xFF4CAF50) : const Color(0xFFFF8A50),
          ),
        ),
        title: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D3748),
              ),
            ),
            if (isRequired)
              const Text(
                ' *',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            if (fileName != null) ...[
              const SizedBox(height: 4),
              Text(
                fileName,
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        trailing: Icon(
          fileName != null ? Icons.edit : Icons.add,
          color: const Color(0xFFFF8A50),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSpecialtiesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Specialties',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select your areas of expertise (choose multiple)',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _specialtyOptions.map((specialty) {
              final isSelected = _selectedSpecialties.contains(specialty);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedSpecialties.remove(specialty);
                    } else {
                      _selectedSpecialties.add(specialty);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF8A50)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF8A50)
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: Text(
                    specialty,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF2D3748),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pricing',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _priceController,
            label: 'Price per Hour (RM)',
            icon: Icons.attach_money_outlined,
            hintText: 'e.g., 80',
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your hourly rate';
              }
              final price = int.tryParse(value);
              if (price == null || price <= 0) {
                return 'Please enter a valid price';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          enabled: enabled,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: enabled ? const Color(0xFF2D3748) : Colors.grey[600],
          ),
          decoration: InputDecoration(
            hintText: hintText,
            filled: !enabled,
            fillColor: !enabled ? Colors.grey[100] : null,
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A50).withOpacity(enabled ? 0.1 : 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: const Color(0xFFFF8A50).withOpacity(enabled ? 1.0 : 0.5),
                size: 20,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF8A50)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8A50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.sports,
                color: Color(0xFFFF8A50),
                size: 20,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF8A50)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFFF8A50),
            Color(0xFFFF6B35),
            Color(0xFFE8751A),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A50).withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitApplication,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
          _hasExistingAccount ? 'SUBMIT APPLICATION' : 'CREATE ACCOUNT & SUBMIT',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}