# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Subroutines to Display and Redeem Parcels
# =========================================================================
sub EVENT_SAY {
    # Check 1: Handle the initial !parcel command (typed by the player)
    # Check 2: Handle !parcel reclaim <ID> command (from clickable link or typed)
    if ($text =~ /^!parcel reclaim (\d+)$/) {
        my $parcel_id = $1;
        quest::debug("RedeemParcel called with parcel_id: $parcel_id");
        plugin::RedeemParcel($parcel_id);
        return;
    }

    # Check 3: Handle !reclaim all command
    if ($text eq "!reclaim all") {
        plugin::ReclaimAllParcels();
        return;
    }
        elsif ($text eq "!parcel") {
        plugin::DisplayParcels();
        return;
    }
}

