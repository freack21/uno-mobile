# Google Play listing

Everything needed for the Play Console store listing. Keep the trademark
"UNO" (Mattel) out of the title, descriptions, screenshots and tags: the game
is **Last Card**.

## Assets

| Item | File | Size |
| --- | --- | --- |
| App icon | `web/icons/Icon-512.png` | 512 × 512 |
| Feature graphic | `feature-graphic.png` | 1024 × 500 |
| Phone screenshots (Indonesian, dark) | `screenshot-1.png` … `screenshot-5.png` | 1080 × 1920 |
| Privacy policy | https://uno.refandi.my.id/privacy | |

Screenshots: home, a Classic table, daily challenge, stats and achievements,
online play. They were taken from the web build at 405 × 720 points with a
device scale of 8/3 and the browser language set to Indonesian.

## Store listing — Bahasa Indonesia (default)

**Nama aplikasi** (≤ 30): `Last Card: Game Kartu Seru`

**Deskripsi singkat** (≤ 80):
`Cocokkan warna, main licik, habiskan kartumu. Main sendiri atau online bareng teman!`

**Deskripsi lengkap**:

```
Last Card adalah game kartu seru: cocokkan warna atau angka, serang lawan dengan kartu aksi, dan jadi yang pertama menghabiskan kartu. Jangan lupa tekan LAST CARD saat tinggal satu kartu, atau kamu bisa ketahuan!

★ 16 MODE PERMAINAN
Classic, Point Race, Stacking, Seven-O, Jump-In, Doubles, Draw Until Playable, Merciless, Flipside, Team 2v2, Elimination, Speed, Challenge +4, plus mode pesta Exact Score dan Hold Card, dan Custom untuk meracik aturan rumah sendiri. Setiap mode punya panduan lengkap.

★ MAIN ONLINE BARENG TEMAN
Tanpa akun. Buat room, bagikan link ke WhatsApp, dan teman langsung masuk. Skor dicatat di setiap pertandingan sampai skor akhir. Tidak punya lawan? Quick Match mempertemukanmu dengan pemain lain, dan bot mengisi kursi kosong.

★ TANTANGAN HARIAN
Kartu yang sama untuk semua orang setiap hari. Satu kali coba, adu skor di papan peringkat harian.

★ MAIN SENDIRI MELAWAN BOT
Bot dengan tiga tingkat kesulitan, cocok untuk latihan kapan saja, bahkan tanpa internet.

★ BARU PERTAMA KALI?
Permainan dengan panduan menunjukkan apa yang harus dilakukan di setiap langkah.

★ STATISTIK & PENCAPAIAN
Lacak kemenangan, rekor beruntun, dan buka 12 pencapaian.

★ NYAMAN DIMAINKAN
Bahasa Indonesia & English, tampilan terang dan gelap, efek suara, dan animasi kartu yang halus.

Tanpa iklan. Tanpa akun. Tanpa data pribadi.
```

## Store listing — English

**App name**: `Last Card: Fun Card Game`

**Short description**:
`Match colors, play dirty, empty your hand. Play solo or online with friends!`

**Full description**:

```
Last Card is a fast shedding card game: match the color or number, hit your rivals with action cards and be the first to empty your hand. Call LAST CARD when you are down to one card, or you might get caught!

★ 16 GAME MODES
Classic, Point Race, Stacking, Seven-O, Jump-In, Doubles, Draw Until Playable, Merciless, Flipside, Team 2v2, Elimination, Speed, Challenge +4, the party games Exact Score and Hold Card, and Custom to mix your own house rules. Every mode comes with a full guide.

★ PLAY ONLINE WITH FRIENDS
No account needed. Create a room, share the link on WhatsApp and friends jump right in. Every match is scored up to a final result. Nobody around? Quick Match seats you with other players and bots fill the empty seats.

★ DAILY CHALLENGE
The same deal for everyone, every day. One try, one daily leaderboard.

★ SOLO AGAINST BOTS
Three bot levels, play any time, even offline.

★ NEW TO THE GAME?
A guided first game shows you what to do at every step.

★ STATS & ACHIEVEMENTS
Track wins and streaks and unlock 12 achievements.

★ COMFORTABLE TO PLAY
English and Bahasa Indonesia, light and dark looks, sound effects and smooth card animations.

No ads. No account. No personal data.
```

## Category and tags

- Category: **Games → Card**
- Tags: Card, Casual, Multiplayer, Offline, Party
- Contact email: required by Play; use a project address (not shown here).

## Content rating (IARC questionnaire)

- Violence, fear, sexuality, language, drugs: **No**
- Gambling: **No** (no betting, no real or virtual currency, no prizes)
- User interaction: **Yes** — players can play together online. There is
  **no free-text chat**: only a fixed set of emoji and phrases; nicknames are
  chosen by players (max 16 characters).
- Shares location / personal info: **No**
- Digital purchases: **No**

## Data safety form

| Question | Answer |
| --- | --- |
| Collects or shares user data? | Collects: **Yes** (limited, see below). Shares: **No** |
| Encrypted in transit? | **Yes** (HTTPS / WSS) |
| Users can ask for deletion? | **Yes** — data is deleted automatically (rooms 30 min after empty, daily scores after 7 days); requests via the contact on the privacy page |

Data types:

- **App activity → Other user-generated content**: online nickname, moves and
  reactions while playing online. Purpose: App functionality. Not shared.
  Ephemeral (kept only while the room exists).
- **Device or other IDs**: a random ID created by the app to keep one daily
  challenge score per device. Purpose: App functionality. Not shared.
  Optional (only when playing the daily challenge).

Not collected: name, email, phone, location, contacts, photos, files,
financial info, health, web history, crash logs, diagnostics, advertising ID.

## Release checklist

1. Final upload key in place (`docs/android.md`) and the GitHub secrets set.
2. Bump `version:` in `pubspec.yaml`, tag `vX.Y.Z`, take the AAB from the
   Android workflow run.
3. Enroll in **Play App Signing**, then add the Play signing certificate's
   SHA-256 to `web/.well-known/assetlinks.json` so invite links open the app.
4. Create the app (default language Indonesian), fill in the listing above,
   upload the assets, content rating, data safety, target audience (all ages,
   not designed primarily for children), and the privacy policy URL.
5. Start with an **internal testing** track, then a closed test (Play requires
   12 testers for 14 days for new personal developer accounts), then
   production.
