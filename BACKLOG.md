# Mahjong backlog

Things to do after the current work, roughly in the order they were raised.

## Before release

- **License the National Mah Jongg League cards.** Every year's card belongs to the League. The plan is past cards free and the current card paid, and both need a licence before they ship. Once licensed, each card is a text file in `mahjong/Cards/` in the same format as `practice.txt`.
- **Table polish.** The table plays a whole match, but: there is no deal animation, the tile you just drew is not marked, iPad on its side uses the phone layout in a centered column, and VoiceOver cannot see the tiles (SpriteKit).
- **Calling prompts.** With a joker in your rack you can call almost any discard, so the game asks you often. Consider a setting to only ask when the call helps your closest hands, or a short timer.
- **Start menu, how to play, practice hand, history, saved games, store and tip jar**, as in Sevens.
- **Sounds and haptics.** Same system as Sevens, with tile sounds: a clack for a discard, tiles knocking for a call, a slide for the rack.
- **App icon** drawn by a script, like `AppStore/icon/make_icon.swift` in Sevens.
- **Android port** of `mahjong/Rules` with parity tests, as in Sevens.

## Rules not done yet

- **Blind pass ("stealing")** on the last pass of each Charleston. When everyone passes blind at once, which tiles go where is not obvious, so it needs a decision on how to handle that.
- **Dead hands.** The game stops you making an exposure that fits no hand, so you can never end up with a dead hand. Real play lets you make the mistake and lets others call you dead.
- **Wrong Mahjong.** Mahjong is only offered when the hand really is complete, so a false claim cannot happen.
- **Calling a discard** gives everyone as long as they need to decide. The table will need a short window so play does not stall.

## Gameplay

- **Difficulty.** The bots look only at their own tiles and play well: they finish about 8 hands in 10, which is more often than people do. Easy bots could call less and not trade for jokers; hard ones could avoid throwing tiles an opponent's exposures show they need.
- **Practice card balance.** In bot games most wins are from the Runs section, because those hands can be made in the most ways.
