`timescale 1ns/1ns

`include "util.sv"

module source (
	clock,
	reset,

	dout_data,
	dout_ready,
	dout_valid,
	dout_startofpacket,
	dout_endofpacket,

	// Interface to buffers
	rd_req0,
	q0,
	full0,
	empty_enable0,
	rd_req1,
	q1,
	full1,
	empty_enable1,
	// and source
	ready_to_continue,
	aver_sent
);

input logic clock;
input logic reset;
output logic [DATA_WIDTH-1:0] dout_data;
input logic dout_ready;
output logic dout_valid;
output logic dout_startofpacket;
output logic dout_endofpacket;

output logic rd_req0;
input logic [DATA_WIDTH-1:0] q0;
input logic full0;
input logic empty_enable0;
output logic rd_req1;
input logic [DATA_WIDTH-1:0] q1;
input logic full1;
input logic empty_enable1;

input logic ready_to_continue;
output logic aver_sent;

logic [9:0] cur_px, cur_line;
logic [3:0] ctrl_px_counter;
logic last_line_source_flag;
enum { buff0, buff1 } cur_buff; // Which buffer is now prepared for sending next line
logic send_aver_sent_where_to;
logic [DATA_WIDTH-1:0] px_out;
logic rd_req0_sig, rd_req1_sig;

/*
	States of sender state-machine.
	Sends frames.
*/
enum {
	wait_for_ready, 		// Wait for sink to be ready to recieve data
	form_ctrl_packet,		// Makes ctrl packet for the whole frame
	begin_video_packet,		// Send WIDTH{0}
	send_first_line,
	send_interpolated_line,
	send_next_line,
	send_aver_sent
} source_state; 

