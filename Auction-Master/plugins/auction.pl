package auction;
#Authored by Zerohex
# Constants (Must match constants in auction_master.pl)
my $CURRENCY_ITEM_ID = 147623; 
my $GM_MIN_LEVEL_ADMIN = 200; 
my $AUCTION_LIST_KEY = "AUCTION_LIST_NAMES"; 
my $AUCTION_TIMEOUT_DAYS = 90; 
my $DEFAULT_MIN_INCREMENT = 1; 

# Time Constants for Anti-Sniping Feature (in seconds)
my $SNIPE_WINDOW = 90;   
my $TIME_EXTENSION = 60; 

# RESTORED: Buy It Now Price Constant
my $STATIC_BUY_IT_NOW_PRICE = 350;

# --- Utility Functions ---

sub GetCurrencyName {
    return quest::getitemname($CURRENCY_ITEM_ID);
}

sub GetAuctionDataKey {
    my $auction_name = shift;
    return "auction\_$auction_name";
}

sub ConvertSecondsToTime {
    my $seconds = shift;
    if ($seconds <= 0) { return "NOW"; }
    my $days = int($seconds / 86400); $seconds %= 86400;
    my $hours = int($seconds / 3600); $seconds %= 3600;
    my $minutes = int($seconds / 60);
    my @time_parts;
    push @time_parts, "$days days" if $days > 0;
    push @time_parts, "$hours hours" if $hours > 0;
    push @time_parts, "$minutes minutes" if $minutes > 0;
    return join(', ', @time_parts);
}

# -------------------------------------------------------------------------------------------------
# AUCTION STATE MANAGEMENT LOGIC
# -------------------------------------------------------------------------------------------------

sub UpdateActiveAuctionList {
    my ($auction_name, $add) = @_;
    
    my $current_list_string = quest::get_data($AUCTION_LIST_KEY) || "";
    my @current_list = split /:/, $current_list_string;
    
    # Filter out the current auction name
    @current_list = grep { $_ ne $auction_name && $_ ne '' } @current_list;
    
    if ($add) {
        push @current_list, $auction_name;
    }
    
    my $new_list_string = join(':', @current_list);
    
    if ($new_list_string) {
        quest::set_data($AUCTION_LIST_KEY, $new_list_string, $AUCTION_TIMEOUT_DAYS * 86400);
    } else {
        quest::delete_data($AUCTION_LIST_KEY);
    }
}

# 🔑 FIX 1: Added $is_bin_purchase flag to skip the worldwide message for BIN
sub FinalizeAuction {
    my ($auction_name, $item_id, $winner_id, $winning_bid, $override_winner_name, $is_bin_purchase) = @_;
    my $auction_key = GetAuctionDataKey($auction_name);
    
    my $item_link = quest::varlink($item_id); 
    my $currency_name = GetCurrencyName();
    
    my $auction_data = quest::get_data($auction_key);
    # RESTORED: Correctly define 8 variables for data consistency
    my ($data_item_id, $data_end_time, $data_current_bid, $data_current_winner_id, $data_gm_name, $min_bid, $set_increment, $bin_price) = split /\|/, $auction_data;
    
    my $timestamp = localtime(time());
    
    if ($winner_id > 0) {
        my $winner_name = $override_winner_name;
        
        unless ($winner_name) {
             # Normal auction end, look up name from QGlobal key
             $winner_name = quest::get_data("bidder\_$winner_id\_$auction_name") || "Unknown Player";
        }
        
        my $item_name = quest::getitemname($item_id);
        
        # Log: WINNER
        my $log_message = "[$timestamp] AUCTION WINNER: Key: $auction_name | Item: $item_name (ID $item_id) | Winner: $winner_name (ID $winner_id) | Paid: $winning_bid $currency_name.";
        quest::write("auction_log.txt", $log_message); 
        
        # Send winning item via parcel
        quest::send_parcel({
            name      => $winner_name,
            item_id   => $item_id,
            quantity  => 1,
            from_name => "Remote Auction Master",
            note      => "Winning item from '$auction_name' auction with $winning_bid $currency_name."
        });
        
        # 🔑 FIX 2: Only send the worldwide message if it's NOT a BIN purchase.
        unless ($is_bin_purchase) {
            quest::worldwidemessage(261, "The auction for $item_link has ended! Congratulations to $winner_name (Winning Bid: $winning_bid $currency_name). The item has been sent to your parcel box.");
        }
        
        quest::delete_data("bidder\_$winner_id\_$auction_name"); 
    } else {
        quest::worldwidemessage(261, "The auction for $item_link has ended with no winner (Min bid: $min_bid $currency_name).");
        
        # Log: NO WINNER
        my $item_name = quest::getitemname($item_id);
        my $log_message = "[$timestamp] AUCTION NO WINNER: Key: $auction_name | Item: $item_name (ID $item_id) | Min Bid: $min_bid $currency_name.";
        quest::write("auction_log.txt", $log_message);
    }
    
    UpdateActiveAuctionList($auction_name, 0); 
    quest::delete_data($auction_key);
}

