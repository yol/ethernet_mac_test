library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ethernet_mac;
use ethernet_mac.framing_common.all;
use ethernet_mac.crc32.all;

entity ethernet_mac_test_tb is
end entity;

architecture behavioral of ethernet_mac_test_tb is
	alias logic_vector_t is std_logic_vector;

	--Inputs
	signal clock_125_i  : std_ulogic                 := '0';
	signal mii_tx_clk_i : std_ulogic                 := '0';
	signal mii_rx_clk_i : std_ulogic                 := '0';
	signal mii_rx_er_i  : std_ulogic                 := '0';
	signal mii_rx_dv_i  : std_ulogic                 := '0';
	signal mii_rxd_i    : logic_vector_t(7 downto 0) := (others => '0');

	--BiDirs
	signal mdio_io : std_ulogic;

	--Outputs
	signal phy_reset_o    : std_ulogic;
	signal mdc_o          : std_ulogic;
	signal mii_tx_er_o    : std_ulogic;
	signal mii_tx_en_o    : std_ulogic;
	signal mii_txd_o      : logic_vector_t(7 downto 0);
	signal gmii_gtx_clk_o : std_ulogic;
	signal led_o          : logic_vector_t(3 downto 0);
	signal user_led_o     : std_ulogic;

	-- Clock period definitions
	constant clock_125_i_period  : time := 8 ns;
	constant mii_tx_clk_i_period : time := 40 ns;
	constant mii_rx_clk_i_period : time := 40 ns;
	constant mii_rx_setup        : time := 2 ns;
	constant mii_rx_hold         : time := 0 ns;

	constant SPEED_10100 : boolean := FALSE;

	type t_memory is array (natural range <>) of logic_vector_t(7 downto 0);
	-- ICMP Ping Request
	constant test_packet : t_memory := (
		x"FF", x"FF", x"FF", x"FF", x"FF", x"FF",
		x"54", x"EE", x"75", x"34", x"2a", x"7e",
		x"08", x"00",
		x"45", x"00", x"00", x"54", x"c0", x"04", x"40", x"00", x"40",
		x"01", x"f5", x"4c",
		x"c0", x"a8", x"01", x"05",
		x"c0", x"a8", x"01", x"01",
		x"08", x"00",
		x"95", x"80",
		x"0c", x"4f", x"00", x"01",
		x"b6", x"c4", x"7d", x"55", x"00", x"00", x"00", x"00",
		x"5f", x"42", x"04", x"00", x"00", x"00", x"00", x"00",
		x"10", x"11", x"12", x"13", x"14", x"15", x"16", x"17", x"18", x"19", x"1a", x"1b",
		x"1c", x"1d", x"1e", x"1f", x"20", x"21", x"22", x"23", x"24", x"25", x"26", x"27", x"28",
		x"29", x"2a", x"2b", x"2c", x"2d", x"2e", x"2f", x"30", x"31", x"32", x"33", x"34", x"35",
		x"36", x"37"
	);

begin

	-- Instantiate the Unit Under Test (UUT)
	uut : entity work.ethernet_mac_test port map(
			clock_125_i    => clock_125_i,
			phy_reset_o    => phy_reset_o,
			mdc_o          => mdc_o,
			mdio_io        => mdio_io,
			mii_tx_clk_i   => mii_tx_clk_i,
			mii_tx_er_o    => mii_tx_er_o,
			mii_tx_en_o    => mii_tx_en_o,
			mii_txd_o      => mii_txd_o,
			mii_rx_clk_i   => mii_rx_clk_i,
			mii_rx_er_i    => mii_rx_er_i,
			mii_rx_dv_i    => mii_rx_dv_i,
			mii_rxd_i      => mii_rxd_i,
			gmii_gtx_clk_o => gmii_gtx_clk_o,
			led_o          => led_o,
			user_led_o     => user_led_o
		);

	-- Clock process definitions
	clock_125_i_process : process
	begin
		clock_125_i <= '0';
		wait for clock_125_i_period / 2;
		clock_125_i <= '1';
		wait for clock_125_i_period / 2;
	end process;

	mii_tx_clk_i_process : process
	begin
		mii_tx_clk_i <= '0';
		wait for mii_tx_clk_i_period / 2;
		mii_tx_clk_i <= '1';
		wait for mii_tx_clk_i_period / 2;
	end process;

	-- Stimulus process
	stim_proc : process is
		procedure mii_put1(
			-- lolisim
			-- crashes if (others => '0') is used instead of "00000000"
			data : in logic_vector_t(7 downto 0) := "00000000";
			dv   : in std_ulogic                 := '1';
			er   : in std_ulogic                 := '0') is
		begin
			mii_rx_clk_i <= '0';
			mii_rx_dv_i  <= dv;
			mii_rx_er_i  <= er;
			mii_rxd_i   <= data;
			wait for mii_rx_clk_i_period / 2;
			mii_rx_clk_i <= '1';
			wait for mii_rx_clk_i_period / 2;
		end procedure;

		procedure mii_put(
			data : in logic_vector_t(7 downto 0) := "00000000";
			dv   : in std_ulogic                 := '1';
			er   : in std_ulogic                 := '0') is
		begin
			if SPEED_10100 = TRUE then
				mii_put1("0000" & data(3 downto 0), dv, er);
				mii_put1("0000" & data(7 downto 4), dv, er);
			else
				mii_put1(data, dv, er);
			end if;
		end procedure;

		procedure mii_toggle is
		begin
			mii_put(dv => '0', er => '0', data => open);
		end procedure;
		
		variable fcs : t_crc32;

	begin
		wait until phy_reset_o = '1';
		wait for clock_125_i_period * 1100;
		while TRUE loop
			for i in 0 to 10 loop
				mii_toggle;
			end loop;
			mii_put(logic_vector_t(START_FRAME_DELIMITER_DATA));

			fcs := (others => '1');
			for j in test_packet'range loop
				mii_put(test_packet(j));
				fcs := update_crc32(fcs, std_ulogic_vector(test_packet(j)));
			end loop;
			--			for j in 1 to 1000 loop
			--				mii_put(x"23");
			--			end loop;
			for b in 0 to 3 loop
				mii_put(logic_vector_t(fcs_output_byte(fcs, b)));
			end loop;

			while TRUE loop
				mii_toggle;
			end loop;
		end loop;
		wait;
	end process;

end architecture;
