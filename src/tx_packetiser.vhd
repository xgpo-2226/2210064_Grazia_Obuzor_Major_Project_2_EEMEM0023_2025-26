-- Moore FSM that builds and sends 28-byte UART packets
-- packet: AAAA,PPPP,RRRR,QQQQ,CCCC,S\r\n
-- Outputs are FIXED per state:
--   IDLE:      tx_start=0, waits for trigger
--   PREPARE:   tx_start=0, builds one byte per clock
--   LOAD_BYTE: tx_start=1, loads pkt(idx) onto tx_data
--   WAIT_TX:   tx_start=0, waits for uart_tx to finish

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tx_packetiser is
    Port (
        clk          : in  STD_LOGIC;
        trigger      : in  STD_LOGIC;  -- sample_ready pulse
        -- data inputs (latched on trigger)
        in_adc       : in  integer range 0 to 4095; -- for ecg (filtered) display
        in_peak      : in  integer range 0 to 4095; -- from peak_detector
        in_rr        : in  integer range 0 to 9999;
        in_area      : in  integer range 0 to 9999;
        in_evt       : in  integer range 0 to 9999;
        in_state     : in  integer range 0 to 2;
        -- UART interface
        tx_data      : out std_logic_vector(7 downto 0);
        tx_start     : out STD_LOGIC;
        tx_done      : in  STD_LOGIC
    );
end tx_packetiser;

architecture behav of tx_packetiser is
    constant PKT_LEN : integer := 28;
    type pkt_t is array (0 to PKT_LEN-1) of std_logic_vector(7 downto 0);
    signal pkt : pkt_t := (others => (others => '0'));
    signal idx : integer range 0 to PKT_LEN-1 := 0;

    -- latched copies of inputs frozen at trigger moment
    signal la, lp, lr, lq, le : integer range 0 to 9999 := 0;
    signal ls : integer range 0 to 2 := 0;

    type state_type is (IDLE, PREPARE, LOAD_BYTE, WAIT_TX);
    signal nextState : state_type := IDLE;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            case nextState is
                when IDLE =>
                    tx_start <= '0';
                    if trigger = '1' then
                        la <= in_adc; lp <= in_peak; lr <= in_rr;
                        lq <= in_area; le <= in_evt; ls <= in_state;
                        idx <= 0; nextState <= PREPARE;
                    end if;

                when PREPARE =>
                    tx_start <= '0';
                    -- ASCII conversion of each byte values, commas, carriage return and newline feed
                    case idx is
                        when 0  => pkt(0)  <= std_logic_vector(to_unsigned(48+la/1000,8));
                        when 1  => pkt(1)  <= std_logic_vector(to_unsigned(48+(la/100) mod 10,8));
                        when 2  => pkt(2)  <= std_logic_vector(to_unsigned(48+(la/10) mod 10,8));
                        when 3  => pkt(3)  <= std_logic_vector(to_unsigned(48+la mod 10,8));
                        when 4  => pkt(4)  <= x"2C";
                        when 5  => pkt(5)  <= std_logic_vector(to_unsigned(48+lp/1000,8));
                        when 6  => pkt(6)  <= std_logic_vector(to_unsigned(48+(lp/100) mod 10,8));
                        when 7  => pkt(7)  <= std_logic_vector(to_unsigned(48+(lp/10) mod 10,8));
                        when 8  => pkt(8)  <= std_logic_vector(to_unsigned(48+lp mod 10,8));
                        when 9  => pkt(9)  <= x"2C";
                        when 10 => pkt(10) <= std_logic_vector(to_unsigned(48+lr/1000,8));
                        when 11 => pkt(11) <= std_logic_vector(to_unsigned(48+(lr/100) mod 10,8));
                        when 12 => pkt(12) <= std_logic_vector(to_unsigned(48+(lr/10) mod 10,8));
                        when 13 => pkt(13) <= std_logic_vector(to_unsigned(48+lr mod 10,8));
                        when 14 => pkt(14) <= x"2C";
                        when 15 => pkt(15) <= std_logic_vector(to_unsigned(48+lq/1000,8));
                        when 16 => pkt(16) <= std_logic_vector(to_unsigned(48+(lq/100) mod 10,8));
                        when 17 => pkt(17) <= std_logic_vector(to_unsigned(48+(lq/10) mod 10,8));
                        when 18 => pkt(18) <= std_logic_vector(to_unsigned(48+lq mod 10,8));
                        when 19 => pkt(19) <= x"2C";
                        when 20 => pkt(20) <= std_logic_vector(to_unsigned(48+le/1000,8));
                        when 21 => pkt(21) <= std_logic_vector(to_unsigned(48+(le/100) mod 10,8));
                        when 22 => pkt(22) <= std_logic_vector(to_unsigned(48+(le/10) mod 10,8));
                        when 23 => pkt(23) <= std_logic_vector(to_unsigned(48+le mod 10,8));
                        when 24 => pkt(24) <= x"2C";
                        when 25 => pkt(25) <= std_logic_vector(to_unsigned(48+ls,8));
                        when 26 => pkt(26) <= x"0D";
                        when 27 => pkt(27) <= x"0A";
                        when others => null;
                    end case;
                    if idx = PKT_LEN-1 then idx <= 0; nextState <= LOAD_BYTE;
                    else idx <= idx+1; end if;

                -- one pulse to send byte to uart_tx module
                when LOAD_BYTE =>
                    tx_data  <= pkt(idx);
                    tx_start <= '1';
                    nextState      <= WAIT_TX;

                -- wait until uart_Tx is done
                when WAIT_TX =>
                    tx_start <= '0';
                    if tx_done = '1' then
                        if idx = PKT_LEN-1 then nextState <= IDLE;
                        else idx <= idx+1; nextState <= LOAD_BYTE; end if;
                    end if;
                when others => nextState <= IDLE;             
            end case;
        end if;
    end process;
end behav;
