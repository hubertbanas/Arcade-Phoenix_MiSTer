//============================================================================
//  Arcade: Phoenix
//
//  Port to MiSTer
//  Copyright (C) 2017 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [43:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status ORed with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0; 
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign LED_USER  = 0;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

`include "build_id.v" 
localparam CONF_STR = {
	"A.PHNX;;",
	"-;",
	"O1,Aspect ratio,4:3,16:9;",
	"-;",
	"T6,Reset;",
	"J,Fire,Barrier,Start 1P,Coin;",
	"V,v1.00.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [64:0] ps2_key;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

wire pressed    = (ps2_key[15:8] != 8'hf0);
wire extended   = (~pressed ? (ps2_key[23:16] == 8'he0) : (ps2_key[15:8] == 8'he0));
wire [8:0] code = ps2_key[63:24] ? 9'd0 : {extended, ps2_key[7:0]}; // filter out PRNSCR and PAUSE
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[64];
	
	if(old_state != ps2_key[64]) begin
		casex(code)
			'hX75: btn_right        <= pressed; // up
			'hX72: btn_left         <= pressed; // down
			'h029: btn_fire         <= pressed; // space
			'h005: btn_one_player   <= pressed; // F1
			'h006: btn_two_players  <= pressed; // F2
			'h004: btn_coin         <= pressed; // F3
			'hX14: btn_barrier      <= pressed; // ctrl
		endcase
	end
end

reg btn_coin = 0;
reg btn_one_player = 0;
reg btn_two_players = 0;
reg btn_fire = 0;
reg btn_barrier = 0;
reg btn_right = 0;
reg btn_left = 0;

wire [1:0] r,g,b;

assign CLK_VIDEO = clk_sys;
assign VGA_R  = {r,r,r,r};
assign VGA_G  = {g,g,g,g};
assign VGA_B  = {b,b,b,b};
assign VGA_DE = ~(vblank | hblankb);

wire [11:0] audio;
assign AUDIO_L = {audio, 4'b0000};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;

//   SWITCH 1:     SWITCH 2:    NUMBER OF SPACESHIPS:
//   ---------     ---------    ---------------------
//     OFF           OFF                  6
//     ON            OFF                  5
//     OFF           ON                   4
//     ON            ON                   3
//                               FIRST FREE     SECOND FREE
//   SWITCH 3:     SWITCH 4:     SHIP SCORE:    SHIP SCORE:
//  ---------     ---------     -----------    -----------
//     OFF           OFF           6,000          60,000
//     ON            OFF           5,000          50,000
//     OFF           ON            4,000          40,000
//     ON            ON            3,000          30,000
//
// Cocktail,Factory,Factory,Factory,Bonus2,Bonus1,Ships2,Ships1
wire [7:0] dip_switch = 8'b00001111;

wire vblank, hblankb, hblankf;
phoenix phoenix
(
	.reset(RESET | status[0] | status[6] | buttons[1]),

	.clk(clk_sys),
	.ce_pix(CE_PIXEL),

	.dip_switch(dip_switch),

	.btn_coin(btn_coin | joy[7]),
	.btn_player_start({btn_two_players, btn_one_player | joy[6]}),
	.btn_left(btn_left | joy[2]),
	.btn_right(btn_right | joy[3]),
	.btn_barrier(btn_barrier | joy[5]),
	.btn_fire(btn_fire | joy[4]),

	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_hs(VGA_HS),
	.video_vs(VGA_VS),
	.video_vblank(vblank),
	.video_hblank_bg(hblankb),
	.video_hblank_fg(hblankf),

	.audio_select(0),
	.audio(audio)
);

endmodule