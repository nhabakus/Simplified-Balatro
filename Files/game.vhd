library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library work;
use work.cards.all;

entity game is
    PORT (
        clk_in : IN STD_LOGIC;
        VGA_red : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        VGA_green : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        VGA_blue : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
        VGA_hsync : OUT STD_LOGIC;
        VGA_vsync : OUT STD_LOGIC;
        btnr : IN STD_LOGIC;
        btnc : IN STD_LOGIC;
        SEG7_anode : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
        SEG7_seg : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
        SW : in STD_LOGIC_VECTOR(7 downto 0)
    ); 
end game;

architecture Behavioral of game is
    COMPONENT vga_sync IS
        PORT (
            pixel_clk : IN STD_LOGIC;
            red_in : IN STD_LOGIC_VECTOR (3 DOWNTO 0);
            green_in : IN STD_LOGIC_VECTOR (3 DOWNTO 0);
            blue_in : IN STD_LOGIC_VECTOR (3 DOWNTO 0);
            red_out : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
            green_out : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
            blue_out : OUT STD_LOGIC_VECTOR (3 DOWNTO 0);
            hsync : OUT STD_LOGIC;
            vsync : OUT STD_LOGIC;
            pixel_row : OUT STD_LOGIC_VECTOR (10 DOWNTO 0);
            pixel_col : OUT STD_LOGIC_VECTOR (10 DOWNTO 0)
        );
    END COMPONENT;
    
    COMPONENT clk_wiz_0 is
        PORT (
            clk_in1 : in std_logic;
            clk_out1 : out std_logic
        );
    END COMPONENT;
    
    COMPONENT random is
        PORT ( 
        -- random module
            clock : in STD_LOGIC;
            reset : in STD_LOGIC;
            en : in STD_LOGIC;
            Q : out STD_LOGIC_VECTOR (5 downto 0);
            check: out STD_LOGIC
        );
    END COMPONENT;
    
    COMPONENT leddec16 IS
        PORT (
        -- for showing the score on the the display
            dig : IN STD_LOGIC_VECTOR (2 DOWNTO 0);
            data : IN STD_LOGIC_VECTOR (15 DOWNTO 0);
            anode : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            seg : OUT STD_LOGIC_VECTOR (6 DOWNTO 0)
        );
    END COMPONENT;
    
    signal vga_clock : std_logic;
    signal pixel_row : std_logic_vector(10 downto 0);
    signal pixel_col : std_logic_vector(10 downto 0);
    signal red_in, green_in, blue_in : std_logic_vector(3 downto 0);
    signal Q : std_logic_vector(5 downto 0);
    signal en : STD_LOGIC := '1';
    signal check : STD_LOGIC;
    
    type deck_array is array (0 to 51) of card_t;
    signal deck : deck_array;
    signal shuffled_deck : deck_array;
    signal deck_index : integer range 0 to 51 := 0;
    
    type hand_array is array (0 to 7) of card_t;
    signal hand : hand_array := (others => NULL_CARD);
    signal cards_drawn : integer range 0 to 8 := 0;
    
    signal shuffle_counter : unsigned(25 downto 0) := (others => '0');
    signal shuffle_index : integer range 0 to 52 := 0;
    signal shuffle_done : std_logic := '0';
    signal initial_deal_done : std_logic := '0';
    
    signal btnc_prev : std_logic := '0';
    signal btnr_prev : std_logic := '0';
    signal selected_count : integer range 0 to 8 := 0;
    signal action_idx : integer range 0 to 10 := 0;
    signal cards_remaining : integer range 0 to 52 := 52;
    
    signal discards_remaining : integer range 0 to 4 := 4;
    signal plays_remaining : integer range 0 to 4 := 4;
    signal total_score : integer range 0 to 65535 := 0;
    signal score_display : std_logic_vector(15 downto 0) := (others => '0');
    
    signal led_counter : unsigned(19 downto 0) := (others => '0');
    signal dig : std_logic_vector(2 downto 0) := "000";
    
    type game_state_t is (SHUFFLING, DEALING, PLAYING, DISCARDING, PLAYING_HAND, DECK_EMPTY);
    signal game_state : game_state_t := SHUFFLING;
    
