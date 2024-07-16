----------------------------------------------------------------------------------
-- Company: 	Johns Hopkins University
-- Engineer: 	Akwasi Akwaboah
-- 
-- Create Date:    08/24/2023
-- Design Name: 
-- Module Name:    HermEIS_Top - Behavioral 
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
--
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
use work.FRONTPANEL.all;
-- use work.FIFO_pkg.all;
use work.DDS_pkg.all;
use work.i2c_pkg.all;
use work.ParamPkg.all;
-- use work.MCP3008_ADC_SPI_PKG.all;
-- use work.adc2FIFO_pkg.all;

entity HermEIS_Top is
	generic(
		Nbits : natural := Nbits_val;
		fifoBits : natural := fifoBits_val;
		fcwfifoBits : natural := fcwfifoBits_val;
		FsampBits : natural := fsampBits_val;
		N_samps_bits : natural := N_samps_bits_val;
		nADC_cycles : natural := 18
	);
	port(
		-- Opal Kelly --
		okUH      			: in     STD_LOGIC_VECTOR(4 downto 0);
		okHU      			: out    STD_LOGIC_VECTOR(2 downto 0);
		okUHU     			: inout  STD_LOGIC_VECTOR(31 downto 0);
		okAA      			: inout  STD_LOGIC;
		
		sys_clkp  			: in     STD_LOGIC;
		sys_clkn  			: in     STD_LOGIC;
		led       			: out    STD_LOGIC_VECTOR(7 downto 0);

		--Custom ---
		-- a. AD9850 pins
		W_CLK				:	out			std_logic;
		FQ_UD				:	out			std_logic;
		DDS_DATA			:	out			std_logic_vector(7 downto 0);
		RESET_O2			:	out			std_logic;
		
		-- b. MCP40D17s
		RIN_SCL				: inout		std_logic;
		RIN_SDA				: inout		std_logic;
		ROUT_SCL			: inout		std_logic;
		ROUT_SDA			: inout		std_logic;

		DEBUG				:	out     	std_logic;
		-- ADC SPI Pins 
		A_NCS				:	out			std_logic;
		A_SCK				:	out			std_logic;
		A_SDI				:	out			std_logic; -- input with respect to target (ADC)
		A_SDO				:	in			std_logic_vector(7 downto 0)
		-- tx_end 				:	inout			std_logic_vector(adcBits_val-1 downto 0)

	);

end HermEIS_Top;

