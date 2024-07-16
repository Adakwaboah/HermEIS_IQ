--
--	Package File Template
--
--	Purpose: This package defines supplemental types, subtypes, 
--		 constants, and functions 
--
--   To use any of the example code shown below, uncomment the lines and modify as necessary
--

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;
use ieee.math_real.all;

package ParamPkg is
		-- ADC counts and corresponding channel counts are maximum hardware determined counts
		-- Dynamic version of less than or equal to the maximum count limits are accommodated
		-- through ports i.e. nADCs_dyn and nChs_dyn supplied by the user through FrontPanel wireIn
		


		constant NBits_val				:	natural		:= 32;  --16;                                                                             
		constant adcBits_val			:	natural 	:= 10; -- # ADC bits
		constant nChs_val				:	natural 	:= 5;	-- # channels (Ref + WEs), Parallel mode for this can be captured in nADC_chs/ Pseudo Parallel with multiple ADCs
		constant nADCs_val				:	natural 	:= 5;	-- # ADCs
		constant nBlks_val				:	natural		:= 1;
		constant fcwfifoBits_val		:	natural		:= 1; --integer(log2( real( nBlks_val*nADCs_val )));
		constant fifoBits_val			:	natural		:= 4;
		constant nBlksBits_val			:	natural		:= 2;
		constant fsampBits_val			:	natural		:= 16;
		constant N_samps_bits_val		:	natural		:= 32; --24;
		type adcBufferType is array (0 to nChs_val-1) of std_logic_vector(8+adcBits_val-1 downto 0);
		type fifoBufferType is array (0 to nChs_val-1) of std_logic_vector(nADCs_val*adcBits_val-1 downto 0);
		type x2_type is array (0 to 1) of std_logic_vector(NBits_val-1 downto 0);
		-- type fifo_array is array(0 to (2**FIFObits)-1) of std_logic_vector(nADCs*adcBits-1 downto 0);
		type IQ_buffertype is array (0 to nADCs_val-1) of x2_type;
		type xNbits_buffertype is array (0 to 2*nADCs_val-1) of std_logic_vector(NBits_val-1 downto 0);
		type IQmem_buffertype is array (0 to nADCs_val-1) of std_logic_vector(NBits_val-1 downto 0);
		--constant 

end ParamPkg;
                                                                                       
                                                                                                                                                                                                                                                                                                                                                                           