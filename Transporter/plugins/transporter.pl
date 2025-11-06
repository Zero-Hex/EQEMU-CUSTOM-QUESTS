# ==========================================================
# Dynamic Zone Instancing Plugin (DynamicZoneCommands.pl)
# FINAL VERSION with Standardized Special Zone Name
# ==========================================================

# --- I. CONFIGURATION ---

# Max Expansion ID for zones that can be instanced.
my $MaxExpansionAllowed = 4;

# --- BLOCKED ZONES CONFIGURATION ---
my @BlockedZones = (
    "potimea",
    "potimeb"
);
# -----------------------------------

# --- SPECIAL LOCKOUT ZONES CONFIGURATION ---
my @SpecialLockoutZones = (
    "sleeper" # Sleeper's Tomb: 1 dynamic instance per 23 hours
);
# -------------------------------------------

# --- INSTANCE TOGGLES ---
my $EnableSolo = 1;
my $EnableRaid = 1;
my $EnableGroup = 1;
my $EnableGuild = 1;

# --- COOLDOWNS (in seconds) ---
my $CooldownSoloSeconds = 1800;   # 30 Minutes
my $CooldownRaidSeconds = 3600;  # 1 Hour
my $CooldownGuildSeconds = 7200; # 2 Hours
my $CooldownGroupSeconds = 1800; # 30 Minutes

# Custom 23-hour (82800 seconds) cooldown for zones in @SpecialLockoutZones
my $CooldownSpecialZoneSeconds = 82800; # 23 Hours (24 hours - 1 hour grace)

# --- INSTANCE DURATION (in seconds) ---
my $InstanceDurationSeconds = 14400; # 4 hours

# --- SPECIAL ZONE INSTANCE DURATION (in seconds) ---
# Custom 22-hour duration (79200 seconds) for zones in @SpecialLockoutZones (e.g., Sleeper's Tomb)
my $InstanceSpecialZoneDurationSeconds = 79200; # 22 hours (22 * 3600 seconds)

# --- LOCKOUT CATEGORY CONSTANT ---
my $LockoutCategory = "DZ_LOCKED_CONTENT";


# ==========================================================
# II. EVENT COMMAND REGISTRATION
# ==========================================================
sub EVENT_COMMAND {
    my $client = plugin::get_client_by_name($name);
    my ($command, @args) = split(/\s+/, $text);
    
    if ($command eq '#create') {
        plugin::HandleCreateCommand($client, @args);
        return 1;
    } elsif ($command eq '#enter') {
        plugin::HandleEnterCommand($client);
        return 1;
    } 
    return 0; 
}


# ==========================================================
# III. COMMAND HANDLERS
# ==========================================================

