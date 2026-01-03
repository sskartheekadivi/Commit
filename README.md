# Commit - Habit Tracker

This is a Flutter-based, offline-first application designed to help you commit to your goals by tracking your habits. It's inspired by the popular "Loop Habit Tracker" for Android. This project was generated as Phase 1 and focuses on core local functionality.

## Features

- **Offline-First**: All data is stored locally in a SQLite database. No internet connection is required.
- **Multiple Habit Types**: Supports Boolean (yes/no), Measurable (e.g., 5 liters of water), Enum (e.g., mood), and Description (e.g., daily journal) habits.
- **Data Visualization**: A GitHub-style heatmap calendar shows your progress for the last year.
- **Modern Tech Stack**: Built with Flutter, Riverpod for state management, Drift for database access, and GoRouter for navigation.

## Getting Started

### 1. Prerequisites

- Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed and configured on your machine.
- An IDE like VS Code with the Flutter extension or Android Studio.

### 2. Install Dependencies

First, get all the required packages from `pub.dev`. Run the following command from the project's root directory:

```sh
flutter pub get
```

### 3. Generate Code

This project uses code generation for the database (Drift) and state management (Riverpod). Before running the app, you must run the `build_runner` to generate the necessary files.

Execute the following command in your terminal:

```sh
dart run build_runner build --delete-conflicting-outputs
```

**Note**: If you modify any file containing `@riverpod` annotations or the `database.dart` file, you will need to run this command again to update the generated code.

### 4. Run the Application

Once the dependencies are installed and the code is generated, you can run the app on a connected device or emulator.

```sh
flutter run
```

That's it! The application should now be running on your device.