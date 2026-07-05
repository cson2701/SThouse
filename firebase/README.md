# Firebase setup

## Console setup
1. Use the existing Firebase project `974732252826`.
2. Register the iOS app with bundle ID `scrapps.SThouse`.
3. Enable Email/Password in Firebase Authentication.
4. Add `GoogleService-Info.plist` to the Xcode target.
5. Deploy `firebase/firestore.rules` and `firebase/firestore.indexes.json`.

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
