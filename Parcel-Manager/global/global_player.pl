# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Subroutines to Display and Redeem Parcels
# =========================================================================
sub EVENT_SAY {
    # Debug: Confirm this file is loaded
    quest::debug("ParcelManager global_player.pl EVENT_SAY triggered with text: '$text'");

    # Check 1: Handle the initial !parcel command (typed by the player)
    if ($text eq "!parcel") {
        plugin::DisplayParcels();
        return;
    }

    # Check 2: Handle !parcel reclaim <ID> command (from clickable link or typed)
    if ($text =~ /^!parcel reclaim (\d+)$/) {
        my $parcel_id = $1;
        quest::debug("RedeemParcel called with parcel_id: $parcel_id");
        plugin::RedeemParcel($parcel_id);
        return;
    }

    # Check 3: Handle !parcel send <playername> <itemid|platinum> <quantity> command
    if ($text =~ /^!parcel send (\S+) (\w+) (\d+)$/) {
        my $target_name = $1;
        my $item_id = $2;  # Can be numeric item ID or "platinum"
        my $quantity = $3;
        quest::debug("=== PARCEL SEND MATCH ===");
        quest::debug("Regex captures: 1='$1', 2='$2', 3='$3'");
        quest::debug("Variables BEFORE call: target='$target_name', item_id='$item_id', quantity='$quantity'");
        quest::debug("Type checks: target defined=" . (defined $target_name ? "yes" : "no") . ", item_id defined=" . (defined $item_id ? "yes" : "no") . ", quantity defined=" . (defined $quantity ? "yes" : "no"));
        quest::debug("Calling: plugin::SendParcel('$target_name', '$item_id', '$quantity')");

        my $result = plugin::SendParcel($target_name, $item_id, $quantity);

        quest::debug("Returned from plugin::SendParcel with result: " . (defined $result ? $result : "undef"));
        quest::debug("=== END PARCEL SEND ===");
        return;
    }

    # Check for !send without "parcel" prefix
    if ($text =~ /^!send (\S+) (\w+) (\d+)$/) {
        my $target_name = $1;
        my $item_id = $2;
        my $quantity = $3;
        quest::debug("!send (without parcel) matched! target='$target_name', item_id='$item_id', quantity='$quantity'");
        plugin::SendParcel($target_name, $item_id, $quantity);
        return;
    }

    # Debug: Show if command didn't match
    if ($text =~ /^!parcel send/ || $text =~ /^!send/) {
        quest::debug("Send command didn't match any regex. Full text: '$text'");
    }

    # Check 4: Handle !reclaim all command
    if ($text eq "!reclaim all") {
        plugin::ReclaimAllParcels();
        return;
    }
}

