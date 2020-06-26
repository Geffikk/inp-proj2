-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): xgeffe00 Maros Geffert
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti

   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

---------- SIGNALS -----------

signal pc_address: std_logic_vector(12 downto 0);
signal pc_increase: std_logic;
signal pc_decrement: std_logic;

signal ptr_address: std_logic_vector(12 downto 0);
signal ptr_increase: std_logic;
signal ptr_decrement: std_logic;

signal mux_1_sel: std_logic;
signal mux_2_sel: std_logic;
signal mux_3_sel: std_logic_vector(1 downto 0);

signal mux2s: std_logic_vector(12 downto 0) := (others => '0');

--------- Instructions -------------

type instruction_type is (
cell_inc, cell_dec,
pointer_inc, pointer_dec,
print, get,
tmp, value,
s_return, nothing
);
signal instruction: instruction_type;

------------- STATES ---------------

type automat_state is (
prepare, s_prepare, s_prepare2, state_prepare, state_main,
state_cell_inc, state_cell_dec, state_cell_inc_second, state_cell_dec_second,
state_pointer_inc, state_pointer_dec,
state_print, state_print_second,
state_get, state_get_second,
state_temp, state_temp_second,
state_value, state_value_second,
state_return, state_nothing
);
signal prepare_state : automat_state;
signal state : automat_state;

--------------------------------------------------------------------------
------------------------------ Components --------------------------------
--------------------------------------------------------------------------

begin
----------- PC Register ------------

