library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    Generic (
        CLK_FREQ  : integer := 12000000;
        BAUD_RATE : integer := 57600 -- determines bit period, PWM for uart comms (overwritten in top if needed)
    );
    Port (
        clk       : in  STD_LOGIC;
        tx_start  : in  STD_LOGIC;
        tx_data   : in  STD_LOGIC_VECTOR(7 downto 0);
        tx_serial : out STD_LOGIC;
        tx_done   : out STD_LOGIC
    );
end uart_tx;

architecture behav of uart_tx is

    constant BIT_PERIOD : integer := CLK_FREQ / BAUD_RATE;

    signal bit_timer   : integer range 0 to BIT_PERIOD-1 := 0;
    signal bit_index   : integer range 0 to 7 := 0;
    signal tx_data_reg : std_logic_vector(7 downto 0) := (others => '0');

    type state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal nextState : state_type := IDLE;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            tx_done <= '0';

            case nextState is

                when IDLE =>
                    tx_serial <= '1'; -- last latched data is sent and protocol is currently'paused'
                    if tx_start = '1' then
                        tx_data_reg <= tx_data;
                        bit_timer   <= 0;
                        nextState       <= START_BIT;
                    end if;

                -- per UART protocol 1 low bit, 8 byte, 1 high bit
                when START_BIT =>
                    tx_serial <= '0';
                    if bit_timer < BIT_PERIOD - 1 then
                        bit_timer <= bit_timer + 1;
                    else
                        bit_timer <= 0;
                        bit_index <= 0;
                        nextState     <= DATA_BITS;
                    end if;

                when DATA_BITS =>
                    tx_serial <= tx_data_reg(bit_index);
                    if bit_timer < BIT_PERIOD - 1 then
                        bit_timer <= bit_timer + 1;
                    else
                        bit_timer <= 0;
                        if bit_index < 7 then
                            bit_index <= bit_index + 1;
                        else
                            nextState <= STOP_BIT;
                        end if;
                    end if;

                when STOP_BIT =>
                    tx_serial <= '1';
                    if bit_timer < BIT_PERIOD - 1 then
                        bit_timer <= bit_timer + 1;
                    else
                        tx_done <= '1';         -- signal done for one pulse
                        nextState   <= IDLE; 
                    end if;

                when others =>
                    nextState <= IDLE;

            end case;
        end if;
    end process;

end behav;