sub ForceEndAuction {
    my ($auction_name, $is_delete) = @_; 
    my $auction_key = GetAuctionDataKey($auction_name);
    my $auction_data = quest::get_data($auction_key);
    my $currency_name = GetCurrencyName();
    
    if (!$auction_data) {
        quest::log(5, "ERROR: ForceEndAuction called on inactive auction: $auction_name");
        return;
    }

    # RESTORED: Correctly define 8 variables for data consistency
    my ($item_id, $end_time, $current_bid, $current_winner_id, $gm_name, $min_bid, $set_increment, $bin_price) = split /\|/, $auction_data;
    my $timestamp = localtime(time()); 
    
    if ($is_delete) {
        # --- AUCTION DELETE LOGIC ---
        my $item_link = quest::varlink($item_id);
        quest::worldwidemessage(261, "The auction for $item_link has been CANCELED. Returning all bids via parcel.");
        
        if ($current_winner_id > 0) {
            my $winner_name = quest::get_data("bidder\_$current_winner_id\_$auction_name") || "Unknown Player";
            
            # Return the coins to the top bidder
            quest::send_parcel({
                name         => $winner_name,
                item_id      => $CURRENCY_ITEM_ID,
                quantity     => $current_bid,
                from_name    => "Remote Auction System",
                note         => "Canceled auction '$auction_name'. Your $current_bid $currency_name have been returned."
            });
            quest::delete_data("bidder\_$current_winner_id\_$auction_name"); 
        }
        
        UpdateActiveAuctionList($auction_name, 0); 
        quest::delete_data($auction_key);
    } else {
        # --- NORMAL ENDING LOGIC (Finalize Auction) ---
        FinalizeAuction($auction_name, $item_id, $current_winner_id, $current_bid, undef, 0); # Passed 0 for $is_bin_purchase
    }
}

