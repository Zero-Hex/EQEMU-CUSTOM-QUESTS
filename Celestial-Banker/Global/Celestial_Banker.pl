#!/usr/bin/perl
# =========================================================================
# CELESTIAL LIVE BANKER - Character-Based Banking System with Flags
# =========================================================================
# Features:
# - Character-based alliances (not account-based)
# - alliance_item flag (visible to alliance members)
# - account_item flag (visible to all your characters)
# - Items can have both flags (visible in both places)
# - Character-specific items (neither flag)
# - Augment and attunement support
# - Full alliance management (invite, kick, promote, restrict, transfer)
# =========================================================================

# =========================================================================
# CONFIGURATION
# =========================================================================

# Table names
my $TABLE_BANKER = "celestial_live_banker";
my $TABLE_ALLIANCE = "celestial_live_alliance";
my $TABLE_ALLIANCE_MEMBERS = "celestial_live_alliance_members";
my $TABLE_ALLIANCE_PENDING = "celestial_live_alliance_pending";

# Special item IDs
my $COIN_ITEM_ID = 99990;
my $COPPER_PER_PLATINUM = 1000;

# Permission levels
my $PERMISSION_OWNER = 1;
my $PERMISSION_OFFICER = 2;
my $PERMISSION_MEMBER = 3;

# =========================================================================
# ACCESS CONTROL CONFIGURATION
# =========================================================================
# Restrict banker access during testing phase
my @ALLOWED_ACCOUNTS = (192, 350, 228, 402, 309, 333, 508, 481, 420, 437    ); # Accounts that can use the NPC for testing/admin
my $MIN_GM_STATUS = 100;          # Minimum Admin() status to use the NPC

# To disable access control and open to all players, set this to 1
my $ACCESS_CONTROL_ENABLED = 1;   # 1 = enabled (restricted), 0 = disabled (open to all)

# =========================================================================
# HELPER FUNCTIONS
# =========================================================================

# =========================================================================
# CheckAccess - ACCESS CONTROL
# =========================================================================
sub CheckAccess {
    my $client = plugin::val('$client');
    
    # If access control is disabled, allow everyone
    return 1 unless $ACCESS_CONTROL_ENABLED;
    
    my $account_id = $client->AccountID();
    my $char_name = $client->GetCleanName();
    
    # Check 1: GM Status (Status 100 or higher is typically GM)
    if ($client->Admin() >= $MIN_GM_STATUS) {
        quest::debug("Banker Access: $char_name (Account: $account_id) granted via GM status (" . $client->Admin() . ")");
        return 1;
    }
    
    # Check 2: Specific Account IDs (Use grep to check if the account_id is in the array)
    if (grep { $_ == $account_id } @ALLOWED_ACCOUNTS) {
        quest::debug("Banker Access: $char_name (Account: $account_id) granted via allowed accounts list");
        return 1;
    }
    
    # If neither condition is met, deny access
    quest::debug("Banker Access: $char_name (Account: $account_id) DENIED - not authorized");
    return 0;
}

# =========================================================================
# GetAllianceID - Get alliance for current CHARACTER
# =========================================================================
sub GetAllianceID {
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    
    my $db = Database::new(Database::Content);
    
    my $query = $db->prepare("SELECT alliance_id FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ?");
    $query->execute($char_id);
    my $row = $query->fetch_hashref();
    $query->close();
    $db->close();
    
    return ($row && $row->{alliance_id}) ? $row->{alliance_id} : 0;
}

