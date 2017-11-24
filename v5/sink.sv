`timescale 1ns/1ns

//`include "util.sv"

module sink (
	clock,
	reset,

	din_data,
	din_ready,
	din_valid,
	din_startofpacket,
	din_endofpacket,

	// Interface to buffers
	wr_req0,
	//full0,
	wr_req1,
	//full1,
	// and source
	ready_to_continue,
	aver_sent
);

input logic clock;
input logic reset;
input logic [DATA_WIDTH-1:0] din_data;
output logic din_ready;
input logic din_valid;
input logic din_startofpacket;
input logic din_endofpacket;

output logic wr_req0;
//input logic full0;
output logic wr_req1;
//input logic full1;

output logic ready_to_continue;
input logic aver_sent;

logic [9:0] cur_px, cur_line;
enum { buff0, buff1 } cur_buff; // Which buffer is now prepared for loading next line
logic got_last_row;
logic wr_req0_sig, wr_req1_sig;

/*
	States of reciever state-machine.
	Recieves fields and store into mem.
*/
enum {
	send_first_ready,		// Prepare to recieve data
	process_ctrl_packet,	// Process control packet
	init_video_packet,
	first_line,
	receive_next_line,
	skip_line_state
} sink_state; 

always_comb begin 
	if ((sink_state == first_line) && din_valid)
		wr_req0_sig <= 1;
	else if ((sink_state == receive_next_line) && din_valid && (cur_buff == buff0))
		wr_req0_sig <= 1;
	else
		wr_req0_sig <= 0;
end

always_comb begin 
	if ((sink_state == receive_next_line) && din_valid && (cur_buff == buff1))
		wr_req1_sig <= 1;
	else
		wr_req1_sig <= 0;
end

always_ff @(posedge clock or posedge reset) begin : sink
	if (reset) begin
		sink_state <= send_first_ready;
		din_ready <= 0;
		cur_px <= 0;
		cur_line <= 0;
		cur_buff <= buff0;
		got_last_row <= 0;
		ready_to_continue <= 0;
	end else begin
		case (sink_state)
		
			send_first_ready : begin
				din_ready <= 1;
 				sink_state <= process_ctrl_packet;
			end

			process_ctrl_packet : begin
				if (din_valid) begin
					if (din_endofpacket)
						sink_state <= init_video_packet;
				end 
			end

			init_video_packet : begin
				if (din_valid) begin
					sink_state <= first_line;
					cur_px <= 0;
					cur_line <= 0;
					got_last_row <= 0;
				end
			end

			first_line : begin
				if (din_valid) begin
					if (cur_px == (WIDTH-1)) begin
						cur_px <= 0;	
						cur_line <= cur_line + 1;
						sink_state <= receive_next_line;
						cur_buff <= buff1;
					end else
						cur_px <= cur_px + 1;
				end
			end

			receive_next_line : begin 
				if (din_valid) begin 
					if (cur_px == (WIDTH-2)) 
						din_ready <= 0;
					if (cur_px == (WIDTH-1)) begin
						cur_px <= 0;	
						if (cur_line == (HALF_HEIGHT-1)) 
							got_last_row <= 1;
						else
							cur_line <= cur_line + 1;
						sink_state <= skip_line_state;
						ready_to_continue <= 1;
						if (cur_buff == buff0) begin
							cur_buff <= buff1;
						end else begin
							cur_buff <= buff0;
						end
					end else
						cur_px <= cur_px + 1;
				end
			end

			skip_line_state : begin
				if (aver_sent) begin
					ready_to_continue <= 0;
					if (got_last_row) 
						sink_state <= process_ctrl_packet;
					else
						sink_state <= receive_next_line;
					din_ready <= 1;
				end
			end
		endcase
	end
end // sink

endmodule