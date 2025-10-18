# Filename: autobuff.pl
# Location: [EQEMU_Root]/quests/plugins/
# Authored by Zerohex
# =========================================================================
# Buff Bag Controls
# =========================================================================
# --- CONFIGURATION ---
my $BAG_ITEM_ID          = 124497; # The Item ID of your buff bag container.
my $TRIGGER_COMMAND      = "!buff";  # NEW: The chat command the player types to trigger this script.
my $MINIMUM_COOLDOWN     = 0;      # Minimum delay between uses (in seconds).

my $ENABLE_DYNAMIC_COOLDOWN = 0;  #This will look at the items it is casting and find the item with the longest cooldown and use that as the cooldown amount after casting. This also enables casting items with a cooldown timer on them.
my $ENABLE_CAST_TIMER       = 0;  #This will  look at the items and find the one with the longest cast time and use it as a cast timer amount for the buffs

# Set to 1 for debugging messages, 0 for silent operation.
my $ENABLE_DEBUG_MESSAGES    = 0; 
# Set to 1 to display ALL non-error messages (warnings, casting, success). Set to 0 to hide them.
my $INFO_TOGGLE            = 1; 

my $COOLDOWN_BUCKET_KEY  = "auto_buff_cd";     
my $CAST_BUCKET_KEY      = "auto_buff_cast";   

my $EQUIP_CLICK_TYPE     = 5; # Don't Change this Value
my $INVENTORY_CLICK_TYPE = 1; # Don't Change this Value
my $ENABLE_EQUIPPED_ITEMS = 1; # This will toggle casting equipped items or not.

my %ITEM_ID_TO_SPELL_MAP = ();
my %ITEM_BLACKLIST       = ();
# Add items here that you DO NOT want to be clicked automatically.
# Example: ( 12345 => 1, 67890 => 1 )
# --- END CONFIGURATION ---

# -----------------------------------------------------------------------------
# CORE LOGIC SUBROUTINES
# -----------------------------------------------------------------------------
sub CastBuffs {
    my ($client, $buffs_ref) = @_;
    my @buffs = @$buffs_ref;

    if ($INFO_TOGGLE) { 
        $client->Message(3, "AUTO-BUFF: Casting " . scalar @buffs . " eligible spell(s)...");
    }
    
    my $buffs_cast = 0;
    
    # --- Pet Handling Setup ---
    my $pcpet;
    
  
    if ($client->GetPetID() && defined $entity_list) {
        # The correct method name is GetMobByID
        $pcpet = $entity_list->GetMobByID($client->GetPetID()); 
    }
    # --- End Pet Handling Setup ---

    foreach my $spell_id (@buffs) {
        
        # A. Player Buff (Casting on self)
        quest::selfcast($spell_id);
        
        # B. Pet Buff (Casting on Pet)
        # Check that the pet object was successfully found
        if (defined $pcpet) { 
            $client->CastSpell($spell_id, $pcpet->GetID(), 0); 
        }
        
        $buffs_cast++;
    }
    
    if ($INFO_TOGGLE) { 
        $client->Message(2, "SUCCESS: Completed $buffs_cast buff(s).");
    }
}