# =========================================================================
# CheckAlliancePermission - Check permission level for current CHARACTER
# =========================================================================
sub CheckAlliancePermission {
    my ($required_level) = @_;
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    return 0 unless $alliance_id > 0;
    
    my $db = Database::new(Database::Content);
    
    my $query = $db->prepare("SELECT permission_level FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $query->execute($char_id, $alliance_id);
    my $row = $query->fetch_hashref();
    $query->close();
    $db->close();
    
    return 0 unless $row;
    
    my $current_level = $row->{permission_level};
    
    # Owner (1) can do anything
    # Officer (2) can do Officer+ actions
    # Member (3) can do Member actions only
    return ($current_level <= $required_level) ? 1 : 0;
}

# =========================================================================
# GetCharacterName - Get character name by ID
# =========================================================================
sub GetCharacterName {
    my ($char_id) = @_;
    
    my $db = Database::new(Database::Content);
    my $query = $db->prepare("SELECT name FROM character_data WHERE id = ?");
    $query->execute($char_id);
    my $row = $query->fetch_hashref();
    $query->close();
    $db->close();
    
    return ($row && $row->{name}) ? $row->{name} : "Unknown";
}

# =========================================================================
# GetCharacterIDByName - Get character ID by name
# =========================================================================
sub GetCharacterIDByName {
    my ($char_name) = @_;
    
    my $db = Database::new(Database::Content);
    my $query = $db->prepare("SELECT id FROM character_data WHERE name = ?");
    $query->execute($char_name);
    my $row = $query->fetch_hashref();
    $query->close();
    $db->close();
    
    return ($row && $row->{id}) ? $row->{id} : 0;
}

# =========================================================================
# GetAccountIDByCharacter - Get account ID for a character
# =========================================================================
sub GetAccountIDByCharacter {
    my ($char_id) = @_;
    
    my $db = Database::new(Database::Content);
    my $query = $db->prepare("SELECT account_id FROM character_data WHERE id = ?");
    $query->execute($char_id);
    my $row = $query->fetch_hashref();
    $query->close();
    $db->close();
    
    return ($row && $row->{account_id}) ? $row->{account_id} : 0;
}

# =========================================================================
# DEPOSIT FUNCTIONS
# =========================================================================

# =========================================================================
# DepositItem - Character-based deposit with flags (NEW LOGIC)
# =========================================================================
sub DepositItem {
    my ($item_id, $deposit_quantity, $item_charges, $augments_ref, $item_inst) = @_;
    my $NPCName = "Banker";
    
    return unless $item_id && $deposit_quantity > 0;
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    my $alliance_id = GetAllianceID();
    
    # Default augments to all zeros if not provided
    my @augments = $augments_ref ? @{$augments_ref} : (0, 0, 0, 0, 0, 0);
    
    # Check if item has any augments
    my $has_augments = 0;
    foreach my $aug (@augments) {
        if ($aug > 0) {
            $has_augments = 1;
            last;
        }
    }
    
    # Check if item is attuned
    my $is_attuned = 0;
    if ($item_inst && $item_inst->IsAttuned()) {
        $is_attuned = 1;
    }
    
    my $db = Database::new(Database::Content);
    
    # --- 1. READ flags from main 'items' table ---
    my $flag_query = $db->prepare("SELECT heirloom, nodrop, maxcharges FROM items WHERE id = ?");
    $flag_query->execute($item_id);
    my $flags = $flag_query->fetch_hashref();
    $flag_query->close();
    
    my $is_heirloom = ($flags && $flags->{heirloom}) ? int($flags->{heirloom}) : 0;
    my $is_nodrop = ($flags && $flags->{nodrop}) ? int($flags->{nodrop}) : 0;
    my $max_charges = ($flags && $flags->{maxcharges}) ? int($flags->{maxcharges}) : 0;
    
    # Default charges to 0 if not provided or if item doesn't support charges
    $item_charges = 0 unless defined($item_charges);
    if ($max_charges == 0) {
        $item_charges = 0;
    }
=begin  
$client->Message(315, "--- DEPOSIT DEBUG ---");
    $client->Message(315, "HAS AUGMENTS: $has_augments");
    $client->Message(315, "IS ATTUNED: $is_attuned");
    $client->Message(315, "IS NO-DROP: $is_nodrop");
    $client->Message(315, "IS HEIRLOOM: $is_heirloom");
    $client->Message(315, "---------------------");
    # --- END DEBUG CODE ---
=cut
    # --- 2. DETERMINE FLAGS (New Rules) ---
    my $alliance_item = 0;
    my $account_item = 0;
    my $target_alliance_id = 0;
    my $restricted_id = 0; 
    
if ($has_augments || $is_attuned || ($is_nodrop == 0 && !$is_heirloom)) {
        # Rule: Character Specific (Attuned, Augmented, or No-Drop w/o Heirloom)
        $alliance_item = 0;
        $account_item = 0;
        $client->Message(315, "$NPCName whispers to you, 'Depositing $deposit_quantity character-specific items to your **Character Bank**.'");
    } else {
        # Rule: Account-Wide Default 
        # (Tradable/is_nodrop=1) OR (Heirloom No-Drop/is_nodrop=0 & is_heirloom=1)
        $alliance_item = 0;
        $account_item = 1;
        $client->Message(315, "$NPCName whispers to you, 'Depositing $deposit_quantity items to your **Account Bank** (accessible by all your characters).'");
    }


    my $check = $db->prepare("
        SELECT id, quantity FROM $TABLE_BANKER
        WHERE char_id = ? AND item_id = ? AND charges = ? AND attuned = ?
        AND alliance_id = ? AND alliance_item = ? AND account_item = ?
        AND restricted_to_character_id = ?
        AND augment_one = ? AND augment_two = ? AND augment_three = ? 
        AND augment_four = ? AND augment_five = ? AND augment_six = ?
    ");
    $check->execute($char_id, $item_id, $item_charges, $is_attuned, $target_alliance_id, $alliance_item, $account_item, $restricted_id, @augments);
    my $row = $check->fetch_hashref();
    $check->close();
    
    my $item_name = quest::getitemname($item_id);

    if ($row) {
        my $new_qty = $row->{quantity} + $deposit_quantity;
        my $update = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
        $update->execute($new_qty, $row->{id});
        $update->close();
    } else {
        my $insert = $db->prepare("
            INSERT INTO $TABLE_BANKER 
            (account_id, char_id, alliance_id, item_id, quantity, charges, attuned,
             alliance_item, account_item, restricted_to_character_id,
             augment_one, augment_two, augment_three, augment_four, augment_five, augment_six) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        
        $insert->execute(
            $account_id, $char_id, $target_alliance_id, $item_id, $deposit_quantity, 
            $item_charges, $is_attuned, $alliance_item, $account_item, $restricted_id, @augments
        );
        $insert->close();
    }
    
    $db->close();
    return 1;
}

sub DepositCurrency {
    my ($copper_amount, $share_type) = @_;
    my $NPCName = "Banker";
    
    return unless $copper_amount > 0;
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    my $alliance_id = GetAllianceID();
    
    # Default to account-wide for platinum
    $share_type = 'account' unless $share_type;
    
    # Convert copper to platinum
    my $platinum_to_deposit = int($copper_amount / 1000);
    my $leftover_copper = $copper_amount % 1000;
    
    unless ($platinum_to_deposit > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You need at least 1000 copper (10 gold) to deposit platinum.'");
        return;
    }
    
    # Validate share type: only 'alliance' or 'account' is allowed
    if ($share_type eq 'alliance' && !($alliance_id > 0)) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance to deposit to alliance platinum pool.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Determine flags based on share type
    my ($alliance_item, $account_item, $target_alliance_id, $restricted_id);
    
    if ($share_type eq 'alliance') {
        # Alliance pool
        $alliance_item = 1;
        $account_item = 0;
        $target_alliance_id = $alliance_id;
        $restricted_id = 0;  
    } else {
        # Account-wide pool (NEW DEFAULT)
        $alliance_item = 0;
        $account_item = 1;
        $target_alliance_id = 0;
        $restricted_id = 0;
    }
    
    # Check if platinum record exists with these exact flags
    my $check = $db->prepare("
        SELECT id, quantity FROM $TABLE_BANKER 
        WHERE char_id = ? 
        AND item_id = $COIN_ITEM_ID
        AND alliance_id = ?
        AND alliance_item = ?
        AND account_item = ?
        AND restricted_to_character_id = ?
    ");
    $check->execute($char_id, $target_alliance_id, $alliance_item, $account_item, $restricted_id);
    my $row = $check->fetch_hashref();
    $check->close();
    
    if ($row) {
        # Update existing
        my $new_qty = $row->{quantity} + $platinum_to_deposit;
        my $update = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
        $update->execute($new_qty, $row->{id});
        $update->close();
    } else {
        # Insert new
        my $insert = $db->prepare("
            INSERT INTO $TABLE_BANKER 
            (account_id, char_id, alliance_id, item_id, quantity, charges, attuned, alliance_item, account_item, restricted_to_character_id,
             augment_one, augment_two, augment_three, augment_four, augment_five, augment_six)
            VALUES (?, ?, ?, $COIN_ITEM_ID, ?, 0, 0, ?, ?, ?, 0, 0, 0, 0, 0, 0)
        ");
        $insert->execute($account_id, $char_id, $target_alliance_id, $platinum_to_deposit, $alliance_item, $account_item, $restricted_id);
        $insert->close();
    }
    
    $db->close();
    
    my $pool_msg = ($share_type eq 'alliance') ? 'alliance platinum pool' : 'account-wide platinum pool';
    
    $client->Message(315, "$NPCName whispers to you, 'Deposited $platinum_to_deposit platinum to $pool_msg.'");
    
    # Return leftover copper as change
    if ($leftover_copper > 0) {
        my $return_gold = int($leftover_copper / 100);
        my $return_silver = int(($leftover_copper % 100) / 10);
        my $return_copper = $leftover_copper % 10;
        
        $client->AddMoneyToPP($return_copper, $return_silver, $return_gold, 0, 1);
        $client->Message(315, "$NPCName whispers to you, 'Returned change: ${return_gold}g ${return_silver}s ${return_copper}c'");
    }
}

# =========================================================================
# ALLIANCE MANAGEMENT FUNCTIONS
# =========================================================================

# Create, Join, Leave Alliance functions
sub CreateAlliance {
    my ($alliance_name) = @_;
    my $NPCName = "Banker";
    
    unless ($alliance_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance create <AllianceName>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $char_name = $client->GetCleanName();
    my $account_id = $client->AccountID();
    
    my $db = Database::new(Database::Content);
    
    # Check if character already owns an alliance
    my $owner_check = $db->prepare("SELECT id, name FROM $TABLE_ALLIANCE WHERE owner_character_id = ?");
    $owner_check->execute($char_id);
    my $existing = $owner_check->fetch_hashref();
    $owner_check->close();
    
    if ($existing) {
        $client->Message(315, "$NPCName whispers to you, 'You already own alliance: $existing->{name}'");
        $db->close();
        return;
    }
    
    # Check if alliance name already exists
    my $name_check = $db->prepare("SELECT id FROM $TABLE_ALLIANCE WHERE name = ?");
    $name_check->execute($alliance_name);
    my $name_exists = $name_check->fetch_hashref();
    $name_check->close();
    
    if ($name_exists) {
        $client->Message(315, "$NPCName whispers to you, 'Alliance name '$alliance_name' is already taken.'");
        $db->close();
        return;
    }
    
    # Create the alliance
    my $insert = $db->prepare("INSERT INTO $TABLE_ALLIANCE (name, owner_character_id, owner_account_id) VALUES (?, ?, ?)");
    $insert->execute($alliance_name, $char_id, $account_id);
    $insert->close();
    
    $db->close();
    
    $client->Message(315, "$NPCName whispers to you, 'Alliance **$alliance_name** created successfully!'");
    $client->Message(315, "$NPCName whispers to you, 'Use [alliance join $alliance_name] to join as Owner.'");
}

sub JoinAlliance {
    my ($alliance_name) = @_;
    my $NPCName = "Banker";
    
    unless ($alliance_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance join <AllianceName>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $char_name = $client->GetCleanName();
    my $account_id = $client->AccountID();
    my $account_name = $client->AccountName();
    
    # Check if already in an alliance
    if (GetAllianceID() > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are already in an alliance. Leave it first with [alliance leave].'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Find the alliance
    my $find_alliance = $db->prepare("SELECT id, owner_character_id FROM $TABLE_ALLIANCE WHERE name = ?");
    $find_alliance->execute($alliance_name);
    my $alliance_row = $find_alliance->fetch_hashref();
    $find_alliance->close();
    
    unless ($alliance_row) {
        $client->Message(315, "$NPCName whispers to you, 'Alliance '$alliance_name' not found.'");
        $db->close();
        return;
    }
    
    my $alliance_id = $alliance_row->{id};
    my $owner_char_id = $alliance_row->{owner_character_id};
    
    # Determine permission level
    my $permission_level = $PERMISSION_MEMBER;
    
    if ($char_id == $owner_char_id) {
        # Owner joining their own alliance
        $permission_level = $PERMISSION_OWNER;
    } else {
        # Check for invitation
        my $check_invite = $db->prepare("SELECT id FROM $TABLE_ALLIANCE_PENDING WHERE alliance_id = ? AND character_id = ?");
        $check_invite->execute($alliance_id, $char_id);
        my $invite_row = $check_invite->fetch_hashref();
        $check_invite->close();
        
        unless ($invite_row) {
            $client->Message(315, "$NPCName whispers to you, 'You have not been invited to this alliance.'");
            $db->close();
            return;
        }
        
        # Remove the pending invite
        my $delete_invite = $db->prepare("DELETE FROM $TABLE_ALLIANCE_PENDING WHERE id = ?");
        $delete_invite->execute($invite_row->{id});
        $delete_invite->close();
    }
    
    # Add to alliance members
    my $insert_member = $db->prepare("
        INSERT INTO $TABLE_ALLIANCE_MEMBERS 
        (alliance_id, character_id, character_name, account_id, account_name, permission_level) 
        VALUES (?, ?, ?, ?, ?, ?)
    ");
    $insert_member->execute($alliance_id, $char_id, $char_name, $account_id, $account_name, $permission_level);
    $insert_member->close();
    
        # Auto-restrict all character's items that were flagged for alliance
    # FIX: Count items manually instead of using rows()
    my $count_items = $db->prepare("
        SELECT COUNT(*) as item_count
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND alliance_item = 1
        AND alliance_id = 0
    ");
    $count_items->execute($char_id);
    my $count_row = $count_items->fetch_hashref();
    $count_items->close();
    my $restricted_count = ($count_row && $count_row->{item_count}) ? $count_row->{item_count} : 0;
    
    # Now do the actual update
    if ($restricted_count > 0) {
        my $restrict_items = $db->prepare("
            UPDATE $TABLE_BANKER
            SET restricted_to_character_id = ?,
                alliance_id = ?
            WHERE char_id = ?
            AND alliance_item = 1
            AND alliance_id = 0
        ");
        $restrict_items->execute($char_id, $alliance_id, $char_id);
        $restrict_items->close();
    }
    
    $db->close();
    
    my $rank_name = ($permission_level == $PERMISSION_OWNER) ? "Owner" : 
                    ($permission_level == $PERMISSION_OFFICER) ? "Officer" : "Member";
    
    $client->Message(315, "$NPCName whispers to you, 'Successfully joined alliance **$alliance_name** as $rank_name!'");
    
    if ($restricted_count > 0) {
        $client->Message(315, "$NPCName whispers to you, '$restricted_count item stack(s) flagged for alliance sharing are now in the alliance bank (restricted to you by default).'");
        $client->Message(315, "$NPCName whispers to you, 'Use [alliance unrestrict] or click [U:All] to share with other members.'");
    }
    
    $client->Message(315, "$NPCName whispers to you, 'Use [balance] to view your items.'");
}

sub LeaveAlliance {
    my $NPCName = "Banker";
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Check if owner
    my $check_permission = $db->prepare("SELECT permission_level FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $check_permission->execute($char_id, $alliance_id);
    my $permission_row = $check_permission->fetch_hashref();
    $check_permission->close();
    
    if ($permission_row && $permission_row->{permission_level} == $PERMISSION_OWNER) {
        $client->Message(315, "$NPCName whispers to you, 'As owner, you must either transfer ownership or disband the alliance before leaving.'");
        $client->Message(315, "$NPCName whispers to you, 'Use [alliance transfer <CharacterName>] or [alliance disband].'");
        $db->close();
        return;
    }
    
    # Remove from alliance
    my $delete_member = $db->prepare("DELETE FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $delete_member->execute($char_id, $alliance_id);
    $delete_member->close();
    
    # Count total items AND platinum that will be moved
    my $count_query = $db->prepare("
        SELECT COUNT(*) as item_count
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND alliance_id = ?
    ");
    $count_query->execute($char_id, $alliance_id);
    my $count_row = $count_query->fetch_hashref();
    $count_query->close();
    my $total_stacks = ($count_row && $count_row->{item_count}) ? $count_row->{item_count} : 0;

    # Get platinum amount BEFORE moving (for display message)
    my $plat_query = $db->prepare("
        SELECT SUM(quantity) as total_plat
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND alliance_id = ?
        AND item_id = $COIN_ITEM_ID
    ");
    $plat_query->execute($char_id, $alliance_id);
    my $plat_row = $plat_query->fetch_hashref();
    $plat_query->close();
    my $platinum_returned = ($plat_row && $plat_row->{total_plat}) ? $plat_row->{total_plat} : 0;

    # Move ALL alliance items back to character-only (INCLUDING PLATINUM!)
    if ($total_stacks > 0) {
        my $move_items = $db->prepare("
            UPDATE $TABLE_BANKER 
            SET alliance_item = 0, 
                alliance_id = 0, 
                restricted_to_character_id = 0
            WHERE char_id = ? 
            AND alliance_id = ?
        ");
        $move_items->execute($char_id, $alliance_id);
        $move_items->close();
    }

    $db->close();
    
    $client->Message(315, "$NPCName whispers to you, 'You have left the alliance.'");
    
    # Display separate messages for items and platinum
    if ($total_stacks > 0) {
        my $item_count = $total_stacks - ($platinum_returned > 0 ? 1 : 0);
        
        if ($item_count > 0) {
            $client->Message(315, "$NPCName whispers to you, 'Your $item_count item stack(s) have been moved back to your character bank.'");
        }
        
        if ($platinum_returned > 0) {
            $client->Message(315, "$NPCName whispers to you, 'Your $platinum_returned alliance platinum has been returned to your character bank.'");
        }
    }
}

# =========================================================================
# WITHDRAW FUNCTIONS
# =========================================================================
sub WithdrawItem {
    my ($item_id, $requested_quantity, $requested_charges, $augment_signature) = @_;
    
    my $NPCName = "Banker";
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    my $alliance_id = GetAllianceID();
    
    my $db = Database::new(Database::Content);
    
    # 1. DETERMINE TARGET CHARGES & FILTER
    my $target_charges = defined($requested_charges) ? $requested_charges : 0;
    my $charge_filter_sql = "AND charges = ?";
    
    # 2. SANITIZE AND DEFAULT QUANTITY
    if ($requested_quantity == 0 || $requested_quantity eq '') {
        $requested_quantity = 99999;
    }
    
    # 3. Parse augment signature if provided (format: "aug1-aug2-aug3-aug4-aug5-aug6")
    my @target_augments = (0, 0, 0, 0, 0, 0);
    my $has_augment_filter = 0;
    
    if ($augment_signature && $augment_signature ne '0-0-0-0-0-0') {
        @target_augments = split('-', $augment_signature);
        $has_augment_filter = 1;
        
        # Verify we have exactly 6 augment values
        while (scalar(@target_augments) < 6) {
            push @target_augments, 0;
        }
    }
    
    # 4. Build augment filter SQL
    my $augment_filter_sql = "";
    if ($has_augment_filter) {
        $augment_filter_sql = "
            AND augment_one = ? AND augment_two = ? AND augment_three = ?
            AND augment_four = ? AND augment_five = ? AND augment_six = ?
        ";
    }
    
    # 5. FIND STORED QUANTITY - CHARACTER, ACCOUNT, AND ALLIANCE ITEMS
    my $find_items_sql = "
        SELECT id, quantity, charges, attuned, char_id, alliance_item, account_item,
               augment_one, augment_two, augment_three, augment_four, augment_five, augment_six
        FROM $TABLE_BANKER
        WHERE item_id = ? $charge_filter_sql $augment_filter_sql
        AND (
            -- Character's personal items (not shared)
            (char_id = ? AND alliance_item = 0 AND account_item = 0)
            -- OR Account-wide items (from any of this account's characters)
            OR (account_id = ? AND account_item = 1)
            -- OR Alliance shared items (not restricted)
            OR (alliance_id = ? AND alliance_item = 1 AND restricted_to_character_id = 0)
            -- OR Alliance items restricted to this character
            OR (alliance_id = ? AND alliance_item = 1 AND restricted_to_character_id = ?)
        )
        ORDER BY account_item DESC, alliance_item DESC, id ASC
    ";
    
    my $q_find = $db->prepare($find_items_sql);
    
    # Build parameter list
    my @params = ($item_id, $target_charges);
    
    # Add augment parameters if filtering
    if ($has_augment_filter) {
        push @params, @target_augments;
    }
    
    # Add access control parameters
    push @params, ($char_id, $account_id, $alliance_id, $alliance_id, $char_id);
    
    $q_find->execute(@params);
    
    my @item_stacks;
    my $total_quantity = 0;
    
    while (my $row = $q_find->fetch_hashref()) {
        push @item_stacks, {
            id => $row->{id},
            quantity => $row->{quantity},
            charges => $row->{charges} || 0,
            attuned => $row->{attuned} || 0,
            char_id => $row->{char_id},
            alliance_item => $row->{alliance_item},
            account_item => $row->{account_item},
            augments => [
                $row->{augment_one} || 0,
                $row->{augment_two} || 0,
                $row->{augment_three} || 0,
                $row->{augment_four} || 0,
                $row->{augment_five} || 0,
                $row->{augment_six} || 0
            ]
        };
        $total_quantity += $row->{quantity};
    }
    $q_find->close();

    unless ($total_quantity > 0) {
        my $charge_msg = ($target_charges > 0) ? " with $target_charges charges" : "";
        my $aug_msg = $has_augment_filter ? " with specific augments" : "";
        $client->Message(315, "$NPCName whispers to you, 'You don't have this item$charge_msg$aug_msg in accessible storage.'");
        $db->close();
        return;
    }

    if ($requested_quantity > $total_quantity) {
        $requested_quantity = $total_quantity;
    }
    
    # --- Item Lookup ---
    my $item_check = $db->prepare("SELECT stacksize, maxcharges FROM items WHERE id = ?"); 
    $item_check->execute($item_id);
    my $item_data = $item_check->fetch_hashref();
    $item_check->close();
    
    my $stacksize = ($item_data && $item_data->{stacksize}) ? $item_data->{stacksize} : 1;
    my $max_charges = ($item_data && $item_data->{maxcharges}) ? $item_data->{maxcharges} : 0;
    
    # --- Give Items to Player with Augments AND Attunement ---
    my $remaining_to_withdraw = $requested_quantity;
    
    foreach my $stack (@item_stacks) {
        last if $remaining_to_withdraw <= 0;
        
        my $from_this_stack = ($stack->{quantity} <= $remaining_to_withdraw) ? $stack->{quantity} : $remaining_to_withdraw;
        my $stored_charges = $stack->{charges};
        my $is_attuned = $stack->{attuned};
        my @augments = @{$stack->{augments}};
        
        # Check if this item has any augments
        my $has_augments = 0;
        foreach my $aug (@augments) {
            if ($aug > 0) {
                $has_augments = 1;
                last;
            }
        }
        
        # Give items based on type
        if ($stacksize > 1) {
            # Stackable items - no augments or attunement possible
            quest::summonitem($item_id, $from_this_stack);
        } else {
            # Non-stackable items (charged or not) - give one at a time
            for (my $i = 0; $i < $from_this_stack; $i++) {
                if ($has_augments || $is_attuned) {
                    # Use SummonItemIntoInventory with a hash reference for augments/attunement
                    my $charges_to_use = ($stored_charges > 0 && $max_charges > 0) ? $stored_charges : 0;
                    
                    my %item_data = (
                        item_id => $item_id,
                        charges => $charges_to_use,
                        attuned => $is_attuned,
                        augment_one => $augments[0],
                        augment_two => $augments[1],
                        augment_three => $augments[2],
                        augment_four => $augments[3],
                        augment_five => $augments[4],
                        augment_six => $augments[5]
                    );
                    
                    $client->SummonItemIntoInventory(\%item_data);
                    
                } else {
                    # No augments or attunement - use regular summon
                    if ($stored_charges > 0 && $max_charges > 0) {
                        quest::summonitem($item_id, $stored_charges);
                    } else {
                        quest::summonitem($item_id);
                    }
                }
            }
        }
        
        $remaining_to_withdraw -= $from_this_stack;
    }
    
    # --- Database Deletion/Update Logic ---
    my $remaining_to_remove = $requested_quantity;
    
    my $delete_stmt = $db->prepare("DELETE FROM $TABLE_BANKER WHERE id = ?");
    my $update_stmt = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
    
    foreach my $stack (@item_stacks) {
        last if $remaining_to_remove <= 0;
        
        my $row_id = $stack->{id};
        my $row_qty = $stack->{quantity};
        
        if ($remaining_to_remove >= $row_qty) {
            $delete_stmt->execute($row_id);
            $remaining_to_remove -= $row_qty;
        } else {
            my $new_qty = $row_qty - $remaining_to_remove;
            $update_stmt->execute($new_qty, $row_id);
            $remaining_to_remove = 0;
        }
    }
    
    $delete_stmt->close();
    $update_stmt->close();
    
    my $item_name = quest::getitemname($item_id);
    my $charge_msg = ($target_charges > 0) ? " ($target_charges charges each)" : "";
    
    # Determine source for message
    my $source_msg = "from your Character Bank";
    if ($item_stacks[0]->{account_item}) {
        $source_msg = "from your Account Bank";
    } elsif ($item_stacks[0]->{alliance_item}) {
        $source_msg = "from your Alliance Bank";
    }
    
    $db->close();
    my $new_remaining = $total_quantity - $requested_quantity;
    $client->Message(315, "$NPCName whispers to you, 'Withdrew $requested_quantity of $item_name$charge_msg $source_msg. (Remaining: $new_remaining)'");
}
# =========================================================================
# WithdrawCurrency - Withdraw platinum (from accessible pools)
# =========================================================================
sub WithdrawCurrency {
    my ($amount) = @_;
    my $NPCName = "Banker";
    
    unless ($amount && $amount > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: withdraw platinum <amount>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    my $alliance_id = GetAllianceID();
    
    my $db = Database::new(Database::Content);
    
    # Get accessible platinum from all pools (character, account, alliance)
    my $sql = "
        SELECT id, quantity, alliance_item, account_item, alliance_id
        FROM $TABLE_BANKER 
        WHERE item_id = $COIN_ITEM_ID
        AND (
            (char_id = ? AND alliance_item = 0 AND account_item = 0)
            OR (account_id = ? AND account_item = 1)
            OR (alliance_id = ? AND alliance_item = 1 AND restricted_to_character_id = 0)
        )
        ORDER BY account_item DESC, alliance_item DESC, id ASC
    ";
    
    my $query = $db->prepare($sql);
    $query->execute($char_id, $account_id, $alliance_id);
    
    my @platinum_pools;
    my $total_available = 0;
    
    while (my $row = $query->fetch_hashref()) {
        push @platinum_pools, {
            id => $row->{id},
            quantity => $row->{quantity},
            alliance_item => $row->{alliance_item},
            account_item => $row->{account_item},
            alliance_id => $row->{alliance_id}
        };
        $total_available += $row->{quantity};
    }
    $query->close();
    
    unless ($total_available >= $amount) {
        $client->Message(315, "$NPCName whispers to you, 'You do not have enough platinum in accessible storage. (Available: $total_available)'");
        $db->close();
        return;
    }
    
    # Withdraw from pools (prioritize account, then alliance, then character)
    my $remaining_to_withdraw = $amount;
    
    foreach my $pool (@platinum_pools) {
        last if $remaining_to_withdraw <= 0;
        
        my $from_this_pool = ($pool->{quantity} <= $remaining_to_withdraw) ? $pool->{quantity} : $remaining_to_withdraw;
        my $new_qty = $pool->{quantity} - $from_this_pool;
        
        if ($new_qty > 0) {
            my $update = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
            $update->execute($new_qty, $pool->{id});
            $update->close();
        } else {
            my $delete = $db->prepare("DELETE FROM $TABLE_BANKER WHERE id = ?");
            $delete->execute($pool->{id});
            $delete->close();
        }
        
        $remaining_to_withdraw -= $from_this_pool;
    }
    
    $db->close();
    
    # Give platinum to player
    $client->AddMoneyToPP(0, 0, 0, $amount, 1);
    
    my $new_total = $total_available - $amount;
    $client->Message(315, "$NPCName whispers to you, 'Withdrew $amount platinum. (Remaining accessible: $new_total)'");
}

# =========================================================================
# SHOW BALANCE
# =========================================================================
# =========================================================================
# HELPER FUNCTION - Generate Withdraw Links with Augment Support
# =========================================================================
sub GenerateWithdrawLinks {
    my ($item_id, $charges, $quantity, $stacksize, $augments_ref) = @_;
    
    my @augments = $augments_ref ? @{$augments_ref} : (0, 0, 0, 0, 0, 0);
    my $aug_sig = join('-', @augments);
    my $has_augs = ($aug_sig ne '0-0-0-0-0-0') ? 1 : 0;
    
    my %links;
    
    # W:1 link (SILENT)
    if ($has_augs) {
        $links{w1} = quest::saylink("withdraw $item_id 1 $charges $aug_sig", 1, "W:1");
    } elsif ($charges > 0) {
        $links{w1} = quest::saylink("withdraw $item_id 1 $charges", 1, "W:1");
    } else {
        $links{w1} = quest::saylink("withdraw $item_id 1", 1, "W:1");
    }
    
    # W:All link (SILENT)
    if ($has_augs) {
        $links{wall} = quest::saylink("withdraw $item_id 0 $charges $aug_sig", 1, "W:All");
    } elsif ($charges > 0) {
        $links{wall} = quest::saylink("withdraw $item_id $charges", 1, "W:All");
    } else {
        $links{wall} = quest::saylink("withdraw $item_id", 1, "W:All");
    }
    
    # W:Stack link (for stackable items) (SILENT)
    $links{wstack} = "";
    if ($stacksize > 1 && $quantity >= $stacksize) {
        if ($has_augs) {
            $links{wstack} = " " . quest::saylink("withdraw $item_id $stacksize $charges $aug_sig", 1, "(W:Stack)");
        } elsif ($charges > 0) {
            $links{wstack} = " " . quest::saylink("withdraw $item_id $charges $stacksize", 1, "(W:Stack)");
        } else {
            $links{wstack} = " " . quest::saylink("withdraw $item_id $stacksize", 1, "(W:Stack)");
        }
    }
    
    return %links;
}

# =========================================================================
# SHOW BALANCE - UPDATED WITH AUGMENT SIGNATURE SUPPORT
# =========================================================================
sub ShowBalance {
    # 1. Update: Accept an optional filter argument
    my ($filter) = @_; 
    $filter = ($filter) || 'all'; # Default to 'all' if no filter is provided
    
    my $NPCName = "Banker";
    
    # Global Variable Lookups (Assumed to be defined in surrounding code)
    my $COIN_ITEM_ID = plugin::val('$COIN_ITEM_ID') || 99990;
    my $TABLE_BANKER = plugin::val('$TABLE_BANKER') || "celestial_live_banker";
    my $TABLE_ALLIANCE_MEMBERS = plugin::val('$TABLE_ALLIANCE_MEMBERS') || "celestial_live_alliance_members";

    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    
    # Retrieves the alliance ID using the existing helper function
    my $alliance_id = GetAllianceID(); 
    
    my $db = Database::new(Database::Content);
    
    # --- ALLIANCE OWNER SETUP ---
    # Define the owner permission level (as per CONFIGURATION section)
    my $PERMISSION_OWNER = 1; 
    my $is_owner = 0;

    # Check for Alliance Owner status using a direct DB query
    if ($alliance_id > 0) {
        my $rank_query = $db->prepare("
            SELECT permission_level 
            FROM $TABLE_ALLIANCE_MEMBERS 
            WHERE alliance_id = ? 
            AND character_id = ?
        ");
        $rank_query->execute($alliance_id, $char_id);
        my $member_row = $rank_query->fetch_hashref();
        $rank_query->close();

        if ($member_row->{permission_level} eq $PERMISSION_OWNER) {
            $is_owner = 1;
        }
    }
    # --- END OF ALLIANCE OWNER SETUP ---

    # Query for all accessible items
    my $sql = "
        SELECT
            sb.id, sb.item_id, sb.quantity, sb.charges, sb.attuned, sb.char_id,
            sb.alliance_id, sb.alliance_item, sb.account_item, sb.restricted_to_character_id,
            sb.augment_one, sb.augment_two, sb.augment_three, sb.augment_four, sb.augment_five, sb.augment_six,
            i.name, i.stacksize,
            cd.name as owner_character_name
        FROM $TABLE_BANKER sb
        LEFT JOIN items i ON sb.item_id = i.id
        LEFT JOIN character_data cd ON sb.char_id = cd.id
        WHERE sb.item_id != $COIN_ITEM_ID
        AND (
            -- Character's personal items
            (sb.char_id = ? AND sb.alliance_item = 0 AND sb.account_item = 0)
            -- OR Account-wide items
            OR (sb.account_id = ? AND sb.account_item = 1)
            -- OR Alliance items accessible to you OR owner override
            OR (
                sb.alliance_id = ? AND sb.alliance_item = 1
                AND (
                    sb.restricted_to_character_id = 0
                    OR sb.restricted_to_character_id = ?
                    OR ? = 1 -- OWNER OVERRIDE: Show restricted items if owner
                )
            )
        )
        ORDER BY sb.account_item DESC, sb.alliance_item DESC, sb.restricted_to_character_id DESC, i.name ASC
    ";
    
    my $query = $db->prepare($sql);
    # Parameters: (1: char_id), (2: account_id), (3: alliance_id), (4: char_id), (5: is_owner)
    $query->execute($char_id, $account_id, $alliance_id, $char_id, $is_owner);
    
    # Categorize items
    my %alliance_shared;
    my %alliance_shared_charged;
    my %alliance_restricted; # Restricted to THIS character
    my %alliance_restricted_charged; # Restricted to THIS character
    my %alliance_restricted_others; # Restricted to ANOTHER character (Owner view)
    my %alliance_restricted_others_charged; # Restricted to ANOTHER character (Owner view)
    my %account_wide;
    my %account_wide_charged;
    my %character_only;
    my %character_only_charged;
    
    while (my $row = $query->fetch_hashref()) {
        my $item_id = $row->{item_id};
        my $charges = $row->{charges} || 0;
        my $item_name = $row->{name} || "Unknown Item (ID $item_id)";
        
        # Collect augment data (assuming external functions handle this)
        my @augments = (
            $row->{augment_one} || 0,
            $row->{augment_two} || 0,
            $row->{augment_three} || 0,
            $row->{augment_four} || 0,
            $row->{augment_five} || 0,
            $row->{augment_six} || 0
        );
        
        my $has_augments = 0;
        foreach my $aug (@augments) {
            if ($aug > 0) { $has_augments = 1; last; }
        }
        
        my $augment_display = "";
        if ($has_augments) {
            my @aug_names;
            for (my $i = 0; $i < 6; $i++) {
                if ($augments[$i] > 0) {
                    my $aug_name = quest::getitemname($augments[$i]);
                    push @aug_names, $aug_name;
                }
            }
            $augment_display = " [Aug: " . join(", ", @aug_names) . "]";
        }
        
        my $attuned_display = ($row->{attuned}) ? " [ATTUNED]" : "";
        my $owner_display = "";
        if ($row->{owner_character_name} && $row->{char_id} != $char_id) {
            $owner_display = " [From: $row->{owner_character_name}]";
        }
        
        # Create unique key
        my $aug_string = join("-", @augments);
        my $unique_key = $charges > 0 ? "${item_id}_C${charges}_A${aug_string}" : "${item_id}_A${aug_string}";
        
        my $stacksize = $row->{stacksize} || 1;
        
        my $item_entry = {
            id => $item_id,
            qty => $row->{quantity},
            name => $item_name,
            charges => $charges,
            stacksize => $stacksize,
            augment_display => $augment_display,
            attuned_display => $attuned_display,
            owner_display => $owner_display,
            has_augments => $has_augments,
            is_attuned => ($row->{attuned}) ? 1 : 0,
            augments => \@augments  # Store augments for withdraw links
        };
        
        # Categorize based on flags
        if ($row->{alliance_item} && $row->{restricted_to_character_id} > 0 && $row->{restricted_to_character_id} == $char_id) {
            # Alliance restricted TO THIS character
            if ($charges > 0) {
                if (exists $alliance_restricted_charged{$unique_key}) {
                    $alliance_restricted_charged{$unique_key}->{qty} += $row->{quantity};
                } else {
                    $alliance_restricted_charged{$unique_key} = $item_entry;
                }
            } else {
                if (exists $alliance_restricted{$unique_key}) {
                    $alliance_restricted{$unique_key}->{qty} += $row->{quantity};
                } else {
                    $alliance_restricted{$unique_key} = $item_entry;
                }
            }
        }
        # Alliance Restricted TO OTHERS (Owner View)
        elsif ($row->{alliance_item} && $row->{restricted_to_character_id} > 0 && $row->{restricted_to_character_id} != $char_id) {
            # Alliance restricted TO ANOTHER character (Only fetched if $is_owner = 1 in SQL)
            if ($is_owner) {
                my $restricted_char_id = $row->{restricted_to_character_id};

                if ($charges > 0) {
                    if (exists $alliance_restricted_others_charged{$unique_key}) {
                        $alliance_restricted_others_charged{$unique_key}->{qty} += $row->{quantity};
                    } else {
                        $alliance_restricted_others_charged{$unique_key} = { %$item_entry }; # Clone the entry
                        $alliance_restricted_others_charged{$unique_key}->{restricted_char_id} = $restricted_char_id;
                    }
                } else {
                    if (exists $alliance_restricted_others{$unique_key}) {
                        $alliance_restricted_others{$unique_key}->{qty} += $row->{quantity};
                    } else {
                        $alliance_restricted_others{$unique_key} = { %$item_entry }; # Clone the entry
                        $alliance_restricted_others{$unique_key}->{restricted_char_id} = $restricted_char_id;
                    }
                }
            }
        }
        # Alliance Shared (Public/Unrestricted items)
        elsif ($row->{alliance_item}) {
            next if $row->{restricted_to_character_id} > 0;

            if ($charges > 0) {
                if (exists $alliance_shared_charged{$unique_key}) {
                    $alliance_shared_charged{$unique_key}->{qty} += $row->{quantity};
                    if ($row->{char_id} == $char_id) {
                        $alliance_shared_charged{$unique_key}->{your_qty} = ($alliance_shared_charged{$unique_key}->{your_qty} || 0) + $row->{quantity};
                        $alliance_shared_charged{$unique_key}->{is_depositor} = 1; 
                    }
                } else {
                    $alliance_shared_charged{$unique_key} = { %$item_entry };
                    $alliance_shared_charged{$unique_key}->{is_depositor} = 0;
                    if ($row->{char_id} == $char_id) {
                        $alliance_shared_charged{$unique_key}->{your_qty} = $row->{quantity};
                        $alliance_shared_charged{$unique_key}->{is_depositor} = 1;
                    } else {
                        $alliance_shared_charged{$unique_key}->{your_qty} = 0;
                    }
                }
            } else {
                if (exists $alliance_shared{$unique_key}) {
                    $alliance_shared{$unique_key}->{qty} += $row->{quantity};
                    if ($row->{char_id} == $char_id) {
                        $alliance_shared{$unique_key}->{your_qty} = ($alliance_shared{$unique_key}->{your_qty} || 0) + $row->{quantity};
                        $alliance_shared{$unique_key}->{is_depositor} = 1; 
                    }
                } else {
                    $alliance_shared{$unique_key} = { %$item_entry };
                    $alliance_shared{$unique_key}->{is_depositor} = 0;
                    if ($row->{char_id} == $char_id) {
                        $alliance_shared{$unique_key}->{your_qty} = $row->{quantity};
                        $alliance_shared{$unique_key}->{is_depositor} = 1;
                    } else {
                        $alliance_shared{$unique_key}->{your_qty} = 0;
                    }
                }
            }
        }
        # Account-wide
        elsif ($row->{account_item}) {
            if ($charges > 0) {
                if (exists $account_wide_charged{$unique_key}) {
                    $account_wide_charged{$unique_key}->{qty} += $row->{quantity};
                    if ($row->{char_id} == $char_id) {
                        $account_wide_charged{$unique_key}->{can_modify} = 1;
                    }
                } else {
                    $account_wide_charged{$unique_key} = $item_entry;
                    $account_wide_charged{$unique_key}->{can_modify} = ($row->{char_id} == $char_id) ? 1 : 0;
                }
            } else {
                if (exists $account_wide{$unique_key}) {
                    $account_wide{$unique_key}->{qty} += $row->{quantity};
                    if ($row->{char_id} == $char_id) {
                        $account_wide{$unique_key}->{can_modify} = 1;
                    }
                } else {
                    $account_wide{$unique_key} = $item_entry;
                    $account_wide{$unique_key}->{can_modify} = ($row->{char_id} == $char_id) ? 1 : 0;
                }
            }
        }
        # Character-only
        else {
            if ($charges > 0) {
                if (exists $character_only_charged{$unique_key}) {
                    $character_only_charged{$unique_key}->{qty} += $row->{quantity};
                } else {
                    $character_only_charged{$unique_key} = $item_entry;
                }
            } else {
                if (exists $character_only{$unique_key}) {
                    $character_only{$unique_key}->{qty} += $row->{quantity};
                } else {
                    $character_only{$unique_key} = $item_entry;
                }
            }
        }
    }
    
    $query->close();
    
    # --- Platinum Query Logic (Unchanged) ---
    
    # Get platinum from all accessible pools
    my $plat_query = $db->prepare("
        SELECT id, quantity, alliance_item, account_item, alliance_id, char_id
        FROM $TABLE_BANKER 
        WHERE item_id = $COIN_ITEM_ID
        AND (
            (char_id = ? AND alliance_item = 0 AND account_item = 0)
            OR (account_id = ? AND account_item = 1)
            OR (alliance_id = ? AND alliance_item = 1 AND restricted_to_character_id = 0)
        )
        ORDER BY account_item DESC, alliance_item DESC
    ");
    $plat_query->execute($char_id, $account_id, $alliance_id);
    
    my %platinum_pools = (
        character => 0,
        account => 0,
        alliance => 0
    );
    
    my %platinum_ids = (
        character => [],
        account => [],
        alliance => []
    );
    
    while (my $row = $plat_query->fetch_hashref()) {
        if ($row->{account_item}) {
            $platinum_pools{account} += $row->{quantity};
            push @{$platinum_ids{account}}, { id => $row->{id}, qty => $row->{quantity}, char_id => $row->{char_id} };
        } elsif ($row->{alliance_item}) {
            $platinum_pools{alliance} += $row->{quantity};
            push @{$platinum_ids{alliance}}, { id => $row->{id}, qty => $row->{quantity}, char_id => $row->{char_id} };
        } else {
            $platinum_pools{character} += $row->{quantity};
            push @{$platinum_ids{character}}, { id => $row->{id}, qty => $row->{quantity} };
        }
    }
    $plat_query->close();
    
    my $total_platinum = $platinum_pools{character} + $platinum_pools{account} + $platinum_pools{alliance};
    
    $db->close();
    
    # Convert hashes to sorted arrays
    my @alliance_shared_array = sort { $a->{name} cmp $b->{name} } values %alliance_shared;
    my @alliance_shared_charged_array = sort { $a->{name} cmp $b->{name} || $b->{charges} <=> $a->{charges} } values %alliance_shared_charged;
    my @alliance_restricted_array = sort { $a->{name} cmp $b->{name} } values %alliance_restricted;
    my @alliance_restricted_charged_array = sort { $a->{name} cmp $b->{name} || $b->{charges} <=> $a->{charges} } values %alliance_restricted_charged;
    my @alliance_restricted_others_array = sort { $a->{name} cmp $b->{name} } values %alliance_restricted_others;
    my @alliance_restricted_others_charged_array = sort { $a->{name} cmp $b->{name} || $b->{charges} <=> $a->{charges} } values %alliance_restricted_others_charged;
    my @account_wide_array = sort { $a->{name} cmp $b->{name} } values %account_wide;
    my @account_wide_charged_array = sort { $a->{name} cmp $b->{name} || $b->{charges} <=> $a->{charges} } values %account_wide_charged;
    my @character_only_array = sort { $a->{name} cmp $b->{name} } values %character_only;
    my @character_only_charged_array = sort { $a->{name} cmp $b->{name} || $b->{charges} <=> $a->{charges} } values %character_only_charged;
    
    # --- Display Output ---
    $client->Message(315, "$NPCName whispers to you, 'Your stored items (Click item name for info, enter ID to withdraw):'");
    $client->Message(315, "--------------------------------------------------------");

    # Filter Links
    my $all_link = ($filter eq 'all') ? ">> ALL <<" : quest::saylink("show balance all", 0, "ALL");
    my $alliance_link = ($filter eq 'alliance') ? ">> ALLIANCE <<" : quest::saylink("show balance alliance", 0, "ALLIANCE");
    my $account_link = ($filter eq 'account') ? ">> ACCOUNT <<" : quest::saylink("show balance account", 0, "ACCOUNT");
    my $char_link = ($filter eq 'char') ? ">> CHARACTER <<" : quest::saylink("show balance char", 0, "CHARACTER");
    
    $client->Message(315, ":: FILTER VIEW: ($all_link) ($alliance_link) ($account_link) ($char_link) ::");
    $client->Message(315, "--------------------------------------------------------");
    
    # Platinum Pools (Unchanged)
    if ($total_platinum > 0) {
        $client->Message(315, ":: PLATINUM CURRENCY ::");
        
        if ($platinum_pools{alliance} > 0) {
            my $withdraw_all = quest::saylink("withdraw platinum $platinum_pools{alliance}", 0, "(W:All)");
            my $unshare = quest::saylink("platinum unshare alliance", 0, "MakeAcct");
            $client->Message(315, "- Alliance Platinum: $platinum_pools{alliance} (Shared) ($withdraw_all) ($unshare)");
        }
        
        if ($platinum_pools{account} > 0) {
            my $withdraw_all = quest::saylink("withdraw platinum $platinum_pools{account}", 0, "(W:All)");
            my $share_alliance = "";
            if ($alliance_id > 0) {
                $share_alliance = " " . quest::saylink("platinum share alliance", 0, "ShareAlly");
            }
            $client->Message(315, "- Account Platinum: $platinum_pools{account} (All Your Characters) ($withdraw_all) ($share_alliance)");
        }
        
        
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # Alliance Shared (Uncharged)
    if (($filter eq 'all' || $filter eq 'alliance') && @alliance_shared_array && $alliance_id > 0) {
        $client->Message(315, ":: ALLIANCE SHARED ITEMS (PUBLIC) ::");
        foreach my $item (@alliance_shared_array) {
            my $item_link = quest::varlink($item->{id});
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};
            
            my $your_qty_display = "";
            my $unshare_link = "";
            
            if ($item->{your_qty} && $item->{your_qty} > 0) {
                $your_qty_display = " [YQ: $item->{your_qty}]";
                
                if ($item->{is_depositor}) { 
                    my $unshare_all = quest::saylink("alliance unshare $item->{id} $item->{your_qty}", 0, "Unshare");
                    $unshare_link = " ($unshare_all)";
                }
            }
            
            my $restrict_links = "";
            if ($item->{is_depositor}) {
                my $r1 = quest::saylink("alliance restrict $item->{id} 1", 0,"R:1");
                $restrict_links = " ($r1)";
            }

            $client->Message(315, "- $item_link: $item->{qty}$your_qty_display$item->{augment_display}$item->{attuned_display}$item->{owner_display} [ID: $item->{id}] ($w1) $wstack ($wall)$restrict_links$unshare_link");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # Alliance Shared Charged
    if (($filter eq 'all' || $filter eq 'alliance') && @alliance_shared_charged_array && $alliance_id > 0) {
        $client->Message(315, ":: ALLIANCE SHARED CHARGED ITEMS (PUBLIC) ::");
        foreach my $item (@alliance_shared_charged_array) {
            my $item_link = quest::varlink($item->{id});
            my $charges_text = ($item->{charges} == 1) ? "Charge: 1" : "Charges: $item->{charges}";
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};
            
            my $your_qty_display = "";
            my $unshare_link = "";
            
            if ($item->{your_qty} && $item->{your_qty} > 0) {
                $your_qty_display = " [YQ: $item->{your_qty}]";
                
                if ($item->{is_depositor}) { 
                    my $unshare_all = quest::saylink("alliance unshare $item->{id} $item->{your_qty} $item->{charges}", 0, "Unshare");
                    $unshare_link = " ($unshare_all)";
                }
            }
            
            my $restrict_links = "";
            if ($item->{is_depositor}) {
                my $r1 = quest::saylink("alliance restrict $item->{id} 1 $item->{charges}", 0, "R:1");
                $restrict_links = " ($r1)";
            }
            
            $client->Message(315, "- $item_link ($charges_text): $item->{qty}$your_qty_display$item->{augment_display}$item->{attuned_display}$item->{owner_display} [ID: $item->{id}] ($w1) $wstack ($wall)$restrict_links$unshare_link");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # ALLIANCE RESTRICTED ITEMS (OTHERS' PRIVATE) - OWNER VIEW
    if (($filter eq 'all' || $filter eq 'alliance') && @alliance_restricted_others_array && $alliance_id > 0 && $is_owner) {
        $client->Message(315, ":: ALLIANCE RESTRICTED ITEMS (OTHERS' PRIVATE) ::");
        $client->Message(315, ":: OWNER OVERRIDE - Use 'OWNER UNRESTRICT' to free up the item. ::");
        foreach my $item (@alliance_restricted_others_array) {
            my $item_link = quest::varlink($item->{id});
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};

            my $unrestrict_all = quest::saylink("alliance unrestrictall $item->{id}", 0, "OWNER UNRESTRICT");
            my $unrestrict_link = " ($unrestrict_all)";
            
            $client->Message(315, "- $item_link: $item->{qty}$item->{augment_display}$item->{attuned_display}$item->{owner_display} [ID: $item->{id}] ($w1) $wstack ($wall)$unrestrict_link");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    if (($filter eq 'all' || $filter eq 'alliance') && @alliance_restricted_others_charged_array && $alliance_id > 0 && $is_owner) {
        $client->Message(315, ":: ALLIANCE RESTRICTED CHARGED ITEMS (OTHERS' PRIVATE) ::");
        $client->Message(315, ":: OWNER OVERRIDE - Use 'OWNER UNRESTRICT' to free up the item. ::");
        foreach my $item (@alliance_restricted_others_charged_array) {
            my $item_link = quest::varlink($item->{id});
            my $charges_text = ($item->{charges} == 1) ? "Charge: 1" : "Charges: $item->{charges}";
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};

            my $restricted_display = " [Restricted to Char ID: $item->{restricted_char_id}]";

            my $unrestrict_all = quest::saylink("alliance unrestrictall $item->{id} $item->{charges}", 0, "OWNER UNRESTRICT");
            my $unrestrict_link = " ($unrestrict_all)";
            
            $client->Message(315, "- $item_link ($charges_text): $item->{qty}$item->{augment_display}$item->{attuned_display}$item->{owner_display}$restricted_display [ID: $item->{id}] ($w1) $wstack ($wall)$unrestrict_link");
        }
        $client->Message(315, "--------------------------------------------------------");
    }

    
    # Alliance Restricted (Your Private, Uncharged)
    if (($filter eq 'all' || $filter eq 'alliance') && @alliance_restricted_array && $alliance_id > 0) {
        $client->Message(315, ":: ALLIANCE RESTRICTED ITEMS (YOUR PRIVATE) ::");
        foreach my $item (@alliance_restricted_array) {
            my $item_link = quest::varlink($item->{id});
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};
            
            my $u1 = quest::saylink("alliance unrestrict $item->{id} 1", 0, "U:1");
            my $uall = quest::saylink("alliance unrestrictall $item->{id}", 0, "U:All");
            
            $client->Message(315, "- $item_link: $item->{qty}$item->{augment_display}$item->{attuned_display} [ID: $item->{id}] ($w1) $wstack ($wall) ($u1) ($uall)");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # Alliance Restricted Charged (Your Private, Charged)
    if (($filter eq 'all' || $filter eq 'alliance') && @alliance_restricted_charged_array && $alliance_id > 0) {
        $client->Message(315, ":: ALLIANCE RESTRICTED CHARGED ITEMS (YOUR PRIVATE) ::");
        foreach my $item (@alliance_restricted_charged_array) {
            my $item_link = quest::varlink($item->{id});
            my $charges_text = ($item->{charges} == 1) ? "Charge: 1" : "Charges: $item->{charges}";
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};
            
            my $u1 = quest::saylink("alliance unrestrict $item->{id} 1 $item->{charges}", 0, "U:1");
            my $uall = quest::saylink("alliance unrestrictall $item->{id} $item->{charges}", 0, "U:All");
            
            $client->Message(315, "- $item_link ($charges_text): $item->{qty}$item->{augment_display}$item->{attuned_display} [ID: $item->{id}] ($w1) $wstack ($wall) ($u1) ($uall)");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # Account-Wide Items (Uncharged)
    if (($filter eq 'all' || $filter eq 'account') && @account_wide_array) {
        $client->Message(315, ":: ACCOUNT-WIDE ITEMS (ALL YOUR CHARACTERS) ::");
        foreach my $item (@account_wide_array) {
            my $item_link = quest::varlink($item->{id});
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};
            
            my $modification_links = "";
            if (exists $item->{can_modify} && $item->{can_modify} == 1) {
                my $item_check_db = Database::new(Database::Content);
                my $item_prop = $item_check_db->prepare("SELECT heirloom FROM items WHERE id = ?");
                $item_prop->execute($item->{id});
                my $item_flags = $item_prop->fetch_hashref();
                $item_prop->close();
                $item_check_db->close();
                
                my $is_heirloom = ($item_flags && $item_flags->{heirloom}) ? 1 : 0;
                
                my $share_alliance = "";
                if ($alliance_id > 0 && !$is_heirloom) {
                    $share_alliance = " " . quest::saylink("alliance share $item->{id} $item->{qty}", 0, "(ShareAlly)");
                }
                $modification_links .= $share_alliance;
            }
            
            $client->Message(315, "- $item_link: $item->{qty}$item->{augment_display}$item->{attuned_display}$item->{owner_display} [ID: $item->{id}] ($w1) $wstack ($wall)$modification_links");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # Account-Wide Charged Items (Charged)
    if (($filter eq 'all' || $filter eq 'account') && @account_wide_charged_array) {
        $client->Message(315, ":: ACCOUNT-WIDE CHARGED ITEMS (ALL YOUR CHARACTERS) ::");
        foreach my $item (@account_wide_charged_array) {
            my $item_link = quest::varlink($item->{id});
            my $charges_text = ($item->{charges} == 1) ? "Charge: 1" : "Charges: $item->{charges}";
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};

            my $modification_links = "";
            if (exists $item->{can_modify} && $item->{can_modify} == 1) {
                my $item_check_db = Database::new(Database::Content);
                my $item_prop = $item_check_db->prepare("SELECT heirloom FROM items WHERE id = ?");
                $item_prop->execute($item->{id});
                my $item_flags = $item_prop->fetch_hashref();
                $item_prop->close();
                $item_check_db->close();
                
                my $is_heirloom = ($item_flags && $item_flags->{heirloom}) ? 1 : 0;
                
                my $share_alliance = "";
                if ($alliance_id > 0 && !$is_heirloom) {
                    $share_alliance = " " . quest::saylink("alliance share $item->{id} $item->{qty} $item->{charges}", 0, "(ShareAlly)");
                }
                $modification_links .= $share_alliance;
            }
            
            $client->Message(315, "- $item_link ($charges_text): $item->{qty}$item->{augment_display}$item->{attuned_display}$item->{owner_display} [ID: $item->{id}] ($w1) $wstack ($wall)$modification_links");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # Character-Only Items (Uncharged)
    if (($filter eq 'all' || $filter eq 'char') && @character_only_array) {
        $client->Message(315, ":: CHARACTER-ONLY ITEMS ::");
        foreach my $item (@character_only_array) {
            my $item_link = quest::varlink($item->{id});
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};

            my $share_account_link = "";
            my $share_alliance_link = "";
            
            # Logic: Only show sharing options if the item is NOT augmented, NOT attuned, AND NOT no-drop
            unless ($item->{has_augments} || $item->{is_attuned}) {
                # Check if item is no-drop
                my $item_check_db = Database::new(Database::Content);
                my $item_prop = $item_check_db->prepare("SELECT nodrop, heirloom FROM items WHERE id = ?");
                $item_prop->execute($item->{id});
                my $item_flags = $item_prop->fetch_hashref();
                $item_prop->close();
                $item_check_db->close();
                
                my $is_nodrop = ($item_flags && $item_flags->{nodrop} == 0) ? 1 : 0;
                my $is_heirloom = ($item_flags && $item_flags->{heirloom}) ? 1 : 0;
                
                # Only show sharing if item is NOT no-drop (nodrop should be 1 for tradable items)
                unless ($is_nodrop) {
                    my $share_account = quest::saylink("account share $item->{id} $item->{qty}", 0, "ShareAcct");
                    $share_account_link = " ($share_account)";

                    if ($alliance_id > 0 && !$is_heirloom) {
                        $share_alliance_link = " " . quest::saylink("alliance share $item->{id} $item->{qty}", 0, "ShareAlly");
                    }
                }
            }
            
            $client->Message(315, "- $item_link: $item->{qty}$item->{augment_display}$item->{attuned_display} [ID: $item->{id}] ($w1) $wstack ($wall)$share_account_link $share_alliance_link");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
    
    # Character-Only Charged Items (Charged)
    if (($filter eq 'all' || $filter eq 'char') && @character_only_charged_array) {
        $client->Message(315, ":: CHARACTER-ONLY CHARGED ITEMS ::");
        foreach my $item (@character_only_charged_array) {
            my $item_link = quest::varlink($item->{id});
            my $charges_text = ($item->{charges} == 1) ? "Charge: 1" : "Charges: $item->{charges}";
            
            # Generate withdraw links with augment support
            my %wlinks = GenerateWithdrawLinks($item->{id}, $item->{charges}, $item->{qty}, $item->{stacksize}, $item->{augments});
            my $w1 = $wlinks{w1};
            my $wall = $wlinks{wall};
            my $wstack = $wlinks{wstack};

            my $share_account_link = "";
            my $share_alliance_link = "";

            # Logic: Only show sharing options if the item is NOT augmented, NOT attuned, AND NOT no-drop
            unless ($item->{has_augments} || $item->{is_attuned}) {
                # Check if item is no-drop
                my $item_check_db = Database::new(Database::Content);
                my $item_prop = $item_check_db->prepare("SELECT nodrop, heirloom FROM items WHERE id = ?");
                $item_prop->execute($item->{id});
                my $item_flags = $item_prop->fetch_hashref();
                $item_prop->close();
                $item_check_db->close();
                
                my $is_nodrop = ($item_flags && $item_flags->{nodrop} == 0) ? 1 : 0;
                my $is_heirloom = ($item_flags && $item_flags->{heirloom}) ? 1 : 0;
                
                # Only show sharing if item is NOT no-drop (nodrop should be 1 for tradable items)
                unless ($is_nodrop) {
                    my $share_account = quest::saylink("account share $item->{id} $item->{qty} $item->{charges}", 0, "ShareAcct");
                    $share_account_link = " ($share_account)";

                    if ($alliance_id > 0 && !$is_heirloom) {
                        $share_alliance_link = " " . quest::saylink("alliance share $item->{id} $item->{qty} $item->{charges}", 0, "ShareAlly");
                    }
                }
            }
            
            $client->Message(315, "- $item_link ($charges_text): $item->{qty}$item->{augment_display}$item->{attuned_display} [ID: $item->{id}] ($w1) $wstack ($wall)$share_account_link $share_alliance_link");
        }
        $client->Message(315, "--------------------------------------------------------");
    }
}
sub RestrictAllianceItemToCharacter {
    my ($item_id, $target_char_id, $quantity, $charges) = @_;
    my $NPCName = "Banker";
    
    my $PERMISSION_OWNER = plugin::val('$PERMISSION_OWNER') || 1;
    my $TABLE_BANKER = plugin::val('$TABLE_BANKER') || "celestial_live_banker";
    my $TABLE_ALLIANCE_MEMBERS = plugin::val('$TABLE_ALLIANCE_MEMBERS') || "celestial_live_alliance_members";
    
    unless ($item_id && $target_char_id) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance restrict <ItemID> <TargetCharID> [Quantity] [Charges]'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance.'");
        return;
    }
    
    $quantity = 99999 unless defined($quantity) && $quantity > 0;
    $charges = 0 unless defined($charges);
    
    my $db = Database::new(Database::Content);
    
    # Check if user is owner or depositor of the item
    my $is_owner = 0;
    my $rank_query = $db->prepare("
        SELECT permission_level 
        FROM $TABLE_ALLIANCE_MEMBERS 
        WHERE alliance_id = ? AND character_id = ?
    ");
    $rank_query->execute($alliance_id, $char_id);
    my $member_row = $rank_query->fetch_hashref();
    $rank_query->close();
    
    if ($member_row && $member_row->{permission_level} eq $PERMISSION_OWNER) {
        $is_owner = 1;
    }
    
    # Verify target character is in the alliance
    my $target_check = $db->prepare("
        SELECT character_id 
        FROM $TABLE_ALLIANCE_MEMBERS 
        WHERE alliance_id = ? AND character_id = ?
    ");
    $target_check->execute($alliance_id, $target_char_id);
    my $target_exists = $target_check->fetch_hashref();
    $target_check->close();
    
    unless ($target_exists) {
        my $target_name = GetCharacterName($target_char_id);
        $client->Message(315, "$NPCName whispers to you, 'Character $target_name (ID: $target_char_id) is not in your alliance.'");
        $db->close();
        return;
    }
    
    # Find items that can be restricted (owner can restrict any, depositor can only restrict their own)
    my $where_clause = $is_owner ? 
        "alliance_id = ? AND item_id = ? AND charges = ? AND alliance_item = 1 AND (restricted_to_character_id = 0 OR restricted_to_character_id = ?)" :
        "char_id = ? AND alliance_id = ? AND item_id = ? AND charges = ? AND alliance_item = 1 AND (restricted_to_character_id = 0 OR restricted_to_character_id = ?)";
    
    my @params = $is_owner ? 
        ($alliance_id, $item_id, $charges, $char_id) :
        ($char_id, $alliance_id, $item_id, $charges, $char_id);
    
    my $find = $db->prepare("SELECT id, quantity, char_id FROM $TABLE_BANKER WHERE $where_clause ORDER BY id ASC LIMIT 1");
    $find->execute(@params);
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        $client->Message(315, "$NPCName whispers to you, 'No alliance items found matching item ID $item_id$charge_msg that you can restrict.'");
        $db->close();
        return;
    }
    
    # Limit quantity to available
    if ($quantity > $row->{quantity}) {
        $quantity = $row->{quantity};
    }
    
    # If restricting partial quantity, split the stack
    if ($quantity < $row->{quantity}) {
        my $get_full_row = $db->prepare("SELECT * FROM $TABLE_BANKER WHERE id = ?");
        $get_full_row->execute($row->{id});
        my $full_row = $get_full_row->fetch_hashref();
        $get_full_row->close();
        
        # Reduce the original stack
        my $new_qty = $row->{quantity} - $quantity;
        my $update_original = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
        $update_original->execute($new_qty, $row->{id});
        $update_original->close();
        
        # Check if restricted stack to target already exists
        my $find_restricted = $db->prepare("
            SELECT id, quantity 
            FROM $TABLE_BANKER
            WHERE char_id = ? AND item_id = ? AND charges = ? AND alliance_id = ?
            AND alliance_item = 1 AND restricted_to_character_id = ?
            AND augment_one = ? AND augment_two = ? AND augment_three = ?
            AND augment_four = ? AND augment_five = ? AND augment_six = ?
        ");
        $find_restricted->execute(
            $full_row->{char_id}, $item_id, $charges, $alliance_id, $target_char_id,
            $full_row->{augment_one} || 0, $full_row->{augment_two} || 0, $full_row->{augment_three} || 0,
            $full_row->{augment_four} || 0, $full_row->{augment_five} || 0, $full_row->{augment_six} || 0
        );
        my $restricted_row = $find_restricted->fetch_hashref();
        $find_restricted->close();
        
        if ($restricted_row) {
            # Add to existing restricted stack
            my $new_restricted_qty = $restricted_row->{quantity} + $quantity;
            my $update_restricted = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
            $update_restricted->execute($new_restricted_qty, $restricted_row->{id});
            $update_restricted->close();
        } else {
            # Create new restricted stack
            my $insert_restricted = $db->prepare("
                INSERT INTO $TABLE_BANKER 
                (account_id, char_id, alliance_id, item_id, quantity, charges, attuned,
                 alliance_item, account_item, restricted_to_character_id,
                 augment_one, augment_two, augment_three, augment_four, augment_five, augment_six)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ");
            $insert_restricted->execute(
                $full_row->{account_id}, $full_row->{char_id}, $full_row->{alliance_id},
                $full_row->{item_id}, $quantity, $full_row->{charges}, $full_row->{attuned},
                $full_row->{alliance_item}, $full_row->{account_item}, $target_char_id,
                $full_row->{augment_one}, $full_row->{augment_two}, $full_row->{augment_three},
                $full_row->{augment_four}, $full_row->{augment_five}, $full_row->{augment_six}
            );
            $insert_restricted->close();
        }
    } else {
        # Restricting entire stack
        my $update = $db->prepare("UPDATE $TABLE_BANKER SET restricted_to_character_id = ? WHERE id = ?");
        $update->execute($target_char_id, $row->{id});
        $update->close();
    }
    
    $db->close();
    
    my $item_name = quest::getitemname($item_id);
    my $target_name = GetCharacterName($target_char_id);
    my $charge_msg = ($charges > 0) ? " ($charges charges each)" : "";
    $client->Message(315, "$NPCName whispers to you, 'Restricted $quantity of $item_name$charge_msg to $target_name (ID: $target_char_id).'");
}
sub RestrictAllAllianceItemOwnerOnly {
    my ($item_id, $charges) = @_;
    my $NPCName = "Banker";
    
    my $PERMISSION_OWNER = plugin::val('$PERMISSION_OWNER') || 1;
    my $TABLE_BANKER = plugin::val('$TABLE_BANKER') || "celestial_live_banker";
    my $TABLE_ALLIANCE_MEMBERS = plugin::val('$TABLE_ALLIANCE_MEMBERS') || "celestial_live_alliance_members";
    
    unless ($item_id) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance restrictall <ItemID> [Charges]'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance.'");
        return;
    }
    
    # Check if user is owner
    my $db = Database::new(Database::Content);
    
    my $rank_query = $db->prepare("
        SELECT permission_level 
        FROM $TABLE_ALLIANCE_MEMBERS 
        WHERE alliance_id = ? AND character_id = ?
    ");
    $rank_query->execute($alliance_id, $char_id);
    my $member_row = $rank_query->fetch_hashref();
    $rank_query->close();
    
    unless ($member_row && $member_row->{permission_level} eq $PERMISSION_OWNER) {
        $client->Message(315, "$NPCName whispers to you, 'Only the alliance owner can use restrictall.'");
        $db->close();
        return;
    }
    
    $charges = 0 unless defined($charges);
    
    # Handle charges filtering
    my $charges_where = ($charges > 0) ? "charges = ?" : "(charges = 0 OR charges IS NULL)";
    my @execute_params = ($alliance_id, $item_id);
    push @execute_params, $charges if ($charges > 0);
    
    # Check if any items exist to restrict
    my $check_sql = "
        SELECT char_id, SUM(quantity) as total_qty 
        FROM $TABLE_BANKER 
        WHERE alliance_id = ? AND item_id = ? AND $charges_where AND alliance_item = 1 AND restricted_to_character_id = 0
        GROUP BY char_id
    ";
    my $check_query = $db->prepare($check_sql);
    $check_query->execute(@execute_params);
    
    my %depositor_totals;
    my $grand_total = 0;
    
    while (my $row = $check_query->fetch_hashref()) {
        $depositor_totals{$row->{char_id}} = $row->{total_qty};
        $grand_total += $row->{total_qty};
    }
    $check_query->close();
    
    unless ($grand_total > 0) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        $client->Message(315, "$NPCName whispers to you, 'No unrestricted alliance items found matching item ID $item_id$charge_msg.'");
        $db->close();
        return;
    }
    
    # Restrict all copies - each depositor's items become restricted to them
    my $update_sql = "
        UPDATE $TABLE_BANKER 
        SET restricted_to_character_id = char_id 
        WHERE alliance_id = ? AND item_id = ? AND $charges_where AND alliance_item = 1 AND restricted_to_character_id = 0
    ";
    my $update_query = $db->prepare($update_sql);
    $update_query->execute(@execute_params);
    $update_query->close();
    
    $db->close();
    
    my $item_name = quest::getitemname($item_id);
    my $charge_msg = ($charges > 0) ? " ($charges charges each)" : "";
    my $depositor_count = scalar(keys %depositor_totals);
    
    $client->Message(315, "$NPCName whispers to you, 'Owner Restricted: All $grand_total of $item_name$charge_msg from $depositor_count depositor(s) are now private.'");
    $client->Message(315, "$NPCName whispers to you, 'Only you (as owner) and the original depositors can withdraw these items.'");
}
sub SearchItems {
    my ($search_term) = @_;
    
    my $NPCName = "Banker";
    
    # Global Variable Lookups (Matches ShowBalance)
    my $COIN_ITEM_ID = plugin::val('$COIN_ITEM_ID') || 99990;
    my $TABLE_BANKER = plugin::val('$TABLE_BANKER') || "celestial_live_banker";
    my $TABLE_ALLIANCE_MEMBERS = plugin::val('$TABLE_ALLIANCE_MEMBERS') || "celestial_live_alliance_members";

    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    
    # Retrieves the alliance ID using the existing helper function
    my $alliance_id = GetAllianceID(); 
    
    my $db = Database::new(Database::Content);
    
    # --- ALLIANCE OWNER SETUP (Copied from ShowBalance for context) ---
    my $PERMISSION_OWNER = 1; 
    my $is_owner = 0;

    if ($alliance_id > 0) {
        my $rank_query = $db->prepare("
            SELECT permission_level 
            FROM $TABLE_ALLIANCE_MEMBERS 
            WHERE alliance_id = ? 
            AND character_id = ?
        ");
        $rank_query->execute($alliance_id, $char_id);
        my $member_row = $rank_query->fetch_hashref();
        $rank_query->close();

        if ($member_row->{permission_level} eq $PERMISSION_OWNER) {
            $is_owner = 1;
        }
    }
    # --- END OF ALLIANCE OWNER SETUP ---

    # Prepare search term for SQL LIKE operator
    my $like_search = "%" . $search_term . "%";

    # Query for all accessible items matching the search term
    my $sql = "
        SELECT
            sb.id, sb.item_id, sb.quantity, sb.charges, sb.attuned, sb.char_id,
            sb.alliance_id, sb.alliance_item, sb.account_item, sb.restricted_to_character_id,
            sb.augment_one, sb.augment_two, sb.augment_three, sb.augment_four, sb.augment_five, sb.augment_six,
            i.name, i.stacksize,
            cd.name as owner_character_name
        FROM $TABLE_BANKER sb
        INNER JOIN items i ON sb.item_id = i.id
        LEFT JOIN character_data cd ON sb.char_id = cd.id
        WHERE sb.item_id != $COIN_ITEM_ID
        AND i.name LIKE ?
        AND (
            -- Character's personal items
            (sb.char_id = ? AND sb.alliance_item = 0 AND sb.account_item = 0)
            -- OR Account-wide items
            OR (sb.account_id = ? AND sb.account_item = 1)
            -- OR Alliance items accessible to you OR owner override
            OR (
                sb.alliance_id = ? AND sb.alliance_item = 1
                AND (
                    sb.restricted_to_character_id = 0
                    OR sb.restricted_to_character_id = ?
                    OR ? = 1 -- OWNER OVERRIDE: Show restricted items if owner
                )
            )
        )
        ORDER BY i.name ASC, sb.charges DESC
    ";
    
    my $query = $db->prepare($sql);
    # Parameters: (1: search_term), (2: char_id), (3: account_id), (4: alliance_id), (5: char_id), (6: is_owner)
    $query->execute($like_search, $char_id, $account_id, $alliance_id, $char_id, $is_owner);

    my @results;
    
    while (my $row = $query->fetch_hashref()) {
        my $item_id = $row->{item_id};
        my $charges = $row->{charges} || 0;
        my $item_name = $row->{name} || "Unknown Item (ID $item_id)";
        
        # --- Augment and Attuned Display Logic ---
        my @augments = (
            $row->{augment_one} || 0,
            $row->{augment_two} || 0,
            $row->{augment_three} || 0,
            $row->{augment_four} || 0,
            $row->{augment_five} || 0,
            $row->{augment_six} || 0
        );
        
        my $has_augments = 0;
        my $augment_display = "";
        my @aug_names;
        for (my $i = 0; $i < 6; $i++) {
            if ($augments[$i] > 0) { 
                $has_augments = 1;
                my $aug_name = quest::getitemname($augments[$i]);
                push @aug_names, $aug_name;
            }
        }
        if ($has_augments) {
            $augment_display = " [Aug: " . join(", ", @aug_names) . "]";
        }
        
        my $attuned_display = ($row->{attuned}) ? " [ATTUNED]" : "";
        
        # --- Item Ownership/Scope Display Logic ---
        my $scope_display = "";
        if ($row->{alliance_item}) {
            if ($row->{restricted_to_character_id} == $char_id) {
                $scope_display = " (YOUR PRIVATE ALLY)";
            } elsif ($row->{restricted_to_character_id} > 0) {
                $scope_display = " (RESTRICTED ALLY: $row->{owner_character_name})";
            } else {
                $scope_display = " (ALLIANCE SHARED)";
            }
        } elsif ($row->{account_item}) {
            $scope_display = " (ACCOUNT WIDE)";
        } else {
            $scope_display = " (CHARACTER ONLY)";
        }
        
        # --- Final Link/Text Construction ---
        my $charges_text = $charges > 0 ? " ($charges " . ($charges == 1 ? "Charge" : "Charges") . ")" : "";
        
        my $item_link = quest::varlink($item_id);
        my $w_command = $charges > 0 ? "withdraw $item_id $charges" : "withdraw $item_id";
        
        my $w1 = quest::saylink("$w_command 1", 0, "W:1");
        my $wall = quest::saylink("$w_command", 0, "W:All");
        
        # Add W:Stack for stackable items
        my $wstack = "";
        if ($row->{stacksize} > 1 && $row->{quantity} >= $row->{stacksize}) {
            my $stack_qty = $row->{stacksize};
            my $w_stack_command = $charges > 0 ? "withdraw $item_id $charges $stack_qty" : "withdraw $item_id $stack_qty";
            $wstack = " " . quest::saylink($w_stack_command, 0, "(W:Stack)");
        }

        my $message = "- $item_link $charges_text: $row->{quantity}$augment_display$attuned_display$scope_display [ID: $item_id] ($w1) $wstack ($wall)";
        push @results, $message;
    }
    
    $query->close();
    $db->close();
    
    # --- Display Results ---
    if (@results) {
        $client->Message(315, "$NPCName whispers to you, 'Found " . scalar(@results) . " items matching \"$search_term\":'");
        $client->Message(315, "--------------------------------------------------------");
        foreach my $msg (@results) {
            $client->Message(315, $msg);
        }
        $client->Message(315, "--------------------------------------------------------");
    } else {
        $client->Message(315, "$NPCName whispers to you, 'I could not find any items matching \"$search_term\" that are accessible to you.'");
    }
}
# =========================================================================
# CELESTIAL LIVE BANKER - PART 2: Sharing & Restriction Functions
# =========================================================================
# This is Part 2 of the complete script
# Contains: Account Share/Unshare, Alliance Share/Unshare, Restrict/Unrestrict
# =========================================================================


# =========================================================================
# PLATINUM SHARING FUNCTIONS
# =========================================================================

sub SharePlatinum {
    my ($target_pool) = @_;
    my $NPCName = "Banker";
    
    # Only allow 'alliance' as target pool for sharing
    unless ($target_pool eq 'alliance') {
        $client->Message(315, "$NPCName whispers to you, 'Usage: platinum share <alliance>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    my $alliance_id = GetAllianceID();
    
    if ($target_pool eq 'alliance' && !($alliance_id > 0)) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance to share platinum with alliance.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # SOURCE: Account-wide pool (alliance_item=0, account_item=1)
    # TARGET: Alliance pool (alliance_item=1, account_item=0)
    
    my $target_alliance_item = 1;
    my $target_account_item = 0;
    my $target_alliance_id = $alliance_id;
    
    # Find source platinum (from Account-wide pool)
    my $find = $db->prepare("
        SELECT id, quantity
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = $COIN_ITEM_ID
        AND alliance_item = 0
        AND account_item = 1
        AND alliance_id = 0
    ");
    $find->execute($char_id);
    
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        $client->Message(315, "$NPCName whispers to you, 'You do not have account-wide platinum to share with alliance.'");
        $db->close();
        return;
    }
    
    my $amount = $row->{quantity};
    my $source_id = $row->{id};
    
    # Check if target pool (Alliance) exists
    my $check_target = $db->prepare("
        SELECT id, quantity
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = $COIN_ITEM_ID
        AND alliance_id = ?
        AND alliance_item = ?
        AND account_item = ?
    ");
    $check_target->execute($char_id, $target_alliance_id, $target_alliance_item, $target_account_item);
    my $target_row = $check_target->fetch_hashref();
    $check_target->close();
    
    if ($target_row) {
        # Add to existing target pool
        my $new_qty = $target_row->{quantity} + $amount;
        my $update = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
        $update->execute($new_qty, $target_row->{id});
        $update->close();
    } else {
        # Create new target pool
        my $insert = $db->prepare("
            INSERT INTO $TABLE_BANKER 
            (account_id, char_id, alliance_id, item_id, quantity, charges, attuned, alliance_item, account_item, restricted_to_character_id,
             augment_one, augment_two, augment_three, augment_four, augment_five, augment_six)
            VALUES (?, ?, ?, $COIN_ITEM_ID, ?, 0, 0, ?, ?, 0, 0, 0, 0, 0, 0, 0)
        ");
        $insert->execute($account_id, $char_id, $target_alliance_id, $amount, $target_alliance_item, $target_account_item);
        $insert->close();
    }
    
    # Delete source pool
    my $delete = $db->prepare("DELETE FROM $TABLE_BANKER WHERE id = ?");
    $delete->execute($source_id);
    $delete->close();
    
    $db->close();
    
    $client->Message(315, "$NPCName whispers to you, 'Moved $amount platinum to alliance pool.'");
}

sub UnsharePlatinum {
    my ($source_pool) = @_;
    my $NPCName = "Banker";
    
    # Only allow 'alliance' as source pool
    unless ($source_pool eq 'alliance') {
        $client->Message(315, "$NPCName whispers to you, 'Usage: platinum unshare <alliance>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $account_id = $client->AccountID();
    my $alliance_id = GetAllianceID();
    
    my $db = Database::new(Database::Content);
    
    # SOURCE: Alliance pool (alliance_item=1, account_item=0)
    # TARGET: Account-wide pool (alliance_item=0, account_item=1)
    
    my $source_alliance_item = 1;
    my $source_account_item = 0;
    my $source_alliance_id = $alliance_id;
    my $target_msg = 'account-wide pool';
    
    # Find source platinum (from Alliance pool)
    my $find = $db->prepare("
        SELECT id, quantity
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = $COIN_ITEM_ID
        AND alliance_id = ?
        AND alliance_item = ?
        AND account_item = ?
    ");
    $find->execute($char_id, $source_alliance_id, $source_alliance_item, $source_account_item);
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        $client->Message(315, "$NPCName whispers to you, 'You do not have platinum in the alliance pool.'");
        $db->close();
        return;
    }
    
    my $amount = $row->{quantity};
    my $source_id = $row->{id};
    
    # Determine target flags: Account-Wide Pool
    my $target_alliance_item = 0;
    my $target_account_item = 1;
    my $target_alliance_id = 0;
    
    # Check if target pool (Account-Wide) exists
    my $check_target = $db->prepare("
        SELECT id, quantity
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = $COIN_ITEM_ID
        AND alliance_id = ?
        AND alliance_item = ?
        AND account_item = ?
    ");
    $check_target->execute($char_id, $target_alliance_id, $target_alliance_item, $target_account_item);
    my $target_row = $check_target->fetch_hashref();
    $check_target->close();
    
    if ($target_row) {
        # Add to existing target pool
        my $new_qty = $target_row->{quantity} + $amount;
        my $update = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
        $update->execute($new_qty, $target_row->{id});
        $update->close();
    } else {
        # Create new target pool
        my $insert = $db->prepare("
            INSERT INTO $TABLE_BANKER 
            (account_id, char_id, alliance_id, item_id, quantity, charges, attuned, alliance_item, account_item, restricted_to_character_id,
             augment_one, augment_two, augment_three, augment_four, augment_five, augment_six)
            VALUES (?, ?, ?, $COIN_ITEM_ID, ?, 0, 0, ?, ?, 0, 0, 0, 0, 0, 0, 0)
        ");
        $insert->execute($account_id, $char_id, $target_alliance_id, $amount, $target_alliance_item, $target_account_item);
        $insert->close();
    }
    
    # Delete source pool
    my $delete = $db->prepare("DELETE FROM $TABLE_BANKER WHERE id = ?");
    $delete->execute($source_id);
    $delete->close();
    
    $db->close();
    
    $client->Message(315, "$NPCName whispers to you, 'Moved $amount platinum to $target_msg.'");
}

# =========================================================================
# ALLIANCE SHARING FUNCTIONS (UPDATED LOGIC)
# =========================================================================
sub AllianceShareItem {
    my ($item_id, $quantity, $charges) = @_;
    my $NPCName = "Banker";
    
    unless ($item_id && $quantity > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance share <ItemID> <Quantity> [Charges]'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance to share items.'");
        return;
    }
    
    $charges = 0 unless defined($charges);
    my $db = Database::new(Database::Content);
    
    # Check item flags for non-sharable type (No-Drop w/ Heirloom)
    my $item_check = $db->prepare("SELECT nodrop, heirloom FROM items WHERE id = ?");
    $item_check->execute($item_id);
    my $item_data = $item_check->fetch_hashref();
    $item_check->close();
    
    if ($item_data && $item_data->{nodrop} && $item_data->{heirloom}) {
        my $item_name = quest::getitemname($item_id);
        $client->Message(315, "$NPCName whispers to you, 'Heirloom items like $item_name are shared with your account but cannot be shared with the alliance.'");
        $db->close();
        return;
    }
    
    # Find items owned by this character that are NOT already alliance shared (alliance_item = 0)
    my $find = $db->prepare("
        SELECT id, quantity, attuned, augment_one, augment_two, augment_three, augment_four, augment_five, augment_six 
        FROM $TABLE_BANKER 
        WHERE char_id = ? AND item_id = ? AND charges = ? AND alliance_item = 0
    ");
    $find->execute($char_id, $item_id, $charges);
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        $client->Message(315, "$NPCName whispers to you, 'You do not have items matching item ID $item_id$charge_msg in your account/character bank that are sharable.'");
        $db->close();
        return;
    }
    
    # Check for character-bound flags that prevent sharing (Augmented or Attuned)
    my $has_augments = 0;
    foreach my $aug (
        $row->{augment_one}, $row->{augment_two}, $row->{augment_three}, 
        $row->{augment_four}, $row->{augment_five}, $row->{augment_six}
    ) {
        $has_augments = 1 if $aug > 0;
    }
    
    if ($row->{attuned} || $has_augments) {
        my $item_name = quest::getitemname($item_id);
        $client->Message(315, "$NPCName whispers to you, 'Attuned or Augmented items like $item_name are character-specific and cannot be shared.'");
        $db->close();
        return;
    }
    
    if ($quantity > $row->{quantity}) {
        $client->Message(315, "$NPCName whispers to you, 'You only have $row->{quantity} of this item.'");
        $db->close();
        return;
    }
    
    # UPDATE: Set alliance_item flag, alliance_id, AND set restricted_to_character_id = 0 (UNRESTRICTED)
    my $update = $db->prepare("
        UPDATE $TABLE_BANKER 
        SET alliance_item = 1, alliance_id = ?, restricted_to_character_id = 0 
        WHERE id = ? 
    ");
    $update->execute($alliance_id, $row->{id});
    $update->close();
    $db->close();
    
    my $item_name = quest::getitemname($item_id);
    my $charge_msg = ($charges > 0) ? " ($charges charges each)" : "";
    $client->Message(315, "$NPCName whispers to you, '$quantity of $item_name$charge_msg are now in alliance bank (UNRESTRICTED).'");
    $client->Message(315, "$NPCName whispers to you, 'Use [alliance restrict 1] or click [R:1] to restrict items back to yourself if needed.'");
}
sub AllianceUnshareItem {
    my ($item_id, $quantity, $charges) = @_;
    my $NPCName = "Banker";
    
    unless ($item_id && $quantity > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance unshare <ItemID> <Quantity> [Charges]'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance.'");
        return;
    }
    
    $charges = 0 unless defined($charges);
    
    my $db = Database::new(Database::Content);
    
    # Find alliance items owned by this character
    my $find = $db->prepare("
        SELECT id, quantity 
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = ?
        AND charges = ?
        AND alliance_item = 1
        AND alliance_id = ?
    ");
    $find->execute($char_id, $item_id, $charges, $alliance_id);
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        $client->Message(315, "$NPCName whispers to you, 'You do not have alliance items matching item ID $item_id$charge_msg.'");
        $db->close();
        return;
    }
    
    if ($quantity > $row->{quantity}) {
        $client->Message(315, "$NPCName whispers to you, 'You only have $row->{quantity} of this item.'");
        $db->close();
        return;
    }
    
    # Update to remove alliance_item flag
    my $update = $db->prepare("
        UPDATE $TABLE_BANKER 
        SET alliance_item = 0, 
            alliance_id = 0,
            restricted_to_character_id = 0
        WHERE id = ?
    ");
    $update->execute($row->{id});
    $update->close();
    
    $db->close();
    
    my $item_name = quest::getitemname($item_id);
    my $charge_msg = ($charges > 0) ? " ($charges charges each)" : "";
    $client->Message(315, "$NPCName whispers to you, '$quantity of $item_name$charge_msg removed from alliance bank. Now character-specific.'");
}
# =========================================================================
# ALLIANCE RESTRICTION FUNCTIONS
# =========================================================================

sub RestrictAllianceItem {
    my ($item_id, $quantity, $charges) = @_;
    my $NPCName = "Banker";
    
    unless ($item_id && $quantity > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance restrict <ItemID> <Quantity> [Charges]'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance.'");
        return;
    }
    
    $charges = 0 unless defined($charges);
    
    my $db = Database::new(Database::Content);
    
    # Find shared alliance items owned by this character
    my $find = $db->prepare("
        SELECT id, quantity 
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = ?
        AND charges = ?
        AND alliance_id = ?
        AND alliance_item = 1
        AND restricted_to_character_id = 0
    ");
    $find->execute($char_id, $item_id, $charges, $alliance_id);
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        $client->Message(315, "$NPCName whispers to you, 'You do not have shared alliance items matching item ID $item_id$charge_msg.'");
        $db->close();
        return;
    }
    
    if ($quantity > $row->{quantity}) {
        $client->Message(315, "$NPCName whispers to you, 'You only have $row->{quantity} of this item.'");
        $db->close();
        return;
    }
    
    # If restricting partial quantity, need to split the stack
    if ($quantity < $row->{quantity}) {
        # Get full row data first (including augments)
        my $get_full_row = $db->prepare("SELECT * FROM $TABLE_BANKER WHERE id = ?");
        $get_full_row->execute($row->{id});
        my $full_row = $get_full_row->fetch_hashref();
        $get_full_row->close();
        
        # Reduce the shared stack
        my $new_shared_qty = $row->{quantity} - $quantity;
        my $update_shared = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
        $update_shared->execute($new_shared_qty, $row->{id});
        $update_shared->close();
        
        # Check if restricted stack already exists WITH SAME AUGMENTS
        my $find_restricted = $db->prepare("
            SELECT id, quantity 
            FROM $TABLE_BANKER
            WHERE char_id = ?
            AND item_id = ?
            AND charges = ?
            AND alliance_id = ?
            AND alliance_item = 1
            AND restricted_to_character_id = ?
            AND augment_one = ?
            AND augment_two = ?
            AND augment_three = ?
            AND augment_four = ?
            AND augment_five = ?
            AND augment_six = ?
        ");
        $find_restricted->execute(
            $char_id, $item_id, $charges, $alliance_id, $char_id,
            $full_row->{augment_one} || 0,
            $full_row->{augment_two} || 0,
            $full_row->{augment_three} || 0,
            $full_row->{augment_four} || 0,
            $full_row->{augment_five} || 0,
            $full_row->{augment_six} || 0
        );
        my $restricted_row = $find_restricted->fetch_hashref();
        $find_restricted->close();
        
        if ($restricted_row) {
            # Add to existing restricted stack (with matching augments)
            my $new_qty = $restricted_row->{quantity} + $quantity;
            my $update_restricted = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
            $update_restricted->execute($new_qty, $restricted_row->{id});
            $update_restricted->close();
        } else {
            # Create new restricted stack by copying the row
            my $insert_restricted = $db->prepare("
                INSERT INTO $TABLE_BANKER 
                (account_id, char_id, alliance_id, item_id, quantity, charges, attuned,
                 alliance_item, account_item, restricted_to_character_id,
                 augment_one, augment_two, augment_three, augment_four, augment_five, augment_six)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ");
            $insert_restricted->execute(
                $full_row->{account_id}, $full_row->{char_id}, $full_row->{alliance_id},
                $full_row->{item_id}, $quantity, $full_row->{charges}, $full_row->{attuned},
                $full_row->{alliance_item}, $full_row->{account_item}, $char_id,
                $full_row->{augment_one}, $full_row->{augment_two}, $full_row->{augment_three},
                $full_row->{augment_four}, $full_row->{augment_five}, $full_row->{augment_six}
            );
            $insert_restricted->close();
        }
    } else {
        # Restricting entire stack
        my $update = $db->prepare("UPDATE $TABLE_BANKER SET restricted_to_character_id = ? WHERE id = ?");
        $update->execute($char_id, $row->{id});
        $update->close();
    }
    
    $db->close();
    
    my $item_name = quest::getitemname($item_id);
    my $charge_msg = ($charges > 0) ? " ($charges charges each)" : "";
    $client->Message(315, "$NPCName whispers to you, 'Restricted $quantity of $item_name$charge_msg. Only you can withdraw them now.'");
}

sub UnrestrictAllianceItem {
    my ($item_id, $quantity, $charges) = @_;
    my $NPCName = "Banker";
    
    unless ($item_id && $quantity > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance unrestrict <ItemID> <Quantity> [Charges]'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance.'");
        return;
    }
    
    $charges = 0 unless defined($charges);
    
    my $db = Database::new(Database::Content);
    
    # Find restricted alliance items
    my $find = $db->prepare("
        SELECT id, quantity 
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = ?
        AND charges = ?
        AND alliance_id = ?
        AND alliance_item = 1
        AND restricted_to_character_id = ?
    ");
    $find->execute($char_id, $item_id, $charges, $alliance_id, $char_id);
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        $client->Message(315, "$NPCName whispers to you, 'You do not have restricted alliance items matching item ID $item_id$charge_msg.'");
        $db->close();
        return;
    }
    
    if ($quantity > $row->{quantity}) {
        $client->Message(315, "$NPCName whispers to you, 'You only have $row->{quantity} restricted items.'");
        $db->close();
        return;
    }
    
    # If unrestricting partial quantity, need to split the stack
    if ($quantity < $row->{quantity}) {
        # Get full row data first (including augments)
        my $get_full_row = $db->prepare("SELECT * FROM $TABLE_BANKER WHERE id = ?");
        $get_full_row->execute($row->{id});
        my $full_row = $get_full_row->fetch_hashref();
        $get_full_row->close();
        
        # Reduce the restricted stack
        my $new_restricted_qty = $row->{quantity} - $quantity;
        my $update_restricted = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
        $update_restricted->execute($new_restricted_qty, $row->{id});
        $update_restricted->close();
        
        # Check if shared stack already exists WITH SAME AUGMENTS
        my $find_shared = $db->prepare("
            SELECT id, quantity 
            FROM $TABLE_BANKER
            WHERE char_id = ?
            AND item_id = ?
            AND charges = ?
            AND alliance_id = ?
            AND alliance_item = 1
            AND restricted_to_character_id = 0
            AND augment_one = ?
            AND augment_two = ?
            AND augment_three = ?
            AND augment_four = ?
            AND augment_five = ?
            AND augment_six = ?
        ");
        $find_shared->execute(
            $char_id, $item_id, $charges, $alliance_id,
            $full_row->{augment_one} || 0,
            $full_row->{augment_two} || 0,
            $full_row->{augment_three} || 0,
            $full_row->{augment_four} || 0,
            $full_row->{augment_five} || 0,
            $full_row->{augment_six} || 0
        );
        my $shared_row = $find_shared->fetch_hashref();
        $find_shared->close();
        
        if ($shared_row) {
            # Add to existing shared stack (with matching augments)
            my $new_qty = $shared_row->{quantity} + $quantity;
            my $update_shared = $db->prepare("UPDATE $TABLE_BANKER SET quantity = ? WHERE id = ?");
            $update_shared->execute($new_qty, $shared_row->{id});
            $update_shared->close();
        } else {
            # Create new shared stack
            my $insert_shared = $db->prepare("
                INSERT INTO $TABLE_BANKER 
                (account_id, char_id, alliance_id, item_id, quantity, charges, attuned,
                 alliance_item, account_item, restricted_to_character_id,
                 augment_one, augment_two, augment_three, augment_four, augment_five, augment_six)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?)
            ");
            $insert_shared->execute(
                $full_row->{account_id}, $full_row->{char_id}, $full_row->{alliance_id},
                $full_row->{item_id}, $quantity, $full_row->{charges}, $full_row->{attuned},
                $full_row->{alliance_item}, $full_row->{account_item},
                $full_row->{augment_one}, $full_row->{augment_two}, $full_row->{augment_three},
                $full_row->{augment_four}, $full_row->{augment_five}, $full_row->{augment_six}
            );
            $insert_shared->close();
        }
    } else {
        # Unrestricting entire stack
        my $update = $db->prepare("UPDATE $TABLE_BANKER SET restricted_to_character_id = 0 WHERE id = ?");
        $update->execute($row->{id});
        $update->close();
    }
    
    $db->close();
    
    my $item_name = quest::getitemname($item_id);
    my $charge_msg = ($charges > 0) ? " ($charges charges each)" : "";
    $client->Message(315, "$NPCName whispers to you, 'Unrestricted $quantity of $item_name$charge_msg. Now accessible to alliance members.'");
}
sub UnrestrictAllAllianceItem {
    my ($item_id, $charges) = @_;
    my $NPCName = "Banker";
    
    # Define or ensure scope for global configuration variables
    my $PERMISSION_OWNER = plugin::val('$PERMISSION_OWNER') || 1;
    my $TABLE_BANKER = plugin::val('$TABLE_BANKER') || "celestial_live_banker";
    my $TABLE_ALLIANCE_MEMBERS = plugin::val('$TABLE_ALLIANCE_MEMBERS') || "celestial_live_alliance_members";
    
    unless ($item_id) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance unrestrictall <ItemID> [Charges]'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance.'");
        return;
    }
    
    $charges = 0 unless defined($charges);
    
    my $db = Database::new(Database::Content);
    
    # --- ALLIANCE OWNER CHECK ---
    my $is_owner = 0;
    
    my $rank_query = $db->prepare("
        SELECT permission_level 
        FROM $TABLE_ALLIANCE_MEMBERS 
        WHERE alliance_id = ? 
        AND character_id = ?
    ");
    $rank_query->execute($alliance_id, $char_id);
    my $member_row = $rank_query->fetch_hashref();
    $rank_query->close();

    if ($member_row && $member_row->{permission_level} eq $PERMISSION_OWNER) {
        $is_owner = 1;
    }
    # --- END ALLIANCE OWNER CHECK ---

    my $where_clause;
    my $charges_where;
    my @execute_params;
    
    # --- Charges Handling: Be explicitly NULL-safe for 0 charges ---
    if ($charges > 0) {
        $charges_where = "charges = ?";
        # $charges will be pushed into @execute_params later
    } else {
        # This handles the case where $charges is 0 (the default for uncharged items)
        $charges_where = "(charges = 0 OR charges IS NULL)";
    }
    # --- End Charges Handling ---

    
    if ($is_owner) {
        # OWNER OVERRIDE: Unrestrict ANY restricted item of this type in the alliance
        $where_clause = "
            alliance_id = ?
            AND item_id = ?
            AND $charges_where
            AND alliance_item = 1
            AND restricted_to_character_id > 0
        ";
        @execute_params = ($alliance_id, $item_id);
    } else {
        # MEMBER: Unrestrict only items THEY restricted to themselves
        $where_clause = "
            item_id = ?
            AND $charges_where
            AND alliance_id = ?
            AND alliance_item = 1
            AND char_id = ?
            AND restricted_to_character_id = ?
        ";
        @execute_params = ($item_id, $alliance_id, $char_id, $char_id);
    }
    
    # Push $charges to parameters ONLY if it's > 0 (because the WHERE clause already handles the 0 case)
    if ($charges > 0) {
        push @execute_params, $charges;
    }
    
    # 1. Check if any items exist to unrestrict
    my $check_sql = "SELECT SUM(quantity) as total_qty FROM $TABLE_BANKER WHERE $where_clause";
    my $check_query = $db->prepare($check_sql);
    $check_query->execute(@execute_params);
    
    my $check_row = $check_query->fetch_hashref();
    $check_query->close();
    
    my $total_unrestricted = $check_row->{total_qty} || 0;
    
    unless ($total_unrestricted > 0) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        my $restrict_type = $is_owner ? "any restricted alliance items" : "your restricted alliance items";
        $client->Message(315, "$NPCName whispers to you, 'Could not find $restrict_type matching item ID $item_id$charge_msg.'");
        $db->close();
        return;
    }
    
    # 2. Perform the update: set restricted_to_character_id = 0
    my $update_sql = "UPDATE $TABLE_BANKER SET restricted_to_character_id = 0 WHERE $where_clause";
    my $update_query = $db->prepare($update_sql);
    $update_query->execute(@execute_params);
    $update_query->close();
    
    $db->close();
    
    my $item_name = quest::getitemname($item_id);
    my $charge_msg = ($charges > 0) ? " ($charges charges each)" : "";
    my $action_msg = $is_owner ? "Owner override: Unrestricted" : "Unrestricted all";
    
    $client->Message(315, "$NPCName whispers to you, '$action_msg $total_unrestricted of $item_name$charge_msg. These items are now public and accessible to all alliance members.'");
}
sub RestrictAllAllianceItem {
    my ($item_id, $charges) = @_;
    my $NPCName = "Banker";
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance.'");
        return;
    }
    
    $charges = 0 unless defined($charges);
    
    my $db = Database::new(Database::Content);
    
    # Find shared alliance items
    my $find = $db->prepare("
        SELECT id, quantity 
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND item_id = ?
        AND charges = ?
        AND alliance_id = ?
        AND alliance_item = 1
        AND restricted_to_character_id = 0
    ");
    $find->execute($char_id, $item_id, $charges, $alliance_id);
    my $row = $find->fetch_hashref();
    $find->close();
    
    unless ($row) {
        my $charge_msg = ($charges > 0) ? " with $charges charges" : "";
        $client->Message(315, "$NPCName whispers to you, 'You do not have shared alliance items matching item ID $item_id$charge_msg.'");
        $db->close();
        return;
    }
    
    my $total_quantity = $row->{quantity};
    
    $db->close();
    
    # Just call the regular restrict with full quantity
    RestrictAllianceItem($item_id, $total_quantity, $charges);
}

sub AllianceItemTransfer {
    my ($item_id, $charges, $target_name) = @_;
    unless (CheckAlliancePermission($PERMISSION_OFFICER)) {
        quest::say("You must be an alliance Officer or Owner to transfer alliance items.");
        return;
    }
    
    my $alliance_id = GetAllianceID();
    unless ($alliance_id) {
        quest::say("You are not currently in an alliance.");
        return;
    }
    
    my $target_char_id = GetCharacterIDByName($target_name);
    unless ($target_char_id) {
        quest::say("Target character '$target_name' not found.");
        return;
    }
    
    # **2. Check if the target is in the alliance (CORRECTED FETCH METHOD)**
    my $is_in_alliance = 0;
    my $db = Database::new(Database::Content); 
    
    # Use 'character_id' for the alliance member table lookup (as previously diagnosed)
    my $query = $db->prepare("SELECT 1 FROM $TABLE_ALLIANCE_MEMBERS WHERE alliance_id = ? AND character_id = ?");
    $query->execute($alliance_id, $target_char_id);
    
    # CORRECTED: Use fetch_hashref() as demonstrated in UnrestrictAllianceItem
    my $row = $query->fetch_hashref(); 
    
    if ($row) {
        $is_in_alliance = 1;
    }
    
    $query->close();

    unless ($is_in_alliance) {
        $db->close(); # Close connection since we are returning
        quest::say("Character '$target_name' is not a member of your alliance.");
        return;
    }
    my $target_account_id = GetAccountIDByCharacter($target_char_id);

    my $update_query = $db->prepare(
        "UPDATE $TABLE_BANKER SET char_id = ?, account_id = ?, restricted_to_character_id = ? 
         WHERE item_id = ? AND charges = ? AND alliance_id = ? AND alliance_item = 1 AND char_id != 0 AND char_id != ?"
    );
    $update_query->execute($target_char_id, $target_account_id, $target_char_id, $item_id, $charges, $alliance_id, $target_char_id); 
    
    $update_query->close();
    MergeDuplicateStacks($db, $target_char_id);
    $db->close(); # Close the database connection once all work is complete
    $item_link = quest::varlink($item_id, $charges);
    quest::say("$item_link has been transferred to $target_name restricted section.");
    
    

}

sub MergeDuplicateStacks {
    my ($db, $char_id) = @_;

    # 1) Merge quantities of duplicate stacks
    my $merge_update_sql = qq{
        UPDATE $TABLE_BANKER AS b1
        JOIN $TABLE_BANKER AS b2
          ON b1.char_id = b2.char_id
          AND b1.item_id = b2.item_id
          AND b1.charges = b2.charges
          AND b1.alliance_item = 1
          AND b1.id < b2.id
        SET b1.quantity = b1.quantity + b2.quantity
        WHERE b1.char_id = ?
    };
    my $stmt = $db->prepare($merge_update_sql);
    $stmt->execute($char_id);
    $stmt->close();   # <-- use close() instead of finish()

    # 2) Delete duplicate rows (keep the lowest id)
    my $merge_delete_sql = qq{
        DELETE b2 FROM $TABLE_BANKER AS b2
        JOIN $TABLE_BANKER AS b1
          ON b1.char_id = b2.char_id
          AND b1.item_id = b2.item_id
          AND b1.charges = b2.charges
          AND b1.alliance_item = 1
          AND b1.id < b2.id
        WHERE b2.char_id = ?
    };
    $stmt = $db->prepare($merge_delete_sql);
    $stmt->execute($char_id);
    $stmt->close();   # <-- close() again
}


# =========================================================================
# CELESTIAL LIVE BANKER - PART 3: Alliance Management Functions
# =========================================================================
# ALLIANCE MEMBER MANAGEMENT
# =========================================================================

sub InviteToAlliance {
    my ($target_char_name) = @_;
    my $NPCName = "Banker";
    
    unless ($target_char_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance invite <CharacterName>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $char_name = $client->GetCleanName();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        return;
    }
    
    # Check permission (Officer or Owner can invite)
    unless (CheckAlliancePermission($PERMISSION_OFFICER)) {
        $client->Message(315, "$NPCName whispers to you, 'Only Officers and Owners can invite members.'");
        return;
    }
    
    # Get target character ID
    my $target_char_id = GetCharacterIDByName($target_char_name);
    unless ($target_char_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Character '$target_char_name' not found.'");
        return;
    }
    
    if ($target_char_id == $char_id) {
        $client->Message(315, "$NPCName whispers to you, 'You cannot invite yourself.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Get alliance name
    my $alliance_query = $db->prepare("SELECT name FROM $TABLE_ALLIANCE WHERE id = ?");
    $alliance_query->execute($alliance_id);
    my $alliance_row = $alliance_query->fetch_hashref();
    $alliance_query->close();
    my $alliance_name = $alliance_row->{name};
    
    # Check if target is already in an alliance
    my $check_member = $db->prepare("SELECT alliance_id FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ?");
    $check_member->execute($target_char_id);
    my $existing = $check_member->fetch_hashref();
    $check_member->close();
    
    if ($existing) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is already in an alliance.'");
        $db->close();
        return;
    }
    
    # Check if already invited
    my $check_invite = $db->prepare("SELECT id FROM $TABLE_ALLIANCE_PENDING WHERE alliance_id = ? AND character_id = ?");
    $check_invite->execute($alliance_id, $target_char_id);
    my $pending = $check_invite->fetch_hashref();
    $check_invite->close();
    
    if ($pending) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name has already been invited.'");
        $db->close();
        return;
    }
    
    # Get target's account ID
    my $target_account_id = GetAccountIDByCharacter($target_char_id);
    
    # Create invitation
    my $insert = $db->prepare("
        INSERT INTO $TABLE_ALLIANCE_PENDING 
        (alliance_id, character_id, character_name, account_id, invited_by_character_id, invited_by_character_name)
        VALUES (?, ?, ?, ?, ?, ?)
    ");
    $insert->execute($alliance_id, $target_char_id, $target_char_name, $target_account_id, $char_id, $char_name);
    $insert->close();
    
    $db->close();
    
    # Send mail notification to invited player
    my $mail_subject = "Alliance Invitation from $alliance_name";
    my $mail_message = "Greetings!\n\n" .
                      "You have been invited to join the alliance '$alliance_name' by $char_name.\n\n" .
                      "To accept this invitation:\n" .
                      "1. Visit any Celestial Banker NPC\n" .
                      "2. Say: alliance join $alliance_name\n\n" .
                      "This invitation will allow you to share tradable items with all alliance members through the alliance bank.\n\n" .
                      "You can check your pending invitations by saying 'alliance status' to any Banker.\n\n" .
                      "Welcome to the alliance!";
    
    quest::SendMail($target_char_name, "Alliance Banker", $mail_subject, $mail_message);
    
    $client->Message(315, "$NPCName whispers to you, 'Invited $target_char_name to join alliance **$alliance_name**.'");
    $client->Message(315, "$NPCName whispers to you, 'A notification has been sent to $target_char_name via mail.'");
    
    quest::debug("Alliance Invite: $target_char_name invited to $alliance_name by $char_name");
}

sub KickFromAlliance {
    my ($target_char_name) = @_;
    my $NPCName = "Banker";
    
    unless ($target_char_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance kick <CharacterName>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        return;
    }
    
    # Check permission
    unless (CheckAlliancePermission($PERMISSION_OFFICER)) {
        $client->Message(315, "$NPCName whispers to you, 'Only Officers and Owners can kick members.'");
        return;
    }
    
    # Get target character ID
    my $target_char_id = GetCharacterIDByName($target_char_name);
    unless ($target_char_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Character '$target_char_name' not found.'");
        return;
    }
    
    if ($target_char_id == $char_id) {
        $client->Message(315, "$NPCName whispers to you, 'You cannot kick yourself. Use [alliance leave] instead.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Get target's permission level
    my $check_target = $db->prepare("SELECT permission_level FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $check_target->execute($target_char_id, $alliance_id);
    my $target_row = $check_target->fetch_hashref();
    $check_target->close();
    
    unless ($target_row) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is not in your alliance.'");
        $db->close();
        return;
    }
    
    my $target_permission = $target_row->{permission_level};
    
    # Get your permission level
    my $check_self = $db->prepare("SELECT permission_level FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $check_self->execute($char_id, $alliance_id);
    my $self_row = $check_self->fetch_hashref();
    $check_self->close();
    my $self_permission = $self_row->{permission_level};
    
    # Officers cannot kick other Officers or Owner
    if ($self_permission == $PERMISSION_OFFICER && $target_permission <= $PERMISSION_OFFICER) {
        $client->Message(315, "$NPCName whispers to you, 'Officers cannot kick other Officers or the Owner.'");
        $db->close();
        return;
    }
    
    # Cannot kick the owner
    if ($target_permission == $PERMISSION_OWNER) {
        $client->Message(315, "$NPCName whispers to you, 'You cannot kick the alliance owner.'");
        $db->close();
        return;
    }
    
    # Get alliance name for mail notification
    my $alliance_query = $db->prepare("SELECT name FROM $TABLE_ALLIANCE WHERE id = ?");
    $alliance_query->execute($alliance_id);
    my $alliance_row = $alliance_query->fetch_hashref();
    $alliance_query->close();
    my $alliance_name = $alliance_row->{name};
    
    # Remove from alliance
    my $delete_member = $db->prepare("DELETE FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $delete_member->execute($target_char_id, $alliance_id);
    $delete_member->close();
    
    # Count their alliance items AND platinum
    my $count_query = $db->prepare("
        SELECT COUNT(*) as item_count
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND alliance_id = ?
    ");
    $count_query->execute($target_char_id, $alliance_id);
    my $count_row = $count_query->fetch_hashref();
    $count_query->close();
    my $total_stacks = ($count_row && $count_row->{item_count}) ? $count_row->{item_count} : 0;

    # Get their platinum amount BEFORE moving (for display message)
    my $plat_query = $db->prepare("
        SELECT SUM(quantity) as total_plat
        FROM $TABLE_BANKER
        WHERE char_id = ?
        AND alliance_id = ?
        AND item_id = $COIN_ITEM_ID
    ");
    $plat_query->execute($target_char_id, $alliance_id);
    my $plat_row = $plat_query->fetch_hashref();
    $plat_query->close();
    my $platinum_returned = ($plat_row && $plat_row->{total_plat}) ? $plat_row->{total_plat} : 0;

    # Move their alliance items back to character-only (INCLUDING PLATINUM!)
    if ($total_stacks > 0) {
        my $move_items = $db->prepare("
            UPDATE $TABLE_BANKER 
            SET alliance_item = 0, 
                alliance_id = 0, 
                restricted_to_character_id = 0
            WHERE char_id = ? 
            AND alliance_id = ?
        ");
        $move_items->execute($target_char_id, $alliance_id);
        $move_items->close();
    }
    $db->close();
    
    # Send mail notification to kicked player
    my $kicker_name = $client->GetCleanName();
    my $mail_subject = "Removed from Alliance $alliance_name";
    my $mail_message = "Greetings,\n\n" .
                      "You have been removed from the alliance '$alliance_name' by $kicker_name.\n\n";
    
    # Add details about returned items/platinum
    if ($total_stacks > 0) {
        my $item_count = $total_stacks - ($platinum_returned > 0 ? 1 : 0);
        
        if ($item_count > 0 && $platinum_returned > 0) {
            $mail_message .= "Your $item_count item stack(s) and $platinum_returned platinum have been returned to your character bank.\n\n";
        } elsif ($item_count > 0) {
            $mail_message .= "Your $item_count item stack(s) have been returned to your character bank.\n\n";
        } elsif ($platinum_returned > 0) {
            $mail_message .= "Your $platinum_returned platinum has been returned to your character bank.\n\n";
        }
    }
    
    $mail_message .= "All your alliance items and currency are now in your character bank.\n\n" .
                     "You are free to join another alliance if you wish.";
    
    quest::SendMail($target_char_name, "Alliance Banker", $mail_subject, $mail_message);
    
    $client->Message(315, "$NPCName whispers to you, 'Kicked $target_char_name from the alliance.'");
    $client->Message(315, "$NPCName whispers to you, 'A notification has been sent to $target_char_name via mail.'");
    
    # Display separate messages for items and platinum
    if ($total_stacks > 0) {
        my $item_count = $total_stacks - ($platinum_returned > 0 ? 1 : 0);
        
        if ($item_count > 0) {
            $client->Message(315, "$NPCName whispers to you, 'Their $item_count item stack(s) have been returned to their character bank.'");
        }
        
        if ($platinum_returned > 0) {
            $client->Message(315, "$NPCName whispers to you, 'Their $platinum_returned alliance platinum has been returned to their character bank.'");
        }
    }
    
    quest::debug("Alliance Kick: $target_char_name kicked from alliance $alliance_id");
}

sub PromoteMember {
    my ($target_char_name) = @_;
    my $NPCName = "Banker";
    
    unless ($target_char_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance promote <CharacterName>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        return;
    }
    
    # Only owner can promote
    unless (CheckAlliancePermission($PERMISSION_OWNER)) {
        $client->Message(315, "$NPCName whispers to you, 'Only the alliance owner can promote members.'");
        return;
    }
    
    # Get target character ID
    my $target_char_id = GetCharacterIDByName($target_char_name);
    unless ($target_char_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Character '$target_char_name' not found.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Get target's current permission
    my $check_target = $db->prepare("SELECT permission_level FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $check_target->execute($target_char_id, $alliance_id);
    my $target_row = $check_target->fetch_hashref();
    $check_target->close();
    
    unless ($target_row) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is not in your alliance.'");
        $db->close();
        return;
    }
    
    if ($target_row->{permission_level} == $PERMISSION_OWNER) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is already the owner.'");
        $db->close();
        return;
    }
    
    if ($target_row->{permission_level} == $PERMISSION_OFFICER) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is already an officer.'");
        $db->close();
        return;
    }
    
    # Promote to officer
    my $update = $db->prepare("UPDATE $TABLE_ALLIANCE_MEMBERS SET permission_level = ? WHERE character_id = ? AND alliance_id = ?");
    $update->execute($PERMISSION_OFFICER, $target_char_id, $alliance_id);
    $update->close();
    
    $db->close();
    
    $client->Message(315, "$NPCName whispers to you, 'Promoted $target_char_name to Officer.'");
}

sub DemoteMember {
    my ($target_char_name) = @_;
    my $NPCName = "Banker";
    
    unless ($target_char_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance demote <CharacterName>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        return;
    }
    
    # Only owner can demote
    unless (CheckAlliancePermission($PERMISSION_OWNER)) {
        $client->Message(315, "$NPCName whispers to you, 'Only the alliance owner can demote members.'");
        return;
    }
    
    # Get target character ID
    my $target_char_id = GetCharacterIDByName($target_char_name);
    unless ($target_char_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Character '$target_char_name' not found.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Get target's current permission
    my $check_target = $db->prepare("SELECT permission_level FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $check_target->execute($target_char_id, $alliance_id);
    my $target_row = $check_target->fetch_hashref();
    $check_target->close();
    
    unless ($target_row) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is not in your alliance.'");
        $db->close();
        return;
    }
    
    if ($target_row->{permission_level} == $PERMISSION_OWNER) {
        $client->Message(315, "$NPCName whispers to you, 'You cannot demote the owner.'");
        $db->close();
        return;
    }
    
    if ($target_row->{permission_level} == $PERMISSION_MEMBER) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is already a regular member.'");
        $db->close();
        return;
    }
    
    # Demote to member
    my $update = $db->prepare("UPDATE $TABLE_ALLIANCE_MEMBERS SET permission_level = ? WHERE character_id = ? AND alliance_id = ?");
    $update->execute($PERMISSION_MEMBER, $target_char_id, $alliance_id);
    $update->close();
    
    $db->close();
    
    $client->Message(315, "$NPCName whispers to you, 'Demoted $target_char_name to Member.'");
}

sub TransferOwnership {
    my ($target_char_name) = @_;
    my $NPCName = "Banker";
    
    unless ($target_char_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance transfer <CharacterName>'");
        return;
    }
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        return;
    }
    
    # Only owner can transfer
    unless (CheckAlliancePermission($PERMISSION_OWNER)) {
        $client->Message(315, "$NPCName whispers to you, 'Only the alliance owner can transfer ownership.'");
        return;
    }
    
    # Get target character ID
    my $target_char_id = GetCharacterIDByName($target_char_name);
    unless ($target_char_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'Character '$target_char_name' not found.'");
        return;
    }
    
    if ($target_char_id == $char_id) {
        $client->Message(315, "$NPCName whispers to you, 'You are already the owner.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Check if target is in alliance
    my $check_target = $db->prepare("SELECT permission_level FROM $TABLE_ALLIANCE_MEMBERS WHERE character_id = ? AND alliance_id = ?");
    $check_target->execute($target_char_id, $alliance_id);
    my $target_row = $check_target->fetch_hashref();
    $check_target->close();
    
    unless ($target_row) {
        $client->Message(315, "$NPCName whispers to you, '$target_char_name is not in your alliance.'");
        $db->close();
        return;
    }
    
    # Get target's account ID
    my $target_account_id = GetAccountIDByCharacter($target_char_id);
    
    # Update alliance owner
    my $update_alliance = $db->prepare("UPDATE $TABLE_ALLIANCE SET owner_character_id = ?, owner_account_id = ? WHERE id = ?");
    $update_alliance->execute($target_char_id, $target_account_id, $alliance_id);
    $update_alliance->close();
    
    # Update permissions - OLD OWNER BECOMES OFFICER, NEW OWNER PROMOTED
    my $demote_old = $db->prepare("UPDATE $TABLE_ALLIANCE_MEMBERS SET permission_level = ? WHERE character_id = ? AND alliance_id = ?");
    $demote_old->execute($PERMISSION_OFFICER, $char_id, $alliance_id);
    $demote_old->close();
    
    my $promote_new = $db->prepare("UPDATE $TABLE_ALLIANCE_MEMBERS SET permission_level = ? WHERE character_id = ? AND alliance_id = ?");
    $promote_new->execute($PERMISSION_OWNER, $target_char_id, $alliance_id);
    $promote_new->close();
    
    $db->close();
    
    my $old_owner_name = $client->GetCleanName();
    $client->Message(315, "$NPCName whispers to you, 'Transferred alliance ownership to $target_char_name.'");
    $client->Message(315, "$NPCName whispers to you, 'You have been promoted to Officer rank.'");
}

sub DisbandAlliance {
    my $NPCName = "Banker";
    
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        return;
    }
    
    # Only owner can disband
    unless (CheckAlliancePermission($PERMISSION_OWNER)) {
        $client->Message(315, "$NPCName whispers to you, 'Only the alliance owner can disband the alliance.'");
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Get alliance name
    my $alliance_query = $db->prepare("SELECT name FROM $TABLE_ALLIANCE WHERE id = ?");
    $alliance_query->execute($alliance_id);
    my $alliance_row = $alliance_query->fetch_hashref();
    $alliance_query->close();
    my $alliance_name = $alliance_row->{name};
    
    # Count all alliance items AND platinum that will be moved
    my $count_query = $db->prepare("
        SELECT COUNT(*) as item_count
        FROM $TABLE_BANKER
        WHERE alliance_id = ?
    ");
    $count_query->execute($alliance_id);
    my $count_row = $count_query->fetch_hashref();
    $count_query->close();
    my $total_stacks = ($count_row && $count_row->{item_count}) ? $count_row->{item_count} : 0;
 
    # Get total platinum BEFORE moving (for display message)
    my $plat_query = $db->prepare("
        SELECT SUM(quantity) as total_plat
        FROM $TABLE_BANKER
        WHERE alliance_id = ?
        AND item_id = $COIN_ITEM_ID
    ");
    $plat_query->execute($alliance_id);
    my $plat_row = $plat_query->fetch_hashref();
    $plat_query->close();
    my $total_platinum = ($plat_row && $plat_row->{total_plat}) ? $plat_row->{total_plat} : 0;

    # Move all alliance items back to character-only for each owner (INCLUDING PLATINUM!)
    if ($total_stacks > 0) {
        my $move_items = $db->prepare("
            UPDATE $TABLE_BANKER 
            SET alliance_item = 0, 
                alliance_id = 0, 
                restricted_to_character_id = 0
            WHERE alliance_id = ?
        ");
        $move_items->execute($alliance_id);
        $move_items->close();
    }
    # Delete alliance (cascade will delete members and pending invites)
    my $delete_alliance = $db->prepare("DELETE FROM $TABLE_ALLIANCE WHERE id = ?");
    $delete_alliance->execute($alliance_id);
    $delete_alliance->close();
    
    $db->close();
    
    $client->Message(315, "$NPCName whispers to you, 'Alliance **$alliance_name** has been disbanded.'");
    
    # Display separate messages for items and platinum
    if ($total_stacks > 0) {
        if ($total_platinum > 0) {
            $client->Message(315, "$NPCName whispers to you, 'Alliance platinum totaling $total_platinum has been returned to members.'");
        }
        
        my $item_count = $total_stacks - ($total_platinum > 0 ? 1 : 0);
        if ($item_count > 0) {
            $client->Message(315, "$NPCName whispers to you, '$item_count item stack(s) have been returned to their owners.'");
        }
    }
    
    quest::debug("Alliance Disbanded: $alliance_name (ID: $alliance_id) disbanded by char $char_id");
}

sub AllianceStatus {
    my $NPCName = "Banker";
    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $alliance_id = GetAllianceID();
    
    unless ($alliance_id > 0) {
        my $db = Database::new(Database::Content);
        my $q_pending = $db->prepare("
            SELECT a.name 
            FROM $TABLE_ALLIANCE a 
            JOIN $TABLE_ALLIANCE_PENDING ap ON a.id = ap.alliance_id 
            WHERE ap.character_id = ?
        ");
        $q_pending->execute($char_id);
        my @pending;
        while (my $row = $q_pending->fetch_hashref()) { 
            push @pending, $row->{name}; 
        }
        $q_pending->close();
        $db->close();
        
        $client->Message(315, "$NPCName whispers to you, 'You are currently not in an alliance.'");
        if (@pending) {
            my $accept_links = join(", ", map { quest::saylink("alliance join $_", 1, $_) } @pending);
            $client->Message(315, "$NPCName whispers to you, 'You have pending invites from: $accept_links'");
        }
        return;
    }
    
    my $db = Database::new(Database::Content);
    
    # Get alliance name
    my $alliance_query = $db->prepare("SELECT name FROM $TABLE_ALLIANCE WHERE id = ?");
    $alliance_query->execute($alliance_id);
    my $alliance_row = $alliance_query->fetch_hashref();
    $alliance_query->close();
    my $alliance_name = $alliance_row->{name};
    
    # Get members with their character names
    my $member_query = $db->prepare("
        SELECT 
            am.character_id, 
            am.permission_level,
            cd.name as character_name
        FROM $TABLE_ALLIANCE_MEMBERS am
        JOIN character_data cd ON cd.id = am.character_id
        WHERE am.alliance_id = ?
        ORDER BY am.permission_level ASC, cd.name ASC
    ");
    $member_query->execute($alliance_id);
    
    my @member_list;
    while (my $row = $member_query->fetch_hashref()) {
        push @member_list, {
            character_id => $row->{character_id},
            character_name => $row->{character_name},
            permission_level => $row->{permission_level}
        };
    }
    $member_query->close();
    $db->close();
    
    $client->Message(315, "--- ALLIANCE: $alliance_name ---");
    
    foreach my $member (@member_list) {
        my $level_name = "";
        if ($member->{permission_level} == 1) { $level_name = "Owner"; }
        elsif ($member->{permission_level} == 2) { $level_name = "Officer"; }
        elsif ($member->{permission_level} == 3) { $level_name = "Member"; }
        
        my $current_status = ($member->{character_id} == $char_id) ? " (You)" : "";
        $client->Message(315, "- $member->{character_name} ($level_name)$current_status");
    }
    $client->Message(315, "------------------------------");
    
    # Check user's permission to show appropriate commands
    my $user_permission = CheckAlliancePermission($PERMISSION_OFFICER);
    
    if ($user_permission) {
        # Owner or Officer
        my $kick_link = quest::saylink("alliance kick", 1, "kick");
        my $promote_link = quest::saylink("alliance promote", 1, "promote");
        my $demote_link = quest::saylink("alliance demote", 1, "demote");
        $client->Message(315, "Commands: [$kick_link CharacterName], [$promote_link CharacterName], [$demote_link CharacterName]");
    }
    
    # Check for pending invites at the bottom
    $db = Database::new(Database::Content);
    my $invites_query = $db->prepare("
        SELECT a.name as alliance_name, ap.invited_by_character_name
        FROM $TABLE_ALLIANCE_PENDING ap
        JOIN $TABLE_ALLIANCE a ON ap.alliance_id = a.id
        WHERE ap.character_id = ?
    ");
    $invites_query->execute($char_id);
    
    my @invites;
    while (my $row = $invites_query->fetch_hashref()) {
        push @invites, $row;
    }
    $invites_query->close();
    $db->close();
    
    if (@invites) {
        $client->Message(315, "$NPCName whispers to you, 'Pending Alliance Invitations:'");
        foreach my $invite (@invites) {
            my $accept_link = quest::saylink("alliance join $invite->{alliance_name}", 0, "Accept");
            $client->Message(315, "- $invite->{alliance_name} (invited by $invite->{invited_by_character_name}) ($accept_link)");
        }
    }
}
sub DeclineInvitation {
    my ($alliance_name) = @_;
    my $NPCName = "Banker";

    my $client = plugin::val('$client');
    my $char_id = $client->CharacterID();
    my $char_name = $client->GetCleanName();

    unless ($alliance_name) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: alliance decline <AllianceName>'");
        return;
    }

    my $db = Database::new(Database::Content);

    # Look up the alliance by name
    my $alliance_query = $db->prepare("SELECT id FROM $TABLE_ALLIANCE WHERE name = ?");
    $alliance_query->execute($alliance_name);
    my $alliance_row = $alliance_query->fetch_hashref();
    $alliance_query->close();

    unless ($alliance_row) {
        $client->Message(315, "$NPCName whispers to you, 'Alliance $alliance_name not found.'");
        $db->close();
        return;
    }

    my $alliance_id = $alliance_row->{id};

    # Check if the player has a pending invitation
    my $check_invite = $db->prepare("SELECT id FROM $TABLE_ALLIANCE_PENDING WHERE alliance_id = ? AND character_id = ?");
    $check_invite->execute($alliance_id, $char_id);
    my $pending = $check_invite->fetch_hashref();
    $check_invite->close();

    unless ($pending) {
        $client->Message(315, "$NPCName whispers to you, 'You do not have a pending invitation for $alliance_name.'");
        $db->close();
        return;
    }

    # Delete the pending invitation
    my $delete = $db->prepare("DELETE FROM $TABLE_ALLIANCE_PENDING WHERE id = ?");
    $delete->execute($pending->{id});
    $delete->close();

    $db->close();

    $client->Message(315, "$NPCName whispers to you, 'You have declined the invitation to join alliance $alliance_name.'");

    quest::debug("Alliance Decline: $char_name declined invitation to $alliance_name");
}


# =========================================================================
# CELESTIAL LIVE BANKER - PART 4: EVENT Handlers
# =========================================================================
# This is Part 4 (FINAL) of the complete script
# Contains: EVENT_ITEM, EVENT_SAY, and all command parsing
# =========================================================================

# =========================================================================
# EVENT_ITEM - Handle item deposits
# =========================================================================

sub EVENT_ITEM {
    my $NPCName = "Banker";
    
    my $client = plugin::val('$client');
    my $npc = plugin::val('$npc');
    
    # ACCESS CONTROL CHECK
    unless (CheckAccess()) {
        $client->Message(315, "$NPCName whispers to you, 'I'm sorry, but the banking system is currently undergoing testing and is only available to authorized personnel.'");
        $client->Message(315, "$NPCName whispers to you, 'Please check back later when the system is available to all adventurers.'");
        plugin::return_items(\%itemcount);
        return;
    }
    
    # Currency Calculation: Convert all coin to total copper
    my $total_copper = $copper + ($silver * 10) + ($gold * 100) + ($platinum * 1000);
    
    my $db = Database::new(Database::Content);
    
    # Collect item and charge information from each slot
    my %slot_data;
    
    for my $slot (1..4) {
        my $item_id = plugin::val("\$item$slot");
        next unless $item_id;
        
        my $item_inst = plugin::val("\$item${slot}_inst");
        
        # Query the database for item properties including bagtype, norent (temporary flag)
        my $query = $db->prepare("SELECT stacksize, maxcharges, bagtype, bagslots, norent FROM items WHERE id = ?");
        $query->execute($item_id);
        my $item_props = $query->fetch_hashref();
        $query->close();
        
        # REJECT TEMPORARY ITEMS (norent = 0)
        my $norent = ($item_props && defined($item_props->{norent})) ? $item_props->{norent} : 1;
        if ($norent == 0) {
            my $item_name = quest::getitemname($item_id);
            $client->Message(315, "$NPCName whispers to you, 'I cannot accept temporary items like $item_name. These items cannot be stored.'");
            plugin::return_items(\%itemcount);
            $db->close();
            return;
        }
        
        # REJECT BAGS/CONTAINERS - they have contents we can't track
        my $bagtype = ($item_props && $item_props->{bagtype}) ? $item_props->{bagtype} : 0;
        my $bagslots = ($item_props && $item_props->{bagslots}) ? $item_props->{bagslots} : 0;
        
        if ($bagtype > 0 || $bagslots > 0) {
            my $item_name = quest::getitemname($item_id);
            $client->Message(315, "$NPCName whispers to you, 'I cannot accept containers like $item_name. Please empty it first and deposit the contents individually.'");
            plugin::return_items(\%itemcount);
            $db->close();
            return;
        }
        
        my $stacksize = ($item_props && $item_props->{stacksize}) ? $item_props->{stacksize} : 1;
        my $maxcharges = ($item_props && $item_props->{maxcharges}) ? $item_props->{maxcharges} : 0;
        
        my $charges = 0;
        my $quantity = 1;
        
        if ($item_inst) {
            $charges = $item_inst->GetCharges();
        }
        
        # Determine if this is truly a charged item or a stackable item
        if ($stacksize > 1) {
            # This is a STACKABLE item
            $quantity = ($charges > 0) ? $charges : 1;
            $charges = 0;
        } elsif ($maxcharges > 0 && $charges > 0) {
            # This is a TRULY CHARGED item
            $quantity = 1;
            # Keep charges
        } else {
            # Single, non-charged, non-stackable item
            $quantity = 1;
            $charges = 0;
        }
        
        $slot_data{$slot} = {
            item_id => $item_id,
            charges => $charges,
            quantity => $quantity,
            inst => $item_inst
        };
        
        # Debug message
        my $item_name = quest::getitemname($item_id);
        my $attuned_msg = ($item_inst && $item_inst->IsAttuned()) ? " (ATTUNED)" : "";
        quest::debug("Slot $slot - $item_name (ID: $item_id) - Qty: $quantity, Charges: $charges$attuned_msg");
    }
    
    $db->close();
    
    # Build the check structure for CheckHandin
    my %items_to_check;
    foreach my $slot (keys %slot_data) {
        my $item_id = $slot_data{$slot}->{item_id};
        my $quantity = $slot_data{$slot}->{quantity};
        
        # ADD quantities instead of replacing
        if (exists $items_to_check{$item_id}) {
            $items_to_check{$item_id} += $quantity;
        } else {
            $items_to_check{$item_id} = $quantity;
        }
    }
    
    my %needs = (%items_to_check);
    $needs{platinum} = $platinum if $platinum > 0;
    $needs{gold} = $gold if $gold > 0;
    $needs{silver} = $silver if $silver > 0;
    $needs{copper} = $copper if $copper > 0;
    
    my @inst = (
        plugin::val('$item1_inst'), 
        plugin::val('$item2_inst'), 
        plugin::val('$item3_inst'), 
        plugin::val('$item4_inst')
    );
    
    if ($npc->CheckHandin($client, \%items_to_check, \%needs, @inst)) {
        
        if ($total_copper > 0) {
            DepositCurrency($total_copper);
        }
        
        # Process each slot with correct quantity, charges, AND item instance
        foreach my $slot (sort keys %slot_data) {
            my $item_id = $slot_data{$slot}->{item_id};
            my $charges = $slot_data{$slot}->{charges};
            my $quantity = $slot_data{$slot}->{quantity};
            my $inst = $slot_data{$slot}->{inst};
            
            # Get augments from instance if it exists
            my @augments = (0, 0, 0, 0, 0, 0);
            if ($inst) {
                for (my $i = 0; $i < 6; $i++) {
                    my $aug = $inst->GetAugment($i);
                    $augments[$i] = $aug ? $aug->GetID() : 0;
                }
            }
            
            DepositItem($item_id, $quantity, $charges, \@augments, $inst);
        }
        
        $client->Message(315, "$NPCName whispers to you, 'Your deposit has been recorded.'");
    } else {
        plugin::return_items(\%itemcount);
    }
}
# =========================================================================
# EVENT_SAY - Command parser
# =========================================================================

#!/usr/bin/perl
# =========================================================================
# CELESTIAL LIVE BANKER - Character-Based Banking System with Flags
# =========================================================================
# UPDATED VERSION with Improved User Experience
# Features improved EVENT_SAY with tiered help system and context-aware responses
# =========================================================================

# [Previous 3895 lines remain exactly the same - only EVENT_SAY is updated]
# For brevity, I'm showing just the updated EVENT_SAY section below
# In production, this would be the complete file with only EVENT_SAY changed

# =========================================================================
# EVENT_SAY - UPDATED Command parser with improved UX
# =========================================================================

sub EVENT_SAY {
    my $NPCName = "Banker";
    my $client = plugin::val('$client');
    
    # ACCESS CONTROL CHECK
    unless (CheckAccess()) {
        $client->Message(315, "$NPCName whispers to you, 'I'm sorry, but the banking system is currently undergoing testing and is only available to authorized personnel.'");
        $client->Message(315, "$NPCName whispers to you, 'Please check back later when the system is available to all adventurers.'");
        return;
    }
    
    # Get alliance status for context-aware help
    my $alliance_id = GetAllianceID();
    my $in_alliance = ($alliance_id > 0) ? 1 : 0;
    
    # =========================================================================
    # GREETING & MAIN HELP
    # =========================================================================
    
    if ($text =~ /^hail/i) {
        $client->Message(315, "$NPCName whispers to you, 'Greetings, " . $client->GetCleanName() . "!'");
        $client->Message(315, "$NPCName whispers to you, 'I manage the Celestial Banking system - a secure way to store and share items.'");
        $client->Message(315, "---");
        
        my $quick_start = quest::saylink("help", 1, "Help Menu");
        my $balance = quest::saylink("balance", 1, "View Balance");
        my $examples = quest::saylink("help examples", 1, "See Examples");
        
        $client->Message(315, ":: Quick Links: ($quick_start) ($balance) ($examples) ::");
        
        if (!$in_alliance) {
            my $create_link = quest::saylink("alliance create", 1, "Create Alliance");
            $client->Message(315, ":: You're not in an alliance. ($create_link) to share items with others! ::");
        }
    }
    
    # =========================================================================
    # TIERED HELP SYSTEM
    # =========================================================================
    
    elsif ($text =~ /^help$/i) {
        $client->Message(315, "=== CELESTIAL BANKER HELP MENU ===");
        
        my $basic = quest::saylink("help basic", 1, "Basic Commands");
        my $alliance = quest::saylink("help alliance", 1, "Alliance System");
        my $advanced = quest::saylink("help advanced", 1, "Advanced Features");
        my $examples = quest::saylink("help examples", 1, "Usage Examples");
        
        $client->Message(315, "---");
        $client->Message(315, "Choose a topic:");
        $client->Message(315, "- ($basic) - Deposit, withdraw, view items");
        $client->Message(315, "- ($alliance) - Create & manage alliances");
        $client->Message(315, "- ($advanced) - Sharing, restrictions, transfers");
        $client->Message(315, "- ($examples) - Real-world usage examples");
        $client->Message(315, "---");
        
        my $balance = quest::saylink("balance", 1, "balance");
        $client->Message(315, "TIP: Say ($balance) to see your stored items at any time!");
    }
    
    # BASIC HELP
    elsif ($text =~ /^help basic$/i) {
        $client->Message(315, "=== BASIC COMMANDS ===");
        $client->Message(315, "---");
        $client->Message(315, "**DEPOSITING:**");
        $client->Message(315, "- Trade items to me to deposit them");
        $client->Message(315, "- Trade platinum/gold/silver to deposit currency");
        $client->Message(315, "---");
        $client->Message(315, "**VIEWING YOUR ITEMS:**");
        my $bal_all = quest::saylink("balance", 1, "balance");
        my $bal_char = quest::saylink("show balance char", 1, "show balance char");
        my $bal_acct = quest::saylink("show balance account", 1, "show balance account");
        $client->Message(315, "- ($bal_all) - View all items");
        $client->Message(315, "- ($bal_char) - Character-only items");
        $client->Message(315, "- ($bal_acct) - Account-wide items");
        $client->Message(315, "---");
        $client->Message(315, "**WITHDRAWING:**");
        $client->Message(315, "- Click [W:1] or [W:All] links in balance view");
        $client->Message(315, "- Or say: withdraw <ItemID> [Quantity]");
        $client->Message(315, "- Example: withdraw 1001 - withdraws all of item 1001");
        $client->Message(315, "---");
        $client->Message(315, "**SEARCHING:**");
        my $search = quest::saylink("search sword", 1, "search sword");
        $client->Message(315, "- ($search) - Find items by name");
        $client->Message(315, "---");
        
        my $help_alliance = quest::saylink("help alliance", 1, "help alliance");
        $client->Message(315, "Ready to share items? Say ($help_alliance)!");
    }
    
    # ALLIANCE HELP
    elsif ($text =~ /^help alliance$/i || $text =~ /^alliance$/i) {
        $client->Message(315, "=== ALLIANCE SYSTEM ===");
        
        if (!$in_alliance) {
            $client->Message(315, "You are NOT in an alliance.");
            $client->Message(315, "---");
            $client->Message(315, "**GETTING STARTED:**");
            my $create = quest::saylink("alliance create MyAlliance", 1, "alliance create <Name>");
            $client->Message(315, "- ($create) - Create new alliance");
            $client->Message(315, "- Wait for invite, then: alliance join <Name>");
            my $status = quest::saylink("alliance status", 1, "alliance status");
            $client->Message(315, "- ($status) - Check pending invites");
        } else {
            my $status = quest::saylink("alliance status", 1, "alliance status");
            $client->Message(315, "You are in an alliance! ($status) to view members.");
        }
        
        $client->Message(315, "---");
        $client->Message(315, "**BASIC ALLIANCE COMMANDS:**");
        $client->Message(315, "- alliance create <Name> - Found new alliance");
        $client->Message(315, "- alliance join <Name> - Join (needs invite)");
        $client->Message(315, "- alliance leave - Leave current alliance");
        $client->Message(315, "- alliance status - View members & ranks");
        $client->Message(315, "- alliance decline <Name> - Reject invite");
        $client->Message(315, "---");
        $client->Message(315, "**MANAGEMENT (Officer/Owner):**");
        $client->Message(315, "- alliance invite <CharName> - Invite player");
        $client->Message(315, "- alliance kick <CharName> - Remove member");
        $client->Message(315, "- alliance promote <CharName> - Make officer");
        $client->Message(315, "- alliance demote <CharName> - Demote to member");
        $client->Message(315, "---");
        
        my $help_adv = quest::saylink("help advanced", 1, "help advanced");
        $client->Message(315, "Want to share items? Say ($help_adv)!");
    }
    
    # ADVANCED HELP
    elsif ($text =~ /^help advanced$/i) {
        $client->Message(315, "=== ADVANCED FEATURES ===");
        $client->Message(315, "---");
        $client->Message(315, "**SHARING WITH ALLIANCE:**");
        $client->Message(315, "1. Have item in Character or Account bank");
        $client->Message(315, "2. Say: alliance share <ItemID> <Qty>");
        $client->Message(315, "3. Item becomes available to all members!");
        $client->Message(315, "---");
        $client->Message(315, "**RESTRICTION SYSTEM:**");
        $client->Message(315, "- alliance restrict <ID> <Qty> - Make private");
        $client->Message(315, "- alliance unrestrict <ID> <Qty> - Make public");
        $client->Message(315, "- Click [R:1] or [U:1] links in balance view");
        $client->Message(315, "---");
        $client->Message(315, "**PLATINUM POOLS:**");
        $client->Message(315, "- platinum share alliance - Pool with alliance");
        $client->Message(315, "- platinum unshare alliance - Back to account");
        $client->Message(315, "---");
        $client->Message(315, "**TRANSFERS (Officer+):**");
        $client->Message(315, "- alliance itemtransfer <ID> <CharName>");
        $client->Message(315, "- Moves items to another member");
        $client->Message(315, "---");
        $client->Message(315, "**OWNER POWERS:**");
        $client->Message(315, "- alliance restrictall <ID> - Lock all copies");
        $client->Message(315, "- alliance unrestrictall <ID> - Override unlock");
        $client->Message(315, "- alliance transfer <Name> - Change owner");
        $client->Message(315, "- alliance disband - Destroy alliance");
        $client->Message(315, "---");
        
        my $examples = quest::saylink("help examples", 1, "help examples");
        $client->Message(315, "See ($examples) for real usage scenarios!");
    }
    
    # EXAMPLES HELP
    elsif ($text =~ /^help examples$/i) {
        $client->Message(315, "=== USAGE EXAMPLES ===");
        $client->Message(315, "---");
        $client->Message(315, "**EXAMPLE 1: Basic Deposit/Withdraw**");
        $client->Message(315, "1. Trade me 10x Bandages");
        $client->Message(315, "2. Say: balance");
        $client->Message(315, "3. Click [W:All] next to Bandages to withdraw");
        $client->Message(315, "---");
        $client->Message(315, "**EXAMPLE 2: Create Alliance**");
        $client->Message(315, "1. Say: alliance create Raiders");
        $client->Message(315, "2. Say: alliance join Raiders");
        $client->Message(315, "3. Say: alliance invite FriendName");
        $client->Message(315, "4. Friend says: alliance join Raiders");
        $client->Message(315, "---");
        $client->Message(315, "**EXAMPLE 3: Share Items**");
        $client->Message(315, "1. Deposit 20x Spider Silk (becomes Account-wide)");
        $client->Message(315, "2. Say: balance");
        $client->Message(315, "3. Click (ShareAlly) link next to Spider Silk");
        $client->Message(315, "4. All alliance members can now withdraw it!");
        $client->Message(315, "---");
        $client->Message(315, "**EXAMPLE 4: Make Items Private**");
        $client->Message(315, "1. Share 50x Bone Chips with alliance");
        $client->Message(315, "2. Change your mind? Click [R:1] to restrict 1");
        $client->Message(315, "3. Or say: alliance restrict <ItemID> 50");
        $client->Message(315, "4. Now only you can withdraw them!");
        $client->Message(315, "---");
        
        my $help = quest::saylink("help", 1, "help");
        $client->Message(315, "Return to ($help) menu anytime!");
    }
    
    # =========================================================================
    # BALANCE & SEARCH COMMANDS
    # =========================================================================
    
    elsif ($text =~ /^balance$/i || $text =~ /^show balance all$/i) {
        ShowBalance('all');
    }
    elsif ($text =~ /^show balance alliance$/i) {
        if (!$in_alliance) {
            $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
            my $help = quest::saylink("help alliance", 1, "help alliance");
            $client->Message(315, "$NPCName whispers to you, 'Say ($help) to learn about alliances!'");
        } else {
            ShowBalance('alliance');
        }
    }
    elsif ($text =~ /^show balance account$/i) {
        ShowBalance('account');
    }
    elsif ($text =~ /^show balance char$/i) {
        ShowBalance('char');
    }
    elsif ($text =~ /^search (.+)$/i) {
        my $search_term = $1;
        if (length($search_term) < 3) {
            $client->Message(315, "$NPCName whispers to you, 'Search term must be at least 3 characters.'");
        } else {
            SearchItems($search_term);
        }
    }
    
    # =========================================================================
    # WITHDRAW COMMANDS
    # =========================================================================
    
    elsif ($text =~ /^withdraw platinum (\d+)$/i) {
        WithdrawCurrency($1);
    }
    elsif ($text =~ /^withdraw (\d+) (\d+) (\d+) ([\d\-]+)$/i) {
        # withdraw <item_id> <quantity> <charges> <aug_sig>
        WithdrawItem($1, $2, $3, $4);
    }
    elsif ($text =~ /^withdraw (\d+) (\d+) (\d+)$/i) {
        WithdrawItem($1, $2, $3);
    }
    elsif ($text =~ /^withdraw (\d+) (\d+)$/i) {
        WithdrawItem($1, $2);
    }
    elsif ($text =~ /^withdraw (\d+)$/i) {
        WithdrawItem($1, 99999);
    }
    elsif ($text =~ /^withdraw$/i) {
        $client->Message(315, "$NPCName whispers to you, 'Usage: withdraw <ItemID> [Quantity]'");
        my $balance = quest::saylink("balance", 1, "balance");
        $client->Message(315, "$NPCName whispers to you, 'Say ($balance) and use the [W:1] or [W:All] links!'");
    }
    
    # =========================================================================
    # PLATINUM COMMANDS
    # =========================================================================
    
    elsif ($text =~ /^platinum share alliance$/i) {
        if (!$in_alliance) {
            $client->Message(315, "$NPCName whispers to you, 'You must be in an alliance to share platinum.'");
        } else {
            SharePlatinum('alliance');
        }
    }
    elsif ($text =~ /^platinum unshare alliance$/i) {
        if (!$in_alliance) {
            $client->Message(315, "$NPCName whispers to you, 'You are not in an alliance.'");
        } else {
            UnsharePlatinum('alliance');
        }
    }
    elsif ($text =~ /^platinum$/i) {
        $client->Message(315, "$NPCName whispers to you, 'Platinum commands:'");
        $client->Message(315, "- platinum share alliance - Pool with alliance");
        $client->Message(315, "- platinum unshare alliance - Move to account");
        $client->Message(315, "- withdraw platinum <amount> - Withdraw currency");
    }
    
    # =========================================================================
    # ALLIANCE MANAGEMENT
    # =========================================================================
    
    elsif ($text =~ /^alliance create (.+)$/i) {
        CreateAlliance($1);
    }
    elsif ($text =~ /^alliance join (.+)$/i) {
        JoinAlliance($1);
    }
    elsif ($text =~ /^alliance leave$/i) {
        LeaveAlliance();
    }
    elsif ($text =~ /^alliance status$/i) {
        AllianceStatus();
    }
    elsif ($text =~ /^alliance decline (.+)$/i) {
        DeclineInvitation($1);
    }
    elsif ($text =~ /^alliance invite (.+)$/i) {
        InviteToAlliance($1);
    }
    elsif ($text =~ /^alliance kick (.+)$/i) {
        KickFromAlliance($1);
    }
    elsif ($text =~ /^alliance promote (.+)$/i) {
        PromoteMember($1);
    }
    elsif ($text =~ /^alliance demote (.+)$/i) {
        DemoteMember($1);
    }
    elsif ($text =~ /^alliance transfer (.+)$/i) {
        TransferOwnership($1);
    }
    elsif ($text =~ /^alliance disband$/i) {
        DisbandAlliance();
    }
    
    # =========================================================================
    # ALLIANCE SHARING
    # =========================================================================
    
    elsif ($text =~ /^alliance share (\d+) (\d+) (\d+)$/i) {
        AllianceShareItem($1, $2, $3);
    }
    elsif ($text =~ /^alliance share (\d+) (\d+)$/i) {
        AllianceShareItem($1, $2);
    }
    elsif ($text =~ /^alliance unshare (\d+) (\d+) (\d+)$/i) {
        AllianceUnshareItem($1, $2, $3);
    }
    elsif ($text =~ /^alliance unshare (\d+) (\d+)$/i) {
        AllianceUnshareItem($1, $2);
    }
    
    # =========================================================================
    # ALLIANCE RESTRICTIONS
    # =========================================================================
    
    elsif ($text =~ /^alliance restrict (\d+) (\d+) (\d+) (\d+)$/i) {
        RestrictAllianceItemToCharacter($1, $2, $3, $4);
    }
    elsif ($text =~ /^alliance restrict (\d+) (\d+) (\d+)$/i) {
        RestrictAllianceItemToCharacter($1, $2, $3);
    }
    elsif ($text =~ /^alliance restrict (\d+) (\d+)$/i) {
        RestrictAllianceItem($1, $2);
    }
    elsif ($text =~ /^alliance unrestrict (\d+) (\d+) (\d+)$/i) {
        UnrestrictAllianceItem($1, $2, $3);
    }
    elsif ($text =~ /^alliance unrestrict (\d+) (\d+)$/i) {
        UnrestrictAllianceItem($1, $2);
    }
    elsif ($text =~ /^alliance restrictall (\d+) (\d+)$/i) {
        RestrictAllAllianceItemOwnerOnly($1, $2);
    }
    elsif ($text =~ /^alliance restrictall (\d+)$/i) {
        RestrictAllAllianceItemOwnerOnly($1);
    }
    elsif ($text =~ /^alliance unrestrictall (\d+) (\d+)$/i) {
        UnrestrictAllAllianceItem($1, $2);
    }
    elsif ($text =~ /^alliance unrestrictall (\d+)$/i) {
        UnrestrictAllAllianceItem($1);
    }
    
    # =========================================================================
    # ALLIANCE TRANSFERS
    # =========================================================================
    
    elsif ($text =~ /^alliance itemtransfer (\d+) (\d+) (\w+)$/i) {
        AllianceItemTransfer($1, $2, $3);
    }
    elsif ($text =~ /^alliance itemtransfer (\d+) (\w+)$/i) {
        AllianceItemTransfer($1, 0, $2);
    }
    
    # =========================================================================
    # SMART ERROR HANDLING
    # =========================================================================
    
    elsif ($text =~ /^alliance\s+/i) {
        # Unrecognized alliance command
        $client->Message(315, "$NPCName whispers to you, 'Unknown alliance command.'");
        my $help = quest::saylink("help alliance", 1, "help alliance");
        $client->Message(315, "$NPCName whispers to you, 'Say ($help) for available commands.'");
    }
    elsif ($text =~ /^help\s+/i) {
        # Unrecognized help topic
        $client->Message(315, "$NPCName whispers to you, 'Unknown help topic.'");
        my $help = quest::saylink("help", 1, "help");
        $client->Message(315, "$NPCName whispers to you, 'Say ($help) to see all topics.'");
    }
    else {
        # Completely unrecognized command
        if (length($text) > 2 && $text !~ /^(hail,?\s|hi|hello|hey)/i) {
            my $help = quest::saylink("help", 1, "help");
            my $balance = quest::saylink("balance", 1, "balance");
            $client->Message(315, "$NPCName whispers to you, 'I don't understand that command.'");
            $client->Message(315, "$NPCName whispers to you, 'Try ($help) or ($balance).'");
        }
    }
}

