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
        #quest::debug("Error: Client context lost in DisplayParcels.");
        return;
    }

    my $char_id = $client->CharacterID();
    my $db = Database::new(Database::Content);
    # Fix: Select the id column to uniquely identify each parcel
    my $stmt = $db->prepare("SELECT id, item_id, quantity FROM character_parcels WHERE char_id = ?");
    $stmt->execute($char_id);

    my $output = "Your pending parcels:\n\n";
    my $qglobal_data = "";

    while (my $row = $stmt->fetch_hashref())
    {
        my $parcel_id = int($row->{"id"});
        my $item_id   = int($row->{"item_id"});
        my $quantity  = int($row->{"quantity"});

        # Fix: Use the database row id as the unique key instead of item_id_quantity
        my $unique_key = $parcel_id;
        $qglobal_data .= ($qglobal_data ? "|" : "") . $unique_key;

        my $item_name = quest::getitemname($item_id);

        # Create the clickable link: RECLAIM_KEY
        # Format: quest::saylink(text, silent, link_text)
        # silent=0 means the click will echo to other players
        my $reclaim_link = quest::saylink("!parcel reclaim $unique_key", 1, "Reclaim");

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
        my $reclaim_all_link = quest::saylink("!reclaim all", 0, "[RECLAIM ALL]");
        
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
    my ($parcel_id) = @_;

    # Fetch $client internally
    my $client = plugin::val('$client');

    if (!defined $client) {
        #quest::debug("Error: Client context lost in RedeemParcel.");
        return;
    }

    my $char_id = $client->CharacterID();
    my $qglobal_key = "PARCELS_$char_id";

    ##quest::debug("RedeemParcel: char_id=$char_id, parcel_id=$parcel_id");

    # 1. INITIAL CHECK: Retrieve the current list of reclaimable items from the QGlobal
    my $qglobal_data = quest::get_data($qglobal_key);
   ##quest::debug("RedeemParcel: qglobal_data=" . (defined $qglobal_data ? $qglobal_data : "undef"));

    # Fix: Check if the parcel_id exists in the qglobal data (only if qglobal is set)
    if (defined $qglobal_data && $qglobal_data ne "" && $qglobal_data !~ /\b\Q$parcel_id\E\b/) {
        $client->Message(315, "That parcel has already been claimed or is invalid.");
        #quest::debug("RedeemParcel: parcel_id not found in qglobal");
        plugin::DisplayParcels(); # Refresh the display
        return;
    }

    # Fix: Fetch the parcel data from the database using the row id
    my $db = Database::new(Database::Content);
    my $fetch_stmt = $db->prepare("SELECT item_id, quantity FROM character_parcels WHERE id = ? AND char_id = ?");
    $fetch_stmt->execute($parcel_id, $char_id);
    my $parcel_row = $fetch_stmt->fetch_hashref();
    $fetch_stmt->close();

    if (!defined $parcel_row) {
        $client->Message(315, "That parcel has already been claimed or is invalid.");
        $db->close();
        plugin::DisplayParcels();
        return;
    }

    my $item_id = int($parcel_row->{"item_id"});
    my $quantity = int($parcel_row->{"quantity"});
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

        # Check if item is stackable
        my $item_check = $db->prepare("SELECT stacksize FROM items WHERE id = ?");
        $item_check->execute($item_id);
        my $item_data = $item_check->fetch_hashref();
        $item_check->close();

        my $stacksize = $item_data ? int($item_data->{"stacksize"}) : 1;

        if ($stacksize > 1) {
            # Stackable item - use quantity parameter
            quest::summonitem($item_id, $quantity);
        } else {
            # Non-stackable item - summon one at a time
            for (my $i = 0; $i < $quantity; $i++) {
                quest::summonitem($item_id);
            }
        }

        $message = "You have reclaimed $quantity x $item_name!";
    }

    # 2. Delete the parcel from the database using the row id
    my $del_stmt = $db->prepare("DELETE FROM character_parcels WHERE id = ? AND char_id = ?");
    $del_stmt->execute($parcel_id, $char_id);
    $del_stmt->close();
    $db->close();

    # Inform the player
    $client->Message(315, $message);

    # 3. REMOVE THE CLAIMED ITEM FROM THE QGLOBAL
    $qglobal_data =~ s/\b\Q$parcel_id\E\b\|?//g;
    $qglobal_data =~ s/^\|//;
    $qglobal_data =~ s/\|$//;
    quest::set_data($qglobal_key, $qglobal_data);

    # 4. REFRESH THE LIST
    plugin::DisplayParcels();
}

