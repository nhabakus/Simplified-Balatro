library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package cards is
    -- Each card is represented by a 6 bit vector. The first 4
    -- bits represent the numerical value, the last two the suit
    subtype card_t is std_logic_vector(0 to 5);
    
    -- Card value
    constant CARD_2    : std_logic_vector(0 to 3) := "0010"; -- 2
    constant CARD_3    : std_logic_vector(0 to 3) := "0011"; -- 3
    constant CARD_4    : std_logic_vector(0 to 3) := "0100"; -- 4
    constant CARD_5    : std_logic_vector(0 to 3) := "0101"; -- 5
    constant CARD_6    : std_logic_vector(0 to 3) := "0110"; -- 6
    constant CARD_7    : std_logic_vector(0 to 3) := "0111"; -- 7
    constant CARD_8    : std_logic_vector(0 to 3) := "1000"; -- 8
    constant CARD_9    : std_logic_vector(0 to 3) := "1001"; -- 9
    constant CARD_10   : std_logic_vector(0 to 3) := "1010"; -- 10
    constant CARD_J    : std_logic_vector(0 to 3) := "1011"; -- 11 (Jack)
    constant CARD_Q    : std_logic_vector(0 to 3) := "1100"; -- 12 (Queen)
    constant CARD_K    : std_logic_vector(0 to 3) := "1101"; -- 13 (King)
    constant CARD_A    : std_logic_vector(0 to 3) := "1110"; -- 14 (Ace)
    
    -- Card Suits
    constant SUIT_HEARTS : std_logic_vector(0 to 1) := "00";
    constant SUIT_DIAMONDS : std_logic_vector(0 to 1) := "01";
    constant SUIT_CLUBS : std_logic_vector(0 to 1):= "10";
    constant SUIT_SPADES : std_logic_vector(0 to 1):= "11";
    
    constant NULL_CARD : card_t := "000000"; -- no card
    
    
    type hand is array (0 to 7) of card_t;
    type deck is array (0 to 51) of card_t;
    
-- Function to generate cards
    function make_card(value : std_logic_vector(0 to 3);
                        suit: std_logic_vector(0 to 1)) return card_t;
                        
-- Function to get card value
    function get_value(card : card_t) return std_logic_vector;
    
    -- Function to get card suit
    function get_suit(card : card_t) return std_logic_vector;
    
    -- Function to check if card is valid
    function is_valid_card(card : card_t) return boolean;
    
     type hand_type_t is (HIGH_CARD, PAIR, TWO_PAIR, THREE_KIND, STRAIGHT, 
                         FLUSH, FULL_HOUSE, FOUR_KIND, STRAIGHT_FLUSH, ROYAL_FLUSH);
    
    -- Score record containing base value and multiplier
    type score_t is record
        value : integer;
        multiplier : integer;
    end record;
	
	-- Function to score hands
	function score_hand(h : hand) return score_t;
	
	-- Function to add the value of cards to score, like in Balatro
	function get_card_score_value(card : card_t) return integer;

end package cards;

package body cards is

    function make_card(value : std_logic_vector(0 to 3); 
                      suit : std_logic_vector(0 to 1)) return card_t is
    begin
        return value & suit;
    end function;

    function get_value(card : card_t) return std_logic_vector is
    begin
        return card(0 to 3);
    end function;

    function get_suit(card : card_t) return std_logic_vector is
    begin
        return card(4 to 5);
    end function;

    function is_valid_card(card : card_t) return boolean is
    begin
        return card /= NULL_CARD;
    end function;
	
	
	-- Get the value of a card. Face cards are scored as 10, Ace as 11
	function get_card_score_value(card : card_t) return integer is
		variable val : std_logic_vector(0 to 3);
		variable int_val : integer;
		
	begin
		val := get_value(card);
		int_val := to_integer(unsigned(val));
		
		if int_val >= 11 and int_val <= 13 then
			return 10;
		elsif int_val = 14 then
			return 11;
		else
			return int_val;
		end if;
	end function;
	
	
	-- Count cards of each value in hand (for pairing and x of a kind purposes)
	type value_count_array is array (2 to 14) of integer;
	
	function count_values(h : hand) return value_count_array is
		variable counts : value_count_array;
		variable val : integer;
	begin
		-- Initialize all counts to 0
		for i in 2 to 14 loop
			counts(i) := 0;
		end loop;
		
		-- Count occurrences of each card value
		for i in h'range loop
				val := to_integer(unsigned(get_value(h(i))));
				counts(val) := counts(val) +1;
		end loop;
		
		return counts;
	end function;
	
	-- Check if the hand contains a flush (all the same suit)
	function is_flush(h: hand) return boolean is
		variable first_suit : std_logic_vector(0 to 1);
		variable card_count : integer := 0;
	begin 
		for i in h'range loop
				if card_count = 0 then
					first_suit := get_suit(h(i));
				elsif get_suit(h(i)) /= first_suit then
					return false;
				end if;
				card_count := card_count + 1;
		end loop;
		return card_count >= 5;
	end function;
	
	-- Check if hand is a straight
	function is_straight(h : hand) return boolean is
		type bool_array is array (2 to 14) of boolean;
		variable present : bool_array := (others => false);
		variable consecutive : integer := 0;
		variable val: integer;
	begin
		-- Mark which values are present
		for i in h'range loop
				val := to_integer(unsigned(get_value(h(i))));
                if val >= 2 and val <= 14 then
                    present(val) := true;
				end if;
		end loop;
		
		-- Check if cards are consecutive
		for i in 2 to 14 loop
			if present(i) then
				consecutive := consecutive + 1;
				if consecutive >= 5 then
					return true;
				end if;
			else
				consecutive := 0;
			end if;
		end loop;
		
		-- Check for A-5 straight
		if present(14) and present(2) and present(3) and present(4) and present(5) then	
			return true;
		end if;
		
		return false;
	end function;
	
	-- Main scoring Function
	function score_hand(h : hand) return score_t is
		variable counts : value_count_array := (others => 0);
		variable val : integer;
		variable has_pair : boolean := false;
        variable has_three : boolean := false;
        variable has_four : boolean := false;
        variable pair_count : integer := 0;
        variable three_val : integer := 0;
        variable four_val : integer := 0;
        variable pair_vals : integer := 0;
        variable is_flush_hand : boolean;
        variable is_straight_hand : boolean;
        variable is_royal : boolean := false;
        variable base_value : integer := 0;
        variable multiplier : integer := 1;
        variable card_sum : integer := 0;
        variable result : score_t;
        type bool_array is array (2 to 14) of boolean;
        variable present : bool_array := (others => false);
	begin
	-- Count occurences of each value
