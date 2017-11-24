`timescale 1ns/1ns

module deinterlacer_v4 (
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

parameter  DATA_WIDTH 		= 8;
parameter  WIDTH 			= 640;
parameter  HEIGHT 			= 480;
localparam HALF_HEIGHT 		= HEIGHT / 2;

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

logic [9:0] num_of_pixel_in_line;
logic [9:0] num_of_line;
logic [9:0] cols, rows;
enum { buff0, buff1 } current_buff, current_buff_to_read; // Which buffer is now prepared for loading and sending next line
logic got_last_row;

logic aver_sent; // Average line was sent
logic send_aver_sent_where_to; // Which state is go after send_aver_sent
logic ready_to_continue; 
logic buff0_full, buff1_full;
logic [3:0] ctrl_px_counter;

logic [DATA_WIDTH-1:0] px1, px2, px_out;
logic last_line_source_flag;

logic inner_rd_req0, inner_wr_req0, inner_rd_req1, inner_wr_req1;
logic empty_en0, empty_en1;
logic [7:0] from_fifo0, from_fifo1;

FIFO_1K fifo0 ( // Buffer for 1 line
	.reset 		(reset),
	.clock 		(clock),

	.rd_req 	(inner_rd_req0),
	.q 			(from_fifo0),
	.wr_req 	(inner_wr_req0),
	.data 		(din_data),
	.full 		(buff0_full),
	.empty_enable (empty_en0)
);

FIFO_1K fifo1 ( // Buffer for 1 line
	.reset 		(reset),
	.clock 		(clock),

	.rd_req 	(inner_rd_req1),
	.q 			(from_fifo1),
	.wr_req 	(inner_wr_req1),
	.data 		(din_data),
	.full 		(buff1_full),
	.empty_enable (empty_en1)
);

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
		inner_wr_req0 <= 1;
	else if ((sink_state == receive_next_line) && din_valid && (current_buff == buff0))
		inner_wr_req0 <= 1;
	else
		inner_wr_req0 <= 0;
end

always_comb begin 
	if ((sink_state == receive_next_line) && din_valid && (current_buff == buff1))
		inner_wr_req1 <= 1;
	else
		inner_wr_req1 <= 0;
end

always_ff @(posedge clock or posedge reset) begin : sink
	if ( reset ) begin
		sink_state <= send_first_ready;
		din_ready <= 0;
		cols <= 0;
		rows <= 0;
		current_buff <= buff0;
		got_last_row <= 0;
		ready_to_continue <= 0;
	end else begin
		case ( sink_state )
		
			send_first_ready : begin
				din_ready <= 1;
 				sink_state <= process_ctrl_packet;
			end

			process_ctrl_packet : begin
				if ( din_valid ) begin
					if ( din_endofpacket )
						sink_state <= init_video_packet;
				end 
			end

			init_video_packet : begin
				if ( din_valid ) begin
					sink_state <= first_line;
					cols <= 0;
					rows <= 0;
					got_last_row <= 0;
				end
			end

			first_line : begin
				if ( din_valid ) begin
					if( cols == ( WIDTH - 1 ) ) begin
						cols <= 0;	
						rows <= rows + 1;
						sink_state <= receive_next_line;
						current_buff <= buff1;
					end else
						cols <= cols + 1;
				end
			end

			receive_next_line : begin 
				if ( din_valid ) begin 
					if ( cols == ( WIDTH - 2 ) )
							din_ready <= 0;
					if ( rows == 1 ) begin 
						if( cols == ( WIDTH - 1 ) ) begin
							cols <= 0;	
							rows <= rows + 1;
							sink_state <= skip_line_state;
							ready_to_continue <= 1;
							current_buff <= buff0;
						end else
							cols <= cols + 1;
					end else begin
						if( cols == ( WIDTH - 1 ) ) begin
							cols <= 0;	

							if ( rows == ( HALF_HEIGHT - 1 ) ) 
								got_last_row <= 1;
							else
								rows <= rows + 1;

							sink_state <= skip_line_state;
							ready_to_continue <= 1;

							if (current_buff == buff0) begin
								current_buff <= buff1;
							end else begin
								current_buff <= buff0;
							end
						end else
							cols <= cols + 1;
					end
				end
			end

			skip_line_state : begin
				if ( aver_sent ) begin
					ready_to_continue <= 0;
					if ( got_last_row ) 
						sink_state <= process_ctrl_packet;
					else
						sink_state <= receive_next_line;
					din_ready <= 1;
				end
			end
		endcase
	end
end // sink

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
	if ( reset ) begin
		source_state <= wait_for_ready;
		dout_valid <= 0;
		dout_startofpacket <= 0;
		dout_endofpacket <= 0;
		num_of_pixel_in_line <= 0;
		num_of_line <= 0;
		ctrl_px_counter <= 0;
		last_line_source_flag <= 0;
		aver_sent <= 0;
		inner_rd_req0 <= 0;
		inner_rd_req1 <= 0;
		current_buff_to_read <= buff0;
		send_aver_sent_where_to <= 0;
	end else begin
		
		case ( source_state )
		
			wait_for_ready : begin
				if ( dout_ready && buff0_full ) begin 
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
				if ( dout_ready ) begin 
					dout_valid <= 1;
					case ( ctrl_px_counter )

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
				if ( dout_ready ) begin 
					dout_valid <= 1;
					dout_endofpacket <= 0;
					dout_startofpacket <= 1;
					dout_data <= 8'h00;
					num_of_pixel_in_line <= 0;
					num_of_line <= 0;
					source_state <= send_first_line;
				end else
					dout_valid <= 0;
			end

			send_first_line : begin 
				if ( dout_ready ) begin 
					if ( num_of_pixel_in_line == 0 )
						dout_startofpacket <= 0;
					dout_valid <= 1;
					dout_data <= from_fifo0;

					if( num_of_pixel_in_line == ( WIDTH - 1 ) ) begin
						num_of_pixel_in_line <= 0;	
						source_state <= send_interpolated_line;
						current_buff_to_read <= buff1;
						inner_rd_req0 <= 0;
					end else begin
						num_of_pixel_in_line <= num_of_pixel_in_line + 1;
						inner_rd_req0 <= 1;
					end
				end else begin
					dout_valid <= 0;
					inner_rd_req0 <= 0;
				end
			end

			send_interpolated_line : begin 
				if ( dout_ready && buff0_full && buff1_full ) begin 
					dout_valid <= 1;
					dout_data <= px_out;

					if( num_of_pixel_in_line == ( WIDTH - 1 ) ) begin
						num_of_pixel_in_line <= 0;	
						num_of_line <= num_of_line + 1;
						if (current_buff_to_read == buff0) begin
							current_buff_to_read <= buff1;
						end else begin
							current_buff_to_read <= buff0;
						end
						if ( num_of_line != ( HALF_HEIGHT - 2 ) ) begin
							//aver_sent <= 1;
							send_aver_sent_where_to <= 0;
							source_state <= send_aver_sent;
						end else
							source_state <= send_next_line;

						inner_rd_req0 <= 0;
						inner_rd_req1 <= 0;
					end else begin
						num_of_pixel_in_line <= num_of_pixel_in_line + 1;
						inner_rd_req0 <= 1;
						inner_rd_req1 <= 1;
					end
				end else begin
					dout_valid <= 0;
					inner_rd_req0 <= 0;
					inner_rd_req1 <= 0;
				end
			end

			send_next_line : begin 
				if ( dout_ready ) begin 
					if ( num_of_pixel_in_line == 0 )
						aver_sent <= 0;
					dout_valid <= 1;
					if (current_buff_to_read == buff0) begin
						dout_data <= from_fifo0;
						// inner_rd_req0 <= 1;
						// inner_rd_req1 <= 0;
					end else begin 
						dout_data <= from_fifo1;
						// inner_rd_req1 <= 1;
						// inner_rd_req0 <= 0;
					end

					if( num_of_pixel_in_line == ( WIDTH - 1 ) ) begin
						num_of_pixel_in_line <= 0;	

						if ( num_of_line == ( HALF_HEIGHT - 1 ) ) begin 
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
						
						if (current_buff_to_read == buff0) begin
							current_buff_to_read <= buff1;
						end else begin
							current_buff_to_read <= buff0;
						end

						inner_rd_req1 <= 0;
						inner_rd_req0 <= 0;
					end else begin
						num_of_pixel_in_line <= num_of_pixel_in_line + 1;
						if (current_buff_to_read == buff0) begin
							inner_rd_req0 <= 1;
							inner_rd_req1 <= 0;
						end else begin 
							inner_rd_req1 <= 1;
							inner_rd_req0 <= 0;
						end
					end
				end else begin
					dout_valid <= 0;
					inner_rd_req0 <= 0;
					inner_rd_req1 <= 0;
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
	px1 = (current_buff_to_read == buff0) ? from_fifo0 : from_fifo1,
	px2 = (current_buff_to_read == buff0) ? from_fifo1 : from_fifo0;


endmodule // deinterlacer_v3

/*
force /structure/clock 0 0, 1 10ns -r 20ns
force /structure/reset 1 0, 0 10ns

*/