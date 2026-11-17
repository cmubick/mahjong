# Mahjong backlog

Things to do after the current work, roughly in the order they were raised.

## Before release

- **The League's cards.** The 2026 card is in `mahjong/Cards/y2026.txt`, entered from a bought card in this app's own format, like other independent apps do. The app tells players to own an official card and links to the League's site. Each new year is one more file without the `kind: practice` line: the newest year is the one for sale and older years become free.
- **Table polish.** iPad on its side uses the phone layout in a centered column, and VoiceOver cannot see the tiles (SpriteKit).
- **Calling prompts.** With a joker in your rack you can call almost any discard, so the Pung/Kong buttons come up often. Each discard now has a timed window (Time to call, 2, 3 or 5 seconds) and runs out on its own, but a setting to only offer calls that help your closest hands might still be welcome.
- **Practice hand**, as in Sevens: a scripted first hand that teaches the Charleston, calling and Mahjong.
- **App Store Connect.** Products, all non-consumable except tips:
  - `mahjong.card.<year>`, $3.99: that year's card only. A new product every year.
  - `mahjong.fullgame.<year>`, $4.99: that year's card plus the full game (history, stats, Charleston off, time to call). A new product every year.
  - `mahjong.upgrade`, $0.99: the full game for people who already own this year's card. Bought once.
  - `mahjong.tip.small`, `.medium`, `.large`: consumable tips.
  The app offers whichever make sense for what you own (`StoreOffers` in `Store.swift`). Until a licensed card ships, only the $0.99 full game is on sale.
- **Legal check before release.** The League publishes no licensing program. Before shipping the 2026 card, ask the League whether they license card data to apps, and have an intellectual-property lawyer review the plan (hands entered in our own format, no copy of the card's layout, players told to own the card, no claim of affiliation).
- **Store tests** use `mahjongTests/Mahjong.storekit`. On the iPhone 18 Pro simulator (Xcode 27.2) they fail the same way Sevens' store tests do: products don't load or purchases don't complete. Check them on another simulator or Xcode release.
- **Android port** of `mahjong/Rules` with parity tests, as in Sevens.

## Rules not done yet

- **Blind pass ("stealing")** on the last pass of each Charleston. When everyone passes blind at once, which tiles go where is not obvious, so it needs a decision on how to handle that.
- **Dead hands.** The game stops you making an exposure that fits no hand, so you can never end up with a dead hand. Real play lets you make the mistake and lets others call you dead.
- **Wrong Mahjong.** Mahjong is only offered when the hand really is complete, so a false claim cannot happen.

## Gameplay

- **Reorder your rack.** Let the player drag tiles into their own order instead of the automatic sort, and keep that order as tiles come and go.
- **Track a hand.** Optionally pick a hand from the card and highlight, in your rack, the tiles that belong to it, so you can see what to keep and what to pass or discard. The single-hand view (tap a hand on the Card) is the place for a "Track this hand" button.
- **Difficulty.** The bots look only at their own tiles and play well: they finish about 8 hands in 10, which is more often than people do. Easy bots could call less and not trade for jokers; hard ones could avoid throwing tiles an opponent's exposures show they need.
- **Practice card balance.** In bot games most wins are from the Runs section, because those hands can be made in the most ways.
