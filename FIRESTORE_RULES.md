# Recommended Firestore Rules for F.A.C.T.S

These example rules provide basic protections. Adapt them to your exact project layout and security model before deploying.

Rules (example):

service cloud.firestore {
  match /databases/{database}/documents {

    // Users: users can read their own document and write only if authenticated
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null && request.auth.uid == userId;
      allow update: if request.auth != null && request.auth.uid == userId;
      allow delete: if false; // prevent client-side deletion of user documents
    }

    // Classes: only the owner (userId) can create/update/delete
    match /classes/{classId} {
      allow read: if resource.data.userId == request.auth.uid || request.auth != null;
      allow create: if request.auth != null && request.auth.uid == request.resource.data.userId;
      allow update, delete: if request.auth != null && request.auth.uid == resource.data.userId;

      // Students subcollection: only owners can write, authenticated users can read
      match /students/{studentId} {
        allow read: if request.auth != null; // or restrict to class owner if desired
        allow create: if request.auth != null && get(/databases/$(database)/documents/classes/$(classId)).data.userId == request.auth.uid;
        allow update: if request.auth != null && get(/databases/$(database)/documents/classes/$(classId)).data.userId == request.auth.uid;
        allow delete: if false;
      }
    }

    // Default deny
    match /{document=**} {
      allow read, write: if false;
    }
  }
}

Notes & Recommendations:
- Always test rules using the Firebase Emulator Suite before deploying to production.
- Tailor `read` rules for student lists: if you want only class owners to see the student data, restrict `read` similarly to `create/update`.
- Consider adding additional constraints (e.g., field validation) using `request.resource.data` to prevent clients writing unexpected fields or types.
- For sensitive operations (face data), prefer uploading to Firebase Storage with stricter rules and storing only references in Firestore.
