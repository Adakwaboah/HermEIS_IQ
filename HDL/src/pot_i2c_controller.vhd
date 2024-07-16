library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


entity pot_i2c_controller is 
    generic (
		  command_code: std_logic_vector(7 downto 0) := b"0000_0000";
		  address:      std_logic_vector(6 downto 0) := b"010_1110";
		  word_size:	 natural	:= 8
		  );
	 port(
		  rst:        in          std_logic;
		  clk:        in          std_logic;
		  scl:        inout       std_logic;
		  sda:        inout       std_logic;
		  pot_write_byte:   in          std_logic_vector(word_size-1 downto 0);
		  pot_read_byte:  out         std_logic_vector(word_size-1 downto 0);
		  trig:       in          std_logic;
		  rw_mode:    in          std_logic;
		  nBytes:     in          unsigned(2 downto 0)
    );
end pot_i2c_controller;

architecture behavioral of pot_i2c_controller is
    signal sda_reg, sda_next:   std_logic;
    signal scl_reg, scl_next:   std_logic;
    signal hold_count_reg, hold_count_next: unsigned(word_size-1 downto 0):= (others=>'0');
    type state_type is (idle, start_bit, write1, write2, read_ack1, read_ack2,
                     read_data1, read_data2, write_ack1, write_ack2, post_ack,
                    stop1, stop2);
    signal state_reg, state_next: state_type:= idle;
    signal idx_reg, idx_next: unsigned(5 downto 0) := (others=>'0'); -- up to 64 bits word size count
    signal byte_reg, byte_next: std_logic_vector(word_size-1 downto 0):= address&'0';
    signal ack_reg, ack_next: std_logic := '0';
    signal post_add_reg, post_add_next: std_logic:= '0';
    signal read_ready_reg, read_ready_next: std_logic:='0';
    signal byte_count_reg, byte_count_next: unsigned(2 downto 0) := b"001";
    signal read_buffer_reg, read_buffer_next: std_logic_vector(word_size-1 downto 0):=(others=>'0');
	 --signal pot_byte: std_logic_vector(7 downto 0) := (others=>'0');
	 signal trig_out: std_logic;

