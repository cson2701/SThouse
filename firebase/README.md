# Firebase setup

## Console setup
1. Use the existing Firebase project `974732252826`.
2. Register the iOS app with bundle ID `scrapps.SThouse`.
3. Enable Email/Password in Firebase Authentication.
4. Download `GoogleService-Info.plist` from the Firebase Console and place it at `SThouse/GoogleService-Info.plist`.
5. Deploy `firebase/firestore.rules` and `firebase/firestore.indexes.json`.

## Local Firebase config
`SThouse/GoogleService-Info.plist` contains project-specific Firebase client configuration and is intentionally ignored by git. Keep the real file local or inject it from CI secrets before building.

Use `SThouse/GoogleService-Info.example.plist` only as a shape/reference for required keys. Do not put real API keys in the example file.

To download the real iOS config file:
1. Open the Firebase Console.
2. Select the Firebase project.
3. Go to Project settings -> General -> Your apps.
4. Select the iOS app for bundle ID `scrapps.SThouse`.
5. Download `GoogleService-Info.plist`.
6. Place the downloaded file at `SThouse/GoogleService-Info.plist`.

For collaborators, either grant Firebase Console access so each developer can download the file, or share the plist through the team's password manager. For CI builds, store the plist as a secret and write it to `SThouse/GoogleService-Info.plist` before running the Xcode build.

## API key rotation
Rotate the matched iOS key in Google Cloud Console, not the Browser key. Restrict the iOS key to bundle ID `scrapps.SThouse` and the Firebase APIs this app uses.

After rotating the iOS key, download `GoogleService-Info.plist` again from Firebase Console. A newly downloaded plist should contain the rotated iOS key, but existing local plist files do not update automatically. Replace each local or CI-provided plist, confirm sign-in and Firestore sync still work, then delete the previous key only after all collaborators and CI builds are using the new plist.

## Firestore structure
- `households/shared-household`
- `households/shared-household/items/{itemId}`
- `households/shared-household/locations/{locationId}`
- `households/shared-household/categories/{categoryId}`

All authenticated users share the same household document and subcollections.

## Required document fields

### Household
- `ownerUid`
- `email`
- `createdAt`
- `updatedAt`

### Item
- `id`
- `name`
- `category`
- `quantity`
- `tag` (optional)
- `lastEditedBy`
- `locationId`
- `deleted`
- `updatedAt`
- `serverUpdatedAt`

### Location
- `id`
- `name`
- `parentId`
- `sortOrder`
- `deleted`
- `updatedAt`
- `serverUpdatedAt`

### Category
- `id`
- `name`
- `sortOrder`
- `deleted`
- `updatedAt`
- `serverUpdatedAt`

## App behavior
- Email/password auth gates access to the inventory UI.
- Local JSON persistence remains the source of truth for the UI.
- Firestore is used for cloud sync after sign-in.
- All signed-in users share the same cloud dataset and local cache namespace.
