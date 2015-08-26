library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library ethernet_mac;
use ethernet_mac.ethernet_types.all;
use ethernet_mac.miim_types.all;

entity ethernet_mac_test is
	port(
		clock_125_i    : in    std_ulogic;

		phy_reset_o    : out   std_ulogic;
		mdc_o          : out   std_ulogic;
		mdio_io        : inout std_ulogic;

		mii_tx_clk_i   : in    std_ulogic;
		mii_tx_er_o    : out   std_ulogic;
		mii_tx_en_o    : out   std_ulogic;
		mii_txd_o      : out   std_ulogic_vector(7 downto 0);
		mii_rx_clk_i   : in    std_ulogic;
		mii_rx_er_i    : in    std_ulogic;
		mii_rx_dv_i    : in    std_ulogic;
		mii_rxd_i      : in    std_ulogic_vector(7 downto 0);
		gmii_gtx_clk_o : out   std_ulogic;

		led_o          : out   std_ulogic_vector(3 downto 0);
		user_led_o     : out   std_ulogic
	);
end entity;

architecture rtl of ethernet_mac_test is
	signal clock      : std_ulogic;
	signal clock_inv  : std_ulogic;
	signal dcm_locked : std_ulogic;
	signal reset      : std_ulogic;

	signal speed          : t_ethernet_speed;
	signal speed_detected : t_ethernet_speed;
	signal link_up        : std_ulogic;

	signal rx_empty         : std_ulogic;
	signal rx_rd_en         : std_ulogic;
	signal rx_data          : t_ethernet_data;
	signal clock_unbuffered : std_ulogic;

	signal copy_reset : std_ulogic;

	signal tx_data  : t_ethernet_data;
	signal tx_wr_en : std_ulogic;
	signal tx_full  : std_ulogic;

	type t_test_mode is (
		TEST_LOOPBACK,
		TEST_TX
	);
	constant TEST_MODE : t_test_mode := TEST_LOOPBACK; 

	constant TEST_MODE_TX_PACKET_SIZE : positive             := 1514;
	type t_test_tx_state is (
		TX_WAIT,
		TX_WRITE_SIZE_HI,
		TX_WRITE_SIZE_LO,
		TX_WRITE_DATA
	);
	signal test_tx_state      : t_test_tx_state;
	signal test_tx_data_count : integer range 0 to TEST_MODE_TX_PACKET_SIZE;
	signal test_tx_skip_next  : std_ulogic := '0';

begin

	-- From left to right above the Ethernet connector
	led_o <= (not link_up) & (not speed) & "1";

	phy_reset_o <= not reset;
	user_led_o  <= reset;

	speed <= speed_detected;

	test_proc : process(clock)
	begin
		if rising_edge(clock) then
			tx_wr_en <= '0';
			rx_rd_en <= '0';
			if copy_reset = '1' then
				test_tx_state     <= TX_WAIT;
				test_tx_skip_next <= '0';
			else
				case TEST_MODE is
					when TEST_LOOPBACK =>
						if rx_empty = '0' then
							rx_rd_en <= '1';
							if rx_rd_en = '1' then
								tx_wr_en <= '1';
								tx_data  <= rx_data;
							end if;
						end if;
					when TEST_TX =>
						if tx_full = '0' then
							if test_tx_skip_next = '1' then
								test_tx_skip_next <= '0';
								-- Write remaining byte
								if test_tx_state /= TX_WAIT then
									tx_wr_en <= '1';
								end if;
							else
								case test_tx_state is
									when TX_WAIT =>
										--if one_second_elapsed = '1' then
										test_tx_state <= TX_WRITE_SIZE_HI;
									--end if;
									when TX_WRITE_SIZE_HI =>
										tx_wr_en      <= '1';
										tx_data       <= std_ulogic_vector(to_unsigned(TEST_MODE_TX_PACKET_SIZE, 16)(15 downto 8));
										test_tx_state <= TX_WRITE_SIZE_LO;
									when TX_WRITE_SIZE_LO =>
										tx_wr_en           <= '1';
										tx_data            <= std_ulogic_vector(to_unsigned(TEST_MODE_TX_PACKET_SIZE, 16)(7 downto 0));
										test_tx_state      <= TX_WRITE_DATA;
										test_tx_data_count <= 0;
									when TX_WRITE_DATA =>
										tx_wr_en <= '1';
										tx_data  <= "11111111";
										if test_tx_data_count = TEST_MODE_TX_PACKET_SIZE - 1 then
											test_tx_state <= TX_WRITE_SIZE_HI;
										end if;
										test_tx_data_count <= test_tx_data_count + 1;
								end case;
							end if;
						else
							test_tx_skip_next <= '1';
						end if;
				end case;
			end if;
		end if;
	end process;

	reset_generator_inst : entity work.reset_generator
		-- pragma translate_off
		generic map(
			RESET_DELAY => 10
		)
		-- pragma translate_on
		port map(
			clock_i  => clock,
			locked_i => dcm_locked,
			reset_o  => reset
		);

	clock_generator_inst : entity work.clock_generator
		port map(
			reset_i                => reset,
			clock_125_i            => clock_125_i,
			clock_125_o            => clock,
			clock_125_unbuffered_o => clock_unbuffered,
			clock_125_inv_o        => clock_inv,
			clock_50_o             => open,
			locked_o               => dcm_locked
		);

	ethernet_with_fifos_inst : entity ethernet_mac.ethernet_with_fifos
		generic map(
			MIIM_PHY_ADDRESS      => "00111",
			MIIM_RESET_WAIT_TICKS => 1250000 -- 10 ms at 125 MHz clock, minimum: 5 ms
		)
		port map(
			clock_125_i    => clock_unbuffered,
			reset_i        => reset,
			rx_reset_o     => copy_reset, -- Identical to tx_reset_o
			mii_tx_clk_i   => mii_tx_clk_i,
			mii_tx_er_o    => mii_tx_er_o,
			mii_tx_en_o    => mii_tx_en_o,
			mii_txd_o      => mii_txd_o,
			mii_rx_clk_i   => mii_rx_clk_i,
			mii_rx_er_i    => mii_rx_er_i,
			mii_rx_dv_i    => mii_rx_dv_i,
			mii_rxd_i      => mii_rxd_i,
			gmii_gtx_clk_o => gmii_gtx_clk_o,
			rgmii_tx_ctl_o => open,
			rgmii_rx_ctl_i => '0',
			miim_clock_i   => clock,
			mdc_o          => mdc_o,
			mdio_io        => mdio_io,
			link_up_o      => link_up,
			speed_o        => speed_detected,
			rx_clock_i     => clock,
			rx_empty_o     => rx_empty,
			rx_rd_en_i     => rx_rd_en,
			rx_data_o      => rx_data,
			tx_clock_i     => clock,
			tx_data_i      => tx_data,
			tx_wr_en_i     => tx_wr_en,
			tx_full_o      => tx_full
-- Force 1000 Mbps/GMII in simulation only
-- pragma translate_off
, speed_override_i         => SPEED_1000MBPS
		-- pragma translate_on			
		);

end architecture;

