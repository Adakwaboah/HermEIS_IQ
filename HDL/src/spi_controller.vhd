----------------------------------------------------------------------------------
-- Company: Johns Hopkins University
-- Engineer: Akwasi D. Akwaboah
-- Date: 08/08/2023
--
----------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ADC_spiCon is
    generic(
        nChnls_dyn  : natural := 1; -- nChnls_dyn_gen_val;
        adcBits     : natural := 10;
        FsampBits   : natural := 32;-- (27 for h_hold_time*2)-- 2**26
        Nbits       : natural := 18;
        idxBits     : natural := 6 -- ceil(log2(Nbits))
    );
    port(
        clk: 					in 		std_logic;
		rst:					in		std_logic;
		nss:					out		std_logic;
		sck:					out		std_logic;
		sdi:					out		std_logic; --MOSI considering FPGA as Controller
		sdo:					in		std_logic; --MISO 
        TxData:                 in      std_logic_vector(7+adcBits downto 0); -- read MCP3008 datasheet on #sck cycles
        RxData:                 out     std_logic_vector(7+adcBits downto 0);
        Samp_en:                in      std_logic; -- enable sampling; useful for free running sampling
        tx_end:                 out     std_logic;
        h_hold_time:            in      unsigned(FsampBits-1 downto 0);
        offset_time :           in      unsigned(FsampBits-1 downto 0) -- remainder
    );

end ADC_spiCon;

architecture Behavioral of ADC_spiCon is
    signal hold_count : unsigned(FsampBits-1 downto 0);
    signal idx : unsigned(idxBits-1 downto 0);
    signal j_idx: unsigned(idxBits-1 downto 0);
    signal h_hold_limit_a : unsigned(FsampBits-1 downto 0);
    signal h_hold_limit_b : unsigned(FsampBits-1 downto 0);

begin
    process(rst, clk, offset_time, h_hold_time)
    begin
        if (rst = '1') then
            nss <= '1';
            sck <= '1';
            sdi <= '0';
            RxData <= (others=>'0');
            tx_end <= '0';
            idx    <= to_unsigned(Nbits-1, idxBits);
            -- j_idx    <= to_unsigned(0, idxBits);
            -- j_idx <= to_unsigned(to_integer(offset_time), idxBits);
            j_idx <= to_unsigned(3, idxBits);
            hold_count <= (others=>'0');
            h_hold_limit_a <= to_unsigned(14, FsampBits); -- hold_time -> # intervals (hence +1 for interval end point)
            h_hold_limit_b <= to_unsigned(27, FsampBits); -- to_unsigned(to_integer(2*h_hold_time), FsampBits);

        else
            if rising_edge(clk) then
                if Samp_en = '1' then
                    if (idx = 0) then
                        nss <= '1';
                    else
                        nss <= '0';
                    end if;
                    tx_end <= '0';
                    hold_count <= hold_count + 1;
                    if (hold_count=0) then 
                        sck <= '0';
                        sdi <= TxData(to_integer(idx));
                        if (j_idx /= 0) then
                            h_hold_limit_a <= h_hold_time+1;  -- (1+1) shave a clk_cycle off;
                            j_idx <= j_idx - 1;
                        else
                            h_hold_limit_a <= h_hold_time;
                        end if;
                            
                    elsif (hold_count = h_hold_limit_a) then -- rising edge
                        sck <= '1';
                        RxData(to_integer(idx)) <= sdo;
                        if (j_idx /= 0) then
                            h_hold_limit_b <= to_unsigned(to_integer(2*(h_hold_time+1)), FsampBits); --shave a clk_cycle off;
                            j_idx <= j_idx - 1;
                        else
                            h_hold_limit_b <= to_unsigned(to_integer(2*h_hold_time), FsampBits);
                            if hold_count > h_hold_time then -- fix odd j_idx single clk_period offset
                                h_hold_limit_b <= to_unsigned(to_integer(2*h_hold_time+1), FsampBits);
                            end if;
                        end if;

                        -- if idx = 0 then
                        --     hold_count <= hold_count + offset_count_b;
                        -- end if;
                    elsif (hold_count = h_hold_limit_b - 1) then --falling edge
                        hold_count <= (others=>'0');
                        idx <= idx - 1; 
                        if (idx = 0) then
                            --hold_count <= offset_count; 
                            idx <= to_unsigned(Nbits-1, idxBits);
                            j_idx <= to_unsigned(to_integer(offset_time), idxBits);
                            tx_end <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end Behavioral;