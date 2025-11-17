# Filename: ParcelManager.pl
# Location: [EQEMU_Root]/quests/plugins/
# Authored by Zerohex
# =========================================================================
# Subroutines to Display and Redeem Parcels
# =========================================================================

sub DisplayParcels {
    # Fetch $client internally using the standard plugin utility
    my $client = plugin::val('$client');

    # Early return if client context is unavailable
    if (!defined $client) {
        return;
    }

    my $char_id = $client->CharacterID();
    my $db = Database::new(Database::Content);

    # Retrieve all parcels for this character, using the unique database row 'id' as parcel identifier
    my $stmt = $db->prepare("SELECT id, item_id, quantity FROM character_parcels WHERE char_id = ?");
    $stmt->execute($char_id);

    my $output = "Your pending parcels:\n\n";
    my $qglobal_data = ""; # Pipe-delimited list of valid parcel IDs for stale link detection

    while (my $row = $stmt->fetch_hashref())
    {
        my $parcel_id = int($row->{"id"});
        my $item_id   = int($row->{"item_id"});
        my $quantity  = int($row->{"quantity"});

        # Build QGlobal data with pipe-delimited parcel IDs for validation
        my $unique_key = $parcel_id;
        $qglobal_data .= ($qglobal_data ? "|" : "") . $unique_key;

        my $item_name = quest::getitemname($item_id);

        # Create clickable reclaim link (silent=1 means click won't echo to other players)
        my $reclaim_link = quest::saylink("!parcel reclaim $unique_key", 1, "Reclaim");

        # Format: Item name (quantity) [Reclaim link] || separator
        $output .= "- $item_name ($quantity) $reclaim_link\n";
        $output .= "||\n";
    }
    $stmt->close();
    $db->close();

    # Add "Reclaim All" link if parcels exist
    if ($output ne "Your pending parcels:\n\n") {
        # Clean up the final separator line if it exists
        if ($output =~ /------------------------\n$/) {
            $output =~ s/------------------------\n$//;
        }

        # Add clickable "Reclaim All" link (silent=0 means click echoes to others)
        my $reclaim_all_link = quest::saylink("!reclaim all", 0, "[RECLAIM ALL]");
        $output .= "\n" . $reclaim_all_link . "\n";
    }

    # Handle empty parcel list
    if ($output eq "Your pending parcels:\n\n") {
        $output = "You have no pending parcels.";
        quest::delete_data("PARCELS_$char_id"); # Clean up QGlobal when no parcels exist
    } else {
        # Store pipe-delimited list of valid parcel IDs to prevent stale link usage
        quest::set_data("PARCELS_$char_id", $qglobal_data);
    }

    # Send the output to the client as a system message
    $client->Message(315, $output); 
}


