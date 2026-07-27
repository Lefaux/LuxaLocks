# LuxaLocks

LuxaLocks is a World of Warcraft Classic Era addon for coordinating warlock
summoning teams across multiple characters and WoW accounts.

The addon provides two independent windows:

- A bag-slot overview for saved warlock characters.
- A synchronized summoning queue for level-20+ warlocks.

Players join a queue by whispering `123`, optionally followed by a configured
location keyword:

```text
123
123 DMT
123 Felwood
123 DMT please
```

Keywords are case-insensitive. Only the first word after `123` is used; any
remaining text is ignored.

## Requirements

- World of Warcraft Classic Era.
- A level-20 or higher warlock for summoning features.
- LuxaLocks installed on every warlock client that should participate in
  synchronization.
- Participating clients must be logged in and in the same party or raid to
  exchange data.

The bag-slot tracker continues to work independently of the summoning system.

## Installation

1. Download or clone the repository.
2. Place the `LuxaLocks` directory in:

   ```text
   World of Warcraft/_classic_era_/Interface/AddOns/
   ```

3. Confirm that the resulting path contains `LuxaLocks.toc`:

   ```text
   Interface/AddOns/LuxaLocks/LuxaLocks.toc
   ```

4. Restart World of Warcraft or run `/reload`.
5. Enable LuxaLocks in the character-selection AddOns menu.

Install the same addon version on every participating WoW client.

## Quick start

### 1. Log in the warlocks

Log in each level-20+ warlock that will participate in the summoning team. Put
the warlocks in the same party or raid.

LuxaLocks automatically discovers eligible warlocks running the addon.

### 2. Configure location keywords

Open:

```text
Options > AddOns > LuxaLocks > Summoning
```

Enter a space-separated list of one-word keywords for each warlock:

```text
DMT DMTRIBUTE
FELWOOD FEL
BOOTYBAY BB
```

Press **Apply** for each changed warlock.

An offline warlock can be added manually with its character name. Include the
realm when necessary:

```text
CharacterName-RealmName
```

Configured warlocks are retained; the settings screen does not remove them.

### 3. Synchronize

Settings and queue data synchronize automatically when participating clients
join the same party or raid.

To request a manual synchronization:

1. Right-click the LuxaLocks minimap icon.
2. Select **Sync summon data**.

Each WoW account keeps a local copy of the shared state. WoW does not provide a
SavedVariables file that can be read by separate accounts, so LuxaLocks
replicates data using hidden addon messages while clients are grouped.

After initial setup, allow every client to receive the configuration. Logging
out or running `/reload` writes that account's local copy to disk.

### 4. Receive requests

Players can whisper a participating warlock:

```text
123 DMT
```

If `DMT` belongs to another configured warlock, the request is routed to that
warlock's queue.

If the player sends only:

```text
123
```

the request goes to the queue of the warlock who received the whisper.

Unknown keywords also fall back to the whispered warlock's queue.

## Queue rules

- A player can have one request in each warlock's queue.
- The same player may therefore be queued for multiple locations.
- Repeating a request for the same warlock does not change the original
  position.
- Requests do not expire automatically.
- Requests persist across logout, restart, and synchronization.
- Players do not need to be in the party or raid when they submit a request.
- Removing an entry is synchronized immediately.
- Removal records prevent an old client from restoring a request that was
  already removed or completed.
- A successful summon removes that player from every queue.

Existing requests remain assigned to their original warlock if keyword
settings are changed later.

## Queue window

Right-click the minimap icon and select:

```text
Show / hide summon queues
```

The queue window has two columns:

- **My queue** contains the current warlock's actionable requests.
- **Other queues** displays requests grouped under every other configured
  warlock.

Each entry displays:

- Queue position.
- Player name.
- Matched keyword, or `direct` for a fallback/direct request.
- Time spent in the queue.
- A `Summoning…` status when a summon is in progress.

The window is independently movable and resizable. Its position, size, and
open/closed state are restored on the next login. It shares the addon's font
and opacity preferences.

