// classconfig.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- ClassInfo Model ---
class ClassInfo {
  final String? id; // Firestore Document ID
  final String userId;
  final String subjectCode;
  final String subjectTitle;
  final String classSection;
  final String faculty;
  final String schedules;

  ClassInfo({
    this.id, 
    required this.userId,
    required this.subjectCode,
    required this.subjectTitle,
    required this.classSection,
    required this.faculty,
    required this.schedules,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'subjectCode': subjectCode,
      'subjectTitle': subjectTitle,
      'classSection': classSection,
      'faculty': faculty,
      'schedules': schedules,
    };
  }

  factory ClassInfo.fromMap(Map<String, dynamic> map, {String? id}) {
    return ClassInfo(
      id: id,
      userId: map['userId'] ?? '',
      subjectCode: map['subjectCode'] ?? '',
      subjectTitle: map['subjectTitle'] ?? '',
      classSection: map['classSection'] ?? '',
      faculty: map['faculty'] ?? '',
      schedules: map['schedules'] ?? '',
    );
  }
}

// Top-level parser used with compute()
Map<String, dynamic> _parseJson(String jsonText) {
  return jsonDecode(jsonText) as Map<String, dynamic>;
}

class ClassConfigPage extends StatefulWidget {
  const ClassConfigPage({super.key});

  @override
  State<ClassConfigPage> createState() => _ClassConfigPageState();
}
class _ClassConfigPageState extends State<ClassConfigPage> {
  String? _pickedFileName;
  final _formKey = GlobalKey<FormState>();

  final _subjectCodeController = TextEditingController();
  final _subjectTitleController = TextEditingController();
  final _classSectionController = TextEditingController();
  final _facultyController = TextEditingController();
  final _schedulesController = TextEditingController();

  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  late final GenerativeModel _geminiModel;
  bool _isModelReady = false;
  bool _isExtracting = false;
  
  // Removed _isCreating because the action is now instant