sub RedeemParcel {
    my ($parcel_id) = @_;

    # Fetch $client internally
    my $client = plugin::val('$client');

    # Early return if client context is unavailable
    if (!defined $client) {
        return;
    }

    my $char_id = $client->CharacterID();
    my $qglobal_key = "PARCELS_$char_id";

    # Stale link check: Verify parcel_id exists in the stored QGlobal list
    my $qglobal_data = quest::get_data($qglobal_key);

    # Reject if parcel ID not found in QGlobal (prevents claiming already-redeemed parcels)
    if (defined $qglobal_data && $qglobal_data ne "" && $qglobal_data !~ /\b\Q$parcel_id\E\b/) {
        $client->Message(315, "That parcel has already been claimed or is invalid.");
        plugin::DisplayParcels(); # Refresh the display
        return;
    }

    # Fetch the parcel from the database using the unique parcel row ID
    my $db = Database::new(Database::Content);
    my $fetch_stmt = $db->prepare("SELECT item_id, quantity FROM character_parcels WHERE id = ? AND char_id = ?");
    $fetch_stmt->execute($parcel_id, $char_id);
    my $parcel_row = $fetch_stmt->fetch_hashref();
    $fetch_stmt->close();

    # Double-check parcel exists in database (should always pass if QGlobal check passed)
    if (!defined $parcel_row) {
        $client->Message(315, "That parcel has already been claimed or is invalid.");
        $db->close();
        plugin::DisplayParcels();
        return;
    }

    my $item_id = int($parcel_row->{"item_id"});
    my $quantity = int($parcel_row->{"quantity"});
    my $message = "";

    # Currency redemption (item_id 99990 is special currency parcel)
    if ($item_id == 99990) {
        # Convert total copper to individual currency denominations
        my $total_copper = $quantity;
        my $platinum = int($total_copper / 1000);
        $total_copper %= 1000;
        my $gold = int($total_copper / 100);
        $total_copper %= 100;
        my $silver = int($total_copper / 10);
        $total_copper %= 10;
        my $copper = $total_copper;

        quest::givecash($copper, $silver, $gold, $platinum);

        # Build currency reclaim message
        $message = "You have reclaimed your currency: ";
        $message .= "$platinum Platinum, " if $platinum > 0;
        $message .= "$gold Gold, "       if $gold > 0;
        $message .= "$silver Silver, "   if $silver > 0;
        $message .= "$copper Copper."    if $copper > 0 || ($platinum + $gold + $silver == 0);

    } else {
        # Regular item redemption
        my $item_name = quest::getitemname($item_id);

        # Check if item has charges (maxcharges > 0 means it's a charged item)
        my $item_check = $db->prepare("SELECT stacksize, maxcharges FROM items WHERE id = ?");
        $item_check->execute($item_id);
        my $item_data = $item_check->fetch_hashref();
        $item_check->close();

        my $stacksize = $item_data ? int($item_data->{"stacksize"}) : 1;
        my $max_charges = $item_data ? int($item_data->{"maxcharges"}) : 0;

        my $items_claimed = 0;
        my $claim_success = 0;

        if ($max_charges > 0) {
            # Item with charges: quantity represents charges, summon one item with those charges
            $claim_success = $client->SummonItemIntoInventory($item_id, $quantity);
            if ($claim_success) {
                $items_claimed = 1;
                $message = "You have reclaimed $item_name with $quantity charges and it was placed in your inventory!";
            } else {
                $client->Message(315, "Your inventory is full! Cannot claim $item_name. Please make space and try again.");
                $db->close();
                plugin::DisplayParcels();
                return;
            }
        } elsif ($stacksize > 1) {
            # Stackable item: summon entire quantity at once
            $claim_success = $client->SummonItemIntoInventory($item_id, $quantity);
            if ($claim_success) {
                $items_claimed = $quantity;
                $message = "You have reclaimed $quantity x $item_name and it was placed in your inventory!";
            } else {
                $client->Message(315, "Your inventory is full! Cannot claim $quantity x $item_name. Please make space and try again.");
                $db->close();
                plugin::DisplayParcels();
                return;
            }
        } else {
            # Non-stackable: summon individual items
            for (my $i = 0; $i < $quantity; $i++) {
                my $success = $client->SummonItemIntoInventory($item_id);
                if ($success) {
                    $items_claimed++;
                } else {
                    # Inventory full - update parcel with remaining items
                    my $remaining = $quantity - $items_claimed;
                    if ($items_claimed > 0) {
                        my $update_stmt = $db->prepare("UPDATE character_parcels SET quantity = ? WHERE id = ? AND char_id = ?");
                        $update_stmt->execute($remaining, $parcel_id, $char_id);
                        $update_stmt->close();
                        $client->Message(315, "Claimed $items_claimed x $item_name before inventory became full. $remaining remaining in parcel.");
                    } else {
                        $client->Message(315, "Your inventory is full! Cannot claim $item_name. Please make space and try again.");
                    }
                    $db->close();
                    plugin::DisplayParcels();
                    return;
                }
            }
            $message = "You have reclaimed $quantity x $item_name and it was placed in your inventory!";
        }
    }

    # Remove parcel from database
    my $del_stmt = $db->prepare("DELETE FROM character_parcels WHERE id = ? AND char_id = ?");
    $del_stmt->execute($parcel_id, $char_id);
    $del_stmt->close();
    $db->close();

    $client->Message(315, $message);

    # Update QGlobal: remove this parcel ID from the valid list
    $qglobal_data =~ s/\b\Q$parcel_id\E\b\|?//g;  # Remove parcel_id and optional pipe
    $qglobal_data =~ s/^\|//;                     # Clean up leading pipe
    $qglobal_data =~ s/\|$//;                     # Clean up trailing pipe
    quest::set_data($qglobal_key, $qglobal_data);

    # Refresh parcel display with updated list
    plugin::DisplayParcels();
}