# Core Logic Function (ExecuteInstantBuffs) 
sub ExecuteInstantBuffs {
    my $client = shift;
    my $bag_item_instance;
    
    my $longest_recast_seconds = 0; 
    my $longest_cast_ms        = 0; 
    
    my $client_class_id = $client->GetClass();
    my $client_bitmask  = 1 << ($client_class_id - 1); 
    
    my @buff_candidates = ();
    
    # --- 1. SEARCH FOR BUFF BAG CONTAINER ---
    # Slots 23-32 (Inventory), 2000-2023 (Bank/Shared Bank)
    my @bag_search_slots = (23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023);
    
    foreach my $bag_slot (@bag_search_slots) {
        my $current_item = $client->GetItemAt($bag_slot);
        if ($current_item && $current_item->GetItem() && $current_item->GetItem()->GetID() == $BAG_ITEM_ID) {
            $bag_item_instance = $current_item;
            last;
        }
    }

    if ($bag_item_instance) {
        # --- 2. PROCESS ITEMS INSIDE THE FOUND BAG ---
        my $num_slots = $bag_item_instance->GetItem()->GetBagSlots(); 
        if ($INFO_TOGGLE) { 
            $client->Message(3, "AUTO-BUFF: Buff Bag found. Checking " . $num_slots . " item slot(s)...");
        }
        for (my $inner_slot = 0; $inner_slot < $num_slots; $inner_slot++) {
            my $buff_item_instance = $bag_item_instance->GetItem($inner_slot); 
            if ($buff_item_instance) {
                 push(@buff_candidates, $buff_item_instance);
            }
        }
    }
    
    # --- 3. PROCESS EQUIPPED ITEMS (Slots 0-22) IF TOGGLE IS ON ---
    # This is now an independent 'if' block to check equipped items *in addition* to bag items.
    if ($ENABLE_EQUIPPED_ITEMS) { 
        my @equipped_slots = (0..22);
        if ($INFO_TOGGLE) { 
            # Customize message based on whether the bag was found.
            my $message_prefix = $bag_item_instance ? "AUTO-BUFF: Also checking" : "AUTO-BUFF: Buff Bag not found, checking";
            $client->Message(3, "$message_prefix " . scalar @equipped_slots . " equipped item slot(s).");
        }
        foreach my $equip_slot (@equipped_slots) {
            my $equipped_item = $client->GetItemAt($equip_slot);
            if ($equipped_item) {
                push(@buff_candidates, $equipped_item);
            }
        }
    } 

    # --- 4. NO BUFF SOURCE CHECK (EXIT CONDITION) ---
    if (!@buff_candidates) {
        # Exit with a specific error if neither buff source was found/enabled
        if (!$bag_item_instance && !$ENABLE_EQUIPPED_ITEMS) {
             $client->Message(13, "AUTO-BUFF ERROR: Buff Bag (ID $BAG_ITEM_ID) not found and Equipped Item check is disabled.");
        } elsif ($INFO_TOGGLE) { 
            # Exit if sources were checked but contained no valid items.
            $client->Message(5, "AUTO-BUFF: No castable, eligible buffs found in the buff source(s).");
        }
        return (0, 0, []); 
    }
    
    # --- 5. FILTER AND COLLECT BUFF SPELLS ---
    my @buffs = ();
    
    foreach my $buff_item_instance (@buff_candidates) {
        if (!$buff_item_instance) { next; } 
        
        my $item_data = $buff_item_instance->GetItem();
        if (!defined($item_data)) { next; }
        
        my $item_id          = $item_data->GetID();
        my $item_name        = quest::getitemname($item_id); 
        my $default_spell_id = $item_data->GetClickEffect();
        my $item_charges     = $buff_item_instance->GetCharges(); 
        my $item_classes_mask = $item_data->GetClasses();
        my $item_click_type   = $item_data->GetClickType();

        my $spell_id = $default_spell_id;
        my $eligible = 1; 

        if ($spell_id <= 0) { $eligible = 0; }
        if (exists $ITEM_ID_TO_SPELL_MAP{$item_id}) { $spell_id = $ITEM_ID_TO_SPELL_MAP{$item_id}; }
        if ($eligible && $spell_id <= 0) { $eligible = 0; }
        
        # BLACKLIST CHECK
        if ($eligible && exists $ITEM_BLACKLIST{$item_id}) {
            if ($INFO_TOGGLE) { 
                $client->Message(14, "AUTO-BUFF WARNING: Skipping item $item_name. Item is blacklisted.");
            }
            $eligible = 0;
        }
        
        # --- FINAL BUFF CHECK: quest::IsBuffSpell() ---
        if ($eligible) {
            if ($ENABLE_DEBUG_MESSAGES) {
                my $is_buff = quest::IsBuffSpell($spell_id) ? "True" : "False";
                $client->Message(15, "DEBUG: Item $item_name (Spell $spell_id) - IsBuffSpell: $is_buff.");
            }
            
            if (!quest::IsBuffSpell($spell_id)) {
                if ($INFO_TOGGLE) { 
                    $client->Message(14, "AUTO-BUFF WARNING: Skipping item $item_name. Spell ID $spell_id is not a long-term buff spell.");
                }
                $eligible = 0;
            }
        }
        
        # --- Secondary Filter (Excludes Detrimental Spells) ---
        if ($eligible && $spell_id > 0 && quest::IsDetrimentalSpell($spell_id)) { 
            if ($INFO_TOGGLE) { 
                $client->Message(14, "AUTO-BUFF WARNING: Skipping item $item_name. Spell ID $spell_id failed the IsDetrimentalSpell check.");
            }
            $eligible = 0; 
        }
        
        # --- Existing Filtering ---
        # Classes Check
        if ($eligible && $item_click_type == $EQUIP_CLICK_TYPE) { 
            if ($item_classes_mask != 65535 && !($item_classes_mask & $client_bitmask)) { 
                if ($INFO_TOGGLE) { 
                    $client->Message(14, "AUTO-BUFF WARNING: Skipping item $item_name. Class is not eligible to click this item.");
                }
                $eligible = 0; 
            }
        }
        
        # Charges Check
        if ($eligible && $item_charges != -1 && $item_charges != 1) { 
            if ($INFO_TOGGLE) { 
                $client->Message(14, "AUTO-BUFF WARNING: Skipping item $item_name. Item has multiple charges. Only unlimited or 1-charge items supported.");
            }
            $eligible = 0; 
        }
        
        my $item_recast = quest::getitemstat($item_id, "recastdelay") || 0;
        my $item_recast_time = quest::getitemstat($item_id, "recasttime") || 0;
        my $item_click_cast_time = quest::getitemstat($item_id, "casttime") || 0;
        my $item_casttime = ($item_recast_time > $item_click_cast_time) ? $item_recast_time : $item_click_cast_time;

        if ($item_casttime >= 60000 && $item_casttime % 60 == 0) {
             $item_casttime = $item_casttime / 60;
        }

        if ($item_recast > 0 && !$ENABLE_DYNAMIC_COOLDOWN) {
            if ($INFO_TOGGLE) { 
                $client->Message(14, "AUTO-BUFF WARNING: Skipping item $item_name. It has a recast delay but dynamic cooldown is disabled.");
            }
            $eligible = 0;
        }
        
        if ($eligible) { 
            push(@buffs, $spell_id); 
            if ($ENABLE_DYNAMIC_COOLDOWN && $item_recast > $longest_recast_seconds) {
                $longest_recast_seconds = $item_recast;
            }
            if ($ENABLE_CAST_TIMER && $item_casttime > $longest_cast_ms) {
                $longest_cast_ms = $item_casttime;
            }
        }
    }

    if (!@buffs) {
        if ($INFO_TOGGLE) { 
            $client->Message(5, "AUTO-BUFF: No castable, eligible buffs found in the buff source(s).");
        }
        return (0, 0, []); 
    }
    
    return ($longest_recast_seconds, $longest_cast_ms, \@buffs); 
}

