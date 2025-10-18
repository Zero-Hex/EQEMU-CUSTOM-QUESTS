# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Auction Say Controls
# =========================================================================
sub EVENT_SAY {
    # --- GM COMMANDS (MUST BE CHECKED FIRST) ---
    # 1. GM HELP COMMANDS: !auction gm, !auction help
    if ($text eq "!auction gm" || $text eq "!auction help") {
        if (defined(&auction::CommandGMHelp)) {
            auction::CommandGMHelp($client);
        }
        return;
    }
    
    # 2. GM START COMMAND: !auction start [name] [item id] [hours] [min bid] [OPT: increment]
    if ($text =~ /^\!auction start\s+(\w+)\s+(\d+)\s+(\d+)\s+(\d+)(?:\s+(\d+))?$/) {
        my ($auction_name, $item_id, $hours, $min_bid, $custom_increment) = ($1, $2, $3, $4, $5);
        
        if (defined(&auction::CommandStartAuction)) {
            auction::CommandStartAuction($client, $auction_name, $item_id, $hours, $min_bid, $custom_increment || 0);
        }
        return;
    }

    # 3. GM END COMMAND: !auction end [name]
    if ($text =~ /^\!auction end\s+(\w+)$/) {
        my $auction_name = $1;
        
        if (defined(&auction::CommandEndAuction)) {
            auction::CommandEndAuction($client, $auction_name);
        }
        return;
    }
    
    # 4. GM DELETE COMMAND: !auction delete [name]
    if ($text =~ /^\!auction delete\s+(\w+)$/) {
        my $auction_name = $1;
        
        if (defined(&auction::CommandDeleteAuction)) {
            auction::CommandDeleteAuction($client, $auction_name);
        }
        return;
    }
    
    # --- PLAYER COMMANDS ---

    # 5. LIST COMMANDS: !auction or !auctions (Exact match)
    if ($text eq "!auction" || $text eq "!auctions") {
        if (defined(&auction::ListActiveAuctions)) {
            auction::ListActiveAuctions($client);
        }
        return;
    }

    
    # 6. STATUS COMMAND: !auction [name] (General Regex - MUST COME AFTER RESERVED WORDS)
    if ($text =~ /^\!auction\s+(\w+)$/) {
        my $auction_name = $1;
        if (defined(&auction::CommandCheckStatus)) {
            auction::CommandCheckStatus($client, $auction_name);
        }
        return;
    }
    
    # 7. BID COMMAND: !bid [name] [amount]
    if ($text =~ /^\!bid\s+(\w+)\s+(\d+)$/) {
        my $auction_name = $1;
        my $bid_amount = $2;
        
        if (defined(&auction::CommandRemoteBid)) {
            auction::CommandRemoteBid($client, $auction_name, $bid_amount);
        }
        return;
    }
}

