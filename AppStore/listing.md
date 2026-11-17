# App Store listing for Mahjong

Draft text to paste into App Store Connect. Character limits are Apple's; counts are in brackets.
Items marked **TODO** need a decision or a detail from you.

## Name and subtitle

- **App name** (30 max): `Mahjong: Tuesday Games` [22] (plain "Mahjong" is taken)
- **Subtitle** (30 max): `American Mahjong vs. 3 Bots` [27]. "American" is what people search for, and the app name doesn't have it.
- **Name under the icon:** Mahjong (already set in the project)

## Promotional text (170 max)

> American mahjong against three computer opponents: the Charleston, calling, jokers and the card. Free to play with the practice card. No ads, no account. [157]

## Description

> Play American mahjong against three computer opponents, any time, with no one to wait for.
>
> Build a hand from the card, pass tiles in the Charleston, call discards for your pungs, kongs and quints, swap your tiles for exposed jokers, and declare Mahjong. The scorepad keeps a running total across hands, just like the one on your table.
>
> HOW IT PLAYS
> • The full Charleston: right, across, left, an optional second Charleston, and the courtesy pass.
> • Every discard waits in the middle for a moment, so you never miss a call.
> • Jokers stand in for any tile in a group of three or more, and you can take them back from exposures.
> • The Card button shows every hand on the card, closest first, with the tiles you still need dimmed. Tap a hand to see it large.
> • Press and hold any tile to see it up close, with its name.
> • The tile you just drew glows gold.
>
> FREE TO PLAY
> • The practice card: a full card of hands written for this game, always free
> • How to play pages that walk through the tiles, the card, the Charleston and calling
> • A scorepad you can clear whenever you like
> • Sound effects and haptic feedback
> • Plays entirely offline. No ads, no accounts, no data collected
>
> THIS YEAR'S CARD AND THE FULL GAME
> • This year's card: play the current card's hands.
> • The full game: this year's card, plus your hand history and stats, playing without the Charleston, the wall and dice (roll for East, break the wall, deal from it), and a choice of how long each discard can be called.
> • Already bought this year's card? Upgrade to the full game for less.
> • Next year's card is sold separately.
>
> You need your own official card from the National Mah Jongg League to play a League card. The League's printed card and the card in this app are bought separately: buying one doesn't include the other. This app is independent and is not affiliated with the National Mah Jongg League.
>
> You can also leave a tip. Tips are optional and unlock nothing extra.

## In-app purchases

Create these in App Store Connect with exactly these product IDs; the app looks them up by ID. Each one has a **Review Information** section at the bottom of its page: upload `AppStore/screenshots/iap-review-store.png` as the screenshot, and add the note "Opened from Unlock full game on the start menu."

| Product ID | Type | Reference name | Price | Display name | Description |
|---|---|---|---|---|---|
| `mahjong.card.2026` | Non-consumable | 2026 Card | $3.99 | 2026 Card | Play the 2026 card. |
| `mahjong.fullgame.2026` | Non-consumable | Full Game 2026 | $4.99 | Full Game | The 2026 card, plus your history and game options. |
| `mahjong.upgrade` | Non-consumable | Full Game Upgrade | $0.99 | Full Game Upgrade | History and game options, for 2026 card owners. |
| `mahjong.tip.small` | Consumable | Small tip | $0.99 | Small tip | A small thank-you to the dealer. |
| `mahjong.tip.medium` | Consumable | Generous tip | $2.99 | Generous tip | A generous thank-you to the dealer. |
| `mahjong.tip.large` | Consumable | Big tip | $4.99 | Big tip | A very generous thank-you to the dealer. |

Notes:

- Each new year needs two new products, `mahjong.card.<year>` and `mahjong.fullgame.<year>`, plus that year's card file in the app.
- Selling anything needs the Paid Apps agreement, with banking and tax details, in App Store Connect.
- Each purchase needs a review screenshot; the store screen in the app works for all of them.
- The store screen already has the required "Restore purchases" button.

### Review notes for each purchase

Paste into each product's **Review Information → Review Notes**:

