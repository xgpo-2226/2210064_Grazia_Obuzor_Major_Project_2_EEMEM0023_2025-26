-- INPUTS: fir_bandpass filtered samples and ready signal (enable)
-- OUTPUTS:
-- R-peak detection using threshold, slope, refractory period guard (per Pan Tomkins)
-- calculates QRS area, 3 different EDR method envelopes
--- and uses  majority-vote apnoea detector of the 3 EDR methods (hypo/apnoea flag and 5min window count)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity peak_detector is
    Generic (
        PEAK_THRESHOLD : integer := 900;  -- FIR value to cross (signed, 0-centred)
        REFRACTORY     : integer := 90;   -- blanking after beat (samples, 360ms at 250Hz), a physiological limit of 00BPM
        MIN_SLOPE      : integer := 50;   -- min rise per sample for valid peak
        ENV_AMP_THRESH : integer := 30;   -- amplitude envelope breath threshold (from prelim testing)
        ENV_RR_THRESH  : integer := 3;    -- RR envelope breath threshold
        ENV_AREA_THRESH: integer := 12;   -- area envelope breath threshold
        HYPO_LIMIT     : integer := 750;  -- samples without breath for hypopnoea (3s, due to 5s delay in prelim testing)
        APNOEA_LIMIT   : integer := 1250; -- samples without breath for apnoea (ditto, represents 10s real time - superficial fix)
        WINDOW_5MIN    : integer := 75000 -- event counter reset period (5min window)
    );
    Port (
        clk            : in  STD_LOGIC;
        fir_sample     : in  signed(11 downto 0);  -- signed filtered ECG
        fir_display    : in  integer range 0 to 4095; -- unsigned display value
        fir_ready      : in  STD_LOGIC;             -- pulse when new sample ready
        -- Outputs (active for one sample per beat, else zero)
        rr_latched     : out integer range 0 to 9999; -- default max 4-digit number for ASCII conversion
        peak_amp       : out integer range 0 to 4095; -- max ADC value
        qrs_area_out   : out integer range 0 to 9999;
        -- apnoea status (updated continuously)
        apnoea_state   : out integer range 0 to 2;
        apnoea_evt_ctr : out integer range 0 to 9999;
        beat_detected  : out STD_LOGIC
    );
end peak_detector;

architecture behav of peak_detector is
    -- peak detection
    signal prev_fir    : integer range -2048 to 2047 := 0;
    signal refrac_ctr  : integer range 0 to REFRACTORY := 0;
    signal rr_ctr      : integer range 0 to 9999 := 0;
    signal rr_lat      : integer range 0 to 9999 := 0;
    signal pk_amp      : integer range 0 to 4095 := 0;

    -- QRS area
    constant QRS_HALF : integer := 10;
    constant QRS_POST : integer := 15; -- slightly less steep RS than QR slope (120ms = 30 samples max)
    constant QRS_SHIFT: integer := 3;
--    constant QRS_SHIFT: integer := 2;
    type prebuf_t is array (0 to QRS_HALF-1) of integer range -2048 to 2047;
    signal prebuf      : prebuf_t := (others => 0);
    signal integrating : std_logic := '0';    -- tirggered when peak detected
    signal int_ctr     : integer range 0 to QRS_POST := 0;
    signal qrs_acc     : integer range -65536 to 65535 := 0; -- max area at 25*2048 + head room
--    signal qrs_acc     : integer range -32768 to 32767 := 0; -- max area at 10*2048 + head room
    signal qrs_area    : integer range 0 to 9999 := 0;
    signal baseline_acc: integer range -131072 to 131071 := 0; -- approx 128 samples 
    signal baseline    : integer range -2048 to 2047 := 0;     -- average of the baseline accumulator

    -- EDR envelopes (3 methods, alpha=1/4 and 1-alpha for current values IIR - slow to update to supress noise jumps)
    signal prev_peak_amp : integer range 0 to 4095 := 2048; -- could be useful for adaptive thresholding in future
    signal envelope_amp  : integer range 0 to 4095 := 0;
    signal prev_rr       : integer range 0 to 9999 := 800;  -- avoid huge starting spike in the rr envolope
    signal envelope_rr   : integer range 0 to 9999 := 0;
    signal prev_qrs_area : integer range 0 to 9999 := 0;
    signal envelope_area : integer range 0 to 9999 := 0;

    -- Apnoea state machine
    signal breath_ctr   : integer range 0 to 9999 := 0;
    signal ap_state     : integer range 0 to 2 := 0; -- indicates if significant change observed even if not apnoeic
    signal was_apnoeic  : std_logic := '0'; -- for the running counter
    signal window_ctr   : integer range 0 to WINDOW_5MIN := 0;
    signal evt_ctr      : integer range 0 to 9999 := 0;
