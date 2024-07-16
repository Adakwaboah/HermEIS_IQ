-- Written by Akwasi Akwaboah
-- Date: 07/25/2023
-- Description: In-phase and Quadrature Component extraction from ADC sinusoidal input
--              This will help reduce bandwidth to single I/Q pair values and will eliminate 
--              the need for high bandwidth data characteristic of nyquist sampling

library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all ;
-- use IEEE.STD_LOGIC_ARITH.ALL;
-- use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity IQ_gen is
 generic (
    adcBits :   natural := 10;--adcBits_val;
    -- N_samps       :   natural := 2**18; --specifi 
    N_samps_bits  :   natural := 32;
    Nbits   :   natural := 32;
    dds_bits :   natural := 32;
    f_clk   :    natural := 100_000_000
 );

  port (
    clk:        in      std_logic;
    rst:        in      std_logic;
    -- freq:       in      std_logic_vector(dds_bits-1 downto 0) := std_logic_vector(to_unsigned(10_000, dds_bits)); -- test Freq
    X_in:       in      std_logic_vector(adcBits-1 downto 0); -- ADC data
    Samp_in:    in      std_logic;                        -- indicate arrival of ADC sample    
    int_en:     in      std_logic;                        -- start integration
    int_end:    out      std_logic;   
    I_out:      out     std_logic_vector( Nbits-1 downto 0); -- In-phase
    Q_out:      out     std_logic_vector( Nbits-1 downto 0); -- Quadrature
    --SigmaX_out  out     std_logic_vector(Nbits-1 downto 0); -- Sum(X_in) = T*mean(X_in) | needed for removal offset from I/Q
    S0:          out    signed(N_samps_bits-1 downto 0); --for debugging
    S1:          out    signed(N_samps_bits-1 downto 0); --for debugging
    S2:          out    signed(N_samps_bits-1 downto 0); --for debugging
    S3:          out    signed(N_samps_bits-1 downto 0); --for debugging
    fc:          in     unsigned(N_samps_bits-1 downto 0); --fcw
    fsamp_cn:    in     unsigned(N_samps_bits-1 downto 0) --sampling frequency (dynamic based on Freq In)
    ) ;
end IQ_gen ; 

architecture arch of IQ_gen is
    signal qSamp_count : unsigned(N_samps_bits-1 downto 0):=(others=>'0');  
    -- signal q_end    : std_logic:='0';
    signal X_in_buf   : unsigned(N_samps_bits-1 downto 0):= (others=>'0');
    signal X_in_sig   : unsigned(N_samps_bits-1 downto 0):= (others=>'0');
    type S_arr is array (0 to 3) of signed(N_samps_bits-1 downto 0);
	 type Xm_arr is array (0 to 3) of unsigned(N_samps_bits-1 downto 0);
    signal S:   S_arr := (others=>(others=>'0'));
    -- signal s_idx :      unsigned(1 downto 0) :=(others=>'1');
    signal j :      unsigned(1 downto 0) :=(others=>'1');
    signal I_sig :      signed(N_samps_bits-1 downto 0):= (others=>'0');
    signal Q_sig :      signed(N_samps_bits-1 downto 0):= (others=>'0');
--    signal X_s :        signed(Nbits-1 downto 0):= (others=>'0');
    signal r : Xm_arr := (others=>(others=>'0'));
    signal Xm : Xm_arr := (others=>(others=>'0')); 
    signal first_samp : std_logic := '0';
    -- signal qPrd :       unsigned(rBits-1 downto 0);
    -- signal fc : signed(Nbits-1 downto 0);
    -- signal fsamp_cn : signed(Nbits-1 downto 0);
	signal f_dds_scale : integer range 0 to 255 := 43; --(2**dds_bits)/f_clk;
    signal X_bar : signed(N_samps_bits-1 downto 0):= (others=>'0');
	signal fc_4 : unsigned(N_samps_bits-1 downto 0):=(others=>'0');
    signal T : unsigned(N_samps_bits-1 downto 0):=(others=>'0');
    
begin
    I_out <= std_logic_vector(I_sig(Nbits-1 downto 0)); -- std_logic_vector(to_unsigned(2**18, Nbits));--
    Q_out <= std_logic_vector(Q_sig(Nbits-1 downto 0)); -- std_logic_vector(to_unsigned(2**19, Nbits)); --
    X_in_sig <= to_unsigned(0, N_samps_bits-10) & unsigned(X_in);
    S0 <= S(0);
    S1 <= S(1);
    S2 <= S(2);
    S3 <= S(3);
    -- fc_4 <= fc sll 2;
    -- T <= fsamp_cn/fc;
    -- fc <= to_signed(to_integer(f_dds_scale*unsigned(freq)), Nbits);
    -- fsamp_c <= to_signed(to_integer(f_dds_scale*unsigned(F_samp)), N_samps_bits+adcBits+1);