- **2026 Card** (`mahjong.card.2026`): On the start menu, tap "Unlock full game" to open the store screen, then tap "2026 card". After buying, tap the card name on the start menu ("Practice Card ›"): the 2026 Card is listed and can be chosen, and "Deal" plays a hand with it. "Hands" next to it shows every hand on the card. Players are told they need their own official card from the National Mah Jongg League.
- **Full Game 2026** (`mahjong.fullgame.2026`): On the start menu, tap "Unlock full game" to open the store screen, then tap "Full game". After buying: the 2026 Card can be chosen from the card name on the start menu; "History" on the start menu opens; under "Options" on the start menu, Charleston Off, Wall & dice On and the 2 sec / 5 sec call times are no longer locked.
- **Full Game Upgrade** (`mahjong.upgrade`): Offered only to people who already own the 2026 Card. Buy "2026 card" first; the store screen then offers "Upgrade to the full game". After buying: "History" on the start menu opens, and under "Options" on the start menu, Charleston Off, Wall & dice On and the 2 sec / 5 sec call times are no longer locked.
- **Small tip, Generous tip, Big tip** (`mahjong.tip.small`, `.medium`, `.large`): On the start menu, tap "More", then "Tip jar". Tips are optional, can be given more than once, and unlock nothing; the screen thanks the player after a tip.

## Free code (offer code)

To give someone the full game for free, add an offer code to **Full Game 2026** (`mahjong.fullgame.2026`): it unlocks the 2026 card and the full game, exactly like buying it. People redeem it with "Redeem code" on the app's store screen, or in the App Store under their account → "Redeem Gift Card or Code".

- **Custom code** (one word you choose, many redemptions, an end date): for friends and family. With Sevens, the custom code looked like it only works in the released App Store version.
- **One-time-use codes** (Apple generates a batch, each works once): for individuals.
- **Sandbox codes:** for testing "Redeem code" in TestFlight.

A code covers one year's product. Next year needs a new code on `mahjong.fullgame.2027`.

## Keywords (100 max, comma separated, no spaces)

`mah jongg,mahjongg,charleston,tiles,jokers,card,bots,offline,bams,craks,dots,dragons,winds,2026` [94]

Words already in the app name are left out on purpose: Apple searches the name too. "NMJL" and the League's name are left out because they are the League's trademarks.

## What's New (version 1.0)

> First release.

## Categories

- **Primary:** Games
- **Game subcategory:** Board
- **Secondary (optional):** Games > Card

## URLs

- **Support URL:** `https://cmubick.github.io/mahjong/` (the pages are in `docs/`; live once pushed)
- **Privacy Policy URL:** `https://cmubick.github.io/mahjong/privacy.html`
- **Marketing URL:** optional, can be left blank

## Copyright

`2026 Tuesday Games` (App Store Connect adds the © symbol itself)

## App Privacy answers

- **Do you or your third-party partners collect data from this app?** No.
- Result shown on the store page: "Data Not Collected".

