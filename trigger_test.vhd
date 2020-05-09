-- GRBalpha trigger algorithm
-- Written by Gergely Dálya, 2020
-- dalyag@caesar.elte.hu

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity TrigCircuit is
    port (
        EMIN_CHOOSE         : inout std_logic_vector (7 downto 0);  
        EMAX_CHOOSE         : inout std_logic_vector (7 downto 0);
        T_CHOOSE            : inout std_logic_vector (2 downto 0);
        -- T is the integration time of the counter before the stack
        K_CHOOSE            : inout unsigned (7 downto 0);
        -- K is the multiplicator for the background i.e. we compare (S-B)^2 to K*B
        WIN_CHOOSE          : inout std_logic_vector (3 downto 0);
        -- Choose the time window for signal and background accumulation
        PH                  : in std_logic_vector (11 downto 0);
        -- The output of the gamma detector is 12 bit ADC data
        CLK                 : in std_logic;
        CLEAR               : in std_logic := '0';
        CLK_EXT	     : in std_logic;
        CLK_EXT_MON         : out std_logic;
        -- if CLEAR='1', it clears the GRB flag output (i.e. TRIGGER)       
        TRIGGER             : out std_logic;
        -- either '1': there is a GRB, or '0': there is no GRB
--        EMIN_OUT            : out std_logic_vector (7 downto 0);
--        EMAX_OUT            : out std_logic_vector (7 downto 0);
--        T_OUT               	: out std_logic_vector (2 downto 0);
--        K_OUT               : out std_logic_vector (7 downto 0);
--        WIN_OUT             : out std_logic_vector (3 downto 0)
	res	: in  std_logic := '0';
	LED1	: out std_logic := '0';
	LED2	: out std_logic := '0'
--	LED3	: out std_logic := '0';
--	LED4	: out std_logic := '0';
--	LED5	: out std_logic := '0';
--	LED6	: out std_logic := '0';
--	LED7	: out std_logic := '0';
--	LED8	: out std_logic := '0'
    );
end TrigCircuit;



architecture TrigArch of TrigCircuit is

type shift_register is array (0 to 4) of unsigned (13 downto 0); -- array size is the max possible value of n+N+1. Each element have to have the same size as counter. 4096

--constant CLK_TIME_MS    : integer := 10; -- what is the clock frequency for our FPGA?
constant CLK_FREQ_KHZ   : integer := 12000;

signal EMIN         : std_logic_vector (15 downto 0);
signal EMAX         : std_logic_vector (15 downto 0);
signal T            : unsigned (9 downto 0);
signal SIGWIN       : unsigned (15 downto 0);
signal BGWIN        : unsigned (15 downto 0);
signal K            : unsigned (7 downto 0);
signal counter      : unsigned (13 downto 0);

signal stack : shift_register := (others => to_unsigned(0, 14));

-- variables cannot be declared here, also the compiler isn't case sensitive, so I changed N to NN  - fg
--signal accumulated_signal         : unsigned (19 downto 0);
--signal accumulated_background     : unsigned (19 downto 0);
--signal n                          : unsigned (10 downto 0);  -- max value: 2048
--signal NN                         : unsigned (10 downto 0);  -- max value: 2048
--signal step_counter               : unsigned (11 downto 0) := 0;  -- have to have size>=n+N
signal S            : unsigned (19 downto 0);
signal B            : unsigned (19 downto 0);

signal stackfull    : std_logic := '0';
signal sbreset      : std_logic := '0';
signal comp1        : std_logic := '0';
signal comp2        : std_logic := '0';
signal trigback     : std_logic := '0';

begin
CLK_EXT_MON <= CLK_EXT;

    with T_CHOOSE select 
        T <= to_unsigned(32, 10)     when "000",
             to_unsigned(64, 10)     when "001",
             to_unsigned(128, 10)    when "010",
             to_unsigned(256, 10)    when "011",
             to_unsigned(512, 10)    when "100",
             to_unsigned(1024, 10)   when "101",
             to_unsigned(1024, 10)   when others;
             
--    with WIN_CHOOSE select  -- signal windows in ms
--        SIGWIN <= 32    when "0000",
--                  64    when "0001",
--                  128   when "0010",
--                  256   when "0011",
--                  512   when "0100",
--                  1024  when "0101",
--                  2048  when "0110",
--                  4096  when "0111",
--                  8192  when "1000",
--                  16384 when "1001",
--                  32768 when "1010",
--                  65536 when "1011",
--                  65536 when others;

    with WIN_CHOOSE select  -- signal windows in ms
        SIGWIN <= x"0020"    when "0000",
                  x"0040"    when "0001",
                  x"0080"   when "0010",
                  x"0100"   when "0011",
                  x"0200"   when "0100",
                  x"0400"  when "0101",
                  x"0800"  when "0110",
                  x"1000"  when "0111",
                  x"2000"  when "1000",
                  x"4000" when "1001",
                  x"8000" when "1010",
                  to_unsigned(65536, 16) when "1011",
                  to_unsigned(65536, 16) when others;
                  
    with WIN_CHOOSE select  -- background windows in ms
        BGWIN <= x"4000"  when "0000" | "0001" | "0010" | "0011" | "0100",
                 x"8000"  when "0101" | "0110" | "0111",
                 to_unsigned(65536, 16)  when "1000" | "1001" | "1010" | "1011",
                 to_unsigned(65536, 16)  when others;

