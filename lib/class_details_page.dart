// class_details_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'classconfig.dart'; // Import to access ClassInfo

class ClassDetailsPage extends StatelessWidget {
  final ClassInfo classInfo;

  const ClassDetailsPage({super.key, required this.classInfo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(classInfo.subjectTitle),
            Text(
              classInfo.classSection,
              style: const TextStyle(fontSize: 12.0),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Monitoring Sheet: ${classInfo.subjectCode}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // Fetch the 'students' subcollection for this specific class
              stream: FirebaseFirestore.instance
                  .collection('classes')
                  .doc(classInfo.id) // We need the ID here
                  .collection('students')
                  .orderBy('fullName') // Optional: Sort by name
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final students = snapshot.data?.docs ?? [];

                if (students.isEmpty) {
                  return const Center(
                    child: Text(
                      'No students found.\nUpload a Master List PDF to populate.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                // Scrollable Table Implementation
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Student No')),
                        DataColumn(label: Text('Full Name')),
                        DataColumn(label: Text('Program')),
                        // The 3 additional monitoring columns
                        DataColumn(label: Text('Present')),
                        DataColumn(label: Text('Late')),
                        DataColumn(label: Text('Absent')),
                      ],
                      rows: students.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return DataRow(cells: [
                          DataCell(Text(data['studentNo'] ?? '')),
                          DataCell(Text(data['fullName'] ?? '')),
                          DataCell(Text(data['program'] ?? '')),
                          // Checkboxes for the monitoring columns
                          DataCell(Checkbox(value: false, onChanged: (v) {})),
                          DataCell(Checkbox(value: false, onChanged: (v) {})),
                          DataCell(Checkbox(value: false, onChanged: (v) {})),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}