## Summoning

The button at the top of the queue window summons the **next available
player**:

1. LuxaLocks starts at the oldest request.
2. Players who are not currently in the party or raid are skipped.
3. Players already marked `Summoning…` are skipped.
4. The oldest remaining available player is targeted.
5. Ritual of Summoning is cast through a secure WoW action button.

The summoned player remains selected as the warlock's target.

After the button is clicked, the request is marked `Summoning…` for up to two
minutes. If the summon is not completed, the request becomes available again.

When WoW reports that the player has arrived through a successful summon, the
request is removed from every queue.

Summoning controls are unavailable during combat.

### Right-click actions

Right-click an entry in **My queue** for:

- **Summon player (arm button)** — selects that player as an override for the
  secure Summon button.
- **Remove from this queue** — immediately removes and synchronizes the entry.

After arming an override, click the Summon button at the top of the window to
perform the cast. WoW's protected-action rules require the actual spell cast
to come from a secure button.

Right-click an entry in **Other queues** for:

- **Remove from this queue**

Other queues do not provide a summon override because they belong to a
different summoning warlock.

## Entry colors

Queue entries use the following colors:

| Player state | Color |
| --- | --- |
| Elysium member currently in the group | Player's class color |
| Elysium member outside the group | Grey |
| Non-Elysium player currently in the group | Bright red |
| Non-Elysium player outside the group | Dark red |
| Guild membership not yet known | Pink |

WoW may not expose guild information for a player who has never joined the
group. Such a player remains pink until the addon can inspect their group unit.

The guild name checked by the addon is `Elysium`, case-insensitively.

## Duplicate keywords

A location keyword should normally belong to exactly one warlock.

If the same keyword is assigned to multiple warlocks, the Summoning settings
screen displays a warning. The setting is still accepted; LuxaLocks does not
block or automatically rewrite it.

Resolve duplicates manually to keep request routing deterministic.

## Settings conflicts

Separate WoW accounts cannot access one another's SavedVariables directly.
When grouped clients reconnect, LuxaLocks merges warlock records that do not
conflict.

A conflict exists when different clients have different keyword settings for
the same warlock. The Summoning settings screen shows:

- The local version.
- The remote version.
- **Keep local**.
- **Use remote**.

Choosing a version resolves the conflict and broadcasts the selected value to
the grouped clients.

Keyword settings are intended to be prepared before a summoning session.
LuxaLocks does not prevent editing while grouped.

## Minimap controls

### Left-click

Shows or hides the bag-slot window.

### Drag

Moves the minimap button.

### Right-click

Opens a menu containing:

- **Refresh data** — refreshes the bag-slot data.
- **Show / hide bag-slot window**.
- **Show / hide summon queues**.
- **Sync summon data**.
- **Close** — closes the bag-slot window.

## Slash commands

```text
/luxalocks
/luxalocks show
```

Shows the bag-slot window.

```text
/luxalocks hide
```

Hides the bag-slot window.

```text
/luxalocks refresh
```

Refreshes the current character's bag-slot record.

```text
/luxalocks q
/luxalocks queue
```

Opens the summoning queue window.

```text
/luxalocks options
/luxalocks config
```

Opens the LuxaLocks settings.

Manual synchronization is available from the minimap menu.

## Bag-slot overview

LuxaLocks retains its original bag-space tracker for eligible warlocks. It
records information such as:

- Character and realm.
- Current location.
- Empty and total bag slots.
- Last update time.

The bag-slot and summoning windows are independent and can be open at the same
time.

## Synchronization details

LuxaLocks exchanges data only through WoW's addon-message channel. It does not
use an external server, network service, or filesystem access.

Synchronization occurs:

- Automatically after login when already grouped.
- When the party or raid roster changes.
- When a grouped client requests a refresh.
- When a request is added or removed.
- When relevant known player information changes.
- When settings are applied or a conflict is resolved.

