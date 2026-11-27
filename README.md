# Last Card (uno-mobile)

A fast shedding card game for Flutter, played offline against bots.
Original name and artwork; classic "match the color or symbol" mechanics.

## Game modes

| Mode | Summary |
| --- | --- |
| Classic | Standard 108-card deck, one round. |
| Point Race | Round winners score leftover card points; first to 250/500/1000. |
| Stacking | +2 on +2, +4 on +4; the first who can't stack draws the total. |
| Seven-O | 7 swaps hands with a chosen player, 0 rotates every hand. |
| Jump-In | Play an identical card out of turn. |
| Doubles | Play several cards with the same number or symbol in one turn; action effects add up. |
| Draw Until Playable | Keep drawing until a card fits. |
| Merciless | 164-card deck (+6, +10, Skip All, Discard All, Wild Draw Color), escalating stacks, 25-card knockout. |
| Flipside | Two-sided deck; Flip turns every card to its light/dark side. |
| Team 2v2 | You and the bot opposite you share the win. |
| Elimination | Each round the biggest hand is knocked out. |
| Speed | 8-second turn clock; time out = draw 2. |
| Challenge +4 | Bluff a Wild +4 or challenge it (4 for the bluffer, 6 for a wrong challenge). |
| Exact Score (party) | Draw cards to fill your track to a target of 20-50 exactly; Wild, Skip, Reverse and +2 have special uses; three discards in a row cost a turn. |
| Hold Card (party) | Everyone secretly plays a number card; on a match, race to press HOLD — the slowest takes the box. |
| Custom | Any deck, format and combination of the rules above. |

## Web app (PWA)

The game ships as an installable Progressive Web App, so one web build runs on
Android, iOS and desktop browsers:

- Installable: "Install app" in Chrome/Edge, or Share → "Add to Home Screen" on iOS Safari.
- Works offline after the first visit (`web/sw.js` caches the app shell and the renderer).
- Updates are downloaded in the background and applied the next time the app is opened.
- Portrait, phone-shaped layout; centered on tablets and desktop.

```bash
tool/build_web.sh              # build into build/web for a site served at /
tool/build_web.sh /uno-mobile/ # build for a sub-path, e.g. GitHub Pages
```

Serve `build/web` over HTTPS (service workers need a secure context; `localhost`
is fine for testing). `index.html`, `flutter_bootstrap.js` and `sw.js` should be
served with `Cache-Control: no-cache`.

### Deploying

Production runs on Coolify at https://uno.refandi.my.id; see
[docs/deploy-coolify.md](docs/deploy-coolify.md). CI (`.github/workflows/ci.yml`)
tests every push and deploys green pushes to `main`. To run the production
image locally: `docker build -t uno-mobile . && docker run --rm -p 8080:8080 uno-mobile`,
then open http://localhost:8080.

App icons are rendered from `tool/icon.svg` with `node tool/render_icons.js`
(requires Playwright).

Every mode has an in-app guide (mode page and the `?` button during a game),
plus a shared "How to play" basics page.

## Project layout

```
lib/game/   Pure Dart engine (no Flutter imports)
  cards.dart   Card model and deck builders
  rules.dart   RuleSet: every house rule as a flag
  game.dart    Game state machine, move validation and effects
  bot.dart     Heuristic bots (easy / normal / hard)
  modes.dart   Mode presets and guide content
  exact_score.dart, hold_card.dart  Party game engines and their bots
lib/ui/     Flutter UI
  game_controller.dart  Bot scheduling, Jump-In races, Speed clock
  game_screen.dart      Table, hand, banners, results
  home_screen.dart, mode_screen.dart, guide_screen.dart
  playing_card.dart     Card renderer
test/       Engine unit tests, bot simulations for every mode, widget smoke tests
```

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # device or emulator
flutter build apk      # requires the Android SDK
```

Font: Fredoka (SIL Open Font License, `assets/fonts/OFL.txt`).