-- Compute quarter Integrals (S1, S2, S3_var, S4)
--- quarter integrator ---
process(clk, int_en, Samp_in, rst, first_samp) --, q_end)
    variable S3_var : signed(N_samps_bits-1 downto 0):= (others=>'0');
    variable S_sum : signed(N_samps_bits-1 downto 0):= (others=>'0');
    variable r_n : unsigned(N_samps_bits-1 downto 0):= (others=>'0');
    variable Xm_n : unsigned(N_samps_bits-1 downto 0):= (others=>'0');
	 variable Sa : unsigned(2*N_samps_bits-1 downto 0):= (others=>'0');
	 variable Sb : unsigned(N_samps_bits-1 downto 0):= (others=>'0');
	 variable Sc : unsigned(2*N_samps_bits-1 downto 0):= (others=>'0');
	--  variable I_sig_v : signed(N_samps_bits-1 downto 0):= (others=>'0');
	--  variable Q_sig_v : signed(N_samps_bits-1 downto 0):= (others=>'0');
    -- variable T_sig :   signed(N_samps_bits-1 downto 0):= (others=>'0');
begin
    if (rst='1') then
        X_in_buf <= (others=>'0');  
        I_sig   <= (others=>'0');
        Q_sig   <= (others=>'0');
        int_end <= '0';
        -- q_end <= '0';
        first_samp <= '0';
        S <= (others=>(others=>'0'));
        r <= (others=>(others=>'0'));
        Xm <= (others=>(others=>'0'));
        -- qSamp_count <= to_unsigned(to_integer(fsamp_cn/(4*to_integer(fc))), Nbits);
        qSamp_count <= (others=>'0');--fsamp_cn/(fc_4);
        j <= (others=>'1');
		fc_4 <= to_unsigned(1, N_samps_bits);--fc sll 2;
        T <= (others=>'1');--fsamp_cn/fc;
    else
        if rising_edge(clk) then
            -- qSamp_count <= fsamp_cn/(fc sll 2);
            fc_4 <= fc sll 2;
            T <= fsamp_cn/fc;
            if (int_en = '1') then
                int_end <='0';
                -- q_end <= '0';
                
                if Samp_in = '1' then
                    first_samp <= '1';   
                end if;
                    
                -- Default case: if (Int_mode >= 4) then
                if first_samp = '1' then 
                -- ensure first sample from ADC in 
                -- useful in single and continuous mode I/Q gen
                    if (Samp_in = '1') then
                        qSamp_count <= qSamp_count + 1;
                        X_in_buf <= X_in_buf + X_in_sig;
                        if qSamp_count = (fsamp_cn/fc_4) then
                            r_n := ((j+1)*fsamp_cn) mod fc_4;
                            Xm_n := X_in_sig;
									 Sa := r(to_integer(j))*Xm(to_integer(j))/fc_4;
									 Sb := X_in_buf+X_in_sig;
									 Sc := (fc_4 - r_n)*Xm_n/fc_4;
                            S(to_integer(j)) <= signed(Sb)-signed(Sa(N_samps_bits-1 downto 0))-signed(Sc(N_samps_bits-1 downto 0));                 
                            r(to_integer(j+1)) <= ((j+1)*fsamp_cn) mod fc_4;
                            Xm(to_integer(j+1)) <= X_in_sig;
                            j <= j + 1;
                            X_in_buf <= X_in_sig;
                            -- q_end <= '1';
                            qSamp_count <= to_unsigned(1, N_samps_bits);
                            if j = 3 then --cycle end
                                S3_var := signed(Sb)-signed(Sa(N_samps_bits-1 downto 0))-signed(Sc(N_samps_bits-1 downto 0));   
                                S_sum := S(0)+S(1)+S(2)+S3_var;
                                j <= (others=>'0');
                                -- T_sig := signed(T(N_samps_bits-1 downto 0));
                                -- I_sig_v := (S(0) + S(1) - (S(2) + S3_var))/2; --/2;
                                -- Q_sig_v := (S(1) + S(2) - (S(0) + S3_var))/2; --/2;
                                I_sig <= (S(0) + S(1) - (S(2) + S3_var))/2; -- I_sig/2
                                Q_sig <= (S(1) + S(2) - (S(0) + S3_var))/2; --Q_sig_v; -- I_sig/2	 
                                x_bar <= S_sum; --/signed(fsamp_cn/fc);
                                int_end <= '1';
                            end if;
                        end if;
                    end if;
                end if;

            else
               
                S <= (others=>(others=>'0'));
                X_in_buf <= (others=>'0');   
                r <= (others=>(others=>'0'));
                Xm <= (others=>(others=>'0'));
                first_samp <= '0';
                -- I_sig <= (others=>'0');
                -- Q_sig <= (others=>'0');
            end if;
        end if;
    end if;
end process; 



end architecture ;
