`timescale 1ns/1ns

module deinterlacer_v2 (
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

parameter  SYMBOLS_PER_BEAT = 3;
parameter  BITS_PER_SYMBOL  = 8;
localparam DATA_WIDTH		= SYMBOLS_PER_BEAT * BITS_PER_SYMBOL;
parameter  WIDTH 			= 640;
parameter  HEIGHT 			= 480;
localparam HALF_HEIGHT 		= HEIGHT / 2;
localparam BUFF0_BASE		= 0; // Base address for buff0
localparam BUFF1_BASE		= WIDTH; // Base address for buff1

input         		clock;                  
input        		reset;           
// AST Source       
output logic [DATA_WIDTH-1:0] dout_data;          
input  logic        		dout_ready;         
output logic        		dout_valid;         
output logic        		dout_startofpacket; 
output logic        		dout_endofpacket;    
// AST Sink
input  logic [DATA_WIDTH-1:0]	din_data;
output logic 				din_ready;
input  logic				din_valid;
input  logic 				din_startofpacket;
input  logic				din_endofpacket;

logic [DATA_WIDTH-1:0] width, half_height, height; // Width and height of the current field and height of frame
logic [DATA_WIDTH-1:0] num_of_pixel_in_line;
logic [DATA_WIDTH-1:0] num_of_line;
logic [DATA_WIDTH-1:0] cols, rows;
logic [DATA_WIDTH-1:0] buffs [0:2*WIDTH-1]; // Buffer for 2 lines (first is from BUFF0_BASE to WIDTH-1, second is from BUFF1_BASE to 2*WIDTH-1)
logic [DATA_WIDTH-1:0] ctrl_data_buff [0:4]; // Buffer for control data F,{D2,D1,D0},{D5,D4,D3},{D8,D7,D6},0 
enum { buff0, buff1 } current_buff; // Which buffer is now prepared for loading next line
logic [12:0] ptr_wr, ptr_rd; // Pointers to buffer cell
logic [2:0] ctrl_ptr_wr, ctrl_ptr_rd; // Pointers to control data buffer
logic ready_to_send; // Determines whether source can send data (1) or not (0)
logic skip_2_lines;
logic [1:0] beat_index; // Determines which beat of ctrl packet it is
logic [1:0] s_beat_index; // Determines which beat of ctrl packet for send it is

/*
	Принять строку, сохранить в буффер. Сменить буффер.
	Если это первая строка, то тут же её выдать.
	(*) Принять следующую строку, сохранить в буффер. Сменить буффер.
	Одновременно с получением строки, выдать линейную интерполяцию этой и предыдущей строки.
	Опустить сигнал din_ready. Выдать только что полученную строку.
	Включить сигнал din_ready. Перейти к (*).
*/
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


always_ff @(posedge clock or posedge reset) begin : sink
	if(reset) begin
		din_ready <= 0;
		ptr_wr <= BUFF0_BASE;
		ctrl_ptr_wr <= 0;
		sink_state <= send_first_ready;
		beat_index <= 0;
		width <= 0;
		half_height <= 0;
		cols <= 0;
		rows <= 0;
		current_buff <= buff0;
		skip_2_lines <= 0;
	end // if(reset)
 	else 
 		case (sink_state)
	 		
 			send_first_ready : begin
 				din_ready <= 1;
 				sink_state <= process_ctrl_packet;
 				ptr_wr <= BUFF0_BASE;
 				ctrl_ptr_wr <= 0;
 				ready_to_send <= 0;
 				beat_index <= 0;
 				cols <= 0;
				rows <= 0;
 			end // send_first_ready :

 			process_ctrl_packet : begin
 				if( din_valid == 1 ) begin
 					if ( din_endofpacket == 1 )
		 				sink_state <= init_video_packet;

	 				if( din_startofpacket == 1 )
	 					ready_to_send <= 1;

					ctrl_data_buff[ctrl_ptr_wr] <= din_data;
					ctrl_ptr_wr <= ctrl_ptr_wr + 1;
					beat_index <= beat_index + 1;

					// Parsing ctrl packet into demensions of the field
					case (beat_index)
						1 : width[15:4] <= {din_data[3:0], din_data[11:8], din_data[19:16]};
						2 : begin
							width[3:0] <= din_data[3:0];
							half_height[15:8] <= {din_data[11:8], din_data[19:16]};
						end // 2 :
						3 : half_height[7:0] <= {din_data[3:0], din_data[11:8]};
					endcase
				end
 			end // process_ctrl_packet :

 			init_video_packet : begin
 				if( din_valid == 1 ) begin
 					ctrl_data_buff[ctrl_ptr_wr] <= din_data;
					sink_state <= first_line;
				end
 			end // init_video_packet :

 			first_line : begin
 				if( din_valid == 1 ) begin
 					buffs[ptr_wr] <= din_data;
					ptr_wr <= ptr_wr + 1;

					if( cols == ( width - 1 ) ) begin
						cols <= 0;	
						rows <= rows + 1;
						sink_state <= receive_next_line;
						current_buff <= buff1;
						ptr_wr <= BUFF1_BASE;
					end
					else
						cols <= cols + 1;
				end
 			end

 			receive_next_line : begin
				if( din_valid == 1 ) begin
					buffs[ptr_wr] <= din_data;
					ptr_wr <= ptr_wr + 1;

					if( cols == ( width - 1 ) ) begin // Last pixel in line
						if( rows == ( half_height - 1) ) // Last line of the field
							skip_2_lines <= 1; // Lower din_ready for 2 lines
						else
							rows <= rows + 1;
						// Change buffer to the opposite
						if( current_buff == buff0 ) begin
							current_buff <= buff1;
							ptr_wr <= BUFF1_BASE;
						end else begin
							current_buff <= buff0;
							ptr_wr <= BUFF0_BASE;
						end
						din_ready <= 0;
						sink_state <= skip_line_state;
						cols <= 0;
					end else
						cols <= cols + 1;
				end // if( din_valid == 1 )
			end

 			skip_line_state : begin
 				if( skip_2_lines == 1 )
 					if( cols == ( 2*width - 2 ) ) begin
 						cols <= 0;
 						sink_state <= send_first_ready;
 						skip_2_lines <= 0;
 					end else
 						cols <= cols + 1;
 				else
	 				if( cols == ( width - 1 ) ) begin
	 					cols <= 0;
 						din_ready <= 1;
 						sink_state <= receive_next_line;
 					end else
	 					cols <= cols + 1;
	 		end

 		endcase
end

always_ff @(posedge clock or posedge reset) begin : source
	if(reset) begin
		dout_valid <= 0;
		dout_startofpacket <= 0;
		dout_endofpacket <= 0;
		ptr_rd <= 0;
		ctrl_ptr_rd <= 0;
		source_state <= wait_for_ready;
		num_of_pixel_in_line <= 0;
		num_of_line <= 0;
		height <= 0;
	end // if(reset) 
	else 
		case (source_state)
		
			wait_for_ready : begin
				dout_endofpacket <= 0;
				if( dout_ready == 1 && ready_to_send == 1 ) begin
					source_state <= form_ctrl_packet;
					dout_valid <= 1;
					dout_startofpacket <= 1;
					dout_data <= 24'h00_00_0F;
					ctrl_ptr_rd <= 1;
					s_beat_index <= 1;
					ptr_rd <= BUFF0_BASE;
				end // if( dout_ready == 1 )
			end // wait_for_ready :

			form_ctrl_packet : begin 
				if( dout_ready == 1 ) begin 
					dout_valid <= 1;

					case (s_beat_index)

						1 : begin 
							dout_startofpacket <= 0;
							dout_data <= ctrl_data_buff[ctrl_ptr_rd];
							height <= {half_height, 1'b0}; // height = half_height * 2
						end // 1 :

						2 : dout_data <= {4'h0, height[11:8], 4'h0, height[15:12], 4'h0, width[3:0]};

						3 : begin
							dout_data <= {
								4'h0, 4'h2/*deinterlaced from f0 field*/,
								4'h0, height[3:0],
								4'h0, height[7:4]
							};
							source_state <= begin_video_packet;
							dout_endofpacket <= 1;
						end // 3 :
						
					endcase

					ctrl_ptr_rd <= ctrl_ptr_rd + 1;
					s_beat_index <= s_beat_index + 1;
				end // if( dout_ready == 1 )
				else
					dout_valid <= 0;
			end // form_ctrl_packet :

			begin_video_packet : begin 
				if( dout_ready == 1 ) begin 
					dout_endofpacket <= 0;
					dout_startofpacket <= 1;
					dout_valid <= 1;
					dout_data <= mem[ptr_rd];
					ptr_rd <= ptr_rd + 1;
					num_of_pixel_in_line <= 0;
					num_of_line <= 0;
					source_state <= send_odd_line;
				end // if( dout_ready == 1 )
				else
					dout_valid <= 0;
			end // begin_video_packet :

			send_odd_line : begin 
				if( dout_ready == 1 ) begin 
					dout_valid <= 1;
					if( num_of_pixel_in_line == 0 ) begin
						current_line_ptr <= ptr_rd;
						if( num_of_line == 0 )
							dout_startofpacket <= 0;
					end // if( num_of_pixel_in_line == 0 )
					dout_data <= mem[ptr_rd];
					ptr_rd <= ptr_rd + 1;

					num_of_pixel_in_line <= num_of_pixel_in_line + 1;

					if( num_of_pixel_in_line == width - 1 ) begin 
						num_of_pixel_in_line <= 0;
						source_state <= send_even_line;
						ptr_rd <= current_line_ptr;
						//num_of_pixel_in_line <= 0;
					end
				end // if( dout_ready == 1 )
				else
					dout_valid <= 0;
			end // send_odd_line :

			send_even_line : begin 
				if( dout_ready == 1 ) begin 
					dout_valid <= 1;
					dout_data <= mem[ptr_rd];
					ptr_rd <= ptr_rd + 1;
					num_of_pixel_in_line <= num_of_pixel_in_line + 1;

					if( num_of_pixel_in_line == width - 1 ) begin 
						if( num_of_line == half_height - 1 ) begin
							dout_endofpacket <= 1;
							source_state <= wait_for_ready;
						end // if( num_of_line == half_height - 1 )
						else begin
							num_of_line <= num_of_line + 1;
							num_of_pixel_in_line <= 0;
							source_state <= send_odd_line;
						end
					end // if( num_of_pixel_in_line == width - 1 )
				end // if( dout_ready == 1 )
				else
					dout_valid <= 0;
			end // send_even_line :

		endcase
end

endmodule