This matches the app: it makes no network requests of its own (the only link opens the League's website in Safari), has no analytics, ads or accounts, and keeps the scorepad and history only on the device.

## Age rating questionnaire

Answer "None" or "No" to everything. In particular:

- Simulated gambling: None. Hands are scored in points on a scorepad; nothing is wagered or bought with points.
- Contests, unrestricted web access, user-generated content, messaging: No.

Expected result: the lowest age rating.

## Export compliance

The project already declares that the app uses no non-exempt encryption, so App Store Connect should not ask on upload.

## Notes for App Review

Apple's first review of Sevens came back with "Guideline 2.1 – Information Needed": a screen recording plus six numbered answers. These notes answer all six up front. Attach the screen recording under App Review Information (or paste a link) and paste this into the Notes field:

```
1. SCREEN RECORDING
See attached video. Recorded on an iPhone running the latest iOS. It shows launching the app, the rules, a hand in progress (the Charleston, a discard, the card and the tile magnifier), and purchasing and using the paid features.

2. PURPOSE AND AUDIENCE
Mahjong: Tuesday Games is a single-player game of American-style mahjong against three computer opponents. It is for people who play American mahjong with friends and want to play or practise on their own, with no ads and no account. Each hand is a game of its own; a scorepad keeps a running total in points.

3. SETUP AND ACCESS
No account, login or setup is needed, and the app works offline.
- "How to play" on the start menu explains the tiles, the card, the Charleston, calling, jokers and scoring.
- "Deal" starts a hand with the free Practice Card, which was written for this app.
- "Card" during a hand lists every hand on the card, closest first; tap a hand to see it large. Press and hold any tile to see it large with its name.
- "Options" on the start menu and in the game menu (☰) holds the settings: Charleston, Wall & dice, time to call, and sound.
- "More" on the start menu has What's next, Send feedback (an email to the developer), the tip jar and the store.
- The game menu (☰) also offers the card, the rules and the main menu.
- In-app purchases are on the store screen, opened with "Unlock full game" on the start menu or by tapping any option marked with a lock:
  - 2026 Card (non-consumable): play the 2026 card.
  - Full Game 2026 (non-consumable): the 2026 card plus the History screen, turning the Charleston off, showing the wall and dice, and a choice of call time.
  - Full Game Upgrade (non-consumable): shown only to people who already own the 2026 card; adds the History screen and game options.
  - Three tips (consumable): optional, unlock nothing.
  "Restore purchases" and "Redeem code" are on the same screen.

4. EXTERNAL SERVICES
None, other than Apple's In-App Purchase (StoreKit). The app makes no network requests of its own and uses no third-party SDKs, analytics, advertising, authentication, data providers or AI services. Sound effects and tile artwork are generated in the app. One link ("Buy an official card") opens the National Mah Jongg League's website in Safari.

5. REGIONAL DIFFERENCES
None. The app behaves the same in every region. It is in English only.

6. REGULATED INDUSTRY OR THIRD-PARTY MATERIAL
The app is not in a regulated industry. Hands are scored in points; there is no real-money play, betting or wagering.
The 2026 Card purchase contains the list of winning hands from the National Mah Jongg League's 2026 card, entered by the developer in the app's own format from a purchased card. The League's printed card design, layout and artwork are not reproduced. The app tells players they need their own official card and links to the League's website to buy one. The app is independent and not affiliated with the National Mah Jongg League. The free Practice Card, the tile artwork, sounds and code are original.
```

Tips for the recording (2 to 3 minutes, on a real iPhone, starting from the home screen): launch the app, open How to play and flip a page, tap Deal and pass tiles in the Charleston, discard a tile, open Card and tap a hand, hold a tile, then go to the store, buy the 2026 card or the full game, and show the 2026 card in the card picker and the History screen. If purchases on your own account don't work, record on a phone where they do (as with Sevens).

**TODO before public release:** Apple may ask whether you have the rights to the 2026 card's content (intellectual property guideline 5.2). Have your answer ready, from the League or your lawyer, before submitting.

## Screenshots

Captured in `AppStore/screenshots/`, all on the free practice card (the League's hands are kept out of marketing images):

- `iphone-6.1/` at 1179 × 2556, for the "iPhone with Dynamic Island (medium display)" slot, the one App Store Connect asks for by default.
- `iphone-6.9/` at 1290 × 2796, for the larger 6.9-inch iPhone slot, if you add it under "View All Sizes in Media Manager".
- `ipad-13/` at 2048 × 2732, for the 13-inch iPad slot.
- `iap-review-store.png`: the store screen, to attach as the review screenshot for every in-app purchase.

Suggested order (the first three show up in search results):

1. `01-table`: a hand in progress, with the tile you just drew in gold.
2. `05-claim`: a discard waiting to be called, with Pung, Kong and Pass.
3. `02-card`: the card, closest hands first, tiles you still need dimmed.
4. `04-magnify`: holding a tile to see its name.
5. `03-detail`: one hand, large.
6. `06-charleston`: choosing tiles to pass.
7. `07-tiles`: How to play, every tile.
8. `08-menu`: the start menu. (Shows the old start menu; retake it for the next version.)

The iPad set has the same names, without `06-charleston`.

To retake them, launch the debug build with `-scenario shot table` (or `card`, `detail`, `magnify`, `claim`, `charleston`), wait about 30 seconds for it to find a good position, then save a screenshot with `xcrun simctl io <device> screenshot <file>`.
