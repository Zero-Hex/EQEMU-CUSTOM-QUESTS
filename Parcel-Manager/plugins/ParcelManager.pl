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
        my $reclaim_link = quest::saylink("RECLAIM_$unique_key", 0, "Reclaim");

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
        quest::debug("Error: Client context lost in RedeemParcel.");
        return;
    }

    my $char_id = $client->CharacterID();
    my $qglobal_key = "PARCELS_$char_id";

    quest::debug("RedeemParcel: char_id=$char_id, parcel_id=$parcel_id");

    # 1. INITIAL CHECK: Retrieve the current list of reclaimable items from the QGlobal
    my $qglobal_data = quest::get_data($qglobal_key);
    quest::debug("RedeemParcel: qglobal_data=" . (defined $qglobal_data ? $qglobal_data : "undef"));

    # Fix: Check if the parcel_id exists in the qglobal data (only if qglobal is set)
    if (defined $qglobal_data && $qglobal_data ne "" && $qglobal_data !~ /\b\Q$parcel_id\E\b/) {
        $client->Message(315, "That parcel has already been claimed or is invalid.");
        quest::debug("RedeemParcel: parcel_id not found in qglobal");
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
        quest::debug("Error: Client context lost in ReclaimAllParcels.");
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
        quest::debug("Error: Client context lost in SendParcel.");
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

    # Get the target character ID from the character name
    my $db = Database::new(Database::Content);
    my $char_stmt = $db->prepare("SELECT id FROM character_data WHERE name = ? LIMIT 1");
    $char_stmt->execute($target_name);
    my $char_row = $char_stmt->fetch_hashref();
    $char_stmt->close();

    if (!defined $char_row) {
        $client->Message(315, "Error: Character '$target_name' not found.");
        $db->close();
        return 0;
    }

    my $target_char_id = int($char_row->{"id"});

    # Optional: Set from_name if not provided
    if (!defined $from_name || $from_name eq "") {
        $from_name = $client->GetCleanName();
    }

    # Insert the parcel into the database
    # Note: If your table has a 'from_char_id' or 'sender_name' column, add it here
    my $insert_stmt = $db->prepare("INSERT INTO character_parcels (char_id, item_id, quantity) VALUES (?, ?, ?)");
    my $result = $insert_stmt->execute($target_char_id, $item_id, $quantity);
    $insert_stmt->close();
    $db->close();

    if ($result) {
        my $item_name = quest::getitemname($item_id);
        $client->Message(315, "Successfully sent $quantity x $item_name to $target_name!");
        return 1;
    } else {
        $client->Message(315, "Error: Failed to send parcel to $target_name.");
        return 0;
    }
}

# Alternative version that uses character ID directly instead of name
sub SendParcelByID {
    my ($target_char_id, $item_id, $quantity) = @_;

    # Validate inputs
    $target_char_id = int($target_char_id) if defined $target_char_id;
    $item_id = int($item_id) if defined $item_id;
    $quantity = int($quantity) if defined $quantity;

    my $client = plugin::val('$client');

    if (!defined $target_char_id || $target_char_id <= 0) {
        if (defined $client) {
            $client->Message(315, "Error: Invalid target character ID.");
        }
        return 0;
    }

    if (!defined $item_id || $item_id <= 0) {
        if (defined $client) {
            $client->Message(315, "Error: Invalid item ID.");
        }
        return 0;
    }

    if (!defined $quantity || $quantity <= 0) {
        if (defined $client) {
            $client->Message(315, "Error: Quantity must be greater than 0.");
        }
        return 0;
    }

    # Insert the parcel into the database
    my $db = Database::new(Database::Content);
    my $insert_stmt = $db->prepare("INSERT INTO character_parcels (char_id, item_id, quantity) VALUES (?, ?, ?)");
    my $result = $insert_stmt->execute($target_char_id, $item_id, $quantity);
    $insert_stmt->close();
    $db->close();

    if ($result) {
        if (defined $client) {
            my $item_name = quest::getitemname($item_id);
            $client->Message(315, "Successfully sent $quantity x $item_name!");
        }
        return 1;
    } else {
        if (defined $client) {
            $client->Message(315, "Error: Failed to send parcel.");
        }
        return 0;
    }
}

# Plugin must return true value
1;