sub ReclaimAllParcels {
    my $client = plugin::val('$client');
    if (!defined $client) {
        #quest::debug("Error: Client context lost in ReclaimAllParcels.");
        return;
    }

    my $char_id = $client->CharacterID();
    my $db = Database::new(Database::Content);
    my $total_claimed = 0;
    my $parcels_claimed_data = ""; # Used to build a comprehensive confirmation message

    # 1. Retrieve ALL parcels for the character with their row IDs
    my $stmt = $db->prepare("SELECT id, item_id, quantity FROM character_parcels WHERE char_id = ?");
    $stmt->execute($char_id);

    my @parcels_to_claim;
    while (my $row = $stmt->fetch_hashref()) {
        push @parcels_to_claim, {
            id => int($row->{"id"}),
            item_id => int($row->{"item_id"}),
            quantity => int($row->{"quantity"})
        };
    }
    $stmt->close();

    # 2. Loop through and claim each parcel
    foreach my $parcel (@parcels_to_claim) {
        my $parcel_id = $parcel->{id};
        my $item_id   = $parcel->{item_id};
        my $quantity  = $parcel->{quantity};

        # --- CLAIM ITEM/MONEY ---
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

            $parcels_claimed_data .= " | Money Claimed";

        } else {
            # Item Logic
            my $item_name = quest::getitemname($item_id);

            # Check if item is stackable
            my $item_check = $db->prepare("SELECT stacksize FROM items WHERE id = ?");
            $item_check->execute($item_id);
            my $item_data = $item_check->fetch_hashref();
            $item_check->close();

            my $stacksize = $item_data ? int($item_data->{"stacksize"}) : 1;

            if ($stacksize > 1) {
                # Stackable item - use quantity parameter
                quest::summonitem($item_id, $quantity);
            } else {
                # Non-stackable item - summon one at a time
                for (my $i = 0; $i < $quantity; $i++) {
                    quest::summonitem($item_id);
                }
            }

            $parcels_claimed_data .= " | $item_name ($quantity)";
        }

        $total_claimed++;

        # 3. Delete the parcel from the database using row id
        my $del_stmt = $db->prepare("DELETE FROM character_parcels WHERE id = ? AND char_id = ?");
        $del_stmt->execute($parcel_id, $char_id);
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

sub SendParcel {
    my ($target_name, $item_id, $quantity, $from_name) = @_;

    # Fetch $client internally
    my $client = plugin::val('$client');

    if (!defined $client) {
        #quest::debug("Error: Client context lost in SendParcel.");
        return 0;
    }

    # Validate inputs
    $item_id = int($item_id) if defined $item_id;
    $quantity = int($quantity) if defined $quantity;

    if (!defined $target_name || $target_name eq "") {
        $client->Message(315, "Error: Target character name is required.");
        return 0;
    }

    if (!defined $item_id || $item_id <= 0) {
        $client->Message(315, "Error: Invalid item ID.");
        return 0;
    }

    if (!defined $quantity || $quantity <= 0) {
        $client->Message(315, "Error: Quantity must be greater than 0.");
        return 0;
    }

    # Get the target character ID from the character name (case-insensitive)
    my $db = Database::new(Database::Content);
    my $char_stmt = $db->prepare("SELECT id FROM character_data WHERE name = ? LIMIT 1");
    $char_stmt->execute($target_name);
    my $char_row = $char_stmt->fetch_hashref();
    $char_stmt->close();

    if (!defined $char_row) {
        $client->Message(315, "Error: Character '$target_name' not found.");
        #quest::debug("SendParcel: Character '$target_name' not found in database");
        $db->close();
        return 0;
    }

    my $target_char_id = int($char_row->{"id"});
    #quest::debug("SendParcel: Found character '$target_name' with ID $target_char_id");

    # Check if player has the item in their inventory
    my $has_item = $client->CountItem($item_id);
    if ($has_item < $quantity) {
        $client->Message(315, "Error: You don't have enough of that item. You have $has_item but need $quantity.");
        $db->close();
        return 0;
    }

    # Check if the item is attuned or nodrop
    my $item_flags_stmt = $db->prepare("SELECT tradeskills, attuneable, nodrop FROM items WHERE id = ? LIMIT 1");
    $item_flags_stmt->execute($item_id);
    my $item_flags = $item_flags_stmt->fetch_hashref();
    $item_flags_stmt->close();

    if (defined $item_flags) {
        # Check nodrop flag (tradeskills = 0 means NODROP, or nodrop field = 1)
        my $is_nodrop = (defined $item_flags->{"nodrop"} && $item_flags->{"nodrop"} == 1) ||
                        (defined $item_flags->{"tradeskills"} && $item_flags->{"tradeskills"} == 0);

        # Check attuneable flag (attuneable != 0 means the item can be/is attuned)
        my $is_attuned = defined $item_flags->{"attuneable"} && $item_flags->{"attuneable"} != 0;

        if ($is_nodrop || $is_attuned) {
            my $item_name = quest::getitemname($item_id);
            my $reason = $is_nodrop && $is_attuned ? "NODROP and ATTUNED" :
                         $is_nodrop ? "NODROP" : "ATTUNED";
            $client->Message(315, "Error: Cannot send '$item_name' - this item is $reason and cannot be parceled.");
            #quest::debug("SendParcel: Blocked parceling of item $item_id ($item_name) - $reason");
            $db->close();
            return 0;
        }
    }

    # Check if any instances of this item in the player's inventory have augments
    my $sender_char_id = $client->CharacterID();
    my $augment_check_stmt = $db->prepare("SELECT augslot1, augslot2, augslot3, augslot4, augslot5, augslot6 FROM inventory WHERE charid = ? AND itemid = ? LIMIT 1");
    $augment_check_stmt->execute($sender_char_id, $item_id);

    while (my $inv_row = $augment_check_stmt->fetch_hashref()) {
        # Check if any augment slot is populated (non-zero)
        my $has_augments = (defined $inv_row->{"augslot1"} && $inv_row->{"augslot1"} != 0) ||
                          (defined $inv_row->{"augslot2"} && $inv_row->{"augslot2"} != 0) ||
                          (defined $inv_row->{"augslot3"} && $inv_row->{"augslot3"} != 0) ||
                          (defined $inv_row->{"augslot4"} && $inv_row->{"augslot4"} != 0) ||
                          (defined $inv_row->{"augslot5"} && $inv_row->{"augslot5"} != 0) ||
                          (defined $inv_row->{"augslot6"} && $inv_row->{"augslot6"} != 0);

        if ($has_augments) {
            my $item_name = quest::getitemname($item_id);
            $client->Message(315, "Error: Cannot send '$item_name' - items with augments cannot be parceled. Please remove augments first.");
            #quest::debug("SendParcel: Blocked parceling of item $item_id ($item_name) - has augments");
            $augment_check_stmt->close();
            $db->close();
            return 0;
        }
    }
    $augment_check_stmt->close();

    # Optional: Set from_name if not provided
    if (!defined $from_name || $from_name eq "") {
        $from_name = $client->GetCleanName();
    }

    # Get the next available ID for the parcel
    my $id_stmt = $db->prepare("SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM character_parcels");
    $id_stmt->execute();
    my $id_row = $id_stmt->fetch_hashref();
    my $next_id = $id_row ? int($id_row->{"next_id"}) : 1;
    $id_stmt->close();
    #quest::debug("SendParcel: next_id = $next_id");

    # Get the next available slot_id for this character
    my $slot_stmt = $db->prepare("SELECT COALESCE(MAX(slot_id), -1) + 1 AS next_slot FROM character_parcels WHERE char_id = ?");
    $slot_stmt->execute($target_char_id);
    my $slot_row = $slot_stmt->fetch_hashref();
    my $next_slot_id = $slot_row ? int($slot_row->{"next_slot"}) : 0;
    $slot_stmt->close();
    #quest::debug("SendParcel: next_slot_id = $next_slot_id for char_id = $target_char_id");

    # Check if a parcel with this char_id and item_id already exists
    #quest::debug("SendParcel: About to check existing - target_char_id=$target_char_id, item_id=$item_id");
    my $check_stmt = $db->prepare("SELECT id, quantity FROM character_parcels WHERE char_id = ? AND item_id = ? LIMIT 1");
    $check_stmt->execute($target_char_id, $item_id);
    my $existing_parcel = $check_stmt->fetch_hashref();
    $check_stmt->close();

    my $result;
    if (defined $existing_parcel) {
        # Update existing parcel by adding to the quantity
        my $existing_id = int($existing_parcel->{"id"});
        my $existing_qty = int($existing_parcel->{"quantity"});
        my $new_qty = $existing_qty + $quantity;
        #quest::debug("SendParcel: Updating existing parcel id=$existing_id, old_qty=$existing_qty, new_qty=$new_qty");

        my $update_stmt = $db->prepare("UPDATE character_parcels SET quantity = ? WHERE id = ? AND char_id = ?");
        $result = $update_stmt->execute($new_qty, $existing_id, $target_char_id);
        if ($result) {
            #quest::debug("SendParcel: UPDATE FAILED - " . $update_stmt->errstr);
        }
        $update_stmt->close();
        #quest::debug("SendParcel: Update result = " . (defined $result ? $result : "undef"));
    } else {
        # Insert new parcel with explicit ID and slot_id
       ##quest::debug("SendParcel: Inserting new parcel - id=$next_id, char_id=$target_char_id, slot_id=$next_slot_id, item_id=$item_id, quantity=$quantity");
        my $insert_stmt = $db->prepare("INSERT INTO character_parcels (id, char_id, slot_id, item_id, quantity) VALUES (?, ?, ?, ?, ?)");
        $result = $insert_stmt->execute($next_id, $target_char_id, $next_slot_id, $item_id, $quantity);
        if (!$result) {
            ##quest::debug("SendParcel: INSERT FAILED - " . $insert_stmt->errstr);
        }
        $insert_stmt->close();
        ##quest::debug("SendParcel: Insert result = " . (defined $result ? $result : "undef"));
    }
    $db->close();

    if (!$result) {
        # Remove the item from the sender's inventory
        $client->RemoveItem($item_id, $quantity);

        my $item_name = quest::getitemname($item_id);
        $client->Message(315, "Successfully sent $quantity x $item_name to $target_name!");
        return 1;
    } else {
        $client->Message(315, "Error: Failed to send parcel to $target_name.");
        return 0;
    }
}


# Plugin must return true value
1;