begin
    vga_clock_gen : clk_wiz_0
        PORT MAP (clk_in1 => clk_in, clk_out1 => vga_clock);
    
    random_gen : random
        PORT MAP (clock => clk_in, reset => '0', en => en, Q => Q, check => check);
    
    vga_sync_inst : vga_sync
        PORT MAP (
            pixel_clk => vga_clock, red_in => red_in, green_in => green_in, blue_in => blue_in,
            red_out => VGA_red, green_out => VGA_green, blue_out => VGA_blue,
            hsync => VGA_hsync, vsync => VGA_vsync, pixel_row => pixel_row, pixel_col => pixel_col
        );
    
    led_display : leddec16
        PORT MAP (
            dig => dig,
            data => score_display,
            anode => SEG7_anode,
            seg => SEG7_seg
        );
    
    -- Initialize deck
    process
    begin
        -- every card is a 6 bit vector. the first four bits represent the value, the last 2 the suit.
        -- see deck.vhd for more information
        for s in 0 to 3 loop
            for v in 2 to 14 loop
                deck(s*13 + (v-2)) <= make_card(
                    value => std_logic_vector(to_unsigned(v, 4)),
                    suit => std_logic_vector(to_unsigned(s, 2))
                );
            end loop;
        end loop;
        wait;
    end process;
    
    -- LED multiplexing
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            led_counter <= led_counter + 1;
            if led_counter(16 downto 0) = 0 then
                if dig = "011" then
                    dig <= "000";
                else
                    dig <= std_logic_vector(unsigned(dig) + 1);
                end if;
            end if;
        end if;
    end process;
    
    -- Update score display
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            score_display <= std_logic_vector(to_unsigned(total_score, 16));
        end if;
    end process;
    
    -- Main game state machine
    process(clk_in)
        variable rand_pos : integer;
        variable temp_card : card_t;
        variable score_result : score_t;
        variable hand_score : integer;
        variable score_hand_input : work.cards.hand;
    begin
        if rising_edge(clk_in) then
            shuffle_counter <= shuffle_counter + 1;
            btnc_prev <= btnc;
            btnr_prev <= btnr;
            -- This is what dictates the flow of the game.
            -- We shuffle by randomizing a shuffle index, and then associating every card in the
            -- deck to a random position.
            -- To change the random order, see random.vhd
            case game_state is
                when SHUFFLING =>
                    if shuffle_counter(19 downto 0) = 0 then
                        if shuffle_index = 0 then
                            shuffled_deck <= deck;
                            shuffle_index <= 1;
                        elsif shuffle_index <= 51 then
                            rand_pos := to_integer(unsigned(Q)) mod (shuffle_index + 1);
                            temp_card := shuffled_deck(shuffle_index);
                            shuffled_deck(shuffle_index) <= shuffled_deck(rand_pos);
                            shuffled_deck(rand_pos) <= temp_card;
                            shuffle_index <= shuffle_index + 1;
                        else
                            shuffle_done <= '1';
                            game_state <= DEALING;
                            cards_drawn <= 0;
                            deck_index <= 0;
                            cards_remaining <= 52;
                        end if;
                    end if;
               -- Here we deal 8 cards to the player     
                when DEALING =>
                    if shuffle_counter(23 downto 0) = 0 then
                        if cards_drawn < 8 and cards_remaining > 0 then
                            hand(cards_drawn) <= shuffled_deck(deck_index);
                            cards_drawn <= cards_drawn + 1;
                            deck_index <= deck_index + 1;
                            cards_remaining <= cards_remaining - 1;
                        else
                            initial_deal_done <= '1';
                            if cards_remaining > 0 then
                                game_state <= PLAYING;
                            else
                                game_state <= DECK_EMPTY;
                            end if;
                        end if;
                    end if;
               -- Here is where we play. Center button takes us to the discard state, right to the playing_hand state     
                when PLAYING =>
                    if btnc = '1' and btnc_prev = '0' then
                        if selected_count > 0 and selected_count <= 5 and discards_remaining > 0 then
                            if cards_remaining >= selected_count then
                                game_state <= DISCARDING;
                                action_idx <= 0;
                            end if;
                        end if;
                    elsif btnr = '1' and btnr_prev = '0' then
                        if selected_count > 0 and selected_count <= 5 and plays_remaining > 0 then
                            game_state <= PLAYING_HAND;
                            action_idx <= 0;
                        end if;
                    end if;
                -- For every switch that is on, when btnc is pressed, those cards are removed and replaced/re-dealt    
                when DISCARDING =>
                    if shuffle_counter(20 downto 0) = 0 then
                        if action_idx < 8 then
                            if SW(action_idx) = '1' and cards_remaining > 0 then
                                hand(action_idx) <= shuffled_deck(deck_index);
                                deck_index <= deck_index + 1;
                                cards_remaining <= cards_remaining - 1;
                            end if;
                            action_idx <= action_idx + 1;
                        else
                            discards_remaining <= discards_remaining - 1;
                            if cards_remaining > 0 then
                                game_state <= PLAYING;
                            else
                                game_state <= DECK_EMPTY;
                            end if;
                        end if;
                    end if;
                -- For every switch on, that card is played, and it is scored as part of a hand. See deck.vhd for info on how
                -- hands are scored.    
                when PLAYING_HAND =>
                    if shuffle_counter(20 downto 0) = 0 then
                        if action_idx = 0 then
                            -- Build temp hand with only selected cards, rest are NULL
                            for i in 0 to 7 loop
                                if SW(i) = '1' then
                                -- We needed to make a temp hand to score, otherwise we'd be scoring the current hand
                                -- rather than the cards we are trying to play.
                                    score_hand_input(i) := hand(i);
                                else
                                    score_hand_input(i) := NULL_CARD;
                                end if;
                            end loop;
                            score_result := score_hand(score_hand_input);
                            hand_score := score_result.value * score_result.multiplier;
                            total_score <= total_score + hand_score;
                            action_idx <= 1;
                        elsif action_idx < 9 then
                            if SW(action_idx - 1) = '1' and cards_remaining > 0 then
                                hand(action_idx - 1) <= shuffled_deck(deck_index);
                                deck_index <= deck_index + 1;
                                cards_remaining <= cards_remaining - 1;
                            end if;
                            action_idx <= action_idx + 1;
                        else
                            plays_remaining <= plays_remaining - 1;
                            if cards_remaining > 0 then
                                game_state <= PLAYING;
                            else
                                game_state <= DECK_EMPTY;
                            end if;
                        end if;
                    end if;
                    -- Self explanatory,
                when DECK_EMPTY =>
                    null;
                    
            end case;
        end if;
    end process;
    
    -- Count selected cards
    process(SW)
        variable count : integer range 0 to 8;
    begin
        count := 0;
        for i in 0 to 7 loop
            if SW(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        selected_count <= count;
    end process;
    
    -- VGA Display
    process(vga_clock)
        variable row_int, col_int, card_x, card_y : integer;
        variable current_card : card_t;
        variable suit_code : std_logic_vector(1 downto 0);
        variable magnitude : std_logic_vector(3 downto 0);
        variable draw_white : boolean;
    begin
        if rising_edge(vga_clock) then
            row_int := to_integer(unsigned(pixel_row));
            col_int := to_integer(unsigned(pixel_col));
            
            red_in <= "0000"; green_in <= "0000"; blue_in <= "0000";
            
            for i in 0 to 7 loop
                card_x := 50 + (i mod 4) * 150;
                card_y := 150 + (i / 4) * 150;
                
                if col_int >= card_x and col_int < card_x + 100 and
                   row_int >= card_y and row_int < card_y + 120 then
                    
                    if i < cards_drawn then
                        current_card := hand(i);
                        suit_code := get_suit(current_card);
                        magnitude := get_value(current_card);
                        
                        case suit_code is
                            when "00" => red_in <= "1111"; green_in <= "0000"; blue_in <= "0000";
                            when "01" => red_in <= "0000"; green_in <= "0000"; blue_in <= "1111";
                            when "10" => red_in <= "0000"; green_in <= "1111"; blue_in <= "0000";
                            when others => red_in <= "0011"; green_in <= "0011"; blue_in <= "0011";
                        end case;
                        -- Here is where we draw the associated numbers/card values.
                        draw_white := false;
                        case magnitude is 
                            when "0010" =>
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                     or (col_int >= card_x + 55 and col_int <= card_x + 60 and
                                     row_int >= card_y + 30 and row_int <= card_y + 55)
                                     or (row_int >= card_y + 55 and row_int <= card_y + 65 and
                                     col_int >= card_x + 40 and col_int <= card_x + 60)
                                     or (col_int >= card_x + 40 and col_int <= card_x + 45 and
                                     row_int >= card_y + 65 and row_int <= card_y + 90)
                                     or (row_int >= card_y + 90 and row_int <= card_y + 100 and
                                     col_int >= card_x + 40 and col_int <= card_x + 60);
                            when "0011" =>
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (row_int >= card_y + 55 and row_int <= card_y + 65 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (row_int >= card_y + 90 and row_int <= card_y + 100 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 20 and row_int <= card_y + 100);
                            when "0100" =>
                                draw_white := (col_int >= card_x + 40 and col_int <= card_x + 45 and row_int >= card_y + 20 and row_int <= card_y + 65)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 20 and row_int <= card_y + 100)
                                    or (row_int >= card_y + 55 and row_int <= card_y + 65 and col_int >= card_x + 40 and col_int <= card_x + 60);
                            when "0101" =>
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 40 and col_int <= card_x + 45 and row_int >= card_y + 20 and row_int <= card_y + 65)
                                    or (row_int >= card_y + 55 and row_int <= card_y + 65 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 55 and row_int <= card_y + 100)
                                    or (row_int >= card_y + 90 and row_int <= card_y + 100 and col_int >= card_x + 40 and col_int <= card_x + 60);
                            when "0110" =>
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 40 and col_int <= card_x + 45 and row_int >= card_y + 20 and row_int <= card_y + 100)
                                    or (row_int >= card_y + 55 and row_int <= card_y + 65 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 55 and row_int <= card_y + 100)
                                    or (row_int >= card_y + 90 and row_int <= card_y + 100 and col_int >= card_x + 40 and col_int <= card_x + 60);
                            when "0111" =>
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 20 and row_int <= card_y + 100);
                            when "1000" =>
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (row_int >= card_y + 55 and row_int <= card_y + 65 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (row_int >= card_y + 90 and row_int <= card_y + 100 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 40 and col_int <= card_x + 45 and row_int >= card_y + 20 and row_int <= card_y + 100)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 20 and row_int <= card_y + 100);
                            when "1001" =>
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (row_int >= card_y + 55 and row_int <= card_y + 65 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (row_int >= card_y + 90 and row_int <= card_y + 100 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 20 and row_int <= card_y + 100)
                                    or (col_int >= card_x + 40 and col_int <= card_x + 45 and row_int >= card_y + 20 and row_int <= card_y + 65);
                            when "1010" =>
                                draw_white := (col_int >= card_x + 35 and col_int <= card_x + 40 and row_int >= card_y + 20 and row_int <= card_y + 100)
                                    or (row_int >= card_y + 20 and row_int <= card_y + 30 and col_int >= card_x + 50 and col_int <= card_x + 65)
                                    or (row_int >= card_y + 90 and row_int <= card_y + 100 and col_int >= card_x + 50 and col_int <= card_x + 65)
                                    or (col_int >= card_x + 50 and col_int <= card_x + 55 and row_int >= card_y + 20 and row_int <= card_y + 100)
                                    or (col_int >= card_x + 60 and col_int <= card_x + 65 and row_int >= card_y + 20 and row_int <= card_y + 100);
                            when "1011" =>
                                draw_white := (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 20 and row_int <= card_y + 100)
                                    or (row_int >= card_y + 90 and row_int <= card_y + 100 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (col_int >= card_x + 40 and col_int <= card_x + 45 and row_int >= card_y + 75 and row_int <= card_y + 95);
                            when "1100" => 
                                draw_white := (col_int >= card_x + 40 and col_int <= card_x + 45 and row_int >= card_y + 25 and row_int <= card_y + 90)
                                    or (col_int >= card_x + 55 and col_int <= card_x + 60 and row_int >= card_y + 25 and row_int <= card_y + 90)
                                    or (row_int >= card_y + 25 and row_int <= card_y + 30 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (row_int >= card_y + 85 and row_int <= card_y + 90 and col_int >= card_x + 40 and col_int <= card_x + 60)
                                    or (abs((col_int - (card_x + 52)) - (row_int - (card_y + 77))) <= 2 and col_int >= card_x + 52 and col_int <= card_x + 67 and row_int >= card_y + 77 and row_int <= card_y + 95);
                            when "1101" => 
                                draw_white := (col_int >= card_x + 40 and col_int <= card_x + 45 and
                                         row_int >= card_y + 20 and row_int <= card_y + 100)
                                         or (abs(
                                            (col_int - (card_x + 45)) -
                                            ((card_y + 60) - row_int)
                                         ) <= 2
                                         and row_int >= card_y + 20 and row_int <= card_y + 60
                                         and col_int >= card_x + 45 and col_int <= card_x + 70)
                                         or (abs(
                                            (col_int - (card_x + 45)) -
                                            (row_int - (card_y + 60))
                                         ) <= 2
                                         and row_int >= card_y + 60 and row_int <= card_y + 100
                                         and col_int >= card_x + 45 and col_int <= card_x + 70);
                            when "1110" => 
                                draw_white := (row_int >= card_y + 20 and row_int <= card_y + 30 and
                                 col_int >= card_x + 40 and col_int <= card_x + 60)
                                 or (col_int >= card_x + 40 and col_int <= card_x + 45 and
                                 row_int >= card_y + 20 and row_int <= card_y + 100)
                                 or (col_int >= card_x + 55 and col_int <= card_x + 60 and
                                 row_int >= card_y + 20 and row_int <= card_y + 100)
                                 or (row_int >= card_y + 55 and row_int <= card_y + 65 and
                                 col_int >= card_x + 40 and col_int <= card_x + 60);
                            when others => draw_white := false;
                        end case;
                        
                        if draw_white then
                            red_in <= "1111"; green_in <= "1111"; blue_in <= "1111";
                        end if;
                        
                        if SW(i) = '1' then
                            if col_int < card_x + 5 or col_int >= card_x + 95 or row_int < card_y + 5 or row_int >= card_y + 115 then
                                red_in <= "1111"; green_in <= "1111"; blue_in <= "0000";
                            end if;
                        else 
                            if col_int < card_x + 5 or col_int >= card_x + 95 or row_int < card_y + 5 or row_int >= card_y + 115 then
                                red_in <= "1111"; green_in <= "1111"; blue_in <= "1111";
                            end if;
                        end if;
                    else
                        red_in <= "0111"; green_in <= "0111"; blue_in <= "0111";
                    end if;
                end if;
            end loop;
        end if;
    end process;
    
end Behavioral;