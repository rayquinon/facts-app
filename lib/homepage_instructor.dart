// homepage_instructor.dart (Modified)

// ignore_for_file: unnecessary_cast, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'classconfig.dart'; // Contains ClassInfo
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_routes.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  // Pagination state
  final List<ClassInfo> _classes = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  final int _pageSize = 20;

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (Route<dynamic> route) => false);
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

      // Remove from local list for immediate UX feedback
      setState(() {
        _classes.removeWhere((c) => c.id == classId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Class successfully deleted.')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting class: $e');
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

  @override
  void initState() {
    super.initState();
    // Load the first page of classes
    _fetchInitial();
  }

  Future<void> _fetchInitial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _isLoading = true;
      _classes.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    try {
      Query query = FirebaseFirestore.instance
          .collection('classes')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);
      final snap = await query.get();
      final docs = snap.docs;
      final items = docs.map((doc) {
        final raw = doc.data();
        if (raw is Map<String, dynamic>) {
          return ClassInfo.fromMap(raw, id: doc.id);
        } else {
          return ClassInfo.fromMap({}, id: doc.id);
        }
      }).toList();
      setState(() {
        _classes.addAll(items);
        _lastDoc = docs.isNotEmpty ? docs.last : null;
        _hasMore = docs.length == _pageSize;
      });
    } catch (e) {
      debugPrint('Failed to load classes: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchNextPage() async {
    if (!_hasMore || _isLoading) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _lastDoc == null) return;
    setState(() => _isLoading = true);
    try {
      Query query = FirebaseFirestore.instance
          .collection('classes')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize);
      final snap = await query.get();
      final docs = snap.docs;
      final items = docs.map((doc) {
        final raw = doc.data();
        if (raw is Map<String, dynamic>) {
          return ClassInfo.fromMap(raw, id: doc.id);
        } else {
          return ClassInfo.fromMap({}, id: doc.id);
        }
      }).toList();
      setState(() {
        _classes.addAll(items);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length == _pageSize;
      });
    } catch (e) {
      debugPrint('Failed to load next page of classes: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addClass() {
    Navigator.pushNamed(context, AppRoutes.classConfig);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _widgetOptions = <Widget>[
      // Paginated list of classes
      Builder(
        builder: (context) {
          if (_isLoading && _classes.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_classes.isEmpty) {
            return const Center(
              child: Text(
                'No classes added yet.\nPress "Add a Class" to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80.0),
            itemCount: _classes.length + 1,
            itemBuilder: (context, index) {
              if (index < _classes.length) {
                final cls = _classes[index];
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
                            ElevatedButton.icon(
                              onPressed: isClassIdValid ? () {
                                Navigator.pushNamed(context, AppRoutes.uploadClassList, arguments: cls);
                              } : null,
                              icon: const Icon(Icons.upload_file, size: 18),
                              label: const Text('Upload List'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: isClassIdValid ? () {
                                Navigator.pushNamed(context, AppRoutes.classDetails, arguments: cls);
                              } : null,
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('Preview'),
                            ),
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
                                  _deleteClass(cls.id!);
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
              }

              // Load more row
              if (_hasMore) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Center(
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _fetchNextPage,
                            child: const Text('Load more'),
                          ),
                  ),
                );
              } else {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Center(child: Text('No more classes')), 
                );
              }
            },
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
                         Navigator.pushNamed(context, AppRoutes.uploadClassList, arguments: cls);
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
                        Navigator.pushNamed(context, AppRoutes.classDetails, arguments: cls);
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