sub CheckExpiredAuctions {
    # CheckExpiredAuctions must be a public function (exported from the package)
    
    my $active_auctions_string = quest::get_data($AUCTION_LIST_KEY) || "";
    my @active_auctions = split /:/, $active_auctions_string;
    my $current_time = time();

    foreach my $auction_name (@active_auctions) {
        next if $auction_name eq ''; 
        
        my $auction_key = GetAuctionDataKey($auction_name);
        my $auction_data = quest::get_data($auction_key);
        next unless $auction_data;
        
        # RESTORED: Correctly define 8 variables for data consistency
        my ($item_id, $end_time, $current_bid, $current_winner_id, $gm_name, $min_bid, $set_increment, $bin_price) = split /\|/, $auction_data;
        
        if ($current_time >= $end_time) {
            # Call the plugin's logic for finalizing
            ForceEndAuction($auction_name, 0); # Finalize (0)
        }
    }
}
# -------------------------------------------------------------------------------------------------
# CORE BIDDING LOGIC (Used by both NPC and Remote Commands)
# -------------------------------------------------------------------------------------------------
sub ProcessSmartBid {
    my ($client, $auction_name, $bid_amount) = @_;
    
    my $auction_key = GetAuctionDataKey($auction_name);
    my $auction_data = quest::get_data($auction_key);
    my $currency_name = GetCurrencyName();
    
    if (!$auction_data) {
        $client->Message(315, "Error: Auction '$auction_name' is no longer active.");
        return;
    }
    
    # 1. CHECK PLAYER INVENTORY FOR CURRENCY
    my $inventory_item_balance = $client->CountItem($CURRENCY_ITEM_ID);
    
    if ($inventory_item_balance < $bid_amount) {
        $client->Message(315, "You need $bid_amount $currency_name (Item ID $CURRENCY_ITEM_ID) to place that bid. You only have $inventory_item_balance in your inventory. Gather more and use the !bid command again!");
        return;
    }
    
    # 2. PROCESS BID LOGIC 
    # RESTORED: Correctly define 8 variables for data consistency
    my ($item_id, $end_time, $current_bid, $current_winner_id, $gm_name, $min_bid, $set_increment, $bin_price) = split /\|/, $auction_data;
    
    my $effective_increment = $set_increment || $DEFAULT_MIN_INCREMENT;
    my $min_legal_bid = ($current_bid == 0) ? $min_bid : ($current_bid + $effective_increment);

    if ($bid_amount < $min_legal_bid) {
        $client->Message(315, "Error: Your bid of $bid_amount is too low. The next minimum legal bid is $min_legal_bid $currency_name (Min Increment: $effective_increment).");
        return;
    }

    # 4. DEDUCT CURRENCY & DEFINE NEW WINNER
    quest::removeitem($CURRENCY_ITEM_ID, $bid_amount);
    $client->Message(315, "Deducted $bid_amount $currency_name items from your inventory.");

    my $new_winner_id = $client->GetID();
    my $winner_name = $client->GetName();

    # 3. RETURN OLD BID & ANNOUNCE 
    if ($current_winner_id > 0) {
        my $previous_bid_amount = $current_bid;
        my $previous_winner_name = quest::get_data("bidder\_$current_winner_id\_$auction_name") || "Unknown Player"; 
        
        # PARCEL: Return coins to previous bidder
        quest::send_parcel({
            name         => $previous_winner_name,
            item_id      => $CURRENCY_ITEM_ID,
            quantity     => $previous_bid_amount,
            from_name    => "Remote Auction System", 
            note         => "Outbid on '$auction_name' auction. Your $previous_bid_amount $currency_name have been returned."
        });

        my $item_link = quest::varlink($item_id);
        quest::worldwidemessage(261, "ALERT: $winner_name has placed a new bid of $bid_amount $currency_name on the $item_link auction! The previous high bid has been returned to the bidder via parcel.");
        
        quest::delete_data("bidder\_$current_winner_id\_$auction_name"); 
    } else {
        my $item_link = quest::varlink($item_id); 
        
        quest::worldwidemessage(261, "ALERT: $winner_name has placed the first bid of $bid_amount $currency_name on the $item_link auction!");
    }

    # 6. ANTI-SNIPING (Soft Close) CHECK
    my $current_time = time();
    my $remaining_time = $end_time - $current_time;
    my $extension_message = "";

    if ($remaining_time <= $SNIPE_WINDOW) {
        $end_time = $end_time + $TIME_EXTENSION;
        my $new_remaining_time = $end_time - $current_time;
        
        $extension_message = " The auction has entered a soft-close phase and has been extended by $TIME_EXTENSION seconds, now ending in approximately $new_remaining_time seconds.";
        
        quest::worldwidemessage(261, "AUCTION EXTENSION: A bid was placed on '$auction_name' in the final " . $SNIPE_WINDOW . " seconds! Time extended by " . $TIME_EXTENSION . " seconds. New end time: " . gmtime($end_time));
    }

    # 5. Update auction data (Uses the potentially extended $end_time)
    $current_bid = $bid_amount;
    
    # RESTORED: Saving 8 fields consistently
    my $new_auction_data = "$item_id|$end_time|$current_bid|$new_winner_id|$gm_name|$min_bid|$set_increment|$bin_price";
    
    quest::set_data($auction_key, $new_auction_data, $AUCTION_TIMEOUT_DAYS * 86400);
    quest::set_data("bidder\_$new_winner_id\_$auction_name", $winner_name, $AUCTION_TIMEOUT_DAYS * 86400);

    $client->Message(315, "Remote Bid accepted! You are the new high bidder with $current_bid $currency_name.$extension_message Good luck!");
}


# -------------------------------------------------------------------------------------------------
# PUBLIC GM COMMANDS (Used by global_player.pl)
# -------------------------------------------------------------------------------------------------


sub CommandGMHelp {
    my $client = shift;
    $client->Message(315, "--- REMOTE GM AUCTION COMMANDS ---");
    $client->Message(315, "1. Start: !auction start [name] [item id] [hours] [min bid] [OPT: increment] [OPT: bin price]");
    $client->Message(315, "2. End: !auction end [name] (Finalizes auction)");
    $client->Message(315, "3. Delete: !auction delete [name] (Cancels and returns coins)");
}

