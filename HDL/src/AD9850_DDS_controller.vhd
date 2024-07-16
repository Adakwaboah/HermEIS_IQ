----------------------------------------------------------------------------------
-- Company: Johns Hopkins University 
-- Engineer: Akwasi D. Akwaboah
-- 
-- Create Date:    23:15:06 06/30/2021 
-- Design Name: 
-- Module Name:    AD9850_DDS_controller - Behavioral 
-- Project Name: 	
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--To do: hardware testing, LUT and MATLAB control
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity AD9850_DDS_controller is
	port(
		clk		:	in			std_logic;
		D			: 	out			std_logic_vector(7 downto 0);
		W_CLK		: 	out			std_logic;
		FQ_UD		: 	out			std_logic;
		fcw		:	in			std_logic_vector(31 downto 0);
		trig		:	in			std_logic
	);
end AD9850_DDS_controller;

architecture Behavioral of AD9850_DDS_controller is
	signal word_array_next, word_array_reg: 		std_logic_vector(39 downto 0); -- will hold 5-bit phase word, power down enable, loading format and fcw
	signal counta_next, counta_reg: 					unsigned(2 downto 0):= (others=>'0'); --count for byte group count- there are 5 words\
	signal w_clk_next, w_clk_reg:						std_logic:= '0';
	signal fq_ud_next, fq_ud_reg:						std_logic:= '0';
	type state_type is (idle, rise, fall);
	signal state_next, state_reg:						state_type:= idle;
	signal byte_next, byte_reg:						std_logic_vector(7 downto 0):=(others=>'0');
	signal ceil_idx_next, ceil_idx_reg:				natural range 0 to 39; 
	signal floor_idx_next, floor_idx_reg:				natural range 0 to 32; 
	
begin
	W_CLK <= w_clk_reg;
	FQ_UD <= fq_ud_reg;
	--RESET <= '0';
	D <= byte_reg;
	--fcw <= b"1001_1111_0000_1011_1110_1111_0110_0001";
	
	seq: process(clk)
	begin
		if rising_edge(clk) then
			state_reg <= state_next;
			w_clk_reg <= w_clk_next;
			fq_ud_reg <= fq_ud_next;
			counta_reg <= counta_next;
			byte_reg <= byte_next;
			word_array_reg <= word_array_next;
			ceil_idx_reg <= ceil_idx_next;
			floor_idx_reg <= floor_idx_next;
		end if;
	end process;
	
	comb: process(word_array_reg, trig, counta_reg, byte_reg, w_clk_reg,
					ceil_idx_reg, floor_idx_reg, state_reg, fq_ud_reg, fcw)
	begin
		state_next <= state_reg;
		w_clk_next <= w_clk_reg;
		fq_ud_next <= fq_ud_reg;
		counta_next <= counta_reg;
		ceil_idx_next <= ceil_idx_reg;
		floor_idx_next <= floor_idx_reg;
		byte_next <= byte_reg;
		word_array_next <= x"00" & fcw;
		
		case state_reg is
			when idle =>
				counta_next <= (others=>'0');
				fq_ud_next <= '0';
				w_clk_next <= '0';
				byte_next	<= word_array_reg(39 downto 32);
				ceil_idx_next <= 31;
				floor_idx_next <= 24;	
				if trig = '1' then
					state_next <= rise;
				else
					state_next <= idle;
				end if;
				
			when rise =>
				if counta_reg >= b"101" then
					state_next <= idle;
					fq_ud_next <= '1'; --pulse for a one clock cycle to end 40-bit data transfer
					w_clk_next <= '0';
				else
					state_next <= fall;
					w_clk_next <= '1';
					fq_ud_next <= '0';
				end if;
				
			when fall =>
				state_next <= rise;
				w_clk_next <= '0';
				state_next <= rise;
				byte_next <= word_array_reg(ceil_idx_reg downto floor_idx_reg);
				counta_next <= counta_reg + 1;
				ceil_idx_next <= ceil_idx_reg - 8;
				floor_idx_next <= floor_idx_reg - 8;
				if counta_reg >= b"011" then
					ceil_idx_next <= 39; --reset to  top
					floor_idx_next <= 32;
				else
					ceil_idx_next <= ceil_idx_reg - 8;
					floor_idx_next <= floor_idx_reg - 8;
				end if;
				
		end case;
	
	end process;
	
end Behavioral;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package DDS_pkg is
	component AD9850_DDS_controller
		port(
			clk		:	in			std_logic;
			D			:	out		std_logic_vector(7 downto 0);
			W_CLK		:	out		std_logic;
			FQ_UD		:	out		std_logic;
			fcw		:	in			std_logic_vector(31 downto 0);
			trig		:	in			std_logic
		);
	end component;
end DDS_pkg;