# -----------------------------------------------------------------------------
## EXPORTED: Logic for EVENT_COMMAND (Replaces EVENT_CAST)
# -----------------------------------------------------------------------------
sub AutoBuff_HandleCommand {
    # Arguments now accept ($client, $command, $arguments) from EVENT_SAY
    my ($client, $command, $arguments) = @_; 
    
    if ($command ne $TRIGGER_COMMAND) {
        return 0; 
    }
    
    my $character_id = $client->CharacterID();
    my $cooldown_bucket_key = $COOLDOWN_BUCKET_KEY . "_" . $character_id; 
    my $cast_bucket_key     = $CAST_BUCKET_KEY . "_" . $character_id; 
    my $current_time = time(); 
    
    my $last_used = $client->GetBucket($cooldown_bucket_key) || 0; 
    my $effective_cooldown = $MINIMUM_COOLDOWN; 
    
    # 1. CHECK COOLDOWN
    if (($current_time - $last_used) < $effective_cooldown) {
        if ($INFO_TOGGLE) { 
            my $time_left = $effective_cooldown - ($current_time - $last_used);
            $client->Message(13, "You must wait $time_left second(s) before using this auto-buff again.");
        }
        return 1; 
    }
    
    # 2. CHECK FOR ACTIVE CAST
    if (quest::get_data($cast_bucket_key)) { 
        if ($INFO_TOGGLE) { 
            $client->Message(13, "System is already processing a buff sequence. Please wait.");
        }
        return 1;
    }
    
    # 3. EXECUTE BUFFS logic to get cooldown/cast time/spell list
    my ($required_cooldown, $required_cast_ms, $buffs_ref) = ExecuteInstantBuffs($client); 

    if (!@$buffs_ref) {
        return 1; 
    }
    
    my $required_cast_seconds = int(($required_cast_ms + 999) / 1000); 
    
    if ($ENABLE_CAST_TIMER && $required_cast_seconds > 0) {
        # --- CAST TIMER ENABLED ---
        
        quest::stoptimer($cast_bucket_key); 
        my $buff_string = join(',', @$buffs_ref);
        quest::set_data($cast_bucket_key, $buff_string); 
        
        if ($INFO_TOGGLE) { 
            $client->Message(3, "Beginning cast time for buffs: $required_cast_seconds seconds...");
        }
        quest::settimer($cast_bucket_key, $required_cast_seconds); 
        
    } else {
        # --- INSTANT CAST ---
        CastBuffs($client, $buffs_ref); 
        if ($required_cooldown > 0) {
            $effective_cooldown = $required_cooldown;
            $client->SetBucket($cooldown_bucket_key, $current_time + $effective_cooldown); 
            if ($INFO_TOGGLE) { 
                $client->Message(3, "Auto-buff reuse set to $effective_cooldown seconds (based on item recast).");
            }
        } 
    }
    
    return 1; 
}