sub CommandStartAuction {
    my ($client, $auction_name_input, $item_id, $hours, $min_bid, $custom_increment) = @_;
    my $admin_level = $client->GetGMStatus() || 0; 
    my $name = $client->GetName();
    my $currency_name = GetCurrencyName();

    if ($admin_level < $GM_MIN_LEVEL_ADMIN) {
        $client->Message(315, "GM access required for this command.");
        return;
    }

    my $set_increment = ($custom_increment && $custom_increment > 0) ? $custom_increment : $DEFAULT_MIN_INCREMENT;
    my $auction_name = $auction_name_input; 
    my $auction_key = GetAuctionDataKey($auction_name); 
    
    if (quest::get_data($auction_key)) {
        $client->Message(315, "Auction '$auction_name' already exists! Please choose a different name.");
        return;
    }

    my $current_time = time();
    my $end_time = $current_time + ($hours * 3600);
    my $bin_price = $STATIC_BUY_IT_NOW_PRICE; # Use the defined static BIN price

    # RESTORED: Saving 8 fields consistently: item_id|end_time|current_bid|current_winner_id|gm_name|min_bid|set_increment|bin_price
    my $auction_data = "$item_id|$end_time|0|0|$name|$min_bid|$set_increment|$bin_price";
    my $item_link = quest::varlink($item_id);

    quest::set_data($auction_key, $auction_data, $AUCTION_TIMEOUT_DAYS * 86400); 
    UpdateActiveAuctionList($auction_name, 1);
    
    quest::worldwidemessage(261, "GM $name has started a new auction for $item_link! Min bid: $min_bid $currency_name. Buy It Now: $bin_price $currency_name. Min Increment: $set_increment. Auction Key: '$auction_name'.");
    $client->Message(315, "Successfully started auction: $auction_name. BIN Price: $bin_price.");
}

sub CommandEndAuction {
    my ($client, $auction_name) = @_;
    my $admin_level = $client->GetGMStatus() || 0; 
    
    if ($admin_level < $GM_MIN_LEVEL_ADMIN) {
        $client->Message(315, "GM access required for this command.");
        return;
    }
    
    my $auction_key = GetAuctionDataKey($auction_name);
    if (!quest::get_data($auction_key)) {
        $client->Message(315, "Auction '$auction_name' is not active.");
        return;
    }

    # Call the logic now in the plugin
    ForceEndAuction($auction_name, 0); # 0 = Normal End
    $client->Message(315, "Auction '$auction_name' manually finalized.");
}

sub CommandDeleteAuction {
    my ($client, $auction_name) = @_;
    my $admin_level = $client->GetGMStatus() || 0; 
    
    if ($admin_level < $GM_MIN_LEVEL_ADMIN) {
        $client->Message(315, "GM access required for this command.");
        return;
    }
    
    my $auction_key = GetAuctionDataKey($auction_name);
    if (!quest::get_data($auction_key)) {
        $client->Message(315, "Auction '$auction_name' is not active.");
        return;
    }

    # Call the logic now in the plugin
    ForceEndAuction($auction_name, 1); # 1 = Delete/Cancel
    $client->Message(315, "Auction '$auction_name' canceled and bids refunded.");
}

# -------------------------------------------------------------------------------------------------
# PUBLIC PLAYER COMMANDS (Used by global_player.pl)
# -------------------------------------------------------------------------------------------------

sub ListActiveAuctions {
    my $client = shift;
    my $active_auctions_string = quest::get_data($AUCTION_LIST_KEY) || "";
    my @active_auctions = split /:/, $active_auctions_string;
    
    if (scalar @active_auctions > 0) {
        $client->Message(315, "--- Active Auctions ---");
        
        foreach my $auction_name (@active_auctions) {
            next if $auction_name eq '';
            
            my $auction_key = GetAuctionDataKey($auction_name); 
            my $auction_data = quest::get_data($auction_key) || "";
            next unless $auction_data;
            
            my ($item_id) = split /\|/, $auction_data;
            my $display_name = quest::getitemname($item_id) || "Unknown Item";
            
            my $clickable_link = quest::saylink("!auction $auction_name", 0, $display_name);
            
            $client->Message(315, "Key: $auction_name | Item: $clickable_link");
        }
        $client->Message(315, "-----------------------");
    } else {
        $client->Message(315, "There are no active auctions at this time.");
    }
}

sub CommandRemoteBid {
    my ($client, $auction_name, $bid_amount) = @_;
    
    if ($bid_amount <= 0) {
        $client->Message(315, "Bid amount must be a positive number.");
        return;
    }
    
    ProcessSmartBid($client, $auction_name, $bid_amount);
}

