// upload_class_list.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:math';
import 'classconfig.dart';


// Using shared `ClassInfo` from `classconfig.dart` to avoid duplicate models.


class UploadClassListPage extends StatefulWidget {
  final ClassInfo classInfo;

  const UploadClassListPage({super.key, required this.classInfo});

  @override
  State<UploadClassListPage> createState() => _UploadClassListPageState();
}

class _UploadClassListPageState extends State<UploadClassListPage> {
  bool _isExtracting = false;
  String? _pickedFileName;
  String _statusMessage = 'Select a PDF file to extract the student list.';

  // Keep a single model instance to avoid re-creating it every upload
  final String _apiKey = const String.fromEnvironment('GEMINI_API_KEY');
  GenerativeModel? _model;
  // Upload progress tracking
  int _uploadedCount = 0;
  int _totalStudents = 0;

  @override
  void initState() {
    super.initState();
    _statusMessage = 'Ready to upload list for: ${widget.classInfo.subjectCode} - ${widget.classInfo.classSection}';

    if (_apiKey.isNotEmpty) {
      _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnackbar('API Key not found. Please set GEMINI_API_KEY.', isError: true);
      });
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : Colors.teal,
        ),
      );
    }
  }

  Future<void> _pickAndExtractPdfAndSaveStudents() async {
    const int maxRetries = 3;
    const baseDelay = Duration(seconds: 2);
    final classId = widget.classInfo.id;

    if (_model == null) {
      _showSnackbar('API Key not found. Cannot proceed.', isError: true);
      return;
    }
    
    if (classId == null) {
      _showSnackbar('Error: Class ID is missing.', isError: true);
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, 
      );
    } catch (e) {
      _showSnackbar('File picker failed: $e', isError: true);
      return;
    }

    if (result == null || result.files.isEmpty) {
      // User cancelled
      return;
    }

    final fileBytes = result.files.first.bytes;
    if (fileBytes == null) return;

    final fileName = result.files.first.name;

    setState(() {
      _isExtracting = true;
      _pickedFileName = fileName;
      _statusMessage = 'Processing $fileName...';
    });

    final prompt = TextPart('''
Analyze the provided PDF document and extract the following information into a single JSON object.

The root JSON object should contain a nested array named "students".

1.  **Extract the student list:**
    * Iterate through the table of students, which may span multiple pages.
    * Create a JSON array named `students`.
    * For each student in the table, add a JSON object to the `students` array with the following keys:
        * `studentNo`: The "Student No"
        * `fullName`: The "Full Name"
        * `program`: The "Program"

Ensure you process all pages to find all students listed in the table, regardless of the total count. The final output should be ONLY the raw JSON object.
''');

    final pdfPart = DataPart('application/pdf', fileBytes);
    
    // --- RETRY LOGIC with exponential backoff ---
    GenerateContentResponse? response;
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        response = await _model!.generateContent([
          Content.multi([prompt, pdfPart])
        ]);
        break;
      } on GenerativeAIException catch (e) {
        final isTransient = e.message.contains('503') || e.message.contains('UNAVAILABLE');
        attempts++;
        if (isTransient && attempts < maxRetries) {
          final wait = Duration(milliseconds: baseDelay.inMilliseconds * (1 << (attempts - 1)));
          _showSnackbar('Model overloaded. Retrying in ${wait.inSeconds}s... (Attempt $attempts/$maxRetries)', isError: true);
          await Future.delayed(wait);
          continue;
        }
        rethrow;
      }
    }
    // --- END RETRY LOGIC ---

    try {
      String? jsonText = response?.text; 
      if (jsonText != null) {
        jsonText = jsonText.trim().replaceAll('```json', '').replaceAll('```', '');

        // Parse JSON off the UI thread to keep the UI responsive
        final data = await compute(_parseJsonToMap, jsonText);
        final students = (data['students'] as List<dynamic>?) ?? <dynamic>[];

        final collectionRef = FirebaseFirestore.instance
            .collection('classes')
            .doc(classId)
            .collection('students');

        // Chunk commits to avoid exceeding Firestore batch limits
        _uploadedCount = 0;
        _totalStudents = students.length;
        const int chunkSize = 400; // safely under 500

        for (int start = 0; start < students.length; start += chunkSize) {
          final end = min(start + chunkSize, students.length);
          final chunk = students.sublist(start, end);

          final batch = FirebaseFirestore.instance.batch();
          for (var student in chunk) {
            final docRef = collectionRef.doc();
            batch.set(docRef, {
              'studentNo': student['studentNo'],
              'fullName': student['fullName'],
              'program': student['program'],
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          await batch.commit();

          if (mounted) {
            setState(() {
              _uploadedCount += chunk.length;
              _statusMessage = 'Uploaded $_uploadedCount / $_totalStudents students';
            });
          }
        }

        if (mounted) {
          setState(() {
            _statusMessage = 'Success! Added ${_totalStudents} students to ${widget.classInfo.subjectCode}.';
          });
        }
        _showSnackbar('Success! Added ${_totalStudents} students.', isError: false);

      } else {
        throw Exception('Received no data from API.');
      }
    } on FormatException {
      _showSnackbar('AI output is not a valid JSON format. Check the PDF content.', isError: true);
    } on TypeError {
      _showSnackbar('AI output is malformed (missing required fields).', isError: true);
    } catch (e) {
      print('Extraction/Save Error: $e');
      _showSnackbar('Extraction failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isExtracting = false;
        });
      }
    }
  }
  
  Widget _buildStudentListTable() {
    if (widget.classInfo.id == null) {
        return const Center(child: Text("Cannot load students: Class ID missing."));
    }
    
    final studentsStream = FirebaseFirestore.instance
        .collection('classes')
        .doc(widget.classInfo.id)
        .collection('students')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
        stream: studentsStream,
        builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
                return Center(child: Text('Error loading students: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No students found. Upload a PDF to populate the list.'),
                ));
            }

            final students = snapshot.data!.docs;
            
            return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                    columns: const [
                        DataColumn(label: Text('Student No', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Program', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: students.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return DataRow(cells: [
                            DataCell(Text(data['studentNo']?.toString() ?? '-')),
                            DataCell(Text(data['fullName']?.toString() ?? '-')),
                            DataCell(Text(data['program']?.toString() ?? '-')),
                        ]);
                    }).toList(),
                ),
            );
        },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reuse the existing layout but add a small progress indicator at the top
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload List for ${widget.classInfo.subjectCode}'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
                if (_isExtracting) const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: LinearProgressIndicator(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isExtracting ? null : _pickAndExtractPdfAndSaveStudents,
                  icon: _isExtracting
                      ? const SizedBox(
                          width: 18, 
                          height: 18, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(_pickedFileName != null 
                    ? 'Re-upload List (${_pickedFileName!})' 
                    : 'Select Student List PDF'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Extracted Student Data Preview:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_totalStudents > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _totalStudents > 0 ? _uploadedCount / _totalStudents : null,
                        ),
                        const SizedBox(height: 8),
                        Text('Uploaded $_uploadedCount / $_totalStudents'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // --- Student List Table ---
          Expanded(
            child: _buildStudentListTable(),
          ),
        ],
      ),
    );
  }
}

// Helper to parse JSON on a background isolate
Map<String, dynamic> _parseJsonToMap(String jsonText) {
  return jsonDecode(jsonText) as Map<String, dynamic>;
}