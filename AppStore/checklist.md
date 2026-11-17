# App Store Connect and TestFlight checklist

Steps marked **You** need your Apple sign-in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com). Steps marked **Claude** can be run from this repo.

## 1. Create the app record (You)

1. Apps → **+** → **New App**.
2. Platform **iOS**. Name: **Mahjong: Tuesday Games**.
3. Primary language **English (U.S.)**.
4. Bundle ID **com.tuesdaygames.mahjong**. It should be in the list already; exporting the build registered it. If not, pick "Register a new bundle ID" in Certificates, Identifiers & Profiles with that exact ID.
5. SKU: anything unique to you, e.g. `mahjong-ios`.
6. User access: Full Access.

## 2. Upload the build (Claude)

The release build is archived and signed for the App Store (version 1.0, build 1). Once the app record exists:

```bash
xcodebuild -exportArchive -archivePath build/archive/mahjong.xcarchive -exportOptionsPlist AppStore/UploadOptions.plist -exportPath build/upload -allowProvisioningUpdates
```

`AppStore/UploadOptions.plist` sends the build to App Store Connect; `AppStore/ExportOptions.plist` only writes the `.ipa` locally. Each later upload needs a higher build number (`CURRENT_PROJECT_VERSION` in the project).

Processing takes 5 to 30 minutes. App Store Connect emails you when the build is ready.

## 3. Create the in-app purchases (You)

In the app → **Monetization → In-App Purchases**, create the six products in the table in `listing.md`, with exactly those product IDs. For TestFlight they only need a reference name, product ID, price and one display name; review screenshots can wait until you submit for review.

Purchases in TestFlight are free test purchases. They won't charge anyone.

## 4. Internal testing (You)

1. **TestFlight → Internal Testing → +** to make a group, e.g. "Tuesday Games".
2. Add yourself and anyone else on your App Store Connect team (up to 100 people, each with an App Store Connect role).
3. Add build 1.0 (1) to the group. Internal builds skip Beta App Review.
4. Testers install the **TestFlight** app on their phone and accept the invitation email.

## 5. What to try on a real phone

- [ ] Call a discard yourself: Pung/Kong/Pass, and letting the bar run out.
- [ ] Sounds (switch off silent mode) and haptics.
- [ ] Buy the 2026 card, then the upgrade; check the 2026 card appears in the card picker and History unlocks.
- [ ] Delete and reinstall, then "Restore purchases".
- [ ] A tip: thank-you message, nothing unlocked.
- [ ] Close the app mid-hand, reopen, "Resume hand".
- [ ] Finish a hand: the end-of-hand screen should stay up until you tap. (Once in the simulator it went straight to the main menu; it could not be repeated.)
- [ ] The "Buy an official card" link opens the League's website.

## Before external testing or release

- [ ] Decide whether the 2026 card file stays in the public GitHub repository.
- [x] Support and privacy policy pages, in `docs/` (live once pushed to GitHub Pages).
- [x] Screenshots, in `AppStore/screenshots/`.
- [ ] Paid Apps agreement, banking and tax in App Store Connect.

## 6. Submit for review (You)

In App Store Connect, open the app → **iOS App 1.0**:

1. **Screenshots:** drag `iphone-6.1/*.png` into the iPhone slot App Store Connect shows (6.1"), optionally `iphone-6.9/*.png` into the 6.9" slot, and `ipad-13/*.png` into the 13" iPad slot, in the order listed in `listing.md`.
2. **Promotional text, description, keywords, support URL, marketing URL:** paste from `listing.md`.
3. **Build:** pick the latest TestFlight build.
4. **App Review information:** a contact name, phone and email; no sign-in is needed. Paste the review notes from `listing.md`.
5. **App information** (left side): subtitle, category (Games → Board, secondary Card), privacy policy URL, age rating questionnaire (all "None"/"No").
6. **App Privacy:** "Data Not Collected".
7. **Pricing and availability:** Free, all territories (or as you like).
8. **In-app purchases:** for each of the six products, add the review screenshot `iap-review-store.png` and a review note ("Opened from Unlock full game on the start menu"). Then, on the version page under **In-App Purchases and Subscriptions**, select the products so they are reviewed with this version.
9. **Add for Review**, then **Submit to App Review**.

First reviews usually take a day or two. If Apple asks about the rights to the 2026 card (guideline 5.2), answer from what the League or your lawyer told you.
