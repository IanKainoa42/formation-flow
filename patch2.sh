#!/bin/bash
cat << 'PATCH' > patch.diff
--- FormationFlow/FormationHomeView.swift
+++ FormationFlow/FormationHomeView.swift
@@ -32,6 +32,8 @@
     @State private var isSwapMode = false
     @State private var triggerDeleteAthlete = false
     @State private var isIPadPortrait = false
+    @State private var showingFormationDeleteConfirmation = false
+    @State private var formationsToDelete: [UUID] = []

     private var isCompactLayout: Bool {
         let isPhone: Bool
@@ -155,6 +157,17 @@
         } message: {
             Text("This clears the roster, formations, notes, and transition data, then starts over with one empty formation.")
         }
+        .confirmationDialog(
+            formationsToDelete.count > 1 ? "Delete \(formationsToDelete.count) formations?" : "Delete formation?",
+            isPresented: $showingFormationDeleteConfirmation,
+            titleVisibility: .visible
+        ) {
+            Button("Delete", role: .destructive) {
+                deleteFormations(ids: formationsToDelete)
+            }
+            Button("Cancel", role: .cancel) {
+                formationsToDelete = []
+            }
+        } message: {
+            Text("This will remove the selected formations and their transitions. This cannot be undone.")
+        }
         .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
             updateOrientation()
         }
@@ -985,7 +998,8 @@
     }

     private func requestFormationDeletion(_ formationIDs: [UUID]) {
-        deleteFormations(ids: formationIDs)
+        formationsToDelete = formationIDs
+        showingFormationDeleteConfirmation = true
     }

     private func deleteSelectedFormation() {
PATCH
patch FormationFlow/FormationHomeView.swift < patch.diff
