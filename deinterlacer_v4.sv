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

parameter  SYMBOLS_PER_BEAT = 1;
parameter  BITS_PER_SYMBOL  = 8;
localparam DATA_WIDTH		= SYMBOLS_PER_BEAT * BITS_PER_SYMBOL;
parameter  WIDTH 			= 640;
parameter  HEIGHT 			= 480;
localparam HALF_HEIGHT 		= HEIGHT / 2;
localparam BUFF0_BASE		= 0; // Base address for buff0
localparam BUFF1_BASE		= WIDTH; // Base address for buff1

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

logic [DATA_WIDTH-1:0] num_of_pixel_in_line;
logic [DATA_WIDTH-1:0] num_of_line;
logic [DATA_WIDTH-1:0] cols, rows;
logic [BITS_PER_SYMBOL-1:0] buffs [0:2*WIDTH-1]; // Buffer for 2 lines (first is from BUFF0_BASE to WIDTH-1, second is from BUFF1_BASE to 2*WIDTH-1)
enum { buff0, buff1 } current_buff; // Which buffer is now prepared for loading next line
logic [12:0] ptr_wr, ptr_rd, ptr_rd2; // Pointers to buffer cell
logic got_last_row;

logic aver_sent; // Average line was sent
logic buff0_full, buff1_full;
logic [3:0] ctrl_px_counter;

logic [BITS_PER_SYMBOL-1:0] px1, px2, px_out;
logic last_line_source_flag;

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

always_ff @(posedge clock or posedge reset) begin : sink
	if ( reset ) begin
		sink_state <= send_first_ready;
		din_ready <= 0;
		cols <= 0;
		rows <= 0;
		ptr_wr <= BUFF0_BASE;
		current_buff <= buff0;
		got_last_row <= 0;
		buff0_full <= 0;
		buff1_full <= 0;
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
					buff0_full <= 0;
					buff1_full <= 0;
					ptr_wr <= BUFF0_BASE;
					got_last_row <= 0;
				end
			end

			first_line : begin
				if ( din_valid ) begin
					buffs[ptr_wr] <= din_data[7:0];
					ptr_wr <= ptr_wr + 1;

					if( cols == ( WIDTH - 1 ) ) begin
						cols <= 0;	
						rows <= rows + 1;
						sink_state <= receive_next_line;
						current_buff <= buff1;
						ptr_wr <= BUFF1_BASE;
						buff0_full <= 1;
					end else
						cols <= cols + 1;
				end
			end

			receive_next_line : begin 
				if ( din_valid ) begin 
					if ( rows == 1 ) begin 
						buffs[ptr_wr] <= din_data[7:0];
						ptr_wr <= ptr_wr + 1;

						if( cols == ( WIDTH - 1 ) ) begin
							cols <= 0;	
							rows <= rows + 1;
							sink_state <= skip_line_state;
							current_buff <= buff0;
							ptr_wr <= BUFF0_BASE;
							buff1_full <= 1;
						end else
							cols <= cols + 1;

						if ( cols == ( WIDTH - 2 ) )
							din_ready <= 0;
					end else begin
						buffs[ptr_wr] <= din_data[7:0];
						ptr_wr <= ptr_wr + 1;

						if( cols == ( WIDTH - 1 ) ) begin
							cols <= 0;	

							if ( rows == ( HALF_HEIGHT - 1 ) ) 
								got_last_row <= 1;
							else
								rows <= rows + 1;

							sink_state <= skip_line_state;

							if (current_buff == buff0) begin
								current_buff <= buff1;
								ptr_wr <= BUFF1_BASE;
								buff0_full <= 1;
							end else begin
								current_buff <= buff0;
								ptr_wr <= BUFF0_BASE;
								buff1_full <= 1;
							end
						end else
							cols <= cols + 1;

						if ( cols == ( WIDTH - 2 ) )
							din_ready <= 0;
					end
				end
			end

			skip_line_state : begin
				if ( aver_sent ) begin
					if ( got_last_row ) 
						sink_state <= process_ctrl_packet;
					else
						sink_state <= receive_next_line;
					din_ready <= 1;

					if ( current_buff == buff0 )
						buff0_full <= 0;
					else
						buff1_full <= 0;
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
	send_next_line
} source_state; 