  @override
  @override
  void initState() {
    super.initState();
    if (_apiKey.isEmpty) {
      // show error after first frame so ScaffoldMessenger/BuildContext is available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showError('API Key missing');
      });
    } else {
      _geminiModel = GenerativeModel(
        model: 'gemini-2.5-pro', 
        apiKey: _apiKey,
      );
      _isModelReady = true;
    }
  }
  @override
  void dispose() {
    _subjectCodeController.dispose();
    _subjectTitleController.dispose();
    _classSectionController.dispose();
    _facultyController.dispose();
    _schedulesController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _pickPDF() async {
    if (!_isModelReady) {
      _showError('API Key not ready. Check launch.json');
      return;
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) {
      // ENHANCEMENT: Clear state if user cancels file selection
      setState(() {
        _pickedFileName = null;
      });
      return;
    }
    
    // File selected, proceed to extraction state
    PlatformFile file = result.files.first;
    setState(() {
      _pickedFileName = file.name;
      _isExtracting = true;
      _subjectCodeController.clear();
      _subjectTitleController.clear();
      _classSectionController.clear();
      _facultyController.clear();
      _schedulesController.clear();
    });

    try {
      Uint8List? fileBytes;
      if (kIsWeb) {
        fileBytes = file.bytes;
      } else {
        if (file.path != null) {
           final fileOnMobile = File(file.path!);
           fileBytes = await fileOnMobile.readAsBytes();
        }
      }

      if (fileBytes != null) {
         await _runGeminiExtraction(fileBytes);
      }
    } catch (e) {
      _showError('Failed to read file: $e');
    } finally {
      setState(() {
        _isExtracting = false;
      });
    }
  }

  // ENHANCEMENT: Improved error handling and robust data assignment.
  Future<void> _runGeminiExtraction(Uint8List fileBytes) async {
    const prompt = """
    Analyze the provided PDF document and extract the following information into a single JSON object.
    The root JSON object should contain the class details as top-level keys:
    - `subjectCode`
    - `subjectTitle`
    - `classSection`
    - `faculty`
    - `schedules` (array of strings)
    Only output the raw JSON object.
    """;

    final content = [
      Content.multi([TextPart(prompt), DataPart('application/pdf', fileBytes)])
    ];

    try {
      final response = await _geminiModel.generateContent(content);
      final text = response.text;
      
      if (text == null || text.isEmpty) {
        _showError('AI extraction failed: received empty response.');
        return;
      }

      String cleanJson = text.trim().replaceAll('```json', '').replaceAll('```', '');
      
      try {
        final data = await compute(_parseJson, cleanJson);
        // Use the null-aware operator and toString() for safer type handling
        _subjectCodeController.text = data['subjectCode']?.toString() ?? '';
        _subjectTitleController.text = data['subjectTitle']?.toString() ?? '';
        _classSectionController.text = data['classSection']?.toString() ?? '';
        _facultyController.text = data['faculty']?.toString() ?? '';
         
        // Robustly handle schedules as a List, defaulting to a comma-separated string
        if (data['schedules'] is List) {
          _schedulesController.text = (data['schedules'] as List).join(', ');
        } else {
          _schedulesController.text = data['schedules']?.toString() ?? '';
        }
      } on FormatException {
        _showError('AI output is not a valid JSON format. Check the PDF content.');
      } on TypeError {
        _showError('AI output is malformed (missing required fields).');
      }

    } catch (e) {
      // ENHANCEMENT: Show API errors to the user
      _showError('Gemini API Error: $e');
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: _isExtracting,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
    );
  }

  // --- ENHANCED: INSTANT CREATE ---
  void _createClass() {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('You must be logged in.');
      return;
    }

    // 1. Generate the ID locally immediately
    final docRef = FirebaseFirestore.instance.collection('classes').doc();

    final newClassMap = {
      'userId': user.uid,
      'subjectCode': _subjectCodeController.text,
      'subjectTitle': _subjectTitleController.text,
      'classSection': _classSectionController.text,
      'faculty': _facultyController.text,
      'schedules': _schedulesController.text,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // 2. Create the object WITH the ID to return to the UI instantly
    final createdClass = ClassInfo(
      id: docRef.id, // We use the generated ID here
      userId: user.uid,
      subjectCode: _subjectCodeController.text,
      subjectTitle: _subjectTitleController.text,
      classSection: _classSectionController.text,
      faculty: _facultyController.text,
      schedules: _schedulesController.text,
    );

    // 3. Save to Firestore in the background (Fire and Forget)
    // We use .set() because we already generated the reference
    docRef.set(newClassMap).catchError((error) {
      debugPrint("Error saving class in background: $error");
    });

    // 4. Close screen immediately (No waiting!)
    Navigator.pop(context, createdClass);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a New Class')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
               ElevatedButton.icon(
                  onPressed: _isExtracting ? null : _pickPDF,
                  icon: const Icon(Icons.upload_file),
                  // ENHANCEMENT: Update button label to show picked file name
                  label: Text(
                    _pickedFileName != null 
                      ? 'Re-select PDF (${_pickedFileName!})' 
                      : 'Upload Master list PDF',
                  ),
               ),
               const SizedBox(height: 20),
               if (_isExtracting) const LinearProgressIndicator(),
               const SizedBox(height: 20),
               _buildTextField(controller: _subjectCodeController, label: 'Subject Code', icon: Icons.qr_code),
               const SizedBox(height: 16),
               _buildTextField(controller: _subjectTitleController, label: 'Subject Title', icon: Icons.title),
               const SizedBox(height: 16),
               _buildTextField(controller: _classSectionController, label: 'Class Section', icon: Icons.group),
               const SizedBox(height: 16),
               _buildTextField(controller: _facultyController, label: 'Faculty', icon: Icons.person),
               const SizedBox(height: 16),
               _buildTextField(controller: _schedulesController, label: 'Schedules', icon: Icons.schedule),
               const SizedBox(height: 32),
               ElevatedButton(
                 onPressed: _isExtracting ? null : _createClass,
                 style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                 child: const Text('Create Class'),
               ),
            ],
          ),
        ),
      ),
    );
  }
}