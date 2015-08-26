-- This file is part of the ethernet_mac_test project.
--
-- For the full copyright and license information, please read the
-- LICENSE.md file that was distributed with this source code.

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clock_generator is
	port(
		reset_i                : in  std_ulogic;
		clock_125_i            : in  std_ulogic;
		clock_125_o            : out std_ulogic;
		clock_125_inv_o        : out std_ulogic;
		clock_125_unbuffered_o : out std_ulogic;
		clock_50_o             : out std_ulogic;
		locked_o               : out std_ulogic
	);
end entity;

architecture spartan of clock_generator is
	signal int_clock_125          : std_ulogic;
	signal int_clock_125_buffered : std_ulogic;
	signal int_clock_125_inv      : std_ulogic;
	signal int_clock_50           : std_ulogic;
	signal clock_feedback         : std_ulogic;

begin
	clock_125_unbuffered_o <= int_clock_125;
	clock_125_o            <= int_clock_125_buffered;

	BUFIO2FB_inst : BUFIO2FB
		generic map(
			DIVIDE_BYPASS => TRUE       -- Bypass divider (TRUE/FALSE)
		)
		port map(
			O => clock_feedback,        -- 1-bit output: Output feedback clock (connect to feedback input of DCM/PLL)
			I => int_clock_125_buffered -- 1-bit input: Feedback clock input (connect to input port)
		);

	clock_125_BUFG_inst : BUFG
		port map(
			O => int_clock_125_buffered, -- 1-bit output: Clock buffer output
			I => int_clock_125          -- 1-bit input: Clock buffer input
		);

	clock_125_inv_BUFG_inst : BUFG
		port map(
			O => clock_125_inv_o,       -- 1-bit output: Clock buffer output
			I => int_clock_125_inv      -- 1-bit input: Clock buffer input
		);

	clock_50_BUFG_inst : BUFG
		port map(
			O => clock_50_o,
			I => int_clock_50
		);

	-- TODO Remove BUFIO2FB
	DCM_SP_inst : DCM_SP
		generic map(
			CLKDV_DIVIDE          => 5.0, -- CLKDV divide value
			-- (1.5,2,2.5,3,3.5,4,4.5,5,5.5,6,6.5,7,7.5,8,9,10,11,12,13,14,15,16).
			CLKFX_DIVIDE          => 5, -- Divide value on CLKFX outputs - D - (1-32)
			CLKFX_MULTIPLY        => 2, -- Multiply value on CLKFX outputs - M - (2-32)
			CLKIN_DIVIDE_BY_2     => FALSE, -- CLKIN divide by two (TRUE/FALSE)
			CLKIN_PERIOD          => 8.0, -- Input clock period specified in nS
			CLKOUT_PHASE_SHIFT    => "NONE", -- Output phase shift (NONE, FIXED, VARIABLE)
			CLK_FEEDBACK          => "1X", -- Feedback source (NONE, 1X, 2X)
			DESKEW_ADJUST         => "SYSTEM_SYNCHRONOUS", -- SYSTEM_SYNCHRNOUS or SOURCE_SYNCHRONOUS
			DFS_FREQUENCY_MODE    => "LOW", -- Unsupported - Do not change value
			DLL_FREQUENCY_MODE    => "LOW", -- Unsupported - Do not change value
			DSS_MODE              => "NONE", -- Unsupported - Do not change value
			DUTY_CYCLE_CORRECTION => TRUE, -- Unsupported - Do not change value
			FACTORY_JF            => X"c080", -- Unsupported - Do not change value
			PHASE_SHIFT           => 0, -- Amount of fixed phase shift (-255 to 255)
			STARTUP_WAIT          => FALSE -- Delay config DONE until DCM_SP LOCKED (TRUE/FALSE)
		)
		port map(
			CLK0     => int_clock_125,  -- 1-bit output: 0 degree clock output
			CLK180   => int_clock_125_inv, -- 1-bit output: 180 degree clock output
			CLK270   => open,           -- 1-bit output: 270 degree clock output
			CLK2X    => open,           -- 1-bit output: 2X clock frequency clock output
			CLK2X180 => open,           -- 1-bit output: 2X clock frequency, 180 degree clock output
			CLK90    => open,           -- 1-bit output: 90 degree clock output
			CLKDV    => open,           -- 1-bit output: Divided clock output
			CLKFX    => int_clock_50,   -- 1-bit output: Digital Frequency Synthesizer output (DFS)
			CLKFX180 => open,           -- 1-bit output: 180 degree CLKFX output
			LOCKED   => locked_o,       -- 1-bit output: DCM_SP Lock Output
			PSDONE   => open,           -- 1-bit output: Phase shift done output
			STATUS   => open,           -- 8-bit output: DCM_SP status output
			CLKFB    => clock_feedback, -- 1-bit input: Clock feedback input
			CLKIN    => clock_125_i,    -- 1-bit input: Clock input
			DSSEN    => '0',            -- 1-bit input: Unsupported, specify to GND.
			PSCLK    => '0',            -- 1-bit input: Phase shift clock input
			PSEN     => '0',            -- 1-bit input: Phase shift enable
			PSINCDEC => '0',            -- 1-bit input: Phase shift increment/decrement input
			RST      => '0'             -- 1-bit input: Active high reset input
		);

end architecture;