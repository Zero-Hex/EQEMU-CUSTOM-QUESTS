# Filename: global_player.pl
# Location: [EQEMU_Root]/quests/global/
# Authored by Zerohex
# =========================================================================
# Buff Bag Controls
# -----------------------------------------------------------------------------
## Event Handler (Timer Completion Logic)
# -----------------------------------------------------------------------------
sub EVENT_TIMER {
    # Autobuff Logic
    # ____________________________________________________________
    plugin::AutoBuff_HandleTimer($client, $timer);
    return 1;
    # ____________________________________________________________
}
sub EVENT_SAY {
    if ($text eq "!buff") {
        # Calls the function in the updated autobuff.pl file
        plugin::AutoBuff_HandleCommand($client, "!buff", ""); 
        return; 
    }
}