architecture Behavioral of HermEIS_Top is
	--- Target Interface Bus ---
	signal sys_clk    : STD_LOGIC;
	
	signal okClk      		: STD_LOGIC:='0';
	signal okHE       		: STD_LOGIC_VECTOR(112 downto 0):= (others=>'0');
	signal okEH       		: STD_LOGIC_VECTOR(64 downto 0):= (others=>'0');
	signal okEHx      		: STD_LOGIC_VECTOR(65*2-1 downto 0):= (others=>'0');
	
	--- Endpoint Connections ---
	--- a. Wires ---
	signal ep00wire_in		: std_logic_vector(31 downto 0):= (others=>'0'); 
	signal fsamp_cn 		: std_logic_vector(31 downto 0):= (others=>'0');		-- fsamp_c (ep02wire_in)
	signal ep03wire_in		: std_logic_vector(31 downto 0):= (others=>'0');
	signal ep04wire_in		: std_logic_vector(31 downto 0):= (others=>'0');-- start iq done
	signal ep05wire_in		: std_logic_vector(31 downto 0):= (others=>'0');  		-- reset
	signal ep06wire_in		: std_logic_vector(31 downto 0):= (others=>'0');-- start iq done
	signal ep07wire_in		: std_logic_vector(31 downto 0):= (others=>'0');
	
	signal ep20wire_out		: std_logic_vector(31 downto 0):= (others=>'0');		-- set digipots
	signal ep21wire_out		: std_logic_vector(31 downto 0):= (others=>'0');		-- start DDS
	-- signal ep22wire_out		: std_logic_vector(31 downto 0);
	-- signal ep23wire_out		: std_logic_vector(31 downto 0);
	
	--- b. Triggers ---
	signal ep40trig_in		: std_logic_vector(31 downto 0):= (others=>'0'); --Global reset(0)
	signal ep41trig_in		: std_logic_vector(31 downto 0):= (others=>'0'); --DDS trig (0)
	-- signal ep42trig_in		: std_logic_vector(31 downto 0):= (others=>'0'); --Pot trig (0)
	signal ep43trig_in		: std_logic_vector(31 downto 0):= (others=>'0'); -- start acquisition, i.e. ADC sampling & I/Q
	signal ep44trig_in		: std_logic_vector(31 downto 0):= (others=>'0'); -- stop acquisition
	
	--- c. Pipes ---
	signal pipe_in_write	: std_logic := '0';
	signal pipe_in_ready 	: std_logic := '0';
	signal pipe_in_data		: std_logic_vector(31 downto 0):= (others=>'0');
	signal bs_in, bs_out	: std_logic := '0';
	
	signal pipe_out_read	: std_logic:='0';
	signal pipe_out_ready 	: std_logic:='0';
	signal pipe_out_data	: std_logic_vector(31 downto 0):= (others=>'0');
	
	--- Other Signals ---
	signal data_within		: std_logic_vector(31 downto 0):= (others=>'0');
	signal pipe_out_full	: std_logic:='0';
	-- signal fifoW_en			: std_logic;
	signal fifoAlmostfull	: std_logic:='0';
	signal fifoD_in			: fifoBufferType ;
	signal nBytes			: unsigned(2 downto 0):= (others=>'0');
	
	--- DDS (AD9850) Signals ---
	signal trigDDS			:	std_logic:='0';
	signal fcw				:	std_logic_vector(31 downto 0):= (others=>'1');
	signal ufcw, ufcw_4		:	unsigned(N_samps_bits-1 downto 0):= (others=>'1');
	
	-- ADC Signals
	signal tx_end			: std_logic_vector(nADCs_val-1 downto 0);
	signal Samp_en			: std_logic:='0';
	signal TxData			: std_logic_vector(8+adcBits_val-1 downto 0):= (others=>'0'); -- sdi tied together for all
	signal RxData			: adcBufferType; -- 8 parallel adc data_out
	signal h_hold_time  	: unsigned(FsampBits-1 downto 0):= (others=>'0');
	signal offset_time  	: unsigned(FsampBits-1 downto 0):= (others=>'0');

	--I/Q signals
	-- signal Samp_in:    std_logic;                        -- indicate arrival of ADC sample    
    signal int_en:     std_logic:= '0';                        -- start integration
	signal int_end:	   std_logic_vector(nADCs_val-1 downto 0); -- := (others=>'0');
	signal iq_done :   std_logic:='0';

    -- signal I_out:      std_logic_vector( Nbits-1 downto 0):=(others=>'0'); -- In-phase
    -- signal Q_out:      std_logic_vector( Nbits-1 downto 0):=(others=>'0'); -- Quadrature
	signal I_out: xNbits_buffertype:=(others=>(others=>'0'));
	signal Q_out: xNbits_buffertype:=(others=>(others=>'0'));
	type S_arr is array (0 to 3) of signed(Nbits-1 downto 0);
    signal S:   S_arr := (others=>(others=>'0'));

	--IQ fifo signals
	signal w_addr_o : unsigned( fifoBits-1 downto 0):= (others=>'0');
    signal r_addr_o : unsigned( fifoBits-1 downto 0):= (others=>'0');
    -- signal w_en :   std_logic;
    signal r_en :   std_logic := '0';
    signal w_data : IQ_buffertype:=(others=>(others=>(others=>'0')));
    -- signal r_data : std_logic_vector(Nbits-1 downto 0);

	signal potRin_w_byte : std_logic_vector(7 downto 0):= (others=>'0');
	signal potRout_w_byte : std_logic_vector(7 downto 0):= (others=>'0');
	
	signal iq_count : unsigned(3 downto 0):=(others=>'0');
	signal sys_clk_div: std_logic:='0';
	
