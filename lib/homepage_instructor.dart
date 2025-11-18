// homepage_instructor.dart (Modified)

// ignore_for_file: unnecessary_cast, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'classconfig.dart'; // Contains ClassInfo
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login.dart';
import 'class_details_page.dart'; // Assuming this is needed for Preview
import 'upload_class_list.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
    }
  }

  // --- Optimized Delete Class Function (Stream-compatible) ---
  void _deleteClass(String classId) async {
    try {
      // Deletion is handled by Firestore, StreamBuilder updates UI automatically.
      await FirebaseFirestore.instance.collection('classes').doc(classId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Class successfully deleted.')),
        );
      }
    } catch (e) {
      print('Error deleting class: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete class. Error: $e')),
        );
      }
    }
  }
  
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _addClass() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ClassConfigPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final classesStream = user == null
      ? null
      : FirebaseFirestore.instance
        .collection('classes')
        .where('userId', isEqualTo: user.uid)
        .snapshots();

    final List<Widget> _widgetOptions = <Widget>[
      StreamBuilder<QuerySnapshot>(
        stream: classesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No classes added yet.\nPress "Add a Class" to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }
          
          final classes = snapshot.data!.docs.map((doc) {
            final raw = doc.data();
            if (raw is Map<String, dynamic>) {
              return ClassInfo.fromMap(raw, id: doc.id);
            } else {
              return ClassInfo.fromMap({}, id: doc.id);
            }
          }).toList();
          
          return ClassListWidget(
              classes: classes,
              onDelete: _deleteClass,
            );
        },
      ),
      
      Center(
        child: ElevatedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Log Out'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Home' : 'Profile'),
        automaticallyImplyLeading: false, 
      ),
      body: _widgetOptions.elementAt(_selectedIndex), 
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _addClass,
              label: const Text('Add a Class'),
              icon: const Icon(Icons.add),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

// --- ClassListWidget is now stateless and only handles navigation ---
class ClassListWidget extends StatelessWidget {
  final List<ClassInfo> classes;
  final Function(String) onDelete;

  const ClassListWidget({super.key, required this.classes, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80.0), 
      itemCount: classes.length,
      itemBuilder: (context, index) {
        final cls = classes[index];
        final isClassIdValid = cls.id != null; 

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColorLight,
              child: Text(
                cls.subjectCode.isNotEmpty ? cls.subjectCode[0] : '?',
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark),
              ),
            ),
            title: Text(cls.subjectTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${cls.subjectCode} - ${cls.classSection}\n${cls.faculty}\n${cls.schedules}'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // --- UPLOAD BUTTON: Navigates to the new dedicated page ---
                    ElevatedButton.icon(
                      onPressed: isClassIdValid ? () {
                         Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UploadClassListPage(classInfo: cls),
                            ),
                          );
                      } : null,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Upload List'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    // --- PREVIEW BUTTON ---
                    ElevatedButton.icon(
                      onPressed: isClassIdValid ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ClassDetailsPage(classInfo: cls),
                          ),
                        );
                      } : null,
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('Preview'),
                    ),
                    // --- DELETE BUTTON ---
                    ElevatedButton.icon(
                      onPressed: isClassIdValid ? () async {
                        final shouldDelete = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Class'),
                            content: Text('Are you sure you want to delete "${cls.subjectTitle}"? This cannot be undone.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
                            ],
                          ),
                        );

                        if (shouldDelete == true) {
                          onDelete(cls.id!); 
                        }
                      } : null,
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('Delete'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }
}