sub HandleCreateCommand {
    my ($client, $type, $zonename) = @_;

    # 1. Parse Input and Syntax Check
    if (!$type || !$zonename) {
        $client->Message(15, "USAGE: \#create solo|group|raid|guild|special zonename");
        return;
    }
    
    $type = lc($type);
    $zonename = lc($zonename);

    # Get client data
    my $charname = $client->GetName();
    $charname =~ s/\s//g; 
    $charname = lc($charname);
    my $char_id = quest::getcharidbyname($charname);
    my $group_id = quest::getgroupidbycharid($char_id);
    my $group_sanity = $client->IsGrouped();
    my $raid_id = quest::getraididbycharid($char_id);
    
    # 2. Get Config and Build Conditional Key
    my ($cooldown_key, $cooldown_time, $enabled) = (undef, 0, 0);
    my $is_special_lockout = grep { $_ eq $zonename } @SpecialLockoutZones;
    my $expedition_type = $type; 
    
    if ($type eq 'special') {
        if (!$is_special_lockout) {
            $client->Message(15, "ERROR: The zone '$zonename' is not configured for a special instance.");
            return;
        }
        
        # Determine the actual expedition type (solo, group, or raid) based on player status
        if ($raid_id != 0) {
            $expedition_type = 'raid';
        } elsif ($group_sanity == 1) {
            $expedition_type = 'group';
        } else {
            $expedition_type = 'solo';
        }
        
        # For AddReplayLockout, the key is the zone name, and the category is hardcoded by the server.
        $cooldown_key = $zonename; 
        $cooldown_time = $CooldownSpecialZoneSeconds;
        $enabled = 1; 

    }
    # Standard Zone Logic 
    elsif (!$is_special_lockout) {
        if ($type eq 'solo' && $group_sanity == 0) {
            $cooldown_key = $charname . "_solo_" . $zonename;
            $cooldown_time = $CooldownSoloSeconds;
            $enabled = $EnableSolo;
        } elsif ($type eq 'raid' && $raid_id != 0) {
            $cooldown_key = $raid_id . "_raid_" . $zonename;
            $cooldown_time = $CooldownRaidSeconds;
            $enabled = $EnableRaid;
        } elsif ($type eq 'group' && $group_sanity == 1) {
            $cooldown_key = $group_id . "_group_" . $zonename;
            $cooldown_time = $CooldownGroupSeconds;
            $enabled = $EnableGroup;
        } elsif ($type eq 'guild' && $client->IsInAGuild() == 1) {
            $cooldown_key = $charname . "_guild_" . $zonename;
            $cooldown_time = $CooldownGuildSeconds;
            $enabled = $EnableGuild;
        } elsif ($type eq 'raid' && $raid_id == 0) {
            $client->Message(15, "You must be apart of a valid raid to request an instance.");
            return;
        } elsif ($type eq 'group' && $group_sanity == 0) {
            $client->Message(15, "You must be apart of a valid group to request an instance.");
            return;
        } elsif ($type eq 'guild' && $client->IsInAGuild() == 0) {
            $client->Message(15, "You must be apart of a valid Guild to request an instance.");
            return;
        } elsif ($type eq 'solo' && $group_sanity == 1) {
            $client->Message(15, "You must be alone to create a solo instance.");
            return;
        } else {
            $client->Message(15, "ERROR: Invalid instance type. Choose solo, group, guild, or raid.");
            return;
        }
    } else {
        $client->Message(15, "ERROR: The zone '$zonename' is a special zone and must be created using the **\#create special $zonename** command.");
        return;
    } 
    
    if (!$is_special_lockout && !$enabled) {
        $client->Message(15, uc($type) . " instances are currently disabled by server policy.");
        return;
    }

    # 3. Zone and Expansion Eligibility Check
    my $zone_id = quest::GetZoneID($zonename);
    
    if ($zone_id == 0) {
        $client->Message(15, "ERROR: Unknown zone name '$zonename'.");
        return;
    }

    if (grep { $_ eq $zonename } @BlockedZones) {
        $client->Message(15, "ERROR: The zone '$zonename' is explicitly blocked and cannot be instanced.");
        return;
    }

    my $expansion_id = quest::GetZoneExpansion($zone_id); 
    if ($expansion_id > $MaxExpansionAllowed) {
        $client->Message(15, "ERROR: This zone belongs to Expansion $expansion_id. Dynamic zones are only allowed up to Expansion $MaxExpansionAllowed.");
        return;
    }
    
    # 4. Check Cooldown/Lockout 
    if ($is_special_lockout) {
        # Check lockout using the hardcoded Replay Timer category
        if ($client->HasExpeditionLockout($cooldown_key, "Replay Timer")) { 
            $client->Message(15, "You are currently on a **23-hour lockout** for the special instance of $zonename. Please check your timers (Replay Timer category).");
            return;
        }
    } else {
        # Standard zone lockout check
        if ($client->HasExpeditionLockout($cooldown_key, $LockoutCategory)) { 
            $client->Message(15, "You are currently on cooldown for a $type instance of $zonename. Please check your timers.");
            return;
        }
    }
    
    # 5. Create Dynamic Zone and Apply Lockout
    
    # --- MODIFIED: Standardize Expedition Name for Special Zones ---
    my $expedition_name = "";
    if ($is_special_lockout) {
        # Fixed name for special zones, regardless of player status (solo/group/raid)
        $expedition_name = "DZ_SPECIAL_$zonename"; 
    } else {
        # Keep standard naming for solo/group/raid/guild types.
        $expedition_name = "DZ_" . uc($expedition_type) . "_$zonename"; 
    }
    # -----------------------------------------------------------------
    
    # --- FIX: Determine the instance duration based on zone type ---
    my $duration_to_use = $InstanceDurationSeconds;
    if ($is_special_lockout) {
        $duration_to_use = $InstanceSpecialZoneDurationSeconds;
        $client->Message(15, "NOTE: Creating special instance with a duration of " . ($duration_to_use / 3600) . " hours.");
    }
    # ---------------------------------------------------------------

    my $zone_version = 0; 
    my $disable_messages = 0;
    
    my $min_p = 1; 
    my $max_p = 72; 
    
    # Override for Standard Solo to enforce only 1 member
    if (!$is_special_lockout && $type eq 'solo') {
        $max_p = 1;
    }

    # *** FIXED LINE: Use $duration_to_use for the duration parameter ***
    my $expedition = $client->CreateExpedition($zonename, $zone_version, $duration_to_use, $expedition_name, $min_p, $max_p, $disable_messages);
    
    if ($expedition) {
        
        # --- LOCKOUT LOGIC ---
        if ($is_special_lockout) {
            # Use the built-in AddReplayLockout for automatic propagation
            $expedition->AddReplayLockout($cooldown_time); 
            $client->Message(15, "**SPECIAL LOCKOUT:** A 23-hour Replay Timer has been set on the expedition.");
            $client->Message(15, "All members, including those added via /dzadd, will receive this lockout.");
            
        } elsif ($type eq 'solo' || $type eq 'raid' || $type eq 'group' || $type eq 'guild') {
            # Standard Zone Lockout: Apply the standard lockout based on the creation type.
            $client->AddExpeditionLockoutDuration($cooldown_key, $LockoutCategory, $cooldown_time);
        }
        # -----------------------------
        
        $client->Message(15, "SUCCESS: Your $expedition_type instance of $zonename has been created with the name **$expedition_name**.");
        $client->Message(15, "Use \#enter to zone in.");
        
    } else {
        $client->Message(15, "ERROR: Could not create the instance.");
    }
}


sub HandleEnterCommand {
    my ($client) = @_;
    
    my $expedition = $client->GetExpedition();

    if ($expedition) {
        my $zone_short_name = $expedition->GetZoneName();
        my $instance_id = $expedition->GetInstanceID();
        $client->MoveZoneInstance($instance_id);
        
        $client->Message(15, "Zoning into your active dynamic zone ($zone_short_name - Instance $instance_id)...");
    } else {
        $client->Message(15, "ERROR: No active dynamic zone instance found.");
        $client->Message(15, "Use \#create solo|raid|group|special zonename to request one.");
    }
}

# ==========================================================
# IV. EXPEDITION EVENT HANDLERS
# ==========================================================
# No custom handlers needed.

# ==========================================================
# V. OTHER EVENTS
# ==========================================================

sub EVENT_RELOAD {
    # No action needed.
}

# ==========================================================
# END OF PLUGIN
# ==========================================================