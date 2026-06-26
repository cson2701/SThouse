# Firebase setup

## Collections
- `households/{householdId}`
- `households/{householdId}/items/{itemId}`
- `households/{householdId}/locations/{locationId}`

## Required document fields

### Item
- `id`
- `name`
- `category`
- `quantity`
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

## App config
1. Copy `SThouse/FirebaseConfig.plist.example` to `SThouse/FirebaseConfig.plist`.
2. Fill in `ProjectID`, `HouseholdID`, and a valid bearer token for development.
3. Deploy `firebase/firestore.rules` and `firebase/firestore.indexes.json` with Firebase CLI.

## Current sync behavior
- Local JSON persistence is the app source of truth.
- Firebase sync is enabled only when `FirebaseConfig.plist` exists.
- The client currently syncs full `items` and `locations` collections after pushing local mutations.
