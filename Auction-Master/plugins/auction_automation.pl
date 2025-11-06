package auction_automation;
#Authored by Zerohex
# Note: This package must be included in your server's plugin manager (plugins/plugins.conf) 

# Constants (Must match constants in auction.pl)
my $CURRENCY_ITEM_ID = 147623; 
my $AUCTION_LIST_KEY = "AUCTION_LIST_NAMES"; 
my $AUCTION_TIMEOUT_DAYS = 90; 
my $DEFAULT_MIN_INCREMENT = 1; 
my $STATIC_BUY_IT_NOW_PRICE = 350;

# --- Utility Functions ---

sub GetCurrencyName {
    return quest::getitemname($CURRENCY_ITEM_ID);
}

sub GetAuctionDataKey {
    my $auction_name = shift;
    return "auction\_$auction_name";
}

sub UpdateActiveAuctionList {
    my ($auction_name, $add) = @_;
    
    my $current_list_string = quest::get_data($AUCTION_LIST_KEY) || "";
    my @current_list = split /:/, $current_list_string;
    
    @current_list = grep { $_ ne $auction_name && $_ ne '' } @current_list;
    
    if ($add) {
        push @current_list, $auction_name;
    }
    
    my $new_list_string = join(':', @current_list);
    
    if ($new_list_string) {
        quest::set_data($AUCTION_LIST_KEY, $new_list_string, $AUCTION_TIMEOUT_DAYS * 86400);
    } else {
        quest::delete_data($AUCTION_LIST_KEY);
    }
}

# -------------------------------------------------------------------------------------------------
# AUTOMATED AUCTION LOGIC
# -------------------------------------------------------------------------------------------------

my @AUTOMATION_ITEMS = (
    147624, # Ancient Zweihander
    147626, # Igris Sword (Solo Leveling)
    147625, # Demonic Plum Flower Sword
    147628, # Gorestriker
    147630, # Moonshadow
    147632, # Fist of Pahoehoe
    147507, # Windforce
    147633, # Orb of Avarice
    101370, # Kerafyrm's Blessed Stone
    147497, # Psionic's Ring
    147496, # Nature's Ring
    147500 # Lionheart's Ring
);

sub GetRandomElement {
    my $array_ref = shift;
    return $array_ref->[int(rand(scalar @$array_ref))];
}

sub RunAutomatedAuctionCheck {
    my $max_auctions_to_start = 2; # Max number of concurrent automated auctions
    my $current_time = time();
    my $active_auctions_string = quest::get_data($AUCTION_LIST_KEY) || "";
    my @active_auctions = split /:/, $active_auctions_string;
    
    my @valid_auctions = grep { $_ ne '' && $_ !~ /^auto\_/ } @active_auctions;
    my $current_auction_count = scalar @valid_auctions;

    my $auctions_to_start = $max_auctions_to_start - $current_auction_count;
    
    quest::log(5, "AUTOMATED AUCTION CHECK: Active: $current_auction_count. Starting $auctions_to_start new auctions.");

    for (my $i = 0; $i < $auctions_to_start; $i++) {
        
        if (scalar @AUTOMATION_ITEMS == 0) {
            quest::log(5, "AUTOMATED AUCTION ERROR: No items defined in \@AUTOMATION\_ITEMS array.");
            return;
        }
        
        my $item_id = GetRandomElement(\@AUTOMATION_ITEMS);
        
        my $hours = int(rand(25)) + 12; 
        my $min_bid = int(rand(5)) + 1;
        
        # FIX: Simplified and more friendly auction name generation.
        my $unique_suffix = int(rand(9000)) + 1000; 
        my $auction_name = "auto\_$item_id\_$unique_suffix"; 
        
        my $end_time = $current_time + ($hours * 3600);
        
        my $bin_price = $STATIC_BUY_IT_NOW_PRICE;
        
        # Auction Data: item_id|end_time|current_bid|current_winner_id|gm_name|min_bid|set_increment|bin_price
        my $auction_data = "$item_id|$end_time|0|0|AUTOMATION|$min_bid|$DEFAULT_MIN_INCREMENT|$bin_price"; 
        my $item_link = quest::varlink($item_id);
        
        my $auction_key = GetAuctionDataKey($auction_name); 
        
        if (quest::get_data($auction_key)) {
             quest::log(5, "AUTOMATED AUCTION ERROR: Generated key $auction_name already exists. Skipping this auction run.");
             next;
        }

        quest::set_data($auction_key, $auction_data, $AUCTION_TIMEOUT_DAYS * 86400); 
        UpdateActiveAuctionList($auction_name, 1);
        
        quest::worldwidemessage(261, "A new **Automated Auction** has started for $item_link! Min bid: $min_bid " . GetCurrencyName() . ". BIN: $bin_price " . GetCurrencyName() . ". Ends in $hours hours.");
        quest::log(5, "AUTOMATED AUCTION: Started $auction_name (Item: $item_id) for $hours hours. BIN: $bin_price.");
    }
}

1;