counts := count_values(h);

-- Populate present array from counts
for i in 2 to 14 loop
    present(i) := (counts(i) > 0);
end loop;

-- Check for pairs, three of a kind, four of a kind
for i in 2 to 14 loop
    if counts(i) = 2 then
        has_pair := true;
        pair_count := pair_count + 1;
        pair_vals := pair_vals + (i * 2);  -- FIXED: accumulate
    elsif counts(i) = 3 then
        has_three := true;
        three_val := i * 3;
    elsif counts(i) = 4 then
        has_four := true;
        four_val := i * 4;
    end if;
end loop;

-- Check for flush and straight;
is_flush_hand := is_flush(h);
is_straight_hand := is_straight(h);

-- Check for royal flush
if is_flush_hand and is_straight_hand then
    is_royal := present(10) and present(11) and present(12) and present(13) and present(14);
end if;
    
-- Determine hand type and scoring
if is_royal then
    base_value := 100;
    multiplier := 8;
    -- Add values of the cards in the hand
    card_sum := 10 + 10 + 10 + 10 + 11;
--Check for straight flush
elsif is_flush_hand and is_straight_hand then  -- FIXED: added elsif
    base_value := 100;
    multiplier := 9;
    -- Add value of cards to hand
    for i in h'range loop
            card_sum := card_sum + get_card_score_value(h(i));
    end loop;
	--Check for 4 of a kind
	elsif has_four then
		base_value := 60;
		multiplier := 7;
		card_sum := four_val;
	--Check for full house
	elsif has_three and has_pair then
		base_value := 40;
		multiplier := 4;
		card_sum := three_val + pair_vals;
	--Check for flush
	elsif is_flush_hand then
		base_value := 35;
		multiplier := 4;
		-- Add all card values
		for i in h'range loop
				card_sum := card_sum + get_card_score_value(h(i));
		end loop;
	-- Check for straight
	elsif is_straight_hand then
		base_value := 30;
		multiplier := 4;
		-- Add all card values
		for i in h'range loop	
				card_sum := card_sum + get_card_score_value(h(i));
		end loop;
	--Check for 3 of a kind
	elsif has_three then
		base_value := 30;
		multiplier := 3;
		card_sum := three_val;
	-- Check for 2 pairs
	elsif pair_count = 2 then
		base_value := 20;
		multiplier := 2;
		card_sum := pair_vals;
	--Check for pair
	elsif has_pair then
		base_value := 10;
		multiplier := 2;
		card_sum := pair_vals;
	-- Check for high card
	else
            -- High card
            base_value := 5;
            multiplier := 1;
            -- Add highest card value
            for i in 14 downto 2 loop
                if present(i) then
                    if i >= 11 and i <= 13 then
                        card_sum := 10;
                    elsif i = 14 then
                        card_sum := 11;
                    else
                        card_sum := i;
                    end if;
                    exit;
                end if;
            end loop;
        end if;
	result.value := base_value + card_sum;
        result.multiplier := multiplier;
        return result;
    end function score_hand;
	

end package body cards;