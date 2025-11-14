# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Subroutines to Display and Redeem Parcels
# =========================================================================
sub EVENT_SAY {
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

    # Check 3: Handle !parcel send <playername> <itemid> <quantity> command
    if ($text =~ /^!parcel send (\S+) (\d+) (\d+)$/) {
        my $target_name = $1;
        my $item_id = $2;
        my $quantity = $3;
        plugin::SendParcel($target_name, $item_id, $quantity);
        return;
    }

    # Check 4: Handle !reclaim all command
    if ($text eq "!reclaim all") {
        plugin::ReclaimAllParcels();
        return;
    }
}

