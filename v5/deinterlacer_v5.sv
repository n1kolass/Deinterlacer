`timescale 1ns/1ns

//`include "util.sv"

module deinterlacer_v5 (
	clock,
	reset,
	// AST Source
	dout_data,
	dout_ready,
	dout_valid,
	dout_startofpacket,
	dout_endofpacket,
	// AST Sink
	din_data,
	din_ready,
	din_valid,
	din_startofpacket,
	din_endofpacket
);

input         					clock;
input        					reset;
// AST Source       
output logic [DATA_WIDTH-1:0] 	dout_data;
input  logic        			dout_ready;
output logic        			dout_valid;
output logic        			dout_startofpacket;
output logic        			dout_endofpacket;
// AST Sink
input  logic [DATA_WIDTH-1:0]	din_data;
output logic 					din_ready;
input  logic					din_valid;
input  logic 					din_startofpacket;
input  logic					din_endofpacket;

logic ready_to_continue_sig;
logic aver_sent_sig;
logic [DATA_WIDTH-1:0] dout_data_sig;
logic dout_valid_sig;
logic dout_startofpacket_sig;
logic dout_endofpacket_sig;

logic rd_req0, rd_req1;
logic wr_req0, wr_req1;
logic buff0_full, buff1_full;
logic empty_en0, empty_en1;
logic [DATA_WIDTH-1:0] from_fifo0, from_fifo1;

FIFO_1K fifo0 ( // Buffer for 1 line
	.reset 			(reset),
	.clock 			(clock),

	.rd_req 		(rd_req0),
	.q 				(from_fifo0),
	.wr_req 		(wr_req0),
	.data 			(din_data),
	.full 			(buff0_full),
	.empty_enable 	(empty_en0)
);

FIFO_1K fifo1 ( // Buffer for 1 line
	.reset 			(reset),
	.clock 			(clock),

	.rd_req 		(rd_req1),
	.q 				(from_fifo1),
	.wr_req 		(wr_req1),
	.data 			(din_data),
	.full 			(buff1_full),
	.empty_enable 	(empty_en1)
);

sink sink0 (
	.clock 				(clock),
	.reset 				(reset),

	.din_data 			(din_data),
	.din_ready 			(din_ready),
	.din_valid 			(din_valid),
	.din_startofpacket 	(din_startofpacket),
	.din_endofpacket 	(din_endofpacket),

	// Interface to buffers
	.wr_req0 			(wr_req0),
	.wr_req1 			(wr_req1),
	// and source
	.ready_to_continue 	(ready_to_continue_sig),
	.aver_sent 			(aver_sent_sig)
);

source source0 (
	.clock 				(clock),
	.reset 				(reset),

	.dout_data 			(dout_data_sig),
	.dout_ready 		(dout_ready),
	.dout_valid			(dout_valid_sig),
	.dout_startofpacket (dout_startofpacket_sig),
	.dout_endofpacket 	(dout_endofpacket_sig),

	// Interface to buffers
	.rd_req0 			(rd_req0),
	.q0 				(from_fifo0),
	.full0 				(buff0_full),
	.empty_enable0 		(empty_enable0),
	.rd_req1 			(rd_req1),
	.q1 				(from_fifo1),
	.full1 				(buff1_full),
	.empty_enable1 		(empty_enable1),
	// and source
	.ready_to_continue 	(ready_to_continue_sig),
	.aver_sent 			(aver_sent_sig)
);

assign dout_data = dout_data_sig;
assign dout_startofpacket = dout_startofpacket_sig;
assign dout_endofpacket = dout_endofpacket_sig;
assign dout_valid = dout_valid_sig;

endmodule