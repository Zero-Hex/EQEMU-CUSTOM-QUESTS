# Filename: ParcelManager.pl
# Location: [EQEMU_Root]/quests/plugins/
# Authored by Zerohex
# =========================================================================
# Subroutines to Display and Redeem Parcels
# =========================================================================

sub DisplayParcels {
    # Fetch $client internally using the standard plugin utility
    my $client = plugin::val('$client');
    
    if (!defined $client) {
        quest::debug("Error: Client context lost in DisplayParcels.");
        return;
    }

    my $char_id = $client->CharacterID(); 
    my $db = Database::new(Database::Content);
    my $stmt = $db->prepare("SELECT item_id, quantity FROM character_parcels WHERE char_id = ?");
    $stmt->execute($char_id);
    
    my $output = "Your pending parcels:\n\n";
    my $qglobal_data = "";

    while (my $row = $stmt->fetch_hashref())
    {
        my $item_id  = int($row->{"item_id"});
        my $quantity = int($row->{"quantity"});
        
        my $unique_key = "${item_id}_${quantity}";
        $qglobal_data .= ($qglobal_data ? "|" : "") . $unique_key;

        my $item_name = quest::getitemname($item_id);
        
        # Create the clickable link: RECLAIM_KEY 
        my $reclaim_link = quest::saylink("RECLAIM_$unique_key", 1, "Reclaim");

        # Add a Separator between each item || is what it is default set as. 
        $output .= "- $item_name ($quantity) $reclaim_link\n";
        $output .= "||\n"; 
    }
   $stmt->close();
    $db->close();
    

    # Check if we found any parcels to display (by checking the initial output string)
    if ($output ne "Your pending parcels:\n\n") {
        
        # 1. Clean up the final separator line if it exists
        if ($output =~ /------------------------\n$/) {
            $output =~ s/------------------------\n$//;
        }

        # 2. Create the clickable link
        my $reclaim_all_link = quest::saylink("!reclaim all", 1, "[RECLAIM ALL]");
        
        # 3. Append the link to the existing output message
        $output .= "\n" . $reclaim_all_link . "\n";
    }
    
    # Final check for empty list
    if ($output eq "Your pending parcels:\n\n") {
        $output = "You have no pending parcels.";
        quest::delete_data("PARCELS_$char_id"); # Clean up the QGlobal if empty
    } else {
        # Store the current list of reclaimable items for stale link prevention
        quest::set_data("PARCELS_$char_id", $qglobal_data);
    }

    # Send the output to the client as a system message
    $client->Message(315, $output); 
}


