# Timber's Mag Assignments

Timber's Mag Assignments is a clean, raid-focused assignment addon for WoW Classic TBC Anniversary (2.5.5) designed for Magtheridon click rotations.

It gives raid leaders and assistants a fast, visual way to assign icon-based clickers, synchronize those assignments to the group, and whisper players their responsibilities.

![image](https://media.forgecdn.net/attachments/description/1494260/description_29a269cb-1c45-4318-81b8-a4605f52d634.png)

## Highlights

- Role-aware control model:
  - Only the raid leader and assistants can edit assignments
  - Non-assigners can view assignments in read-only mode
- Flexible assignment layouts:
  - Standard 2-clicker mode (Primary + Back-up)
  - Optional 4-clicker mode (Clicker 1-4) per icon
- Smart assignment handling:
  - Selecting a player in a new slot automatically clears their old slot
  - Right-click clears name slots quickly
- Group synchronization:
  - Assignment changes propagate to party/raid users running the addon
  - Join-time sync logic helps new group members adopt current assignments
- Import / Export workflow:
  - Paste one character per line to bulk-assign instantly
  - Export current assignments in the same one-name-per-line format
  - Import respects mode:
    - 2-clicker mode: 2 lines per icon
    - 4-clicker mode: 4 lines per icon
- Assignment whispers:
  - Send assignment whispers to assigned players in one click
  - Uses plain-text icon labels (for compatibility with in-game whisper rules)
- On-screen personal overlay:
  - If you are assigned, a center-screen overlay shows your role
  - Hold "shift" and drag the overlay to reposition it
- Minimap integration:
  - Left-click: open/close assignments
  - Right-click: quick menu (Assignments, Help, Hide Minimap Button)

## Slash Commands

- /tma : Open the assignments window
- /tma help : Show command help
- /tma version or /tma v : Show addon version
- /tma minimap : Toggle minimap button visibility

## Typical Use

1. Open the assignments window
2. (Optional) Enable 4-clicker mode
3. Set icons and clickers manually, or use Import
4. Click Send Assignments to whisper assigned players

If your raid needs fast, readable click assignments without UI clutter, Timber's Mag Assignments keeps everything in one place.
