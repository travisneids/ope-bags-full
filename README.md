# Ope! Bag's Full

A **World of Warcraft: Forever** and **Classic Era / Hardcore** addon for the
moment your bags fill up mid-quest. It combines partial stacks, then gets rid
of the **cheapest junk first**, one click at a time, until you have the room
you asked for. At a vendor it sells instead.

```
Ope! Bag's Full                    Goal [-] 5 [+]
Free slots: 2
Combining stacks frees 1, then trash 2 (27c of vendor value).
  [Torn Wing]            12c   [Keep]
  [Broken Fang] x5       15c   [Keep]
  [Rusty Sword]          40c   [Keep]
[Options]                  [ Combine stacks (+1) ]
```

- **Make room**: set how many free slots you want. The button first combines
  partial stacks (free space, nothing lost), then trashes the cheapest item
  per click until you're there.
- **Cheapest first**: items are ranked by vendor value of the whole stack, so a
  lone Torn Wing (12c) goes before five Broken Fangs (15c).
- **Gray items only by default.** White and green items can be allowed in the
  options. Even then, quest items, items that can't be sold, bags, ammo, keys
  and class reagents are always kept, and food, drink and potions are kept
  unless you say otherwise.
- **Keep and junk lists**: *Keep* on any row (or `/ope keep <item>`) protects
  an item for good. `/ope junk <item>` makes an item always count as junk.
- **Sells junk at vendors** automatically (gray items and your junk list only).
  At a vendor, Make room and Trash sell instead of deleting.
- **"Ope! Bag's full!"**: when you loot with full bags it plays a sound, names
  the cheapest item to trash and opens the panel. It also warns you when you're
  down to your last few slots.
- **Works with Stash or Trash**: if you also use
  [Stash or Trash](https://github.com/travisneids/stash-or-trash), white and
  green materials your professions (or alts) can use are never trashed.
- Only counts bags that take any item: emptying a soul bag or quiver doesn't
  make room for loot, so those are left alone.

## One item per click

Blizzard only lets addons destroy **one item per click or key press** (and
never from a timer or event), so Ope can't wipe five items at once. Instead:

- click **Make room** / **Trash next** in the panel once per item,
- **Shift-click** the **Ope** icon beside your backpack,
- bind a key under **Options → Keybindings → AddOns → Ope! Bag's Full →
  Trash the cheapest item** and tap it, or
- put `/ope trash` in a macro.

Combining stacks and selling at vendors aren't restricted, so those happen in
one click.

## Install

The same `OpeBagsFull` folder works in both games; each client picks its own `.toc`:

| Game | AddOns folder | Loads |
| --- | --- | --- |
| WoW Forever (beta) | `World of Warcraft\_classic_beta_\Interface\AddOns\` | `OpeBagsFull.toc` |
| Classic Era / Hardcore / Self-Found | `World of Warcraft\_classic_era_\Interface\AddOns\` | `OpeBagsFull_Vanilla.toc` |

Download the latest `ope-bags-full-<version>.zip` from
[Releases](https://github.com/travisneids/ope-bags-full/releases) and extract
it into that folder; you should end up with `AddOns\OpeBagsFull\`. (GitHub's
green *Code → Download ZIP* button gives you the whole repository instead,
which won't load as-is.)

From a checkout, copy the `OpeBagsFull` folder (not the repository root):

```sh
cp -r OpeBagsFull "/mnt/c/Program Files (x86)/World of Warcraft/_classic_era_/Interface/AddOns/"
```

## Usage

- **Ope** icon beside the default backpack window: a bag icon with your free
  slot count on it (red when you're nearly full). Click to open the panel,
  Shift-click to trash the cheapest item, right-click for options. (Bag
  replacement addons like Bagnon hide the default backpack; use the key
  binding, `/ope` or the minimap addon menu instead.)
- Options: **Esc → Options → AddOns → Ope! Bag's Full**.

| Command | Does |
| --- | --- |
| `/ope` | show the Make room panel |
| `/ope trash` | trash the cheapest item (one per use; works in a macro) |
| `/ope room` | combine stacks, then trash the next item toward your goal |
| `/ope goal <n>` | free slots to aim for |
| `/ope stack` | combine partial stacks |
| `/ope sell` | sell junk (at a vendor) |
| `/ope keep <item>` / `unkeep <item>` | never trash an item |
| `/ope junk <item>` / `unjunk <item>` | always treat an item as junk |
| `/ope lists` | show your keep and junk lists |
| `/ope status` | free slots, what's next, this session's totals |

Shift-click an item into the chat box to fill in `<item>`.

## Tests

The suite runs the real addon files on Lua 5.1 against a mocked WoW client
(bags, cursor, vendor, and Blizzard's one-delete-per-click rule):

```sh
lua5.1 tests/run.lua                  # if you have Lua 5.1
python3 -m pip install lupa && python3 tests/run_tests.py   # otherwise
```

GitHub Actions runs the suite on every push to `main` and on pull requests.

## Releasing

1. Add a section for the new version at the top of `CHANGELOG.md`.
2. Tag and push:
   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

The Release workflow runs the tests, then the
[BigWigs packager](https://github.com/BigWigsMods/packager) builds
`ope-bags-full-v0.2.0.zip` with only the `OpeBagsFull` folder, stamps the tag
into both `.toc` files and publishes it as a GitHub Release. Add
`## X-Curse-Project-ID`, `## X-Wago-ID` or `## X-WoWI-ID` to both `.toc` files
and the matching repository secret (`CF_API_KEY`, `WAGO_API_TOKEN`,
`WOWI_API_TOKEN`) to upload to those sites too.

## Caveats

Checked against Blizzard's UI source for both clients (Forever 1.60.1,
Classic Era 1.15.9) but not yet in a live client:

- Where the Ope icon sits next to the backpack window may need nudging.
- Deleting is permanent. Ope only ever deletes what the panel lists, and it
  checks the item on your cursor before each delete, but there's no undo.
  Sold items can be bought back from the vendor's Buyback tab.

## License

MIT — see [LICENSE](LICENSE).
