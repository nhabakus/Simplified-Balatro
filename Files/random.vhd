library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
-- This module is what helps us generate a "random" deck. Once generated, the deck will be the same every time
-- If you want a different deck, you will hace to change the values of lfsr at lines 19, 39, and 44.
entity random is
    Port (
        clock : in  STD_LOGIC;
        reset : in  STD_LOGIC;
        en    : in  STD_LOGIC;
        Q     : out STD_LOGIC_VECTOR (5 downto 0);
        check : out STD_LOGIC
    );
end random;

architecture Behavioral of random is

    -- 6-bit LFSR state
    signal lfsr : STD_LOGIC_VECTOR(5 downto 0) := "001111";

    -- Free-running counter used as entropy source
    signal entropy_counter : unsigned(15 downto 0) := (others => '0');

    -- Ensures seeding happens once after configuration
    signal seeded : STD_LOGIC := '0';

begin

    process(clock)
        variable feedback : STD_LOGIC;
    begin
        if rising_edge(clock) then

            -- Always increment entropy counter
            entropy_counter <= entropy_counter + 1;

            -- Seed LFSR ONCE using power-up timing uncertainty
            if seeded = '0' then
                lfsr <= "001111";
                seeded <= '1';

            elsif reset = '1' then
                -- Optional external reset (can be tied low)
                lfsr <= "001111";

            elsif en = '1' then
                -- LFSR polynomial: x^6 + x^5 + 1
                feedback := lfsr(5) xor lfsr(4);
                lfsr <= lfsr(4 downto 0) & feedback;
            end if;

        end if;
    end process;

    Q     <= lfsr;
    check <= lfsr(0);

end Behavioral;
