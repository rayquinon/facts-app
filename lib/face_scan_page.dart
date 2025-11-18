// face_scan_page.dart - Modified for 3-Step Enrollment (Straight, Right, Left, 10x each)

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart' show kIsWeb; 
import 'dart:io' show File, Platform;
import 'package:camera/camera.dart'; 

// Define the different stages of the enrollment process
enum FaceScanState {
  straight,
  right,
  left,
  processing,
  complete,
}

class FaceScanPage extends StatefulWidget {
  final String userIdentifier;

  const FaceScanPage({
    super.key,
    required this.userIdentifier, 
  });

  @override
  State<FaceScanPage> createState() => _FaceScanPageState();
}

class _FaceScanPageState extends State<FaceScanPage> {
  // --- Camera & ML Kit Setup ---
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate, 
      enableLandmarks: true, 
    ),
  );

  // --- Enrollment State Variables ---
  FaceScanState _currentState = FaceScanState.straight; // Start with straight pose
  int _captureCount = 0;
  final int _maxCapturesPerPose = 10;
  // Overall captures across all poses (3 poses * 10 captures = 30)
  int _totalCaptured = 0;
  final int _expectedTotalCaptures = 3 * 10;
  // Keep track of uploaded storage paths for this enrollment
  final List<String> _uploadedFiles = [];
  // Keep track of public download URLs for easier access by recognition services
  final List<String> _uploadedUrls = [];
  
  // --- UI State ---
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _statusMessage = 'Initializing camera...';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  /// Determines the current instruction message based on the enrollment state.
  String _getStatusMessage() {
    if (!_isCameraInitialized) return _statusMessage;

    switch (_currentState) {
      case FaceScanState.straight:
        return 'Instruction: Stay still, face in camera frame. (${_captureCount} / $_maxCapturesPerPose captured)';
      case FaceScanState.right:
        return 'Instruction: Look to the RIGHT. (${_captureCount} / $_maxCapturesPerPose captured)';
      case FaceScanState.left:
        return 'Instruction: Look to the LEFT. (${_captureCount} / $_maxCapturesPerPose captured)';
      case FaceScanState.processing:
        return 'Finalizing enrollment and processing 30 images...';
      case FaceScanState.complete:
        return 'Enrollment successful! Returning to registration.';
      // REMOVED 'default' CASE: This resolves the 'unreachable_switch_default' warning 
      // because all enum values are explicitly handled above.
    }
  }

  /// Initializes the camera controller.
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() { _statusMessage = "No camera found."; _isCameraInitialized = false; });
        return;
      }

      CameraDescription cameraDescription = cameras.first;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        cameraDescription = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
      }

      _cameraController = CameraController(
        cameraDescription,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _statusMessage = 'Camera ready. Tap "Capture Face" to begin.';
      });
    } on CameraException catch (e) {
      // FIX: Removed Navigator.pop(context, null); to prevent page closure on error.
      setState(() { 
        _statusMessage = "Camera error: ${e.code}. Check permissions."; 
        _isCameraInitialized = false; 
      });
    } catch (e) {
       // FIX: Removed Navigator.pop(context, null);
       setState(() { 
        _statusMessage = "An unexpected error occurred: ${e.toString()}"; 
        _isCameraInitialized = false; 
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose(); 
    _faceDetector.close();
    super.dispose();
  }

  /// The main function for the capture, validation, and storage loop.
  Future<void> _captureCurrentPose() async {
    if (!_isCameraInitialized || _isProcessing || _cameraController == null) return;
    if (_currentState == FaceScanState.processing || _currentState == FaceScanState.complete) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Capturing image for ${_currentState.name} pose...';
    });

    try {
      // 1. CAPTURE
      final XFile image = await _cameraController!.takePicture();

      // 2. Face Validation Logic (Ensuring one face is present)
      try {
        if (kIsWeb) {
          // MLKit face detection may not behave the same on web for XFile paths.
          // Fall back to optimistic validation on web (skip strict face count check).
        } else {
          final inputImage = InputImage.fromFilePath(image.path);
          final List<Face> faces = await _faceDetector.processImage(inputImage);
          if (faces.length == 1) {
          } else {
            setState(() {
              _statusMessage = faces.isEmpty
                  ? 'No face detected. Please ensure your face is fully visible.'
                  : 'Multiple faces detected. Ensure only your face is in the frame.';
              _isProcessing = false; // Allow retry
            });
            return;
          }
        }
      } catch (e) {
        // If face detection fails for any reason, allow retry but log the error
        setState(() {
          _statusMessage = 'Face validation failed: ${e.toString()}. Please retry.';
          _isProcessing = false;
        });
        return;
      }
      
      // 3. STORE (Upload Image to Firebase Storage)
      final poseName = _currentState.name;
      final fileIndex = (_captureCount + 1).toString().padLeft(2, '0');
      
      // Example Path: 'student_faces/S123456/straight_01.jpg'
      Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('student_faces')
          .child(widget.userIdentifier) 
          .child('${poseName}_$fileIndex.jpg'); 

      // 3. STORE (Upload Image to Firebase Storage) with retry
      Future<void> uploadWithRetry(Reference ref, XFile file) async {
        const int maxUploadAttempts = 3;
        int attempt = 0;
        while (true) {
          attempt++;
          try {
            if (kIsWeb) {
              final bytes = await file.readAsBytes();
              await ref.putData(bytes).whenComplete(() {});
            } else {
              await ref.putFile(File(file.path)).whenComplete(() {});
            }
            return;
          } catch (e) {
            if (attempt >= maxUploadAttempts) rethrow;
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }

      await uploadWithRetry(storageRef, image);
      // Record the uploaded file path for later use (attendance/recognition mapping)
      try {
        _uploadedFiles.add(storageRef.fullPath);
      } catch (_) {
        // If fullPath isn't available for some reason, ignore silently
      }
      // Also attempt to get a download URL and save it for immediate use by recognition
      try {
        final url = await storageRef.getDownloadURL();
        _uploadedUrls.add(url);
      } catch (e) {
        // If we cannot get a download URL (security rules or timing), continue without it
        print('Warning: could not get download URL for ${storageRef.fullPath}: $e');
      }

      // 4. Update State and Transition
      _captureCount++;
      _totalCaptured++;

      if (_captureCount >= _maxCapturesPerPose) {
        _transitionToNextState();
      } else {
         // Update UI to show successful capture, stay in the loop
        setState(() {
          _statusMessage = 'Capture successful. Ready for capture ${(_captureCount + 1)} of $_maxCapturesPerPose.';
          _isProcessing = false;
        });
      }

    } on FirebaseException catch (e) {
      // FIX: Removed Navigator.pop(context, null);
      setState(() { 
        _statusMessage = 'Upload failed: ${e.message}. Please retry.'; 
        _isProcessing = false; // Re-enable button
      });
    } on CameraException catch (e) {
      // FIX: Removed Navigator.pop(context, null);
       setState(() { 
        _statusMessage = 'Camera capture failed: ${e.description}. Please retry.'; 
        _isProcessing = false; // Re-enable button
      });
    } catch (e) {
      // FIX: Removed Navigator.pop(context, null);
      setState(() { 
        _statusMessage = 'An unexpected error occurred: ${e.toString()}. Please retry.'; 
        _isProcessing = false; // Re-enable button
      });
    }
  }

  /// Moves the workflow to the next enrollment phase.
  void _transitionToNextState() {
    setState(() {
      _captureCount = 0;
      if (_currentState == FaceScanState.straight) {
        _currentState = FaceScanState.right;
      } else if (_currentState == FaceScanState.right) {
        _currentState = FaceScanState.left;
      } else if (_currentState == FaceScanState.left) {
        _currentState = FaceScanState.processing;
        _finalizeEnrollment(); // All captures done, finalize.
      }
    });
  }

  /// Finalizes the enrollment and sends the success signal.
  Future<void> _finalizeEnrollment() async {
    setState(() {
      _statusMessage = 'Finalizing enrollment...';
      _currentState = FaceScanState.processing;
    });

    try {
      // Simulate final processing time and optionally write a marker to Firestore
      await Future.delayed(const Duration(seconds: 2));

      // Persist enrollment metadata to Firestore so the recognition service can use it later.
      try {
        final docRef = FirebaseFirestore.instance.collection('face_enrollments').doc(widget.userIdentifier);
        await docRef.set({
          'userIdentifier': widget.userIdentifier,
          'uploadedFiles': _uploadedFiles,
          'uploadedUrls': _uploadedUrls,
          'completed': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // Log but don't fail finalization if Firestore write fails
        print('Warning: failed to write face enrollment metadata: $e');
      }

      setState(() {
        _currentState = FaceScanState.complete;
        _statusMessage = 'Enrollment successful! Returning to registration.';
      });

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _statusMessage = 'Finalization failed: ${e.toString()}';
        _currentState = FaceScanState.processing;
      });
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading/error screen if camera not ready
    if (!_isCameraInitialized || _cameraController == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face Enrollment')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Show indicator if initial message suggests loading, otherwise show error icon
              _statusMessage == 'Initializing camera...' 
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.error_outline, color: Colors.red, size: 50),
              const SizedBox(height: 20),
              Text(_statusMessage, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              // Allow manual exit from an unrecoverable error state
              TextButton(
                onPressed: () => Navigator.pop(context, null), 
                child: const Text('Cancel Enrollment/Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Main enrollment screen
    return PopScope( 
      canPop: !_isProcessing, 
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Face Enrollment Workflow'),
          backgroundColor: Colors.blueAccent,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  _getStatusMessage(), // Use the dynamic status message
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // Overall progress across all poses
                Text('Captured $_totalCaptured / $_expectedTotalCaptures images', style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 20),

                // Camera Preview Widget
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blueAccent, width: 4),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: _cameraController!.value.aspectRatio,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                
                // The main action button
                ElevatedButton.icon(
                  onPressed: _isProcessing || _currentState == FaceScanState.complete ? null : _captureCurrentPose,
                  icon: _isProcessing
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt),
                  label: Text(_isProcessing ? 'Capturing & Uploading...' : 'Capture Face'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _isProcessing || _currentState == FaceScanState.complete ? null : () => Navigator.pop(context, null), 
                  child: const Text('Cancel Enrollment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}