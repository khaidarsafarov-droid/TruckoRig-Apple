# Share sheet import

TruckoRig appears in the iOS share sheet and tries to turn the shared item into a load. Recognition runs on the phone. Nothing is uploaded. If the item is not a load, the journal is left unchanged.

## What was researched

Apple’s current share-extension shape is still an app extension whose `NSExtensionPointIdentifier` is `com.apple.share-services`. The principal class is a `UIViewController`. SwiftUI is hosted inside that controller; there is no separate SwiftUI share-extension template.

Activation uses one `NSExtensionActivationRule` predicate, not the older boolean keys alone. The predicate turns the extension on for text, URL, PDF, and images, and only when that share has at least one matching attachment and at most eight attachments total. The dictionary form (`NSExtensionActivationSupportsImageWithMaxCount` and the other `*WithMaxCount` keys) is the alternative when a predicate gets too long for the system to evaluate. A predicate that is too complex is simply ignored and the extension never appears.

The extension and the app pass files through the existing App Group `group.com.truckorig`. `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` is the shared container. The extension writes `ShareInbox/records` and `ShareInbox/files`. The app also publishes `ShareInbox/index.json`, a list of load number, broker, and file hash, so a later share can skip a duplicate without opening the database.

Share extensions are jetsam-limited. The practical ceiling is about 120 MB. A shared file is copied only when it is 20 MB or smaller and its header is a PDF, JPEG, PNG, or HEIC. The extension reads at most 30 pages, OCRs at most three, and downsamples images to a 1600-pixel edge. A PDF that already has a text layer is not rendered. One attachment is handled at a time.

The journal stays in the encrypted SQLCipher store. The extension does not open that store, and the database passphrase stays in the app’s private keychain. The inbox key is a different Keychain item in the App Group access group `group.com.truckorig` (Apple allows an App Group name as a keychain access group, so no extra Keychain Sharing capability is required). Inbox files and their JSON are AES-GCM sealed, use complete file protection, and are excluded from backup. Rows older than seven days, and files with no row, are deleted. The app imports the inbox on launch, when the scene becomes active, and when it receives the Darwin notification `com.truckorig.share-import`. That notification does not wake a suspended app.

`NSExtensionContext.open(_:completionHandler:)` is the supported way to ask the system to open `truckorig://share`. Each extension point decides whether to allow it, and share sheets often return `false`. The extension still shows the result and a Done button. Walking the responder chain to `UIApplication.open` is private API and is not used. `truckorig://share` is an existing journal route.

## What was built

The share target is `TruckoRigShare`, bundle id `com.truckorig.share`. Debug and Release embed it. The sheet shows Checking…, then Load added, a partial-field note, a duplicate note, or a short refusal. The copy is in English, Russian, French, and Spanish, and follows the language stored for the widget.

Classification reuses `InboundLoadParser` and `ReceiptKindClassifier`. The share gate adds its own score: 25 for a rate, 15 for each city, 10 for a date, 5 for miles, and 5 per keyword family up to 25 (rate confirmation, load number, PO, shipper, consignee, pickup, delivery, broker, MC#, carrier, dispatch). The accept line is 55, which is a rate plus both places, or a rate plus one place and several other signals. Below that line nothing is saved. Fuel receipts and settlements are refused unless the text is clearly a rate confirmation. A high score with blank miles, dates, broker, or one city is still saved, and those gaps are marked. At most 20 loads are taken from one share.

The original PDF is stored as a load scan. An image is stored as a load photo. Word files are read for text only; scans in this app are PDFs. A repeated file hash, or the same load number when the brokers are not both present and different, is not added again. Two different broker names with the same load number are kept. The journal’s trip id is unique, so the second one is stored as `LOAD-BROKER` while the printed number stays in the note.

The new row is selected on the Journal, scrolled into view, and drawn with a gold stroke and a New chip for a few seconds.

## Apple Developer account

On [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → Identifiers:

1. The App Group `group.com.truckorig` must exist. The app and the widget already use it.
2. Create an explicit App ID `com.truckorig.share`.
3. Enable App Groups on that App ID and select `group.com.truckorig`. Do not add iCloud.
4. Confirm the app id `com.truckorig` still has the same App Group.
5. Let Xcode automatic signing create the extension profile, or refresh the App Store profile before the next signed archive.

The extension does not get its own App Store listing. It ships inside the app.

## Unsigned CI builds

The Sideload configuration is `CODE_SIGNING_ALLOWED=NO`. It still compiles `TruckoRigShare.appex` (the workflow checks that the product exists) and then deletes `PlugIns`, the same way it already removes the widget. A free Apple ID cannot sign an app extension, and an unsigned build has no App Group container, so the share sheet would not be able to write the inbox. The unsigned IPA therefore does not contain the extension. Signed Debug, Release, and TestFlight builds keep it.

## Limits

- The share sheet can show TruckoRig only after the `com.truckorig.share` App ID and the App Group are on the signing team.
- A share of a bare link, with no message body, is not a load.
- Scanned PDFs are recognized for the first three pages.
- A Word file is not attached as a document.
- If the app has never launched, the duplicate index is empty. The import still skips a load the journal already has, once the app opens.
- One share imports at most 20 loads.
