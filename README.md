# Take out the Trash

A one-button vendor-junk cleaner for World of Warcraft Classic *Forever* beta
(interface `16001`).

One button sits on screen. Hover it to see the cheapest gray item in your bags;
shift-click to destroy it. The next-cheapest moves up and you repeat. Your bags
never open.

## Controls

| Input | Action |
| --- | --- |
| Hover | Show the cheapest item, its stack value, and the rest of the list |
| **Shift + Left click** | Destroy the cheapest item |
| **Right click** | Permanently skip that item (account-wide) |
| **Ctrl + drag** | Move the button (position is saved) |

## What is eligible

Only **poor (gray) quality** items, and only when every check below passes.
Anything uncertain is excluded rather than offered.

Included:

- Gray equipment (weapons, armor) — the bulk of vendor junk
- Gray trade goods
- Gray items with no vendor value (they sort first)

Excluded, always:

- Anything that is not poor quality
- Quest items (item class *Quest*)
- Items the bag UI flags as quest-related (`GetContainerItemQuestInfo`)
- Items whose tooltip says *This Item Begins a Quest*
- Anything flagged `isCraftingReagent`
- Items whose tooltip or item data could not be read yet
- Locked slots, and containers that still hold loot
- Anything you right-clicked to skip, or added to the blacklist

Deleting is additionally refused when a merchant, mail, trade, bank, auction, or
guild bank window is open, or when your cursor already holds something. Right
before the delete the slot is re-read and the cursor contents verified against
the expected item ID; a mismatch aborts without deleting.

## Commands

```
/tott                      toggle the button
/tott lock | unlock        require Ctrl to drag (default) or not
/tott reset                move the button back to centre screen
/tott list                 show everything currently eligible
/tott skips                show your skipped items
/tott unskip <id or link>  un-skip one item
/tott unskip all           clear the whole skip list
/tott blacklist <id or link>   never offer this item, ever
/tott strict               also exclude gray Trade Goods
/tott debug                explain why each gray item was excluded
```

`/tott debug` is the first thing to run if an item you expected is missing from
the list — it prints a reason per gray item.