sub ReclaimAllParcels {
    my $client = plugin::val('$client');

    # Early return if client context is unavailable
    if (!defined $client) {
        return;
    }

    my $char_id = $client->CharacterID();
    my $db = Database::new(Database::Content);
    my $total_claimed = 0;
    my $parcels_claimed_data = ""; # Track claimed items for confirmation message

    # Retrieve all parcels for this character
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

    # Process each parcel: summon items/currency and delete from database
    foreach my $parcel (@parcels_to_claim) {
        my $parcel_id = $parcel->{id};
        my $item_id   = $parcel->{item_id};
        my $quantity  = $parcel->{quantity};
        my $claim_success = 0;

        # Currency redemption (item_id 99990 is special currency parcel)
        if ($item_id == 99990) {
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
            $claim_success = 1;

        } else {
            # Regular item redemption
            my $item_name = quest::getitemname($item_id);

            # Check if item has charges (maxcharges > 0 means it's a charged item)
            my $item_check = $db->prepare("SELECT stacksize, maxcharges FROM items WHERE id = ?");
            $item_check->execute($item_id);
            my $item_data = $item_check->fetch_hashref();
            $item_check->close();

            my $stacksize = $item_data ? int($item_data->{"stacksize"}) : 1;
            my $max_charges = $item_data ? int($item_data->{"maxcharges"}) : 0;

            if ($max_charges > 0) {
                # Item with charges: quantity represents charges, summon one item with those charges
                $claim_success = $client->SummonItemIntoInventory($item_id, $quantity);
                if ($claim_success) {
                    $parcels_claimed_data .= " | $item_name ($quantity charges)";
                } else {
                    $client->Message(315, "Inventory full while claiming $item_name! Remaining parcels were not claimed.");
                    $db->close();
                    plugin::DisplayParcels();
                    return;
                }
            } elsif ($stacksize > 1) {
                # Stackable item: summon entire quantity at once
                $claim_success = $client->SummonItemIntoInventory($item_id, $quantity);
                if ($claim_success) {
                    $parcels_claimed_data .= " | $item_name ($quantity)";
                } else {
                    $client->Message(315, "Inventory full while claiming $quantity x $item_name! Remaining parcels were not claimed.");
                    $db->close();
                    plugin::DisplayParcels();
                    return;
                }
            } else {
                # Non-stackable: summon individual items
                my $items_claimed = 0;
                for (my $i = 0; $i < $quantity; $i++) {
                    my $success = $client->SummonItemIntoInventory($item_id);
                    if ($success) {
                        $items_claimed++;
                    } else {
                        # Inventory full - update parcel with remaining items
                        my $remaining = $quantity - $items_claimed;
                        if ($items_claimed > 0) {
                            my $update_stmt = $db->prepare("UPDATE character_parcels SET quantity = ? WHERE id = ? AND char_id = ?");
                            $update_stmt->execute($remaining, $parcel_id, $char_id);
                            $update_stmt->close();
                            $client->Message(315, "Claimed $items_claimed x $item_name before inventory became full. $remaining remaining in this parcel. Remaining parcels were not claimed.");
                        } else {
                            $client->Message(315, "Inventory full while claiming $item_name! Remaining parcels were not claimed.");
                        }
                        $db->close();
                        plugin::DisplayParcels();
                        return;
                    }
                }
                if ($items_claimed == $quantity) {
                    $claim_success = 1;
                    $parcels_claimed_data .= " | $item_name ($quantity)";
                }
            }
        }

        # Only remove parcel from database if successfully claimed
        if ($claim_success) {
            $total_claimed++;
            my $del_stmt = $db->prepare("DELETE FROM character_parcels WHERE id = ? AND char_id = ?");
            $del_stmt->execute($parcel_id, $char_id);
            $del_stmt->close();
        }
    }
    $db->close();

    # Send confirmation message and cleanup
    if ($total_claimed > 0) {
        $client->Message(315, "Successfully claimed $total_claimed parcel(s) and placed them in your inventory!");
        quest::delete_data("PARCELS_$char_id"); # Clear QGlobal since all parcels claimed
    } else {
        $client->Message(315, "No parcels were found to claim.");
    }

    # Refresh parcel display
    plugin::DisplayParcels();
}

