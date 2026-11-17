# App Store listing for Mahjong

Draft text to paste into App Store Connect. Character limits are Apple's; counts are in brackets.
Items marked **TODO** need a decision or a detail from you.

## Name and subtitle

- **App name** (30 max): `Mahjong: Tuesday Games` [22] (plain "Mahjong" is taken)
- **Subtitle** (30 max): `Play the card against 3 bots` [28]
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
> • Past years' cards, free
> • How to play pages that walk through the tiles, the card, the Charleston and calling
> • A scorepad you can clear whenever you like
> • Sound effects and haptic feedback
> • Plays entirely offline. No ads, no accounts, no data collected
>
> THIS YEAR'S CARD AND THE FULL GAME
> • This year's card: play the current card's hands.
> • The full game: this year's card, plus your hand history and stats, playing without the Charleston, and a choice of how long each discard can be called.
> • Already bought this year's card? Upgrade to the full game for less.
> • Next year's card is sold separately.
>
> You need your own official card from the National Mah Jongg League to play a League card. This app is independent and is not affiliated with the National Mah Jongg League.
>
> You can also leave a tip. Tips are optional and unlock nothing extra.

## In-app purchases

Create these in App Store Connect with exactly these product IDs; the app looks them up by ID.

| Product ID | Type | Reference name | Price | Display name | Description |
|---|---|---|---|---|---|
| `mahjong.card.2026` | Non-consumable | 2026 Card | $3.99 | 2026 Card | Play the 2026 card. |
| `mahjong.fullgame.2026` | Non-consumable | Full Game 2026 | $4.99 | Full Game | The 2026 card, plus your history and game options. |
| `mahjong.upgrade` | Non-consumable | Full Game Upgrade | $0.99 | Full Game Upgrade | History and game options, for owners of this year's card. |
| `mahjong.tip.small` | Consumable | Small tip | $0.99 | Small tip | A small thank-you to the dealer. |
| `mahjong.tip.medium` | Consumable | Generous tip | $2.99 | Generous tip | A generous thank-you to the dealer. |
| `mahjong.tip.large` | Consumable | Big tip | $4.99 | Big tip | A very generous thank-you to the dealer. |

Notes:

- Each new year needs two new products, `mahjong.card.<year>` and `mahjong.fullgame.<year>`, plus that year's card file in the app.
- Selling anything needs the Paid Apps agreement, with banking and tax details, in App Store Connect.
- Each purchase needs a review screenshot; the store screen in the app works for all of them.
- The store screen already has the required "Restore purchases" button.

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

> Mahjong is a single-player game of American-style mahjong against three computer opponents. It needs no account and no network connection.
>
> To see the free features quickly: on the start menu, tap "How to play" for the rules, then "Deal" to play a hand with the free practice card. Tap "Card" during a hand to see the hands on the card.
>
> In-app purchases are on the store screen, opened with "Unlock full game" on the start menu or by tapping any option marked with a lock. "2026 card" unlocks the 2026 card. "Full game" unlocks the 2026 card, the History screen, turning the Charleston off, and the choice of call time. "Upgrade to the full game" appears only for people who already own the 2026 card. The three tips are consumable, optional, and unlock nothing. "Restore purchases" and "Redeem code" are on the same screen.

**TODO before public release:** Apple may ask whether you have the rights to the 2026 card's content (intellectual property guideline 5.2). Have your answer ready, from the League or your lawyer, before submitting.

## Screenshots

Captured in `AppStore/screenshots/`, all on the free practice card (the League's hands are kept out of marketing images):

- `iphone-6.9/` at 1290 × 2796, for the 6.9-inch iPhone slot. App Store Connect scales these down for smaller iPhones.
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
8. `08-menu`: the start menu.

The iPad set has the same names, without `06-charleston`.

To retake them, launch the debug build with `-scenario shot table` (or `card`, `detail`, `magnify`, `claim`, `charleston`), wait about 30 seconds for it to find a good position, then save a screenshot with `xcrun simctl io <device> screenshot <file>`.