begin
    sda <= '0' when sda_reg = '0' else 'Z';
    scl <= '0' when scl_reg = '0' else 'Z';
    --data_in <= b"0000"&state_count_reg;
	 pot_read_byte <= read_buffer_reg;
	 --pot_byte <= data_out;
	 --led <= led_reg;

    seq: process(clk)
    begin
        if rising_edge(clk) then
            sda_reg <= sda_next;
            scl_reg <= scl_next;
				state_reg <= state_next;
				hold_count_reg <= hold_count_next;
				idx_reg        <= idx_next;
				byte_reg       <= byte_next;
				byte_count_reg <= byte_count_next;
				read_buffer_reg <= read_buffer_next;
				ack_reg			<= ack_next;
				post_add_reg	<= post_add_next;
				read_ready_reg <= read_ready_next;
				--led_reg 			<= led_next;
				--state_count_reg <= state_count_next;
				--restart_reg <= restart_next;
				--rw_mode_reg <= rw_mode_next;
        end if;   
    end process seq;

    comb: process(sda_reg, scl_reg, scl, sda, hold_count_reg,
                idx_reg, byte_reg, ack_reg, state_reg, byte_count_reg,
                read_buffer_reg, trig_out, read_ready_reg, post_add_reg,
					 pot_write_byte, rst, nBytes, trig, rw_mode)
    begin
        if rst = '1' then
            state_next <= idle;
        end if;
        state_next      <= state_reg;
        sda_next        <= sda_reg;
        scl_next        <= scl_reg;
        hold_count_next <= hold_count_reg;
        idx_next        <= idx_reg;
        byte_next       <= byte_reg;
        byte_count_next <= byte_count_reg;
        read_buffer_next <= read_buffer_reg;
		  ack_next			<= ack_reg;
		  post_add_next	<= post_add_reg;
		  read_ready_next <= read_ready_reg;
		  --led_next 			<= led_reg;
		  --state_count_next <= state_count_reg;
		  --restart_next <= restart_reg;
		  --rw_mode_next <= rw_mode_reg;

        case state_reg is
            when idle =>
                sda_next <= '1';
                scl_next <= '1';
					 --state_count_next <= b"0000";
                hold_count_next <= (others=>'0');
                idx_next <= to_unsigned(word_size-1, 6);
                byte_count_next <= nBytes;
					 --led_next <= '0';
					 read_ready_next <= '0';
					 post_add_next <= '0';
                if (trig = '1') then
                    state_next <= start_bit;
						  --restart_next <= '0';
						  --led_next <= '1';
                end if;

            --------------------------------------------------------------
            when start_bit =>
				--state_count_next <= b"0001";
               if scl = '1' then
                    sda_next <= '0';
						  --led_next <= '0'; 
                    if hold_count_reg = to_unsigned(119, 8) then
                        scl_next <= '0';
                        hold_count_next <= (others=>'0');
                        state_next <= write1;
                        byte_next <= address & '0';
								--led_next <= '0';
                    else
                        hold_count_next <= hold_count_reg + 1;
                  end if;
             end if;
            
            --------------------------------------------------------------
            when write1 => 
				--state_count_next <= b"0010";
                if scl = '0' then --clock stretching
                    if hold_count_reg = to_unsigned(119, 8) then
                        sda_next <= byte_reg(to_integer(idx_reg));
                        hold_count_next <= hold_count_reg + 1;
                    elsif hold_count_reg = to_unsigned(239, 8) then
                        hold_count_next <= (others=>'0');
                        scl_next <= '1';
                        state_next <= write2;
								--led_next <= '1'; 
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;

            --------------------------------------------------------------
            when write2 => 
				--state_count_next <= b"0011";
                if scl = '1' then
                    if hold_count_reg = to_unsigned(239, 8) then
                        scl_next <= '0';
                        hold_count_next <= (others=>'0');
                        if (idx_reg > 0) then
                            idx_next <= idx_reg - 1;
                            state_next <= write1;
                        else
                            idx_next <= to_unsigned(word_size-1, 6);                            
                            state_next <= read_ack1;
                        end if;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;

            --------------------------------------------------------------
            when read_ack1 =>
				--state_count_next <= b"0100";
					--led_next <= '1'; 
                if scl = '0' then
                    if hold_count_reg = to_unsigned(119, 8) then
                        hold_count_next <= hold_count_reg + 1;
                        sda_next <= '1'; --release sda
                    elsif hold_count_reg = to_unsigned(239, 8) then
                        hold_count_next <= (others=>'0');
                        scl_next <= '1';
                        state_next <= read_ack2;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;

            --------------------------------------------------------------
            when read_ack2 =>
				--state_count_next <= b"0101";
                if scl = '1' then
                    if hold_count_reg = to_unsigned(119, 8) then
                        hold_count_next <= hold_count_reg + 1;
                        ack_next <= sda; --read ack
                    elsif hold_count_reg = to_unsigned(239, 8) then
                        hold_count_next <= (others=>'0');
                        scl_next <= '0';
                        state_next <= post_ack;
						  else
								hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;
             
            --------------------------------------------------------------
            when post_ack =>
					 if scl = '0' then
						 if ack_reg = '1' then
--							  if hold_count_reg = to_unsigned(119, 8) then
--									hold_count_next <= hold_count_reg + 1;
--									sda_next <= '1';
--							  elsif hold_count_reg = to_unsigned(239, 8) then
--									hold_count_next <= (others=>'0');
--									scl_next <= '1';
									state_next <= stop1; --restart
									--restart_next <= '1'; --retry transmission
--							  else
--									hold_count_next <= hold_count_reg + 1;
--							  end if;

						 else
							--state_count_next <= b"0110";
							  if post_add_reg = '0' then
									byte_next <= command_code;
									post_add_next <= '1';
									state_next <= write1;

							  else
									if rw_mode = '1' then --read
										 if read_ready_reg = '0' then
											  byte_next <= address & '1';
											  read_ready_next <= '1';
											  state_next <= write1;
										 else
											  state_next <= read_data1;
											  read_ready_next <= '0';
											  post_add_next <= '0';
										 end if;
									else --write
										 byte_next <= pot_write_byte;
										 state_next <= write1;
										 byte_count_next <= byte_count_reg - 1;
										 if byte_count_reg = 0 then
											  state_next <= stop1;
											  post_add_next <= '0';
											  byte_count_next <= nBytes;
										 end if;
									end if;
							  end if;
						 end if;
					 end if;
					 