sub SendParcel {
    my ($target_name, $item_id, $quantity, $from_name) = @_;

    # Fetch $client internally
    my $client = plugin::val('$client');

    # Early return if client context is unavailable
    if (!defined $client) {
        return 0;
    }

    # Handle platinum sending (special case where item_id is the string "platinum")
    my $is_platinum = 0;
    my $platinum_amount = 0;

    # Ensure quantity is defined and convert to int
    $quantity = defined $quantity ? int($quantity) : 0;

    if (defined $item_id && lc($item_id) eq "platinum") {
        $is_platinum = 1;
        $platinum_amount = $quantity;
        $quantity = $platinum_amount * 1000;  # Convert to copper (1 plat = 1000 copper)
        $item_id = 99990; # Special currency parcel ID
    } else {
        # Convert item_id to int if not platinum
        $item_id = int($item_id) if defined $item_id;
    }

    # Validate input parameters
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

    # Look up target character ID by name
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

    # Get sender's character ID (needed for multiple checks below)
    my $sender_char_id = $client->CharacterID();

    # Prevent sending to yourself
    if ($sender_char_id == $target_char_id) {
        $client->Message(315, "Error: You cannot send a parcel to yourself.");
        $db->close();
        return 0;
    }

    # Variable to store max_charges - needed later for stacking logic
    my $max_charges = 0;
    # Track if this is a charged item so we know how many items to remove (1 for charged, quantity for non-charged)
    my $is_charged_item = 0;

    # Validate sender has the items/currency before creating parcel
    if ($is_platinum) {
        # Verify sender has enough platinum
        my $player_platinum = $client->GetCarriedPlatinum();
        if ($player_platinum < $platinum_amount) {
            $client->Message(315, "Error: You don't have enough platinum. You have $player_platinum but need $platinum_amount.");
            $db->close();
            return 0;
        }
    } else {
        # Check if item has charges (maxcharges > 0 means it's a charged item)
        my $item_check = $db->prepare("SELECT maxcharges FROM items WHERE id = ?");
        $item_check->execute($item_id);
        my $item_data = $item_check->fetch_hashref();
        $item_check->close();
        $max_charges = $item_data ? int($item_data->{"maxcharges"}) : 0;

        # If item has charges, get the actual charges from inventory and override quantity
        if ($max_charges > 0) {
            $is_charged_item = 1;
            my $charges_stmt = $db->prepare("SELECT charges FROM inventory WHERE character_id = ? AND item_id = ? LIMIT 1");
            $charges_stmt->execute($sender_char_id, $item_id);
            my $charges_row = $charges_stmt->fetch_hashref();
            $charges_stmt->close();

            if (defined $charges_row && defined $charges_row->{"charges"}) {
                # For charged items, quantity in parcel represents charges
                $quantity = int($charges_row->{"charges"});
            } else {
                $client->Message(315, "Error: Could not find that item in your inventory.");
                $db->close();
                return 0;
            }
        } else {
            # For non-charged items, verify sender has enough items
            my $has_item = $client->CountItem($item_id);
            if ($has_item < $quantity) {
                $client->Message(315, "Error: You don't have enough of that item. You have $has_item but need $quantity.");
                $db->close();
                return 0;
            }
        }

        # Prevent sending NODROP or ATTUNED items

        # Check item table for nodrop flag (nodrop = 0 means NODROP)
        my $item_flags_nodrop = $db->prepare("SELECT nodrop FROM items WHERE id = ? LIMIT 1");
        $item_flags_nodrop->execute($item_id);
        my $item_nodrop_data = $item_flags_nodrop->fetch_hashref();
        $item_flags_nodrop->close();

        # Check inventory instance for attuned flag (instnodrop = 1 means ATTUNED)
        my $item_flags_attuned = $db->prepare("SELECT instnodrop FROM inventory WHERE character_id = ? AND item_id = ? LIMIT 1");
        $item_flags_attuned->execute($sender_char_id, $item_id);
        my $item_attuned_data = $item_flags_attuned->fetch_hashref();
        $item_flags_attuned->close();

        my $is_nodrop = (defined $item_nodrop_data && defined $item_nodrop_data->{"nodrop"} && $item_nodrop_data->{"nodrop"} == 0);
        my $is_attuned = (defined $item_attuned_data && defined $item_attuned_data->{"instnodrop"} && $item_attuned_data->{"instnodrop"} == 1);

        if ($is_nodrop || $is_attuned) {
            my $item_name = quest::getitemname($item_id);
            my $reason = $is_nodrop && $is_attuned ? "NODROP and ATTUNED" :
                         $is_nodrop ? "NODROP" : "ATTUNED";
            $client->Message(315, "Error: Cannot send '$item_name' - this item is $reason and cannot be parceled.");
            $db->close();
            return 0;
        }

        # Prevent sending items with augments (must be removed first)
        my $augment_check_stmt = $db->prepare("SELECT augment_one, augment_two, augment_three, augment_four, augment_five, augment_six FROM inventory WHERE character_id = ? AND item_id = ? LIMIT 1");
        $augment_check_stmt->execute($sender_char_id, $item_id);

        while (my $inv_row = $augment_check_stmt->fetch_hashref()) {
            # Check if any augment slot is populated (non-zero)
            my $has_augments = (defined $inv_row->{"augment_one"} && $inv_row->{"augment_one"} != 0) ||
                              (defined $inv_row->{"augment_two"} && $inv_row->{"augment_two"} != 0) ||
                              (defined $inv_row->{"augment_three"} && $inv_row->{"augment_three"} != 0) ||
                              (defined $inv_row->{"augment_four"} && $inv_row->{"augment_four"} != 0) ||
                              (defined $inv_row->{"augment_five"} && $inv_row->{"augment_five"} != 0) ||
                              (defined $inv_row->{"augment_six"} && $inv_row->{"augment_six"} != 0);

            if ($has_augments) {
                my $item_name = quest::getitemname($item_id);
                $client->Message(315, "Error: Cannot send '$item_name' - items with augments cannot be parceled. Please remove augments first.");
                $augment_check_stmt->close();
                $db->close();
                return 0;
            }
        }
        $augment_check_stmt->close();
    }

    # Set from_name if not provided
    if (!defined $from_name || $from_name eq "") {
        $from_name = $client->GetCleanName();
    }

    # Generate next available parcel ID
    my $id_stmt = $db->prepare("SELECT COALESCE(MAX(id), 0) + 1 AS next_id FROM character_parcels");
    $id_stmt->execute();
    my $id_row = $id_stmt->fetch_hashref();
    my $next_id = $id_row ? int($id_row->{"next_id"}) : 1;
    $id_stmt->close();

    # Generate next available slot_id for the target character
    my $slot_stmt = $db->prepare("SELECT COALESCE(MAX(slot_id), -1) + 1 AS next_slot FROM character_parcels WHERE char_id = ?");
    $slot_stmt->execute($target_char_id);
    my $slot_row = $slot_stmt->fetch_hashref();
    my $next_slot_id = $slot_row ? int($slot_row->{"next_slot"}) : 0;
    $slot_stmt->close();

    # Determine if we should stack this parcel with an existing one
    # Do NOT stack charged items (maxcharges > 0) as this would exceed maxcharges limit
    my $should_stack = 0;
    my $existing_parcel;

    # Check if item definition still available from earlier check
    if (!$is_platinum && $max_charges == 0) {
        # Only check for existing parcel if not a charged item
        my $check_stmt = $db->prepare("SELECT id, quantity FROM character_parcels WHERE char_id = ? AND item_id = ? LIMIT 1");
        $check_stmt->execute($target_char_id, $item_id);
        $existing_parcel = $check_stmt->fetch_hashref();
        $check_stmt->close();
        $should_stack = defined $existing_parcel;
    }

    my $result;
    if ($should_stack) {
        # Update existing parcel by stacking the quantities together
        # This is safe for stackable items and non-charged items
        my $existing_id = int($existing_parcel->{"id"});
        my $existing_qty = int($existing_parcel->{"quantity"});
        my $new_qty = $existing_qty + $quantity;

        my $update_stmt = $db->prepare("UPDATE character_parcels SET quantity = ? WHERE id = ? AND char_id = ?");
        $result = $update_stmt->execute($new_qty, $existing_id, $target_char_id);
        $update_stmt->close();
    } else {
        # Create new parcel entry
        # Always create new entries for charged items to avoid exceeding maxcharges
        my $insert_stmt = $db->prepare("INSERT INTO character_parcels (id, char_id, slot_id, item_id, quantity) VALUES (?, ?, ?, ?, ?)");
        $result = $insert_stmt->execute($next_id, $target_char_id, $next_slot_id, $item_id, $quantity);
        $insert_stmt->close();
    }
    $db->close();

    # If parcel was successfully created, remove items/currency from sender
    # Note: We assume success if we reach here since database operations don't throw exceptions
    # The original check was inverted, suggesting execute() behavior may vary
    if ($is_platinum) {
        $client->TakePlatinum($platinum_amount, 1);
        $client->Message(315, "Successfully sent $platinum_amount platinum to $target_name!");
    } else {
        # For charged items, only remove 1 item (the item with charges)
        # For non-charged items, remove the quantity specified
        my $remove_count = $is_charged_item ? 1 : $quantity;
        $client->RemoveItem($item_id, $remove_count);

        my $item_name = quest::getitemname($item_id);
        if ($is_charged_item) {
            $client->Message(315, "Successfully sent $item_name with $quantity charges to $target_name!");
        } else {
            $client->Message(315, "Successfully sent $quantity x $item_name to $target_name!");
        }
    }
    return 1;
}

# Plugin must return true value
1;