-- So we have integration time options of 32-1024 ms, signal time windows of 32-65536 ms and 
-- background time windows of 16384-65536 ms. In this case the possible values of n are between 
-- 1-2048 and the possible values of N are 16-2048. Since we can not dynamically change the hardware 
-- of the stack, we should impement a stack with the maximal size, i.e. 2*2048=4096, and then 
-- dynamically change which parts are added to / subtracted from it.


-- took these out to check synthesis - fg
     
--    with EMIN_CHOOSE select  -- Energy range ~ 10-10.000 keV
--        EMIN <= ...
     
--    with EMAX_CHOOSE select
--        EMAX <= ... 
        
    K <= K_CHOOSE;
        
        
-- I think that whenever we change one of the inputs of [EMIN_CHOOSE, EMAX_CHOOSE, T_CHOOSE, K_CHOOSE, WIN_CHOOSE], the stack should reset, to avoid some strange unwanted behaviour due to leftover count numbers somewhere, so:
        
        
--    n  <= to_unsigned(to_integer(SIGWIN) / to_integer(T), 11);  -- had problems with "=" operator - fg
--    NN <= to_unsigned(to_integer(BGWIN) / to_integer(T), 11);
        
     
    Clk_Proc : process (CLK) is --, EMIN, EMAX, SIGWIN, BGWIN, T, K, trigback) is
        variable ticks                  : unsigned (13 downto 0) := to_unsigned(0, 14);  -- for size we should know CLK_FREQ_MHZ
        variable millisecs              : unsigned (9 downto 0) := to_unsigned(0, 10);  -- have to have at least the same size as T
        variable step_counter           : unsigned (11 downto 0) := to_unsigned(0, 12);  -- have to have size>=n+N
        --variable EMIN_old, EMAX_old     : std_logic_vector (15 downto 0);
        --variable SIGWIN_old, BGWIN_old  : unsigned (15 downto 0);
        --variable T_old                  : unsigned (9 downto 0);
        --variable K_old                  : unsigned (7 downto 0);
    begin
--        if (EMIN /= EMIN_old) or (EMAX /= EMAX_old) or (SIGWIN /= SIGWIN_old) or (BGWIN /= BGWIN_old) or (T /= T_old) or (K /= K_old) or trigback = '1' then
--            ticks := to_unsigned(0, 8);
--            millisecs := to_unsigned(0, 10);
--            step_counter := to_unsigned(0, 12);
--            stackfull <= '0';
--            stack <= (others => to_unsigned(0, 14));
--            counter <= to_unsigned(0, 14);
--            sbreset <= not sbreset;
--        end if;

--        if rising_edge(CLK) then
          if rising_edge(CLK_EXT) then
	    
	    --if (EMIN /= EMIN_old) or (EMAX /= EMAX_old) or (SIGWIN /= SIGWIN_old) or (BGWIN /= BGWIN_old) or (T /= T_old) or (K /= K_old) or trigback = '1' then
	    if res = '1' then
            	ticks := to_unsigned(0, 14);
            	millisecs := to_unsigned(0, 10);
            	step_counter := to_unsigned(0, 12);
            	stackfull <= '0';
            	stack <= (others => to_unsigned(0, 14));
            	counter <= to_unsigned(0, 14);
           	--sbreset <= not sbreset;
		sbreset <= '1';
	    else
	    	ticks := ticks + 1;
             
            	--if EMIN < PH and EMAX > PH then  -- filter based on the energy
            	--    counter <= counter + 1;
            	--end if;
           
	    	if ticks = CLK_FREQ_KHZ - 1 then  -- count the milliseconds based on clk frequency
 			ticks := to_unsigned(0, 14);
                	millisecs := millisecs + 1;
			counter <= counter + 1;
	    	end if;   

	    	if millisecs = 1000 then
              		stack(0) <=  counter;
                	for i in 4 downto 1 loop -- shift_right does not work here, it's for unsigned values - fg
	        	      	stack(i) <= stack(i-1);
                	end loop;
                	step_counter := step_counter + 1;
                	millisecs := to_unsigned(0, 10);
                	counter <= to_unsigned(0, 14);
	    	end if;
 
	    	if (millisecs >= 500) and (millisecs < 1000) then
			LED1 <= '0';
	    	else
			LED1 <= '1';
            	end if;

            	--if step_counter >= (SIGWIN/T) + (BGWIN/T) then   -- Stack full check: step_counter = n+NN
	    	if (step_counter = 5) or (step_counter = 6) then
                	stackfull <= '1';
	    	elsif step_counter < 5 then
			stackfull <= '0';
		elsif step_counter = 7 then
