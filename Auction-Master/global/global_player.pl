# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Auction Say Controls
# =========================================================================
sub EVENT_SAY {
# 1. Standardize and Check for '!' prefix
    my $text = lc($text); 
    
    unless ($text =~ /^!/) {
        return 0; # Not a command, let other EVENT_SAY scripts process it.
    }
    
    # --- Check for REMOTE AUCTION COMMANDS ---
    
    # 1. Primary Auction Command: !auction [key] or !auction list or !auction start ...
    if ($text =~ /^!auction\s*(.*)/) {
        my $arg = $1;
        
        if ($arg eq "list" || $arg eq "") {
            auction::ListActiveAuctions($client);
            return 1;
        }
        
        # --- GM Commands ---
      if ($arg =~ /^start\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s*(\d*)\s*(\d*)/) {
            my ($name, $item_id, $hours, $min_bid, $increment, $bin_price) = ($1, $2, $3, $4, $5, $6);
            auction::CommandStartAuction($client, $name, $item_id, $hours, $min_bid, $increment, $bin_price);
            return 1;
        } 
        
        elsif ($arg =~ /^end\s+(\S+)/) {
            auction::CommandEndAuction($client, $1);
            return 1;
        } 
        
        elsif ($arg =~ /^delete\s+(\S+)/) {
            auction::CommandDeleteAuction($client, $1);
            return 1;
        } 
        
        elsif ($arg =~ /^help/) {
            $client->Message(315, "--- REMOTE AUCTION COMMANDS ---");
            $client->Message(315, "1. List: !auction list (Show all active auctions)");
            $client->Message(315, "2. Status: !auction [auction_key] (Check bid, time, and links)");
            $client->Message(315, "3. Bid: !bid [auction_key] [amount]");
            $client->Message(315, "4. Buy It Now: !bin [auction_key]"); 
            
            if ($client->GetGMStatus() >= 200) {
                auction::CommandGMHelp($client);
            }
            return 1;
        }        
        
        # !auction [key] (Check Status Command)
        elsif ($arg =~ /^(\S+)$/) {
            auction::CommandCheckStatus($client, $1);
            return 1;
        }
    }

    # 2. Remote Bid Command: !bid [key] [amount]
    elsif ($text =~ /^!bid\s+(\S+)\s+(\d+)/) {
        my ($auction_name, $bid_amount) = ($1, $2);
        if ($bid_amount > 0) {
            auction::CommandRemoteBid($client, $auction_name, $bid_amount);
            return 1;
        }
    }

    # 3. Buy It Now Command: !bin [key]
    elsif ($text =~ /^!bin\s+(\S+)/) {
        auction::CommandBuyItNow($client, $1);
        return 1;
    }
    
    # 4. GM Maintenance Command: !autocleanup
    elsif ($text eq "!autocleanup") {
        my $admin_level = $client->GetGMStatus() || 0;
        my $GM_MIN_LEVEL_ADMIN = 200; 

        if ($admin_level >= $GM_MIN_LEVEL_ADMIN) {
            # 1. Finalize expired auctions (Cleanup)
            auction::CheckExpiredAuctions();
            # 2. Start new auctions (Creation)
            auction_automation::RunAutomatedAuctionCheck(); 
            $client->Message(315, "Auction maintenance complete: Checked for expired auctions and initiated auto-auction creation.");
            return 1;
        } else {
            $client->Message(315, "Unauthorized command.");
            return 1;
        }
    }
}


