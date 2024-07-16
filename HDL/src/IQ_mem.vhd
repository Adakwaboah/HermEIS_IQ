-- Author: Akwasi Akwaboah
-- Create Date: 08/24/2023
-- Description: Memory for storing I/Q components to be read by PC

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.ParamPkg.all;

entity IQ_mem is
    generic (
        nBlks           : natural := nBlks_val;
        nADCs           : natural := nADCs_val;
        fifoBits        : natural := fifoBits_val;
        Nbits           : natural := Nbits_val;
        nBlksBits       : natural := nBlksBits_val
    );
    port(
        clk:            in       std_logic;
        rst:            in       std_logic;
        w_addr_o:       out      unsigned( fifoBits-1 downto 0);
        r_addr_o:       out      unsigned( fifoBits-1 downto 0);
        w_data:         in       IQ_buffertype; 
        r_data:         out      std_logic_vector(Nbits-1 downto 0);
        -- w_en:           in       std_logic;
        r_en:           in       std_logic;
        r_ready:        out      std_logic;
        w_ready:        out      std_logic
    );
end entity;

architecture arch of IQ_mem is
   signal fifo         :  xNbits_buffertype; --IQmem_buffertype;--fifo_array;
    signal w_addr       : unsigned( fifoBits-1 downto 0):=(others=>'0');
    signal r_addr       : unsigned( fifoBits-1 downto 0):=(others=>'0');

begin
    w_addr_o <= w_addr;
    r_addr_o <= r_addr;
    r_ready <= '1';
    w_ready <= '1';
    -- w_blk <= (others=>'0');
    -- r_blk_o <= r_blk;
    process(clk, rst)
    begin
        
        if rst = '1' then
            fifo <= (others=>(others=>'0'));
            w_addr <= (others=>'0');
            r_addr <= (others=>'0');

        else
            for i in 0 to nADCs-1 loop
                fifo(2*i) <= w_data(i)(0); -- std_logic_vector(to_unsigned(2*i, Nbits)); --w_data(i)(0);
                fifo(2*i+1) <= w_data(i)(1); -- std_logic_vector(to_unsigned(2*i+1, Nbits)); --
            end loop;

            if rising_edge(clk) then

                -- for i in 0 to nADCs-1 loop
                --     fifo(i)(15 downto 0) <= w_data(i)(0); -- std_logic_vector(to_unsigned(2*i, Nbits)); --w_data(i)(0);
                --     fifo(i)(31 downto 16) <= w_data(i)(1); -- std_logic_vector(to_unsigned(2*i+1, Nbits)); --w_data(i)(1);
                -- end loop;

                if r_en = '1' then
                    r_data <= fifo(to_integer(r_addr));
                    r_addr <= r_addr + 1; 
                end if;
            end if;
        end if;
    end process;

end arch;
