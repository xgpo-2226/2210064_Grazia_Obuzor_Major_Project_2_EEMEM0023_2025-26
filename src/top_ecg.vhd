-- top_ecg.vhd - Top-level wrapper (modular version)
-- Instantiates: XADC, fir_bandpass, peak_detector, tx_packetiser, uart_tx
-- Contains only: clock divider, XADC capture, LED, and wiring between modules.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_ecg is
    Port (
        sys_clk : in  STD_LOGIC;   -- 12 MHz board oscillator
        vauxp4  : in  STD_LOGIC;   -- XADC analogue input +
        vauxn4  : in  STD_LOGIC;   -- XADC analogue input -
        usb_tx  : out STD_LOGIC;   -- UART TX to PC
        led     : out STD_LOGIC    -- heartbeat LED (to check if FPGA is operating)
    );
end top_ecg;

architecture Structural of top_ecg is

    -- from xadc register
    signal do_out   : std_logic_vector(15 downto 0);
    signal eoc_out, drdy_out : std_logic;
    signal ecg_raw  : signed(11 downto 0) := (others => '0');

    -- clock frequency for all modules all modules
    constant SAMPLE_PERIOD : integer := 48000;  -- 12 MHz / 48000 = 250 Hz
    signal sample_ctr   : integer range 0 to SAMPLE_PERIOD-1 := 0;
    signal sample_ready : std_logic := '0';

    -- FIR outputs to peak detector
    signal fir_sample  : signed(11 downto 0);
    signal fir_display : integer range 0 to 4095;
    signal fir_ready   : std_logic;

    -- peak detector feeds into packetiser
    signal rr_latched     : integer range 0 to 9999;
    signal peak_amp       : integer range 0 to 4095;
    signal qrs_area       : integer range 0 to 9999;
    signal apnoea_state   : integer range 0 to 2;
    signal apnoea_evt_ctr : integer range 0 to 9999;

    -- packetiser sent via UART TX
    signal tx_data  : std_logic_vector(7 downto 0);
    signal tx_start, tx_done : std_logic;

    -- debug LED
    signal led_ctr : integer range 0 to 6000000 := 0;
    signal led_reg : std_logic := '0';

    -- Component declarations 
    component xadc_wiz_0
        port (
            daddr_in : in STD_LOGIC_VECTOR(6 downto 0);
            dclk_in, den_in, dwe_in, reset_in : in STD_LOGIC;
            di_in : in STD_LOGIC_VECTOR(15 downto 0);
            vauxp4, vauxn4, vp_in, vn_in : in STD_LOGIC;
            do_out : out STD_LOGIC_VECTOR(15 downto 0);
            drdy_out, eoc_out : out STD_LOGIC;
            channel_out : out STD_LOGIC_VECTOR(4 downto 0);
            eos_out, busy_out : out STD_LOGIC
        );
    end component;

begin
    -- xadc instance
    ADC_INST : xadc_wiz_0
    port map (
        daddr_in => "0010100", dclk_in => sys_clk, den_in => eoc_out,
        di_in => (others=>'0'), dwe_in => '0', reset_in => '0',
        vauxp4 => vauxp4, vauxn4 => vauxn4, vp_in => '0', vn_in => '0',
        do_out => do_out, drdy_out => drdy_out, eoc_out => eoc_out,
        channel_out => open, eos_out => open, busy_out => open
    );

    -- latch 12-bit ADC value on data-ready
    process(sys_clk) begin
        if rising_edge(sys_clk) then
            if drdy_out = '1' then
                ecg_raw <= signed(do_out(15 downto 4));
            end if;
        end if;
    end process;

    -- (250 Hz) clock
    process(sys_clk) begin
        if rising_edge(sys_clk) then
            if sample_ctr = SAMPLE_PERIOD-1 then
                sample_ctr <= 0; sample_ready <= '1';
            else
                sample_ctr <= sample_ctr + 1; sample_ready <= '0';
            end if;
        end if;
    end process;

    -- FIR bandpass
    FIR_INST : entity work.fir_bandpass
    port map (
        clk => sys_clk, sample_in => ecg_raw, sample_en => sample_ready,
        filt_out => fir_sample, display_out => fir_display, ready => fir_ready
    );

    -- peak detector and apnoea
    PEAK_INST : entity work.peak_detector
    generic map (
        PEAK_THRESHOLD => 900, REFRACTORY => 90, MIN_SLOPE => 50,
        ENV_AMP_THRESH => 50, ENV_RR_THRESH => 7, ENV_AREA_THRESH => 13,
        HYPO_LIMIT => 750, APNOEA_LIMIT => 1250
    )
    port map (
        clk => sys_clk, fir_sample => fir_sample, fir_display => fir_display,
        fir_ready => fir_ready,
        rr_latched => rr_latched, peak_amp => peak_amp,
        qrs_area_out => qrs_area,
        apnoea_state => apnoea_state, apnoea_evt_ctr => apnoea_evt_ctr,
        beat_detected => open
    );

    -- TX packet
    PKT_INST : entity work.tx_packetiser
    port map (
        clk => sys_clk, trigger => sample_ready,
        in_adc => fir_display, in_peak => peak_amp,
        in_rr => rr_latched, in_area => qrs_area,
        in_evt => apnoea_evt_ctr, in_state => apnoea_state,
        tx_data => tx_data, tx_start => tx_start, tx_done => tx_done
    );

    -- uart_tx
    UART_INST : entity work.uart_tx
    generic map (CLK_FREQ => 12000000, BAUD_RATE => 115200)
    port map (
        clk => sys_clk, tx_start => tx_start, tx_data => tx_data,
        tx_serial => usb_tx, tx_done => tx_done
    );

    -- LED 1 Hz visible blink
    process(sys_clk) begin
        if rising_edge(sys_clk) then
            if led_ctr = 6000000 then
                led_reg <= not led_reg; led_ctr <= 0;
            else led_ctr <= led_ctr + 1; end if;
        end if;
    end process;
    led <= led_reg;

end Structural;
