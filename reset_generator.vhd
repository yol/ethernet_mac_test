library ieee;
use ieee.std_logic_1164.all;

entity reset_generator is
	generic(
		-- 20 ms at 125 MHz clock
		-- Minimum 88E1111 reset pulse width: 10 ms
		RESET_DELAY : positive := 2500000
	);
	port(
		clock_i  : in  std_ulogic;
		locked_i : in  std_ulogic;
		reset_o  : out std_ulogic
	);
end entity;

architecture rtl of reset_generator is
	signal reset_cnt : natural range 0 to RESET_DELAY := 0;
begin
	reset_proc : process(clock_i, locked_i)
	begin
		if locked_i = '1' then
			if rising_edge(clock_i) then
				-- When locked, wait for RESET_DELAY ticks, then deassert reset
				if reset_cnt < RESET_DELAY then
					reset_cnt <= reset_cnt + 1;
					reset_o   <= '1';
				else
					reset_o <= '0';
				end if;
			end if;
		else
			-- Keep in reset when not locked
			reset_cnt <= 0;
			reset_o   <= '1';
		end if;
	end process;

end architecture;

