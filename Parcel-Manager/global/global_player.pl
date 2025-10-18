# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Subroutines to Display and Redeem Parcels
# =========================================================================
sub EVENT_SAY {
    # Check 1: Handle the initial !parcel command (typed by the player)
    if (defined $text && $text eq "!parcel") {
        plugin::DisplayParcels(); 
        return 1;
    }
    # Check 2: Handle the RECLAIM click (RECLAIM_ITEMID_QUANTITY)
    if (defined $text && $text =~ /^RECLAIM\_(\d+\_\d+)$/) {
        my $unique_key = $1;
        plugin::RedeemParcel($unique_key); 
        return 1;
    }
    if (defined $text && $text eq "!reclaim all") {
        plugin::ReclaimAllParcels();
        return 1;
    }
}