# -----------------------------------------------------------------------------
## EXPORTED: Logic for EVENT_TIMER (Kept unchanged)
# -----------------------------------------------------------------------------
sub AutoBuff_HandleTimer {
    my ($client, $timer_name) = @_;
    
    my $character_id = $client->CharacterID();
    my $cast_bucket_key = $CAST_BUCKET_KEY . "_" . $character_id; 
    
    my $buff_string = quest::get_data($cast_bucket_key) || ""; 

    if ($buff_string && $timer_name eq $cast_bucket_key) { 
        
        quest::stoptimer($cast_bucket_key);
        quest::delete_data($cast_bucket_key); 
        
        my @buffs = split(',', $buff_string);
        CastBuffs($client, \@buffs);
        
        if ($ENABLE_DYNAMIC_COOLDOWN) {
            my ($required_cooldown, undef, undef) = ExecuteInstantBuffs($client); 
            if ($required_cooldown > 0) {
                my $cooldown_bucket_key = $COOLDOWN_BUCKET_KEY . "_" . $character_id; 
                my $current_time = time();
                $client->SetBucket($cooldown_bucket_key, $current_time + $required_cooldown); 
                if ($INFO_TOGGLE) { 
                    $client->Message(3, "Item reuse set to $required_cooldown seconds (based on item recast).");
                }
            }
        }
    } 
    
    if ($timer_name eq $cast_bucket_key) {
        quest::stoptimer($cast_bucket_key);
    }
    return 1;
}

# Required for a Perl module/plugin
1;