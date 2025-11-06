# Filename: scribe_npc.pl (Example file name)
# Description: Triggers the AutoScribe plugin to scribe all available spells,
#              using a stable bitmask check for caster classes.
# =========================================================================

# Define the bitmask values for all spellcaster classes
# 1: Warrior    # 2: Cleric     # 4: Paladin    # 8: Ranger
# 16: Shadowknight # 32: Druid      # 64: Monk     # 128: Bard
# 256: Rogue    # 512: Shaman     # 1024: Necromancer # 2048: Wizard
# 4096: Magician # 8192: Enchanter  # 16384: Beastlord # 32768: Berserker
my $CASTER_MASK = 
      2      # Cleric (Full Caster)
    | 4      # Paladin (Hybrid Caster)
    | 8      # Ranger (Hybrid Caster)
    | 16     # Shadowknight (Hybrid Caster)
    | 32     # Druid (Full Caster)
    | 128    # Bard (Hybrid Caster - Has Songs)
    | 512    # Shaman (Full Caster)
    | 1024   # Necromancer (Full Caster)
    | 2048   # Wizard (Full Caster)
    | 4096   # Magician (Full Caster)
    | 8192   # Enchanter (Full Caster)
    | 16384; # Beastlord (Hybrid Caster)
    
sub EVENT_SAY {
    my $client = $client;
    my $text = $text;
    
    # Get the client's class bitmask
    my $class_bitmask = $client->GetClassBitmask();

    # ---------------------------------------------------------------------
    # OPTION 1: Trigger on a specific keyword (e.g., "scribe")
    # ---------------------------------------------------------------------
    if ($text =~ /scribe/i) {
        
        # Check if the client's class bitmask intersects with our CASTER_MASK
        if ($class_bitmask & $CASTER_MASK) {
            $client->Message(15, "Greetings, $name. I shall now scribe all known spells up to your current level.");
            
            # Call the stable, database-driven plugin function
            # NOTE: We are using the correct signature here: AutoScribe::ScribeClassSpells($client)
            AutoScribe::ScribeClassSpells($client);
        } else {
            $client->Message(15, "Young fighter, I am the greatest spell scribe Norrath has ever seen--I do not waste my time on brutes like you!");
        }
        return;
    }
    
    # ---------------------------------------------------------------------
    # OPTION 2: Default response if no keyword is used
    # ---------------------------------------------------------------------
    else {
        $client->Message(15, "I am the Spellmaster. If you require my services, just say 'scribe' to me.");
        return;
    }
}