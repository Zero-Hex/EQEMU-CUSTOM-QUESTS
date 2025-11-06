sub EVENT_SAY {
# !command / !commands
    if ($text eq "!command" || $text eq "!commands") {
        plugin::display_command_list_popup($client); 
        return 1;
    }
   
}