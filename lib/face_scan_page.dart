// face_scan_page.dart - Modified for 3-Step Enrollment (Straight, Right, Left, 10x each)

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
import 'dart:typed_data';
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
      final inputImage = InputImage.fromFilePath(image.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);
      
      if (faces.length != 1) {
        setState(() {
          _statusMessage = faces.isEmpty 
              ? 'No face detected. Please ensure your face is fully visible.' 
              : 'Multiple faces detected. Ensure only your face is in the frame.';
          _isProcessing = false; // Allow retry
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

      UploadTask uploadTask;
      if (kIsWeb) {
        Uint8List bytes = await image.readAsBytes();
        uploadTask = storageRef.putData(bytes);
      } else {
        uploadTask = storageRef.putFile(File(image.path));
      }

      await uploadTask.whenComplete(() {});

      // 4. Update State and Transition
      _captureCount++;

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
    // In a real application, this is where you might initiate background 
    // processing on the 30 uploaded images (e.g., generating a feature vector).
    await Future.delayed(const Duration(seconds: 2)); // Simulate final processing
    
    setState(() {
      _currentState = FaceScanState.complete;
    });

    // 5. RETURN Success Signal
    if (mounted) {
      Navigator.pop(context, true); 
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