# RESTORED: CommandBuyItNow Logic
sub CommandBuyItNow {
    my ($client, $auction_name) = @_;
    my $auction_key = GetAuctionDataKey($auction_name);
    my $auction_data = quest::get_data($auction_key);
    my $currency_name = GetCurrencyName();

    my $player_id = $client->CharacterID() || 0; 
    my $player_name = $client->GetName() || "Unknown Player"; 
    
    if (!$auction_data) {
        $client->Message(315, "Error: Auction '$auction_name' is not currently active.");
        return;
    }
    
    # Parsing 8 fields:
    my ($item_id, $end_time, $current_bid, $current_winner_id, $gm_name, $min_bid, $set_increment, $bin_price) = split /\|/, $auction_data;
    
    if ($bin_price <= 0) {
        $client->Message(315, "Error: This auction does not have a Buy It Now price set.");
        return;
    }
    
    if ($client->CountItem($CURRENCY_ITEM_ID) < $bin_price) {
        $client->Message(315, "You need $bin_price $currency_name to Buy It Now. You only have " . $client->CountItem($CURRENCY_ITEM_ID) . ".");
        return;
    }
    
    quest::removeitem($CURRENCY_ITEM_ID, $bin_price);
    $client->Message(315, "Deducted $bin_price $currency_name for Buy It Now.");
    
    # 🔑 FIX 3: Call FinalizeAuction with 1 (true) for $is_bin_purchase flag
    # This prevents FinalizeAuction from sending its general worldwide message.
    FinalizeAuction($auction_name, $item_id, $player_id, $bin_price, $player_name, 1); 
    
    my $item_link = quest::varlink($item_id);
    # This remains the single worldwide message for BIN.
    quest::worldwidemessage(261, "$player_name has purchased $item_link from auction using Buy It Now for $bin_price $currency_name! The auction has ended.");
    $client->Message(315, "Buy It Now complete! The item has been sent to your parcel box.");
}


sub CommandCheckStatus {
    my ($client, $auction_name) = @_;
    
    my $auction_key = GetAuctionDataKey($auction_name);
    my $auction_data = quest::get_data($auction_key);
    my $currency_name = GetCurrencyName();

    if (!$auction_data) {
        $client->Message(315, "Auction '$auction_name' is not currently active.");
        return;
    }
    # RESTORED: Correctly define 8 variables for data consistency
    my ($item_id, $end_time, $current_bid, $current_winner_id, $gm_name, $min_bid, $set_increment, $bin_price) = split /\|/, $auction_data;
    
    my $effective_increment = $set_increment || $DEFAULT_MIN_INCREMENT;
    my $item_link = quest::varlink($item_id);
    my $time_left = $end_time - time();
    my $time_left_string = ConvertSecondsToTime($time_left);
    
    my $winner_name = "No Winner Yet (Min Bid: $min_bid $currency_name)";
    if ($current_winner_id > 0) {
        $winner_name = quest::get_data("bidder\_$current_winner_id\_$auction_name") || "Unknown Player";
    }

    $client->Message(315, "--- " . quest::getitemname($item_id) . " Auction Status (Key: $auction_name) ---");
    $client->Message(315, "Item: $item_link");
    $client->Message(315, "Current Bid: $current_bid $currency_name");
    $client->Message(315, "High Bidder: $winner_name");
    
    if ($time_left > 0) {
        $client->Message(315, "Time Remaining: $time_left_string (Ends at " . localtime($end_time) . ")");
    } else {
        $client->Message(315, "The auction has expired and is pending finalization.");
    }
    
    my $base_next_bid = ($current_bid == 0) ? $min_bid : ($current_bid + $effective_increment);
    $client->Message(315, "-----------------");
    
    # BIN Display and Link
    if ($bin_price > 0) {
        $client->Message(315, "Buy It Now Price: $bin_price $currency_name");
        my $bin_link = quest::saylink(
            "!bin $auction_name", 
            0,                                   
            "Click here to Buy It Now ($bin_price $currency_name)" 
        );
        $client->Message(315, $bin_link);
        $client->Message(315, "-----------------");
    }
    
    my $bid_link = quest::saylink(
        "!bid $auction_name $base_next_bid", 
        0,                                   
        "Place Next Bid ($base_next_bid $currency_name)" 
    );
    
    $client->Message(315, "Next Minimum Bid: $base_next_bid $currency_name (Min Inc: $effective_increment)");
    $client->Message(315, "Click here to place the next minimum bid: $bid_link");
    $client->Message(315, "Alternatively, use the command: !bid $auction_name [amount]");
}

1;