Clients that are offline cannot receive live changes. When they later join a
group containing another up-to-date LuxaLocks client, the automatic handshake
merges the saved data.

For the most reliable initial setup:

1. Group all participating warlocks.
2. Wait a few seconds for discovery.
3. Configure the keywords.
4. Use **Sync summon data** if necessary.
5. Verify the settings on each client.
6. Log out or run `/reload` on each client.

## Saved data

LuxaLocks uses the account-wide SavedVariables table:

```text
LuxaLocksDB
```

WoW writes it beneath each account's own directory:

```text
WTF/Account/<AccountName>/SavedVariables/LuxaLocks.lua
```

The summoning data includes:

- Configured warlocks and keywords.
- Per-warlock queues.
- Synchronized removal markers.
- Unresolved setting conflicts.
- Queue-window geometry and visibility.

Do not edit the SavedVariables file while WoW is running. The game may
overwrite manual changes when the client exits.

## Troubleshooting

### A whisper does not create a request

Check that:

- The recipient is a level-20+ warlock.
- LuxaLocks is enabled on that client.
- The message begins with the separate word `123`.
- Lua errors are not being reported by the client.

### Another warlock does not receive queue updates

Check that:

- Both clients have LuxaLocks installed and enabled.
- Both clients use the same addon version.
- Both characters are level-20+ warlocks.
- Both characters are in the same party or raid.
- The addon is not disabled because of an earlier Lua error.

Then right-click the minimap icon and select **Sync summon data**.

### A player is skipped by the Summon button

The player must currently be in the party or raid. A player is also skipped
while their request is marked `Summoning…`.

### The Summon button is disabled

The button is disabled when:

- The warlock is in combat.
- No queued player is currently available in the group.

### A player is pink

Pink means the player's guild membership is unknown. This is expected when WoW
has not exposed that player's unit information, commonly before they join the
group.

### A removed request returns

First verify that every client is running the same addon version. Use manual
synchronization while the clients are grouped. LuxaLocks normally retains
removal markers specifically to prevent stale clients from resurrecting old
requests.

### Settings show a conflict

Open the Summoning settings, compare the local and remote keyword lists, and
choose **Keep local** or **Use remote**.

## Known limitations

- Separate accounts cannot share one physical SavedVariables file.
- Synchronization requires participating clients to be online and grouped.
- WoW addon-message delivery is subject to the game's internal throttling.
- Guild status may remain unknown until the requester joins the group.
- Protected WoW actions require the secure Summon button; a context-menu
  callback cannot cast the spell directly.
- The addon cannot summon a player who is not in the party or raid.
- The addon does not send queue-position whispers, avoiding chat spam and
  whisper throttling.
- Requests never expire automatically and may require manual cleanup.

## Privacy

LuxaLocks does not transmit data outside World of Warcraft. Queue and
configuration data are stored in local SavedVariables and exchanged only with
grouped WoW clients using the LuxaLocks addon-message prefix.

## Bundled libraries

LuxaLocks embeds the following standard WoW libraries for its minimap
launcher:

- LibStub.
- CallbackHandler-1.0.
- LibDataBroker-1.1.
- LibDBIcon-1.0.

These libraries retain their upstream copyright and licensing terms. The
LibDBIcon launcher replaces the addon's former custom minimap button and is
compatible with minimap-button collectors that recognize standard LibDBIcon
objects.

## Contributing

Bug reports and pull requests are welcome.

When reporting a synchronization or summoning issue, include:

- The LuxaLocks version.
- Whether the characters were in a party or raid.
- The number of participating clients.
- The relevant whisper text.
- Any displayed Lua error.
- Whether manual synchronization changed the result.

Avoid committing personal `WTF` data or SavedVariables files to the repository.

## License

No license is currently declared for LuxaLocks itself. The files under `Libs`
retain their respective upstream licenses. Add a root `LICENSE` file before
distributing or accepting contributions if you want to define permissions for
reuse, modification, and redistribution of the addon code.
