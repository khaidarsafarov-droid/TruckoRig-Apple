# Export compliance

This is the basis for `ITSAppUsesNonExemptEncryption` in `Info.plist` and `InfoSideload.plist`. It is not legal advice. The account holder confirms the answers in App Store Connect and with counsel if the storefront list changes.

## What the app actually uses

| Piece | Algorithm | Where it runs |
|---|---|---|
| Journal database | AES-256 | SQLCipher 4.20.0, linked in the app |
| iCloud backup and share inbox | AES-GCM | Apple CryptoKit |
| Telegram and Google Maps | TLS | `URLSession` |
| Passphrase and backup key | Keychain | Apple operating system |
| Photos, scans, receipts on device | Data Protection | `NSFileProtectionCompleteUntilFirstUserAuthentication` |

CryptoKit, `URLSession`, the Keychain, and Data Protection are encryption inside Apple's operating system. SQLCipher is not. It is a published AES-256 implementation (FIPS 197) used only to protect the driver's own journal. There is no proprietary or unpublished cipher.

## Why the flag is false

Apple's key means "uses encryption that is **not** exempt." `false` is the right value when the only extra cryptography is standard and the use qualifies for an exemption.

This use qualifies as mass-market software under the Export Administration Regulations, Category 5, Part 2, Note 3:

- The product is a trucking journal sold to the public, not an encryption product.
- The algorithm is a published standard, not a proprietary cipher.
- The classification is ECCN **5D992**, exported under License Exception ENC, 15 CFR 740.17(b)(1).
- A CCATS classification request is not required for that mass-market end item.

A finished app is an end item. After the 29 March 2021 change to 15 CFR 740.17(e)(3), the annual self-classification report generally applies to mass-market **components** and to a narrow kind of executable software, not to a complete App Store app. Keep the notes anyway (15 CFR part 762). If counsel decides a report is due, it covers the calendar year, is due by 1 February, and goes to crypt-supp8@bis.doc.gov and enc@nsa.gov with the subject "self-classification report."

The same flag is in the sideload plist because that build links the same SQLCipher. Sideload is not an App Store upload.

## What the owner answers in App Store Connect

The plist key stops the per-build questionnaire. It does not file the App Information record. Do this once, before the first TestFlight or App Store build that should leave "Missing Compliance":

1. App Store Connect → Apps → TruckoRig → **App Information**.
2. Next to **App Encryption Documentation**, click **+** and answer the dialogs. The same fields are `usesEncryption`, `exempt`, `containsProprietaryCryptography`, `containsThirdPartyCryptography`, and `availableOnFrenchStore` on the App Store Connect API.

Answer them as follows.

1. **Does your app use, contain, or incorporate cryptography?** Yes. SQLCipher, CryptoKit, HTTPS, the Keychain, and Data Protection are all cryptography. Apple counts standard algorithms and the operating system.
2. **Does your app implement proprietary or non-standard encryption algorithms?** No. AES-256 and AES-GCM are published standards (IEEE, IETF, NIST, ISO). Do not request a CCATS.
3. **Does your app implement standard encryption algorithms instead of, or in addition to, using or accessing the encryption in Apple's operating system?** Yes. SQLCipher's AES-256 is in addition to CryptoKit, `URLSession`, the Keychain, and Data Protection.
4. **Will the app be available on the App Store in France?** This one is the owner's. The app is localized in French, and a new app is available in every territory until you turn France off.
   - **Yes** (France stays on): encryption here is secure storage of the journal. France controls secure storage. The banking and medical exemptions do not apply. File the French encryption declaration with ANSSI, then upload that document in App Encryption Documentation. Apple reviews it in about two business days. If Apple returns a documentation key, add it as `ITSEncryptionExportComplianceCode`. Do not invent the value.
   - **No** (France is removed before release): no French declaration. No other documentation is required for this standard, mass-market use. Leave `ITSAppUsesNonExemptEncryption` as `false`.

Sources: [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations), [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/), [Overview of export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/), [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
