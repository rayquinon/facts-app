import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isUploadingMasterlist = false;
  bool _isUploadingExtracted = false;
  String _uploadStatus = 'Idle';
  final String _apiKey = const String.fromEnvironment('GEMINI_API_KEY');
  GenerativeModel? _masterlistModel;
  bool _masterlistUploaded = false;

  static const String _masterlistPrompt = '''Analyze the provided PDF document and extract the following information into a single JSON object.

The root JSON object should contain a nested array named "students".

1.  **Extract the student list:**
    * Iterate through the table of students, which may span multiple pages.
    * Create a JSON array named `students`.
    * For each student in the table, add a JSON object to the `students` array with the following keys:
        * `studentNo`: The "Student No"
        * `fullName`: The "Full Name"
        * `program`: The "Program"

Ensure you process all pages to find all students listed in the table, regardless of the total count. The final output should be ONLY the raw JSON object, with no introductory text, markdown formatting, or citations.''';

  @override
  void initState() {
    super.initState();
    if (_apiKey.isNotEmpty) {
      _masterlistModel = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: _apiKey,
      );
    }
  }

  void _showMessage(String text, [Color? color]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  Future<void> _uploadMasterlist() async {
    if (_masterlistModel == null) {
      _showMessage('GEMINI_API_KEY missing. Configure it to enable uploads.', Colors.red);
      return;
    }

    setState(() {
      _isUploadingMasterlist = true;
      _uploadStatus = 'Waiting for PDF selection...';
      _masterlistUploaded = false;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _uploadStatus = 'Upload cancelled.';
          _isUploadingMasterlist = false;
        });
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Failed to read PDF bytes.');
      }

      setState(() => _uploadStatus = 'Calling Gemini to extract students...');

      final response = await _masterlistModel!.generateContent([
        Content.multi([
          TextPart(_masterlistPrompt),
          DataPart('application/pdf', bytes),
        ])
      ]);

      var jsonText = response.text;
      if (jsonText == null || jsonText.trim().isEmpty) {
        throw Exception('Gemini returned empty output.');
      }

      jsonText = jsonText.trim().replaceAll('```json', '').replaceAll('```', '');
      setState(() => _uploadStatus = 'Parsing extracted details...');

      final parsed = await compute(_parseJsonToMap, jsonText);
      final students = (parsed['students'] as List<dynamic>? ?? []).cast<dynamic>();
      if (students.isEmpty) {
        throw Exception('No students found in the extracted data.');
      }

      final docId = await _persistStudents(
        fileName: file.name,
        students: students,
        origin: 'gemini-pdf',
      );

      setState(() => _uploadStatus = 'Upload complete! Saved to masterlists/$docId.');
      _masterlistUploaded = true;
      _showMessage('Masterlist uploaded: ${students.length} students saved.', Colors.green);
    } catch (e) {
      _showMessage('Masterlist upload failed: $e', Colors.red);
      setState(() => _uploadStatus = 'Error: $e');
    } finally {
      setState(() {
        _isUploadingMasterlist = false;
      });
    }
  }

  Future<void> _uploadExtractedDetails() async {
    if (!_masterlistUploaded) {
      _showMessage('Upload a masterlist PDF successfully before importing extracted details.', Colors.orange); 
      return;
    }

    setState(() {
      _isUploadingExtracted = true;
      _uploadStatus = 'Waiting for extracted JSON selection...';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _uploadStatus = 'Extracted upload cancelled.';
          _isUploadingExtracted = false;
        });
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Failed to read file bytes.');
      }

      final rawText = String.fromCharCodes(bytes).trim();
      final sanitized = rawText.replaceAll('```json', '').replaceAll('```', '').trim();
      setState(() => _uploadStatus = 'Parsing extracted JSON...');

      final parsed = await compute(_parseJsonToMap, sanitized);
      final students = (parsed['students'] as List<dynamic>? ?? []).cast<dynamic>();
      if (students.isEmpty) {
        throw Exception('No students array found in the provided file.');
      }

      await _saveStudentsCollection(
        fileName: file.name,
        students: students,
      );

      setState(() => _uploadStatus = 'Extracted details uploaded to students collection.');
      _showMessage('Extracted list uploaded: ${students.length} students saved to students collection.', Colors.green);
    } catch (e) {
      _showMessage('Extracted upload failed: $e', Colors.red);
      setState(() => _uploadStatus = 'Error: $e');
    } finally {
      setState(() => _isUploadingExtracted = false);
    }
  }

  Future<String> _persistStudents({
    required String fileName,
    required List<dynamic> students,
    required String origin,
  }) async {
    if (mounted) {
      setState(() => _uploadStatus = 'Saving ${students.length} students to Firestore...');
    }

    final masterlistDoc = _firestore.collection('masterlists').doc();
    await masterlistDoc.set({
      'fileName': fileName,
      'uploadedAt': FieldValue.serverTimestamp(),
      'studentCount': students.length,
      'origin': origin,
    });

    final batch = _firestore.batch();
    final studentsCollection = masterlistDoc.collection('students');

    for (final student in students) {
      if (student is! Map<String, dynamic>) continue;
      final docId = (student['studentNo']?.toString().trim().isNotEmpty ?? false)
          ? student['studentNo'].toString()
          : studentsCollection.doc().id;
      batch.set(studentsCollection.doc(docId), {
        'studentNo': student['studentNo']?.toString() ?? '',
        'fullName': student['fullName']?.toString() ?? '',
        'program': student['program']?.toString() ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return masterlistDoc.id;
  }

  Future<void> _saveStudentsCollection({
    required String fileName,
    required List<dynamic> students,
  }) async {
    if (mounted) {
      setState(() => _uploadStatus = 'Saving ${students.length} students to the students collection...');
    }

    final studentsCollection = _firestore.collection('students');
    final batch = _firestore.batch();

    for (final student in students) {
      if (student is! Map<String, dynamic>) continue;
      final docId = (student['studentNo']?.toString().trim().isNotEmpty ?? false)
          ? student['studentNo'].toString()
          : studentsCollection.doc().id;
      batch.set(studentsCollection.doc(docId), {
        'studentNo': student['studentNo']?.toString() ?? '',
        'fullName': student['fullName']?.toString() ?? '',
        'program': student['program']?.toString() ?? '',
        'sourceFile': fileName,
        'uploadedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin / Masterlist Upload')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: (_isUploadingMasterlist || _isUploadingExtracted)
                  ? null
                  : _uploadMasterlist,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload masterlist PDF (Gemini)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_isUploadingMasterlist || _isUploadingExtracted || !_masterlistUploaded)
                  ? null
                  : _uploadExtractedDetails,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Upload extracted details (JSON)'),
            ),
            const SizedBox(height: 8),
            Text(
              'Status: $_uploadStatus',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            if (_isUploadingMasterlist || _isUploadingExtracted) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _parseJsonToMap(String input) {
  return jsonDecode(input) as Map<String, dynamic>;
}
