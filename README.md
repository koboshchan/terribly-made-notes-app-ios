# Notes iOS

Native SwiftUI iOS application for Notes with Clerk authentication, AI speech-to-text transcription, study guides, interactive flashcards, and quizzes.

## Setup & Running

1. **Install XcodeGen** (if not already installed):
   ```bash
   brew install xcodegen
   ```

2. **Generate the Xcode Project**:
   ```bash
   xcodegen generate
   ```

3. **Open in Xcode**:
   ```bash
   open Notes.xcodeproj
   ```

4. **Configuration (`Notes/App/AppConfig.swift`)**:
   - `baseURL`: Defaults to `http://localhost:3000` for Simulator. For physical devices, point to your Mac's LAN IP or production server.
   - `clerkPublishableKey`: Configured with your Clerk Publishable Key.

5. **Clerk Authentication**:
   - Uses the official [Clerk iOS SDK](https://github.com/clerk/clerk-ios) (`ClerkKit` and `ClerkKitUI`).
   - Prebuilt `AuthView()` handles Sign-in / Sign-up / Passkeys.
   - `UserButton()` provides account management and profile avatar.
   - All backend API requests automatically carry the active Clerk session JWT token (`Authorization: Bearer <token>`).
