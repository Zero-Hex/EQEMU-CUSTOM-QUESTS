# Filename: auction_master.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Auction Master NPC Controller (Not Required)
# =========================================================================
# Constants (Must match constants in auction.pl)
my $CURRENCY_ITEM_ID = 147623;
my $GM_MIN_LEVEL_ADMIN = 200; 
my $AUCTION_CHECK_TIMER = 10;
my $AUCTION_LIST_KEY = "AUCTION_LIST_NAMES"; 

# --- Utility Functions (Only what is necessary for this file) ---
sub GetCurrencyName {
    return quest::getitemname($CURRENCY_ITEM_ID);
}
sub _GetAuctionDataKey {
    my $auction_name = shift;
    return "auction\_$auction_name";
}

# --- TIMER EXECUTION LOGIC (The primary function of this NPC) ---
sub EVENT_SPAWN {
    quest::settimer("AUCTION_CHECK", $AUCTION_CHECK_TIMER);
}

sub EVENT_TIMER {
    if ($timer eq "AUCTION_CHECK") {
        if (defined(&auction::CheckExpiredAuctions)) {
        auction::CheckExpiredAuctions();
        }
    }
}

sub EVENT_SAY {
    
    my $admin_level = $client->GetGMStatus() || 0; 
    my $text = lc($text); 
    my $currency_name = GetCurrencyName();
    my $name = $client->GetName();

    # NPC link click: Auction Status
    if ($text =~ /^auctionlink_(\w+)$/i) {
        my $auction_name = $1;
        # Since CheckAuctionStatus is now a public plugin function, we call it
        auction::CommandCheckStatus($client, $auction_name);
        return;
    }
    
    # NPC link click: Bid Execution (The bid link clicked from the NPC dialogue)
    if ($text =~ /^bidlink_(\w+)_(\d+)$/i) {
        my $auction_name = $1;
        my $bid_amount_int = $2; 
        
        # Call the core bidding logic defined in the plugin.
        auction::ProcessSmartBid($client, $auction_name, $bid_amount_int);
        return;
    }
    
    # HAIL/INITIAL LIST COMMAND
    if ($text =~ /hail/i) {
        my $active_auctions_string = quest::get_data($AUCTION_LIST_KEY) || "";
        my @active_auctions = split /:/, $active_auctions_string;
        
        my @saylinks;
        
        foreach my $auction_name (@active_auctions) {
            next if $auction_name eq '';
            
            my $auction_key = _GetAuctionDataKey($auction_name);
            my $auction_data = quest::get_data($auction_key) || "";
            
            next unless $auction_data;
            
            my ($item_id) = split /\|/, $auction_data;
            my $display_name = quest::getitemname($item_id) || "Auction Key: $auction_name";
            
            # This creates the clickable link that is caught by auctionlink_(\w+)
            push @saylinks, quest::saylink("auctionlink_$auction_name", 0, $display_name);
        }
        
        my $list = join(' | ', @saylinks);
        
        if (scalar @saylinks > 0) {
            quest::whisper("Greetings, $name. Active auctions: $list. Click an auction name to view item details and bid.");
        } else {
            quest::whisper("Greetings, $name. There are no active auctions at this time.");
        }
    }
}