always_ff @(posedge clock or posedge reset) begin : source
	if ( reset ) begin
		source_state <= wait_for_ready;
		dout_valid <= 0;
		dout_startofpacket <= 0;
		dout_endofpacket <= 0;
		ptr_rd <= 0;
		ptr_rd2 <= 0;
		num_of_pixel_in_line <= 0;
		num_of_line <= 0;
		ctrl_px_counter <= 0;
		last_line_source_flag <= 0;
		aver_sent <= 0;
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
					ptr_rd <= BUFF0_BASE;
					ptr_rd2 <= BUFF0_BASE;
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
					dout_data <= buffs[ptr_rd];
					ptr_rd <= ptr_rd + 1;

					if( num_of_pixel_in_line == ( WIDTH - 1 ) ) begin
						num_of_pixel_in_line <= 0;	
						source_state <= send_interpolated_line;
						ptr_rd <= BUFF1_BASE;
					end else
						num_of_pixel_in_line <= num_of_pixel_in_line + 1;
				end else
					dout_valid <= 0;
			end

			send_interpolated_line : begin 
				if ( dout_ready && buff0_full && buff1_full ) begin 
					dout_valid <= 1;
					dout_data <= px_out;

					ptr_rd <= ptr_rd + 1;
					ptr_rd2 <= ptr_rd2 + 1;

					if( num_of_pixel_in_line == ( WIDTH - 1 ) ) begin
						num_of_pixel_in_line <= 0;	
						num_of_line <= num_of_line + 1;
						source_state <= send_next_line;

						if (ptr_rd > WIDTH) begin 
							ptr_rd <= BUFF0_BASE;
							ptr_rd2 <= BUFF0_BASE;
						end else begin 
							ptr_rd <= BUFF1_BASE;
							ptr_rd2 <= BUFF1_BASE;
						end
						if ( num_of_line != ( HALF_HEIGHT - 2 ) )
							aver_sent <= 1;
					end else
						num_of_pixel_in_line <= num_of_pixel_in_line + 1;
				end else
					dout_valid <= 0;
			end

			send_next_line : begin 
				if ( dout_ready ) begin 
					if ( num_of_pixel_in_line == 0 )
						aver_sent <= 0;
					dout_valid <= 1;
					dout_data <= buffs[ptr_rd];
					ptr_rd <= ptr_rd + 1;

					if( num_of_pixel_in_line == ( WIDTH - 1 ) ) begin
						num_of_pixel_in_line <= 0;	

						if ( num_of_line == ( HALF_HEIGHT - 1 ) ) begin 
							if (last_line_source_flag == 1) begin
								aver_sent <= 1;
								dout_endofpacket <= 1;
								source_state <= wait_for_ready;
							end else begin
								last_line_source_flag <= 1;
								source_state <= send_next_line;
							end
						end else
							source_state <= send_interpolated_line;
						
						if ( ptr_rd > WIDTH ) begin 
							ptr_rd <= BUFF0_BASE;
						end else begin 
							ptr_rd <= BUFF1_BASE;
						end
					end else
						num_of_pixel_in_line <= num_of_pixel_in_line + 1;
				end else
					dout_valid <= 0;
			end
		endcase
	end
end


sum_div2 #(BITS_PER_SYMBOL) sd2 (
	.a 		(px1 	),
	.b 		(px2 	),
	.out 	(px_out )
);

assign 
	px1 = buffs[ptr_rd],
	px2 = buffs[ptr_rd2];


endmodule // deinterlacer_v3

/*
force /structure/clock 0 0, 1 10ns -r 20ns
force /structure/reset 1 0, 0 10ns

*/