always_ff @(posedge clock or posedge reset) begin : source
	if (reset) begin
		source_state <= wait_for_ready;
		dout_valid <= 0;
		dout_startofpacket <= 0;
		dout_endofpacket <= 0;
		cur_px <= 0;
		cur_line <= 0;
		ctrl_px_counter <= 0;
		last_line_source_flag <= 0;
		aver_sent <= 0;
		rd_req0_sig <= 0;
		rd_req1_sig <= 0;
		cur_buff <= buff0;
		send_aver_sent_where_to <= 0;
	end else begin
		
		case (source_state)
		
			wait_for_ready : begin
				if (dout_ready && full0) begin 
					dout_endofpacket <= 0;
					dout_valid <= 1;
					dout_startofpacket <= 1;
					dout_data <= 8'h0F;
					ctrl_px_counter <= 1;
					last_line_source_flag <= 0;
					aver_sent <= 0;
					source_state <= form_ctrl_packet;
				end
			end

			form_ctrl_packet : begin 
				if (dout_ready) begin 
					dout_valid <= 1;
					case (ctrl_px_counter)

						1 : begin
							dout_startofpacket <= 0;
							dout_data <= {4'h0, WIDTH[15:12]};
						end 

						2 : begin
							dout_data <= {4'h0, WIDTH[11:8]};
						end 

						3 : begin
							dout_data <= {4'h0, WIDTH[7:4]};
						end 

						4 : begin
							dout_data <= {4'h0, WIDTH[3:0]};
						end 

						5 : begin
							dout_data <= {4'h0, HEIGHT[15:12]};
						end 

						6 : begin
							dout_data <= {4'h0, HEIGHT[11:8]};
						end 

						7 : begin
							dout_data <= {4'h0, HEIGHT[7:4]};
						end 

						8 : begin
							dout_data <= {4'h0, HEIGHT[3:0]};
						end 

						9 : begin 
							dout_data <= 4'b0010; // Progressive, starting with F0
							dout_endofpacket <= 1'b1;
							source_state <= begin_video_packet;
						end 
						
					endcase
					ctrl_px_counter <= ctrl_px_counter + 1;
				end else  
					dout_valid <= 0;
			end

			begin_video_packet : begin 
				if (dout_ready) begin 
					dout_valid <= 1;
					dout_endofpacket <= 0;
					dout_startofpacket <= 1;
					dout_data <= 8'h00;
					cur_px <= 0;
					cur_line <= 0;
					source_state <= send_first_line;
				end else
					dout_valid <= 0;
			end

			send_first_line : begin 
				if (dout_ready) begin 
					if (cur_px == 0)
						dout_startofpacket <= 0;
					dout_valid <= 1;
					dout_data <= q0;
					rd_req0_sig <= 1;

					if(cur_px == (WIDTH-1)) begin
						cur_px <= 0;	
						source_state <= send_interpolated_line;
						cur_buff <= buff1;
					end else begin
						cur_px <= cur_px + 1;
					end
				end else begin
					dout_valid <= 0;
					rd_req0_sig <= 0;
				end
			end

			send_interpolated_line : begin 
				if (dout_ready && full0 && full1) begin 
					if (cur_px == 0) begin 
						empty_enable0 <= 0;
						empty_enable1 <= 1;
					end
					dout_valid <= 1;
					dout_data <= px_out;

					rd_req0_sig <= 1;
					rd_req1_sig <= 1;

					if (cur_px == (WIDTH-1)) begin
						cur_px <= 0;	
						cur_line <= cur_line + 1;
						if (cur_buff == buff0) begin
							cur_buff <= buff1;
							empty_enable0 <= 0;
							empty_enable1 <= 1;
						end else begin
							cur_buff <= buff0;
							empty_enable0 <= 1;
							empty_enable1 <= 0;
						end
						if (cur_line != (HALF_HEIGHT-2)) begin
							//aver_sent <= 1;
							send_aver_sent_where_to <= 0;
							source_state <= send_aver_sent;
						end else
							source_state <= send_next_line;
					end else begin
						cur_px <= cur_px + 1;
					end
				end else begin
					dout_valid <= 0;
					rd_req0_sig <= 0;
					rd_req1_sig <= 0;
				end
			end

			send_next_line : begin 
				if (dout_ready) begin 
					if (cur_px == 0)
						aver_sent <= 0;
					dout_valid <= 1;
					if (cur_buff == buff0) begin
						dout_data <= q0;
						rd_req0_sig <= 1;
						rd_req1_sig <= 0;
					end else begin 
						dout_data <= q1;
						rd_req1_sig <= 1;
						rd_req0_sig <= 0;
					end

					if (cur_px == (WIDTH-1)) begin
						cur_px <= 0;	
						if (cur_line == (HALF_HEIGHT-1)) begin 
							if (last_line_source_flag == 1) begin
								//aver_sent <= 1;
								source_state <= send_aver_sent;
								send_aver_sent_where_to <= 1;
								dout_endofpacket <= 1;
								//source_state <= wait_for_ready;
							end else begin
								last_line_source_flag <= 1;
								source_state <= send_next_line;
							end
						end else
							source_state <= send_interpolated_line;
						
						if (cur_buff == buff0) begin
							cur_buff <= buff1;
						end else begin
							cur_buff <= buff0;
						end
					end else begin
						cur_px <= cur_px + 1;
					end
				end else begin
					dout_valid <= 0;
					rd_req0_sig <= 0;
					rd_req1_sig <= 0;
				end
			end

			send_aver_sent : begin 
				if (ready_to_continue) begin 
					aver_sent <= 1;
					if (send_aver_sent_where_to)
						source_state <= wait_for_ready;
					else
						source_state <= send_next_line;
				end
			end
		endcase
	end
end

sum_div2 #(DATA_WIDTH) sd2 (
	.a 		(px1 	),
	.b 		(px2 	),
	.out 	(px_out )
);

assign 
	px1 = (cur_buff == buff0) ? q0 : q1,
	px2 = (cur_buff == buff0) ? q1 : q0;

endmodule