begin
    -- wire outputs
    rr_latched     <= rr_lat;
    peak_amp       <= pk_amp;
    qrs_area_out   <= qrs_area;
    apnoea_state   <= ap_state;
    apnoea_evt_ctr <= evt_ctr;

    process(clk)
        variable cur_fir   : integer range -2048 to 2047;
        variable cur_raw   : integer range 0 to 4095;
        variable bs_sample : integer range -2048 to 2047;
        variable amp_d     : integer range 0 to 4095;
        variable rr_d      : integer range 0 to 9999;
        variable area_d    : integer range 0 to 9999;
        variable new_env_a : integer range 0 to 4095;
        variable new_env_r : integer range 0 to 9999;
        variable new_env_q : integer range 0 to 9999;
        variable pre_acc   : integer range -131072 to 131071;
        variable area_now  : integer range 0 to 9999;
        variable vote_count: integer range 0 to 3;
        variable slope     : integer range -4096 to 4095;
    begin
        if rising_edge(clk) then
            beat_detected <= '0';
            if fir_ready = '1' then
                cur_fir := to_integer(fir_sample);
                cur_raw := fir_display;
                rr_lat  <= 0;  -- self-clear: non-zero only on beat
                slope   := cur_fir - prev_fir;

                -- 5-minute event window
                if window_ctr = WINDOW_5MIN - 1 then
                    window_ctr <= 0; evt_ctr <= 0;
                else window_ctr <= window_ctr + 1; end if;

                -- continuous counters kept between heartbeat peaks and 'breaths'
                -- breath gap counter (time since last detected breath) - only reset on EDR envolope threshold
                if breath_ctr < 9999 then breath_ctr <= breath_ctr + 1; end if;

                -- Apnoea state transitions (for respective no breath durations)
                if breath_ctr >= APNOEA_LIMIT then
                    if ap_state /= 2 then ap_state <= 2; was_apnoeic <= '1'; end if;
                elsif breath_ctr >= HYPO_LIMIT then
                    if ap_state /= 1 then ap_state <= 1; end if;
                end if;
                -- continous rr interval counts and refactory period countdown
                if rr_ctr < 9999 then rr_ctr <= rr_ctr + 1; end if;
                if refrac_ctr > 0 then refrac_ctr <= refrac_ctr - 1; end if;

                -- slow baseline IIR (paused near QRS)
                if refrac_ctr = 0 then
                    baseline_acc <= baseline_acc - (baseline_acc/128) + cur_fir;
                    baseline <= baseline_acc / 128;
                end if;

                -- QRS pre-peak buffer (simultaneoys to QRS integration, constant running buffer, exploit parallelism)
                for i in 0 to QRS_HALF-2 loop prebuf(i) <= prebuf(i+1); end loop;
                prebuf(QRS_HALF-1) <= cur_fir;

                -- QRS post-peak integration
                if integrating = '1' then
                    bs_sample := cur_fir - baseline;
                    if bs_sample < 0 then qrs_acc <= qrs_acc + (-bs_sample);
                    else qrs_acc <= qrs_acc + bs_sample; end if;
                    if int_ctr = QRS_POST-1 then
                        integrating <= '0';
                        if (qrs_acc/(2**QRS_SHIFT)) > 9999 then qrs_area <= 9999; -- bring typical values to 4-digit range for ASCII
                        else qrs_area <= qrs_acc/(2**QRS_SHIFT); end if;
                    else int_ctr <= int_ctr + 1; end if;
                end if;

                -- R-peak: threshold + slope + refractory for envolopes
                if cur_fir > PEAK_THRESHOLD and prev_fir <= PEAK_THRESHOLD
                   and slope >= MIN_SLOPE and refrac_ctr = 0 then
                    rr_lat    <= rr_ctr; rr_ctr <= 0;
                    refrac_ctr <= REFRACTORY;
                    beat_detected <= '1';
                    pk_amp <= cur_raw;

                    -- QRS pre-peak accumulation
                    pre_acc := 0;
                    for i in 0 to QRS_HALF-1 loop
                        if (prebuf(i)-baseline) < 0 then
                            pre_acc := pre_acc - (prebuf(i)-baseline);
                        else pre_acc := pre_acc + (prebuf(i)-baseline); end if;
                    end loop;
                    qrs_acc <= pre_acc; integrating <= '1'; int_ctr <= 0;

                    -- Amplitude envelope
                    if cur_raw > prev_peak_amp then amp_d := cur_raw - prev_peak_amp;
                    else amp_d := prev_peak_amp - cur_raw; end if;
                    prev_peak_amp <= cur_raw;
                    new_env_a := (3*envelope_amp + amp_d)/4; envelope_amp <= new_env_a;

                    -- RR envelope
                    if rr_ctr > prev_rr then rr_d := rr_ctr - prev_rr;
                    else rr_d := prev_rr - rr_ctr; end if;
                    prev_rr <= rr_ctr;
                    new_env_r := (3*envelope_rr + rr_d)/4; envelope_rr <= new_env_r;

                    -- QRS area envelope
                    area_now := qrs_area;
                    if area_now > prev_qrs_area then area_d := area_now - prev_qrs_area;
                    else area_d := prev_qrs_area - area_now; end if;
                    prev_qrs_area <= area_now;
                    new_env_q := (3*envelope_area + area_d)/4; envelope_area <= new_env_q;

                    -- majority vote: 2 of 3 envelopes must show breathing
                    -- amp envolope is most unreliable (higher range of breath hold values chosen as threshold - from PuTTY log)
                    vote_count := 0;
                    if new_env_a >= ENV_AMP_THRESH then vote_count := vote_count+1; end if;
                    if new_env_r >= ENV_RR_THRESH  then vote_count := vote_count+1; end if;
                    if new_env_q >= ENV_AREA_THRESH then vote_count := vote_count+1; end if;
                    if vote_count >= 2 then
--                    if vote_count >= 1 then
                        breath_ctr <= 0;
                        if was_apnoeic = '1' then
                            was_apnoeic <= '0'; ap_state <= 0;
                            if evt_ctr < 9999 then evt_ctr <= evt_ctr+1; end if;
                        else ap_state <= 0; end if;
                    end if;
                end if;
                prev_fir <= cur_fir;
            end if;
        end if;
    end process;
end behav;
