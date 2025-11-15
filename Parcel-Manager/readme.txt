# Parcel Manager System
Authored by Zerohex

## Overview
The Parcel Manager is a comprehensive mail system that allows players to send and receive items and currency anywhere in the world. This plugin integrates seamlessly with auction systems and other trading mechanisms, providing a convenient way to transfer items between characters.

## Features
- View and retrieve parcels from anywhere in the game world
- Reclaim individual parcels or all parcels at once
- Handles currency (copper, silver, gold, platinum)
- Supports stackable items, charged items, and regular items
- Smart parcel stacking to reduce clutter
- Stale link protection to prevent duplicate claims
- Security validations to prevent exploits

## Installation
Copy `ParcelManager.pl` to your `[EQEMU_Root]/quests/plugins/` directory.

Database table required: `character_parcels`
Schema: id, char_id, slot_id, item_id, quantity

## Player Commands

### !parcel
Displays a list of all pending parcels waiting to be picked up.
- Shows item name, quantity/charges, and a clickable reclaim link for each parcel
- Displays a "Reclaim All" option if multiple parcels are available
- Returns "You have no pending parcels" if no parcels are waiting

### !parcel reclaim <parcel_id>
Reclaims a specific parcel and places it on your cursor.
- Automatically handles charged items (preserves charges)
- Automatically handles stackable items (full stack)
- Automatically handles currency conversion (copper/silver/gold/platinum)
- Removes the parcel from the database after successful claim

### !reclaim all
Reclaims all pending parcels at once.
- Processes all parcels in sequence
- Places all items on cursor
- Displays confirmation message with total count claimed
- Refreshes parcel display after completion

## Plugin Functions (for Developers)

### plugin::DisplayParcels()
Displays the player's pending parcels with clickable reclaim links.
- Fetches all parcels from `character_parcels` table
- Generates interactive parcel list with reclaim links
- Stores valid parcel IDs in QGlobal for stale link detection
- Message color: 315 (system message)

### plugin::RedeemParcel($parcel_id)
Redeems a single parcel by its unique database ID.
- Validates parcel exists and hasn't been claimed (stale link check)
- Handles currency (item_id 99990) and regular items
- Differentiates between charged items, stackable items, and regular items
- Removes parcel from database after redemption
- Refreshes parcel display automatically

### plugin::ReclaimAllParcels()
Reclaims all parcels for the current player.
- Retrieves all parcels from database
- Processes each parcel (currency and items)
- Deletes all parcels after successful claim
- Clears QGlobal data
- Displays total count claimed

### plugin::SendParcel($target_name, $item_id, $quantity, $from_name)
Sends a parcel to another player (returns 1 on success, 0 on failure).

Parameters:
- `$target_name` - Character name of recipient
- `$item_id` - Item ID to send (or "platinum" for currency)
- `$quantity` - Quantity of items (or platinum amount if currency)
- `$from_name` - Sender name (optional, defaults to current player)

Security Validations:
- Prevents sending to yourself
- Prevents sending NODROP items (nodrop = 0 in items table)
- Prevents sending ATTUNED items (instnodrop = 1 in inventory)
- Prevents sending items with augments
- Verifies sender has sufficient items/currency before creating parcel
- Validates target character exists

Special Handling:
- Currency: Use item_id "platinum" and quantity for plat amount
  - Converts to copper internally (item_id 99990)
  - Example: SendParcel("PlayerName", "platinum", 100) sends 100 plat
- Charged Items: Automatically detects maxcharges > 0
  - Stores actual charges from inventory
  - Only removes 1 item from sender (the item with charges)
- Stackable Items: Stacks with existing parcels when possible
  - Does NOT stack charged items (to prevent exceeding maxcharges)

Example Usage:
```perl
# Send 10 platinum to a player
plugin::SendParcel("TargetPlayer", "platinum", 10, "Auction System");

# Send 5 Muffins (item_id 13006)
plugin::SendParcel("TargetPlayer", 13006, 5, "Your Friend");

# Send a charged item (automatically detects charges)
plugin::SendParcel("TargetPlayer", 20532, 0, "Quest Reward");
```

## Database Structure
Table: `character_parcels`
- `id` - Unique parcel identifier (primary key)
- `char_id` - Character ID of recipient
- `slot_id` - Slot position in parcel list
- `item_id` - Item ID (99990 for currency)
- `quantity` - Item quantity or charges (copper for currency)

## Technical Details
- Uses QGlobal data to prevent stale link exploitation
- Smart stacking: Combines identical items into single parcel (except charged items)
- Currency stored as total copper (1 plat = 1000 copper)
- Charged items preserve their charges through the parcel system
- Parcel IDs are pipe-delimited in QGlobal for validation
- Automatic cleanup of QGlobal data when no parcels remain

## Integration Examples
- Auction system payouts
- Quest reward delivery
- Player-to-player trading
- GM item distribution
- Event reward systems
