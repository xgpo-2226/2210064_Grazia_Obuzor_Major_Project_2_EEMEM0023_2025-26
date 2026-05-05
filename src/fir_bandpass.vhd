-- 12-tap symmetric bandpass filter (Q9 fixed-point)
-- removes baseline wander (<0.5 Hz) and high-frequency noise (>40 Hz).
-- Input: 12-bit signed ADC sample at 250 Hz
-- Output: 12-bit signed filtered sample (at y=0) 
--          and  12-bit unsigned ecg wave display value (at y=2048 for sinus reading render)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fir_bandpass is
    Port (
        clk         : in  STD_LOGIC;
        sample_in   : in  signed(11 downto 0);      -- raw ADC, signed
        sample_en   : in  STD_LOGIC;                -- process one sample
        filt_out    : out signed(11 downto 0);      -- signed filtered (centred at 0) 
        display_out : out integer range 0 to 4095;  -- unsigned (filt + 2048 for ASCII conversion)
        ready       : out STD_LOGIC                 -- outputs valid signal
    );
end fir_bandpass;

architecture behav of fir_bandpass is
    constant FIR_LEN   : integer := 12;
    constant FIR_SHIFT : integer := 9;  -- Q9 shift, divide accumulator by 512
    
    -- signed to avoid wrapping for negative values tirggering false peaks
    -- from oldest to newest samples
    type fir_buf_t is array (0 to FIR_LEN-1) of signed(11 downto 0); -- i.e. -2048 to +2047
    signal buf : fir_buf_t := (others => (others => '0'));

    -- half-coefficients for symmetric folding (saves multipliers)
    type coeff_t is array (0 to 5) of integer;
    constant C : coeff_t := (-116, -4, -38, -4, 99, 191); -- Parks-McClellan design

    signal acc_reg  : signed(23 downto 0) := (others => '0'); -- accumulator
    signal do_scale : std_logic := '0';  -- delayed ready for 2-stage pipeline (filter, then shifting)
begin
    -- filter: shift samples in, multiply-accumulate with symmetric folding
    process(clk)
        variable acc : signed(23 downto 0);
        variable s0, s1, s2, s3, s4, s5 : signed(12 downto 0); -- 5 coefficeints for Parks-McClellan filter
    begin
        if rising_edge(clk) then
            do_scale <= '0';
            if sample_en = '1' then
                -- Shift delay line
                for i in 0 to FIR_LEN-2 loop
                    buf(i) <= buf(i+1);
                end loop;
                buf(FIR_LEN-1) <= sample_in;

                -- get symmetric pairs buf(k) + buf(11-k)
                s0 := resize(buf(0),13) + resize(buf(11),13); -- cast to 13 to avoid 12-bit addition overflow
                s1 := resize(buf(1),13) + resize(buf(10),13);
                s2 := resize(buf(2),13) + resize(buf(9),13);
                s3 := resize(buf(3),13) + resize(buf(8),13);
                s4 := resize(buf(4),13) + resize(buf(7),13);
                s5 := resize(buf(5),13) + resize(buf(6),13);

                -- multiply each pair by its coefficient (from factoring)
                acc := resize(s0 * to_signed(C(0),10), 24) -- cast to 24 to prevent overflow
                     + resize(s1 * to_signed(C(1),10), 24)
                     + resize(s2 * to_signed(C(2),10), 24)
                     + resize(s3 * to_signed(C(3),10), 24)
                     + resize(s4 * to_signed(C(4),10), 24)
                     + resize(s5 * to_signed(C(5),10), 24);
                acc_reg  <= acc;
                do_scale <= '1';
            end if;
        end if;
    end process;

    -- shifting: scale from Q9 and produce display value
    -- 1 extra flip flop is more efficient than one long process that depends on stage 1
    process(clk)
        variable shifted : integer range -4096 to 4095;
    begin
        if rising_edge(clk) then
            ready <= '0';
            if do_scale = '1' then
                shifted := to_integer(acc_reg(23 downto FIR_SHIFT)); -- divide by 512
                filt_out <= to_signed(shifted, 12);
                -- add 2048 offset to make unsigned for display/UART
                if    shifted + 2048 > 4095 then display_out <= 4095;
                elsif shifted + 2048 < 0    then display_out <= 0; -- clip errors to avoid wrapped dips/peaks
                else                              display_out <= shifted + 2048;
                end if;
                ready <= '1';
            end if;
        end if;
    end process;
end behav;