pc_register: process(CLK, RESET, pc_address, pc_increase, pc_decrement)
    begin
        if (RESET = '1') then
            pc_address <= (others => '0');
        elsif (CLK'event and CLK = '1') then
            if (pc_increase = '1') then
                pc_address <= pc_address + 1;
            elsif (pc_decrement = '1') then
                pc_address <= pc_address - 1;
            end if;
        end if;
    end process;

---------- PTR Register ------------

ptr_register: process(CLK, RESET, ptr_address, ptr_increase, ptr_decrement)
    begin
        if (RESET = '1') then
            ptr_address <= "1000000000000";
        elsif (CLK'event and CLK = '1') then
            if (ptr_increase = '1') then
                if(ptr_address = "1111111111111") then
                    ptr_address <= "1000000000000";
                else
                    ptr_address <= ptr_address + 1;
                end if;
            elsif (ptr_decrement = '1') then
                if (ptr_address = "1000000000000") then
                    ptr_address <= "1111111111111";
                else
                    ptr_address <= ptr_address - 1;
                end if;
            end if;
        end if;
    end process;

---------- MULTIPLEXOR 1 -----------

mux1: process(CLK, pc_address, mux_1_sel, mux2s)
begin
    case (mux_1_sel) is
        when '0' => DATA_ADDR <= pc_address;
        when '1' => DATA_ADDR <= mux2s;
        when others =>
    end case;
end process;

---------- MULTIPLEXOR 2 -----------

mux2: process(CLK, ptr_address, mux2s, mux_2_sel)
begin
    case (mux_2_sel) is
        when '0' => mux2s <= ptr_address;
        when '1' => mux2s <= "1000000000000";
        when others =>
    end case;
end process;

---------- MULTIPLEXOR 3 ------------

mux3: process(IN_DATA, DATA_RDATA, CLK, mux_3_sel)
begin
    case (mux_3_sel) is
        when "00" => DATA_WDATA <= IN_DATA;
        when "01" => DATA_WDATA <= DATA_RDATA + 1;
        when "10" => DATA_WDATA <= DATA_RDATA - 1;
        when "11" => DATA_WDATA <= DATA_RDATA;
        when others =>
    end case;
end process;

------- Priradenie instrukcie --------

instruction_process: process (DATA_RDATA, instruction)
begin
    case (DATA_RDATA) is
        when X"2B" => instruction <= cell_inc; -- + --
        when X"2D" => instruction <= cell_dec; -- - --
        when X"3E" => instruction <= pointer_inc; -- > --
        when X"3C" => instruction <= pointer_dec; -- < --
        when X"2E" => instruction <= print; -- . --
        when X"2C" => instruction <= get; -- , --
        when X"24" => instruction <= tmp; -- $ --
        when X"21" => instruction <= value; -- ! --
        when X"00" => instruction <= s_return; --null
        when others => instruction <= nothing; --other
    end case;
end process;
------------ Automat -----------------
prepare_state_process: process(RESET, CLK)
begin
    if (RESET = '1') then
        prepare_state <= prepare;
    elsif (CLK'event and CLK = '1') then
        if(EN = '1') then
            prepare_state <= state;
        end if;
    end if;
end process;

main_state_process: process(DATA_RDATA, OUT_BUSY, IN_DATA, IN_VLD, prepare_state, instruction)
begin

    DATA_EN <= '0';
    DATA_RDWR <= '0';
    IN_REQ <= '0';
    OUT_WE <= '0';
    OUT_DATA <= "00000000";

    pc_increase <= '0';
    pc_decrement <= '0';
    ptr_increase <= '0';
    ptr_decrement <= '0';

    mux_1_sel <= '0';
    mux_2_sel <= '0';
    mux_3_sel <= "00";

    case prepare_state is
        when prepare =>
            state <= s_prepare;
        when s_prepare =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mux_1_sel <= '0';
            mux_2_sel <= '0';
            state <= state_main;
        when state_main =>
            case instruction is
                when cell_inc => state <= state_cell_inc;
                when cell_dec => state <= state_cell_dec;
                when pointer_inc => state <= state_pointer_inc;
                when pointer_dec => state <= state_pointer_dec;
                when print => state <= state_print;
                when get => state <= state_get;
                when tmp => state <= state_temp;
                when value => state <= state_value;
                when s_return => state <= state_return;
                when nothing => state <= state_nothing;
            end case;
        ---------- > -----------
        when state_pointer_inc =>
            ptr_increase <= '1';
            pc_increase <= '1';
            state <= s_prepare;
        ---------- < -----------
        when state_pointer_dec =>
            ptr_decrement <= '1';
            pc_decrement <= '1';
            state <= s_prepare;
        ----------- + ----------
        when state_cell_inc =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mux_1_sel <= '1';
            mux_2_sel <= '0';
            state <= state_cell_inc_second;
        when state_cell_inc_second =>
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            mux_1_sel <= '1';
            mux_2_sel <= '0';
            mux_3_sel <= "01";
            pc_increase <= '1';
            state <= s_prepare;
        ---------- - -----------
        when state_cell_dec =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mux_1_sel <= '1';
            mux_2_sel <= '0';
            state <= state_cell_dec_second;
        when state_cell_dec_second =>
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            mux_1_sel <= '1';
            mux_2_sel <= '0';
            mux_3_sel <= "10";
            pc_increase <= '1';
            state <= s_prepare;
        --------- PRINT ---------
        when state_print =>
            if(OUT_BUSY = '1') then
                state <= state_print;
            else
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mux_1_sel <= '1';
                mux_2_sel <= '0';
                state <= state_print_second;
            end if;
        when state_print_second =>
            OUT_WE <= '1';
            OUT_DATA <= DATA_RDATA;
            pc_increase <= '1';
            state <= s_prepare;
        ---------- GET ----------
         when state_get =>
            state <= state_get;
            IN_REQ <= '1';
            if (IN_VLD = '1') then
                state <= s_prepare;
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mux_1_sel <= '1';
                mux_2_sel <= '0';
                mux_3_sel <= "00";
                pc_increase <= '1';
            end if;
         ----- Value to TEMP -------
         when state_temp =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mux_1_sel <= '1';
            mux_2_sel <= '0';
            state <= state_temp_second;
         when state_temp_second =>
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            mux_1_sel <= '1';
            mux_2_sel <= '1';
            pc_increase <= '1';
            state <= s_prepare;
         ------ Temp to VALUE -------
         when state_value =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            state <= state_value_second;
            mux_1_sel <= '1';
            mux_2_sel <= '1';
         when state_value_second =>
            DATA_EN <= '1';
            DATA_RDWR <= '1';
            pc_increase <= '1';
            mux_1_sel <= '1';
            mux_2_sel <= '0';
            mux_3_sel <= "11";
            state <= s_prepare;
         -----------------------------------
         when state_return =>
            state <= state_return;
         when state_nothing =>
            pc_increase <= '1';
            state <= s_prepare;
         when others =>
            state <= s_prepare;
    end case;
end process;
end behavioral;
 
