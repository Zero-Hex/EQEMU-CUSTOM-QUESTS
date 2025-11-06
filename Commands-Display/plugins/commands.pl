# player.pl

use warnings; 

# --- Custom Command Data: Global Hash ---
%CUSTOM_COMMANDS = (
    '#create' => {
        description => 'Creates a New Dynamic Zone Instance usage.',
        syntax      => '#create type [solo/group/raid/guild/special zonename]',
    },
    '#enter' => {
        description => 'Allows the player to enter a dynamic zone instance.',
        syntax      => '#enter',
    },
    '#tp' => {
        description => 'Looks up a zone shortname or teleports you to a public zone using the shortname.',
        syntax      => '#tp xyz (to search) or #tp shortname ',
    },
    '!auction' => {
        description => 'Opens the GM auction house menu',
        syntax      => '!auction',
    },
    '!parcel' => {
        description => 'Checks and manages your in-game mail or delivery parcels.',
        syntax      => '!parcel',
    },
    '!buff' => {
        description => 'Clicks all the items in your buff bag. Buff bag is required.',
        syntax      => '!buff',
    },
    '!pull' => {
        description => 'Places a Riposte and DS Debuff on you to allow easy pulling. 30 Second Cooldown',
        syntax      => '!pull',
    },
    '!command' => {
        description => 'Brings up this screen',
        syntax      => '!command',
    },
    '!petequip' => {
        description => 'Requires a pet bag with items in it. Adds items to the pet. Does not work with charmed pets.',
        syntax      => '!petequip',
    },
    '#petitems' => {
        description => 'Displays what items your pet has in its inventory. Only reliable after a zone.',
        syntax      => '#petitems',
    },
);

# -----------------------------------------------------------------

# --- EVENT HANDLER: Uses global $client and $text directly ---

# -----------------------------------------------------------------

# --- Function to Generate and Display the Command List as a DiaWind ---
sub display_command_list_popup {
    my ($player) = @_;
    
    my $content = "";

    # 1. Title: Use {lb} color and HTML <br> for line breaks
    $content .= "{lb}--- Custom Server Commands ---<br><br>";

    # 2. Build the content string using correct tags and <br>
    foreach my $command (sort keys %CUSTOM_COMMANDS) {
        my $desc = $CUSTOM_COMMANDS{$command}->{description};
        my $syntax = $CUSTOM_COMMANDS{$command}->{syntax};

        # Format: {lb}!command{r} (Syntax: ...)<br>{in}{y}Description<br>
        $content .= sprintf(
            "{lb}%s {r}(Syntax: %s)<br>{in}{y}%s<br>", 
            $command, 
            $syntax, 
            $desc
        );
        # Add an extra line break for visual separation between commands
        $content .= "<br>"; 
    }
    
    # 3. Send the output using the DiaWind method
    # NOTE: We can now add the ~ (End Color Tag) at the very end to clean up
    # any open color codes, although the plugin may handle this.
    $player->DiaWind($content . "~" );
    
    # Optional: Log the action
    if (defined $player->can('log_action')) {
        $player->log_action("Requested custom command list.");
    }
}

1;