// user_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: unused_import
import 'user_type_enum.dart'; // <-- Use the new dedicated enum file

class UserModel {
  final String uid;
  final String email;
  final String fullName;
  final String userType; 
  final String specificId; 

  UserModel({
    required this.uid,
    required this.email,
    required this.fullName,
    // Note: The constructor parameter 'userType' should technically be a String 
    // here because that's what Firestore expects in the Map, 
    // but using the enum internally is better practice. 
    // We will keep it as String for consistency with the toMap() method.
    required this.userType, 
    required this.specificId,
  });

  // Convert UserModel to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'userType': userType,
      'fullName': fullName,
      'specificId': specificId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}