sub RedeemParcel {
    my ($unique_key) = @_; 
    
    # Fetch $client internally
    my $client = plugin::val('$client');
    
    if (!defined $client) {
        quest::debug("Error: Client context lost in RedeemParcel.");
        return;
    }
    
    my $char_id = $client->CharacterID(); 
    my $qglobal_key = "PARCELS_$char_id";

    # 1. INITIAL CHECK: Retrieve the current list of reclaimable items from the QGlobal
    my $qglobal_data = quest::get_data($qglobal_key);

    if ($qglobal_data !~ /\b\Q$unique_key\E\b/) {
        $client->Message(315, "That parcel has already been claimed or is invalid.");
        plugin::DisplayParcels(); # Refresh the display
        return; 
    }

    my ($item_id, $quantity) = split('_', $unique_key);
    $item_id = int($item_id);
    $quantity = int($quantity);

    my $db = Database::new(Database::Content);
    my $message = "";

    # --- Redemption Logic (Item/Cash Summoning) ---
    if ($item_id == 99990) {
        # Currency Logic
        my $total_copper = $quantity;
        my $platinum = int($total_copper / 1000);
        $total_copper %= 1000;
        my $gold = int($total_copper / 100);
        $total_copper %= 100;
        my $silver = int($total_copper / 10);
        $total_copper %= 10;
        my $copper = $total_copper;

        quest::givecash($copper, $silver, $gold, $platinum); 
        
        $message = "You have reclaimed your currency: ";
        $message .= "$platinum Platinum, " if $platinum > 0;
        $message .= "$gold Gold, "       if $gold > 0;
        $message .= "$silver Silver, "   if $silver > 0;
        $message .= "$copper Copper."    if $copper > 0 || ($platinum + $gold + $silver == 0);

    } else {
        # Normal Item Logic
        my $item_name = quest::getitemname($item_id);
        quest::summonitem($item_id, $quantity);
        $message = "You have reclaimed $quantity x $item_name!";
    }

    # 2. Delete the parcel from the database (Autocommit handles saving the deletion)
    my $del_stmt = $db->prepare("DELETE FROM character_parcels WHERE char_id = ? AND item_id = ? AND quantity = ? LIMIT 1");
    $del_stmt->execute($char_id, $item_id, $quantity);
    $del_stmt->close();
    $db->close();

    # Inform the player
    $client->Message(315, $message); 
    
    # 3. REMOVE THE CLAIMED ITEM FROM THE QGLOBAL
    $qglobal_data =~ s/\Q$unique_key\E\|?//g; 
    $qglobal_data =~ s/^\|//;                 
    quest::set_data($qglobal_key, $qglobal_data); 

    # 4. REFRESH THE LIST
    plugin::DisplayParcels(); 

# In ParcelManager.pl, add this new subroutine:

sub ReclaimAllParcels {
    my $client = plugin::val('$client');
    if (!defined $client) {
        quest::debug("Error: Client context lost in ReclaimAllParcels.");
        return;
    }

    my $char_id = $client->CharacterID();
    my $db = Database::new(Database::Content);
    my $total_claimed = 0;
    my $parcels_claimed_data = ""; # Used to build a comprehensive confirmation message

    # 1. Retrieve ALL parcels for the character
    # NOTE: We must fetch the DB 'id' as well if you are using keyset paging in other areas, 
    # but for simple batch processing, we'll use item_id and quantity to delete.
    my $stmt = $db->prepare("SELECT item_id, quantity FROM character_parcels WHERE char_id = ?");
    $stmt->execute($char_id);
    
    my @parcels_to_claim;
    while (my $row = $stmt->fetch_hashref()) {
        push @parcels_to_claim, { 
            item_id => int($row->{"item_id"}), 
            quantity => int($row->{"quantity"}) 
        };
    }
    $stmt->close();
    
    # 2. Loop through and claim each parcel
    foreach my $parcel (@parcels_to_claim) {
        my $item_id  = $parcel->{item_id};
        my $quantity = $parcel->{quantity};
        
        # --- CLAIM ITEM/MONEY ---
        if ($item_id == 99990) {
            # Currency Logic (simplified for batch)
            my $total_copper = $quantity;
            my $platinum = int($total_copper / 1000);
            quest::givecash(0, 0, 0, $platinum); # Only giving plat here for simplicity, adjust as needed.
            
            # NOTE: For full copper/silver/gold redemption, you need the full logic from RedeemParcel
            # For robustness, we'll use the full cash logic:
            my $gold = int(($total_copper % 1000) / 100);
            my $silver = int(($total_copper % 100) / 10);
            my $copper = $total_copper % 10;
            quest::givecash($copper, $silver, $gold, $platinum); 
            
            $parcels_claimed_data .= " | Money Claimed";
            
        } else {
            # Item Logic
            my $item_name = quest::getitemname($item_id);
            # CRITICAL: Use the standard summon function. $client->SummonItemIntoInventory 
            # is not an exported Perl function. Use quest::summonitem.
            quest::summonitem($item_id, $quantity); 
            
            $parcels_claimed_data .= " | $item_name ($quantity)";
        }
        
        $total_claimed++;
        
        # 3. Delete the parcel from the database
        # NOTE: This is the safest way to delete: one at a time, checking char_id, item_id, and quantity.
        my $del_stmt = $db->prepare("DELETE FROM character_parcels WHERE char_id = ? AND item_id = ? AND quantity = ? LIMIT 1");
        $del_stmt->execute($char_id, $item_id, $quantity);
        $del_stmt->close();
    }
    $db->close();
    
    # 4. Final confirmation and cleanup
    if ($total_claimed > 0) {
        $client->Message(315, "Successfully claimed $total_claimed parcel(s)!");
        quest::delete_data("PARCELS_$char_id"); # Clear all QGlobals
    } else {
        $client->Message(315, "No parcels were found to claim.");
    }

    # Refresh the list one final time
    plugin::DisplayParcels(); 
}
}