begin

	-- NEW!!! use wire in as reset

	--debug
	DEBUG <= sys_clk_div;

	--- Leave I2C unused ---
	-- I2C_SDA <= 'Z';
	-- I2C_SCL <= 'Z';

	--- Select USB Communication ---
	-- HI_MUXSEL <= '0';

	LED <=  fcw(15 downto 8);
	RESET_O2 <= ep05wire_in(0);
	ep20wire_out(0) <=  iq_done; --int_end(0);
	ep20wire_out(31 downto 1) <=  (others=>'0');
	potRin_w_byte <= '0'&ep00wire_in(6 downto 0);
	potRout_w_byte <= '0'&ep00wire_in(14 downto 8);
	-- w_data(0)(0) <= std_logic_vector(to_unsigned(0, 22)) & RxData(0)(9 downto 0);
	-- w_data(1)(1) <= std_logic_vector(to_unsigned(0, 22)) & RxData(1)(9 downto 0);
	-- SPI signals --
	--A_NCS <= a_ncs;

	--coordinate fcw read from fcw_mem and offload I/Q to mem
	process(sys_clk_div)
	begin

		if (ep05wire_in(0) = '1') or (ep04wire_in(0) = '0') then
			Samp_en <= '0';
			int_en <= '0';
			ufcw <= (others=>'0');
			-- ufcw_4 <= (others=>'0');
			h_hold_time <= to_unsigned(14, FsampBits);
			offset_time <= to_unsigned(3, FsampBits);
			iq_done <= '0';
			iq_count <= (others=>'0');
		else
			if rising_edge(sys_clk_div) then
				h_hold_time <= unsigned(ep03wire_in(FsampBits-1 downto 0))/(2*nADC_cycles);
    			offset_time <= unsigned(ep03wire_in(FsampBits-1 downto 0)) mod (2*nADC_cycles);
				ufcw <= unsigned(fcw(N_samps_bits-1 downto 0));
				-- ufcw_4 <= ufcw sll 2;

				-- if ep43trig_in(0) = '1' then
				Samp_en <= '1';
				if iq_done = '0' then
					int_en <= '1';
				else
					int_en <= '0';
				end if;
				-- iq_done <= '0';
					
				if (int_end(0) = '1') then
					iq_count <= iq_count + 1;
					iq_done <= '0';
					if iq_count >= 1 then
						iq_count <= to_unsigned(1, 4);
						iq_done <= '1';
						-- int_en <= '0';
					-- else
					-- 	int_en <= '1';
					end if;
				end if;
			end if;
		end if;

	end process;


	clk_divider: entity work.clk_div
		port map(
			clk_in => sys_clk,
			rst => ep05wire_in(0),
			clk_out => sys_clk_div
		);

	RIN_I2C: entity work.pot_i2c_controller 
		generic map (
			command_code => b"0000_0000",
			address => b"010_1110",
			word_size => 8
			)
		port map (
			rst => ep05wire_in(0),
			clk => sys_clk_div, --okclk,
			scl => Rin_scl,
			sda => Rin_sda,
			pot_write_byte => potRin_w_byte,
			pot_read_byte => ep21wire_out(7 downto 0),
			trig => ep06wire_in(0),--ep42trig_in(0),
			rw_mode => ep00wire_in(15),
			nBytes => b"001"
			);
				
	ROUT_I2C: entity work.pot_i2c_controller
		generic map (
			command_code => b"0000_0000",
			address => b"010_1110",
			word_size => 8
			)
		port map (
			rst => ep05wire_in(0),
			clk => sys_clk_div, --okclk,
			scl => Rout_scl,
			sda => Rout_sda,
			pot_write_byte => potRout_w_byte,
			pot_read_byte => ep21wire_out(15 downto 8),
			trig => ep06wire_in(0),
			rw_mode => ep00wire_in(15),
			nBytes => b"001"
			);
				
	DDS0: entity work.AD9850_DDS_Controller 
		port map (
			clk => sys_clk, --okclk,
			D => DDS_DATA,
			W_CLK => W_CLK,
			FQ_UD => FQ_UD,
			fcw => fcw,
			trig => ep07wire_in(0)
			);
								
	ADC_spi_0: entity work.ADC_spiCon
		generic map(
			FsampBits => fsampBits_val
		)
		port map(
			clk => sys_clk_div,
			rst => ep05wire_in(0),
			nss => A_NCS,
			sck => A_SCK,
			sdi => A_SDI,
			sdo => A_SDO(0),
			TxData => b"110_000_0000_0000_0000", --TxData,
			RxData => RxData(0),
			Samp_en => Samp_en,
			tx_end => tx_end(0),
			h_hold_time => h_hold_time,
			offset_time => offset_time
			);

	ADC_bank_1_7: for i in 1 to nADCs_val-1 generate
		ADC_spi: entity work.ADC_spiCon
		generic map(FsampBits => fsampBits_val)
			port map(
				clk=> sys_clk_div,
				rst=> ep05wire_in(0),
				nss=>open,
				sck=>open,
				sdi=>open,
				sdo => A_SDO(i),
				TxData => TxData,
				RxData=> RxData(i),
				Samp_en => Samp_en,
				tx_end => tx_end(i),
				h_hold_time => h_hold_time,
				offset_time => offset_time
			);
	end generate;

	IQ_bank: for i in 0 to nADCs_val-1 generate
		IQ: entity work.IQ_gen
		generic map(
            N_samps_bits => N_samps_bits_val,
            adcBits => adcBits_val,
            -- N_samps => N_samps,
            f_clk => 100_000_000,
            Nbits=>Nbits_val
        )
			port map (
				clk => sys_clk_div,
				rst => ep05wire_in(0),--m_iq_rst,
				X_in  => RxData(i)(9 downto 0),
				Samp_in => tx_end(i),
				int_en => int_en,
				I_out => w_data(i)(0), --I_out(i),
				Q_out => w_data(i)(1), --Q_out(i),
				S0 => open,
				S1 => open,
				S2 => open,
				S3 => open,
				fc => ufcw,
				fsamp_cn => unsigned(fsamp_cn(N_samps_bits-1 downto 0)), --(Nbits-1 downto 0),
				int_end => int_end(i)
			);
	end generate; 

	IQ_fifo: entity work.IQ_mem
		generic map(nBlks => nBlks_val)
		port map (
			clk => okClk,
			rst => ep05wire_in(0),
			w_addr_o => w_addr_o,
			r_addr_o => r_addr_o,
			w_data => w_data,
			r_data => pipe_out_data, --r_data
			-- w_en => w_en,
			r_en => pipe_out_read, --r_en,
			r_ready => pipe_out_ready,
			w_ready => open
		);

	osc_clk : IBUFGDS port map (O=>sys_clk, I=>sys_clkp, IB=>sys_clkn);
					  
	-- Instantiate the okHost and connect endpoints
	okHI : okHost port map (
		okUH=>okUH, 
		okHU=>okHU, 
		okUHU=>okUHU, 
		okAA=>okAA,
		okClk=>okClk, 
		okHE=>okHE, 
		okEH=>okEH
	);

	-- okWO: okWireOR generic map (N=>5)
	okWO : okWireOR     generic map (N=>2) port map (okEH=>okEH, okEHx=>okEHx);

	wi00 : okWireIn    port map (okHE=>okHE, ep_addr=>x"00", ep_dataout=>ep00wire_in); --pot_i2c
	wi01 : okWireIn    port map (okHE=>okHE, ep_addr=>x"01", ep_dataout=>fcw(31 downto 0)); -- DDS [15:0]
	wi02 : okWireIn    port map (okHE=>okHE, ep_addr=>x"02", ep_dataout=>fsamp_cn); -- fsamp_cn
	wi03 : okWireIn    port map (okHE=>okHE, ep_addr=>x"03", ep_dataout=>ep03wire_in); -- adc hold : fclk/fsamp_cn
	wi04 : okWireIn    port map (okHE=>okHE, ep_addr=>x"04", ep_dataout=>ep04wire_in); -- start stop i/q
	wi05 : okWireIn    port map (okHE=>okHE, ep_addr=>x"05", ep_dataout=>ep05wire_in); -- reset
	wi06 : okWireIn    port map (okHE=>okHE, ep_addr=>x"06", ep_dataout=>ep06wire_in); -- start stop i/q
	wi07 : okWireIn    port map (okHE=>okHE, ep_addr=>x"07", ep_dataout=>ep07wire_in); -- reset
	

	wo20 : okWireOut	 port map (okHE=>okHE, okEH=>okEHx( 2*65-1 downto 1*65 ), ep_addr=>x"20", -- IQ_status
								 ep_datain=>ep20wire_out);
	-- wo21 : okWireOut	 port map (okHE=>okHE, okEH=>okEHx( 3*65-1 downto 2*65 ), ep_addr=>x"21", -- number of freqs <=64
	-- 							 ep_datain=>ep21wire_out);
	-- wo22 : okWireOut	 port map (okHE=>okHE, okEH=>okEHx( 5*65-1 downto 4*65 ), ep_addr=>x"22", --debugger
	-- 							 ep_datain=>ep22wire_out);
	-- wo23 : okWireOut	 port map (okHE=>okHE, okEH=>okEHx( 6*65-1 downto 5*65 ), ep_addr=>x"23", --debugger
	-- 							 ep_datain=>ep23wire_out);
	
	-- ti40 : okTriggerIn port map (okHE=>okHE, ep_addr=>x"40", ep_clk=>sys_clk, ep_trigger=> ep40trig_in);  -- global reset trigger
	-- ti41 : okTriggerIn port map (okHE=>okHE, ep_addr=>x"41", ep_clk=>sys_clk, ep_trigger=> ep41trig_in); 	-- dds trigger
	-- ti42 : okTriggerIn port map (okHE=>okHE, ep_addr=>x"42", ep_clk=>sys_clk, ep_trigger=> ep42trig_in);  -- pot trigger
	-- ti43 : okTriggerIn port map (okHE=>okHE, ep_addr=>x"43", ep_clk=>sys_clk, ep_trigger=> ep43trig_in);  -- start acquisition
	-- ti44 : okTriggerIn port map (okHE=>okHE, ep_addr=>x"44", ep_clk=>sys_clk, ep_trigger=> ep44trig_in);  -- stop acquisition


--	ep80: okBTPipeIn port map (okHE=>okHE, ok2=>ok2s(3*17-1 downto 2*17), ep_addr=>x"80",
--								ep_write=>pipe_in_write, ep_blockstrobe=> bs_in, 
--								ep_dataout=>pipe_in_data, ep_ready=>pipe_in_ready);

	epA0: okBTPipeOut port map (okHE=>okHE, okEH=>okEHx(1*65-1 downto 0*65), ep_addr=>x"A0",
								ep_read=>pipe_out_read, ep_blockstrobe=> bs_out,
								ep_datain=>pipe_out_data, ep_ready=>pipe_out_ready);

	-- ep80: okBTPipeIn port map (okHE=>okHE, okEH=>okEHx(2*65-1 downto 1*65), ep_addr=>x"80",
	-- 							ep_write=>pipe_in_write, ep_blockstrobe=> bs_in, 
	-- 							ep_dataout=>pipe_in_data, ep_ready=>pipe_in_ready); -- ep_write is w_en
									
end Behavioral;
