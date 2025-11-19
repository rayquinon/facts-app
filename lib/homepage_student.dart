// homepage_student.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  final user = FirebaseAuth.instance.currentUser;

  // Filters
  String selectedClass = 'All Classes';
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  List<String> _availableClasses = ['All Classes'];

  void _prevMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1);
    });
  }

  String _monthLabel(DateTime dt) {
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${monthNames[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Center(child: Text('Please log in to view attendance.'));
    }

    // Query attendance across all classes for this student (collection group)
    final attendanceStream = FirebaseFirestore.instance
        .collectionGroup('attendance')
        .where('studentId', isEqualTo: user!.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Dashboard')),
      body: StreamBuilder<QuerySnapshot>(
        stream: attendanceStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final docs = snapshot.data?.docs ?? [];

          // Build available classes list from docs
          final classes = <String>{};
          for (var d in docs) {
            final classTitle = (d.data() as Map<String, dynamic>?)?['classTitle']
                ?? (d.data() as Map<String, dynamic>?)?['subjectTitle']
                ?? (d.data() as Map<String, dynamic>?)?['className']
                ?? (d.data() as Map<String, dynamic>?)?['classId']
                ?? 'Unknown Class';
            classes.add(classTitle.toString());
          }
          _availableClasses = ['All Classes', ...classes.toList()];

          // Helper to extract document date
          DateTime? _docDate(QueryDocumentSnapshot d) {
            final data = d.data() as Map<String, dynamic>?;
            if (data == null) return null;
            final ts = data['date'] ?? data['timestamp'] ?? data['createdAt'] ?? data['time'];
            if (ts is Timestamp) return ts.toDate().toLocal();
            if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
            if (ts is String) {
              try {
                return DateTime.parse(ts).toLocal();
              } catch (_) {
                return null;
              }
            }
            return null;
          }

          // Filter by selected month and class
          final filtered = docs.where((d) {
            final data = d.data() as Map<String, dynamic>?;
            if (data == null) return false;

            // class filter
            final classTitle = data['classTitle'] ?? data['subjectTitle'] ?? data['className'] ?? data['classId'];
            if (selectedClass != 'All Classes' && classTitle != null && classTitle.toString() != selectedClass) {
              return false;
            }

            final date = _docDate(d);
            if (date == null) return false;
            return date.year == selectedMonth.year && date.month == selectedMonth.month;
          }).toList();

          // Compute counts
          int present = 0, absent = 0, late = 0;
          for (var d in filtered) {
            final data = d.data() as Map<String, dynamic>?;
            final status = (data?['status'] ?? data?['attendanceStatus'])?.toString().toLowerCase() ?? '';
            if (status.contains('present')) present++;
            else if (status.contains('late')) late++;
            else if (status.contains('absent')) absent++;
            else {
              // Unknown mapping: try numeric codes
              final code = data?['statusCode'];
              if (code == 1) present++;
              else if (code == 2) late++;
              else if (code == 3) absent++;
            }
          }

          final total = present + absent + late;

          Widget _statCard(String label, int count, Color color) {
            final pct = total > 0 ? (count / total * 100).round() : 0;
            return Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(count.toString(), style: TextStyle(fontSize: 28, color: color, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('$pct%')
                    ],
                  ),
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Filters row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedClass,
                        items: _availableClasses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (v) => setState(() { selectedClass = v ?? 'All Classes'; }),
                        decoration: const InputDecoration(labelText: 'Class'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _prevMonth,
                      child: const Icon(Icons.chevron_left),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(_monthLabel(selectedMonth), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    OutlinedButton(
                      onPressed: _nextMonth,
                      child: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stats
                Row(
                  children: [
                    _statCard('Present', present, Colors.green),
                    const SizedBox(width: 8),
                    _statCard('Late', late, Colors.orange),
                    const SizedBox(width: 8),
                    _statCard('Absent', absent, Colors.red),
                  ],
                ),
                const SizedBox(height: 16),

                // Recent Records list
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: filtered.isEmpty
                          ? const Center(child: Text('No attendance records for the selected filters.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final d = filtered[index];
                                final data = d.data() as Map<String, dynamic>?;
                                final status = (data?['status'] ?? data?['attendanceStatus'])?.toString() ?? 'unknown';
                                final classTitle = data?['classTitle'] ?? data?['subjectTitle'] ?? data?['className'] ?? d.id;
                                final date = _docDate(d);
                                final dateLabel = date != null ? '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}' : 'Unknown date';
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: status.toLowerCase().contains('present') ? Colors.green : (status.toLowerCase().contains('late') ? Colors.orange : Colors.red),
                                    child: Text(status[0].toUpperCase()),
                                  ),
                                  title: Text(classTitle.toString()),
                                  subtitle: Text(dateLabel),
                                  trailing: Text(status.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
