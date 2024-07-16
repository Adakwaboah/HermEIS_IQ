library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all ;

entity clk_div is
    Port ( clk_in : in STD_LOGIC;
           rst : in STD_LOGIC;
           clk_out : out STD_LOGIC );
end clk_div;

architecture Behavioral of clk_div is
    signal counter : unsigned(7 downto 0) := (others => '0');
    signal divided_clk_internal : STD_LOGIC := '0';
    constant DIVIDER_VALUE : integer := 1; -- Change this value for the desired division factor
    signal clk_out_reg: std_logic:='0';

begin

    process(clk_in, rst)
    begin
        if rst = '1' then
            counter <= (others => '0');
            clk_out_reg <= '0';
        elsif rising_edge(clk_in) then
            if counter = DIVIDER_VALUE - 1 then
                counter <= (others => '0');
                 clk_out_reg <= not clk_out_reg;
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;
    clk_out <= clk_out_reg;

end Behavioral;