--				when pre_restart =>
--					state_count_next <= b"1101";
--					if scl='1' then
--						if hold_count_reg = to_unsigned(119, 8) then
--							state_next <= start_bit;
--							hold_count_next <= (others=>'0');
--						else
--							hold_count_next <= hold_count_reg + 1;
--						end if;
--					end if;

            --------------------------------------------------------------
            when read_data1 =>
				--state_count_next <= b"0111";
                if scl = '0' then
                    if hold_count_reg = to_unsigned(119, 8) then
                        sda_next <= '1'; --release data
                        hold_count_next <= hold_count_reg + 1;
                    elsif hold_count_reg = to_unsigned(239, 8) then
                        hold_count_next <= (others=>'0');
                        scl_next <= '1';
                        state_next <= read_data2;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;

            --------------------------------------------------------------
            when read_data2 =>
				--state_count_next <= b"1000";
                if scl = '1' then
                    if hold_count_reg = to_unsigned(119, 8) then
                        hold_count_next <= hold_count_reg + 1;
                        read_buffer_next(to_integer(idx_reg)) <= sda;
                    elsif hold_count_reg = to_unsigned(239, 8) then
                        hold_count_next <= (others=>'0');
                        scl_next <= '0';
                        if idx_reg > 0 then
                            idx_next <= idx_reg - 1;
                            state_next <= read_data1;
                        else
                            idx_next <= to_unsigned(word_size-1, 6);
                            state_next <= write_ack1;
                        end if;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;

            --------------------------------------------------------------
            when write_ack1 =>
				--state_count_next <= b"1001";
                if scl = '0' then
                    if hold_count_reg = to_unsigned(119, 8) then
                        if byte_count_reg - 1 > 0 then
                            sda_next <= '0'; -- may change for multi byte
                        else
                            sda_next <= '1'; --A_bar last byte
                        end if;
                        hold_count_next <= hold_count_reg + 1;
                    elsif hold_count_reg = to_unsigned(239, 8) then
                        hold_count_next <= (others=>'0');
                        scl_next <= '1';
                        state_next <= write_ack2;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;

            --------------------------------------------------------------
            when write_ack2 =>
				--state_count_next <= b"1010";
                if scl = '1' then
                    if hold_count_reg = to_unsigned(239, 8) then
                        scl_next <= '0';
                        hold_count_next <= (others=>'0');
                        byte_count_next <= byte_count_reg - 1;
							   if byte_count_reg = 1 then
									state_next <= stop1;
									byte_count_next <= nBytes;
							   else
									state_next <= read_data1;
							   end if;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;			
				
            --------------------------------------------------------------
            when stop1 =>
				--state_count_next <= b"1011";
                if scl = '0' then
                    if hold_count_reg = to_unsigned(119, 8) then
                        sda_next <= '0';
                        hold_count_next <= hold_count_reg + 1;
                    elsif hold_count_reg = to_unsigned(239, 8) then
                        hold_count_next <= (others=>'0');
                        scl_next <= '1';
                        state_next <= stop2;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;

            --------------------------------------------------------------
            when stop2 =>
				--state_count_next <= b"1100";
                if scl = '1' then
                    if hold_count_reg = to_unsigned(119, 8) then
                        sda_next <= '1';
                        hold_count_next <= (others=>'0');
                        state_next <= idle;
								--rw_mode_next <= not rw_mode_reg;
                    else
                        hold_count_next <= hold_count_reg + 1;
                    end if;
                end if;
        end case;
    end process comb;
end behavioral;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

package i2c_pkg is
	component pot_i2C_controller 
	 generic (
		  command_code: std_logic_vector(7 downto 0) := b"0000_0000";
		  address:      std_logic_vector(6 downto 0) := b"010_1110";
		  word_size:	 natural	:= 8
		  );
	 port(
		  rst:        in          std_logic;
		  clk:        in          std_logic;
		  scl:        inout       std_logic;
		  sda:        inout       std_logic;
		  pot_write_byte:   in          std_logic_vector(word_size-1 downto 0);
		  pot_read_byte:  out         std_logic_vector(word_size-1 downto 0);
		  trig:       in          std_logic;
		  rw_mode:    in          std_logic;
		  nBytes:     in          unsigned(2 downto 0)
	 );
	 end component;

end package;