--			res <= '1';
			for j in 4 downto 0 loop
				stack(j) <= 0;
			end loop;
			step_counter := to_unsigned(0, 12);
            	end if;
	    end if;
        end if;
        
        --EMIN_old    := EMIN;
        --EMAX_old    := EMAX;
        --SIGWIN_old  := SIGWIN;
        --BGWIN_old   := BGWIN;
        --T_old       := T;
        --K_old       := K;
        
    end process Clk_Proc;

   led_proc : process (counter, stack, stackfull) is
   begin
	if counter > 500 then
	    LED2 <= '1';
	else 
	    LED2 <= '0';
	end if;

--	if stack(0) /= 0 then
--	    LED3 <= '1';
--	else
--	    LED3 <= '0';
--	end if;
--
--	if stack(1) /= 0 then
--	    LED4 <= '1';
--	else
--	    LED4 <= '0';
--	end if;
--
--	if stack(2) /= 0 then
--	    LED5 <= '1';
--	else
--	    LED5 <= '0';
--	end if;
--
--	if stack(3) /= 0 then
--	    LED6 <= '1';
--	else
--	    LED6 <= '0';
--	end if;
--
--	if stack(4) /= 0 then
--	    LED7 <= '1';
--	else
--	    LED7 <= '0';
--	end if;
--
--	if stackfull = '1' then
--	    LED8 <= '1';
--	else
--	    LED8 <= '0';
--	end if;

    end process led_proc;
--    end process Clk_Proc;

--    LED3 <= '1' when (stack(0) /= 0) else '0';
             
--    LED4 <= '1' when (stack(1) /= 0) else '0';

--    LED5 <= '1' when (stack(2) /= 0) else '0';

--    LED6 <= '1' when (stack(3) /= 0) else '0';

--    LED7 <= '1' when (stack(4) /= 0) else '0';

--    LED8 <= '1' when (stackfull = '1') else '0';

    
     
    S_And_B_Accumulation : process (stack, sbreset) is
        Variable n, NN      : unsigned (10 downto 0);
        Variable accumulated_signal, accumulated_background : unsigned (19 downto 0) := to_unsigned(0, 20);
    begin
    
        if sbreset = '1' then
            accumulated_signal := to_unsigned(0, 20);
            accumulated_background := to_unsigned(0, 20); 
        end if;
        
        n := to_unsigned(to_integer(SIGWIN) / to_integer(T), 11);
        NN := to_unsigned(to_integer(BGWIN) / to_integer(T), 11);
        accumulated_signal := accumulated_signal + stack(0) - stack(to_integer(n));  
        accumulated_background := accumulated_background + stack(to_integer(n)) - stack(to_integer(n+NN));
        S <= accumulated_signal / n;
        B <= accumulated_background / NN;
        
    end process S_And_B_Accumulation;
     
     
   Comparison1 : process (S, B, K) is
       variable SmBsq       : unsigned (19 downto 0);
    begin
       SmBsq := to_unsigned(to_integer(S - B) * to_integer(S - B), 20); -- problems with "**" operator - fg
           
       if SmBsq > K*B then
           comp1 <= '1';
       else
           comp1 <= '0';
       end if;            
    end process Comparison1;       
     
     
    Comparison2 : process (S, B) is
    begin 
        if S > B then
            comp2 <= '1';
        else
            comp2 <= '0';
        end if;
    end process Comparison2;
    
    
    Triggering : process (comp1, comp2, stackfull, CLEAR) is
    begin
        if (comp1 = '1' and comp2 = '1' and CLEAR = '0' and stackfull = '1') then
            TRIGGER <= '1';
            trigback <= '1';
        else
            TRIGGER <= '0';
            trigback <= '0';
        end if;
    end process Triggering;

	--LED1 <= not LED1 when (TRIGGER = '1');
	--LED2 <= not LED2 when (TRIGGER = '1');
	--LED3 <= not LED3 when (TRIGGER = '1');
	--LED4 <= not LED4 when (TRIGGER = '1');
	--LED5 <= not LED5 when (TRIGGER = '1');
	--LED6 <= not LED6 when (TRIGGER = '1');
	--LED7 <= not LED7 when (TRIGGER = '1');
	--LED8 <= not LED8 when (TRIGGER = '1');

end TrigArch;
