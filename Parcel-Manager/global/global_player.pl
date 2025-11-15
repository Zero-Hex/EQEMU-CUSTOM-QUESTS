# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Global player event handler for Parcel Manager commands
# =========================================================================
sub EVENT_SAY {
    # Handle "!parcel" command - displays player's pending parcels
    if ($text eq "!parcel") {
        plugin::DisplayParcels();
        return;
    }

    # Handle "!parcel reclaim <ID>" command - redeems a specific parcel by ID
    if ($text =~ /^!parcel reclaim (\d+)$/) {
        # IMPORTANT: Capture match variable IMMEDIATELY before any function calls
        my $parcel_id = $1;

        plugin::RedeemParcel($parcel_id);
        return;
    }

    # Handle "!parcel send <playername> <itemid|platinum> <quantity>" command
    # Sends items or platinum from current player to target player's parcel box
    if ($text =~ /^!parcel send (\S+) (\w+) (\d+)$/) {
        # IMPORTANT: Capture match variables IMMEDIATELY before any function calls
        my ($target_name, $item_id, $quantity) = ($1, $2, $3);

        plugin::SendParcel($target_name, $item_id, $quantity);
        return;
    }

    # Handle "!send" shortcut (same as !parcel send)
    if ($text =~ /^!send (\S+) (\w+) (\d+)$/) {
        # IMPORTANT: Capture match variables IMMEDIATELY before any function calls
        my ($target_name, $item_id, $quantity) = ($1, $2, $3);

        plugin::SendParcel($target_name, $item_id, $quantity);
        return;
    }

    # Handle "!reclaim all" command - redeems all pending parcels at once
    if ($text eq "!reclaim all") {
        plugin::ReclaimAllParcels();
        return;
    }
}

