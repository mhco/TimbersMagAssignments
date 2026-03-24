# Timber's Mag Assignments

A World of Warcraft Classic TBC Anniversary (20505) addon that allows raid leaders and assistants (and Timberwind-Dreamscythe/Serol-Dreamscythe) to set clicking assignments (and their backups) and their symbols (with skull, X, square, triangle, and diamond being the defaults).

## Assigner Function

A.k.a. "assigner" role.

Only two types of people can be assigners: raid leaders, and raid assists. Everyone else can view the assignments window, and the minimap button, but only raid leaders and raid assists can actually change assignments.

## Assignment Window

A screen containing a table with three columns: symbol on the left, character name representing the primary clicker in the center, and character name representing the back-up clicker on the right.

```
|---------------------------------------------|
| Timber's Mag Assignments v2026.03.23   [] x |
|---------------------------------------------|
|                                             |
|                      [ Import ] [ Export ]  |
|  |-----|----------------|----------------|  |
|  |     | Primary        | Back-up        |  |
|  |-----|----------------|----------------|  |
|  | [1] | character1     | character2     |  |
|  |-----|----------------|----------------|  |
|  | [2] | character3     | character4     |  |
|  |-----|----------------|----------------|  |
|  | [3] | character5     | character6     |  |
|  |-----|----------------|----------------|  |
|  | [4] | character7     | character8     |  |
|  |-----|----------------|----------------|  |
|  | [5] | character9     | character10    |  |
|  |-----|----------------|----------------|  |
|                                             |
|  [ Send Assignments ]        [ Clear All ]  |
|---------------------------------------------|
```

### Clicking

**Only "assigners" will be able to click on a cell to change it and its associations.**

Left-clicking a cell will bring up a dropdown showing either a list of symbols or raid member names (depending on which column was clicked). Clicking on the symbol/name will put the name in that cell, and assign that choice. Character name dropdowns will include all raid member names, but if a character is selected and they are already assigned, their original assignment will be cleared, and they will be assigned the new cell. There will be no choice for "None" as that will be solved with right-clicking (see below).

Right-clicking a cell will only work on character names, and will clear the respective selection (if there is one). Right-clicking on a symbol cell will do nothing.

## Buttons

The "Import" button brings up a small popup window with a textarea, where a user can paste (Ctrl-V) a list of characters to assign roles. There will be one character per line, and they will be assigned in order: the first character will be assigned as follows:

Icon 1 primary: character on line 1
Icon 1 back-up: character on line 2
Icon 2 primary: character on line 3
Icon 2 back-up: character on line 4
Icon 3 primary: character on line 5
Icon 3 back-up: character on line 6
Icon 4 primary: character on line 7
Icon 4 back-up: character on line 8
Icon 5 primary: character on line 9
Icon 5 back-up: character on line 10

The "Export" button uses the same popup as the import button, but populates the text box with the data, with each character on their own line.

Import/Export window:

```
|------------------------|
| Import/Export        x |
| |--------------------| |
| |                    | |
| |                    | |
| |                    | |
| |--------------------| |
|------------------------|
```

Clicking the "Send Assignment Whispers" will automatically send whispers to characters that have assignments, saying "You are the primary clicker for {skull}".

## Assignment Overlay

If you are assigned a role (main/back-up clicker), a shift-draggable bit of text will appear in the center of your screen saying "{skull} primary clicker".

## Minimap Button

Left-clicking toggles the assignment window.

Right-clicking brings up a menu that allows you to select from the following options:

- Assignments
- Help
- Hide Minimap Button

## Slash commands

```/tma``` - Opens assist window
```/tma help``` - Prints help message in chat window
```/tma version``` or ```/tma v``` - Prints addon version number in chat window
```/tma minimap``` - Toggles minimap button visibility
