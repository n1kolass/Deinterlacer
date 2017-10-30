`timescale 1ns/1ns

module deinterlacer (
	input         		clock,                  
	input        		reset,           
	// AST Source       
	output logic [23:0] dout_data,          
	input  logic        dout_ready,         
	output logic        dout_valid,         
	output logic        dout_startofpacket, 
	output logic        dout_endofpacket,    
	// AST Sink
	input logic [23:0]	din_data,
	output logic 		din_ready,
	input logic			din_valid,
	input logic 		din_startofpacket,
	input logic			din_endofpacket
);

parameter WIDTH = 640;
parameter HEIGHT = 480;
parameter HALF_HEIGHT = HEIGHT / 2;
parameter MEM_SIZE = WIDTH * HALF_HEIGHT;


logic [23:0] width, half_height, height; // Width and height of the current field and height of frame
logic [23:0] num_of_pixel_in_line;
logic [23:0] num_of_line;
logic [23:0] cols, rows;
logic [23:0] mem [0:MEM_SIZE]; // Memory for storing 1 field
logic [19:0] ptr_wr, ptr_rd; // Pointers to memory cell
logic [19:0] current_line_ptr; // Pointer to the beggining of line, which will be duplicated
logic ready_to_send; // Determines whether source can send data (1) or not (0)
logic [1:0] beat_index; // Determines which beat of ctrl packet it is
logic [1:0] s_beat_index; // Determines which beat of ctrl packet for send it is

/*
	If 0-field came from source - store it to the mem. Transmit each line twice.
	If 1-field came from source - just recieve it and do nothing. (Ready signal
	is sent).
*/
/*
	States of reciever state-machine.
	Recieves fields and store into mem.
*/
enum {
	send_first_ready,		// Prepare to recieve data
	//wait_ctrl_packet,		// Wait for control packet
	process_ctrl_packet,	// Process control packet
	init_video_packet,
	process_video_packet	// Process video packet
} sink_state; 

/*
	States of sender state-machine.
	Sends frames.
*/
enum {
	wait_for_ready, 	// Wait for sink to be ready to recieve data
	form_ctrl_packet,	//	Makes ctrl packet for the whole frame
	begin_video_packet,
	send_odd_line,
	send_even_line
} source_state; 

enum {
	field0,
	field1
} field_ident; // Defines which field came from source 0 or 1

always_ff @(posedge clock or posedge reset) begin : sink
	if(reset) begin
		din_ready <= 0;
		ptr_wr <= 0;
		field_ident <= field0;
		sink_state <= send_first_ready;
		beat_index <= 0;
		width <= 0;
		half_height <= 0;
		height <= 0;
		cols <= 0;
		rows <= 0;
	end // if(reset)
 	else 
 		case (sink_state)
	 		
 			send_first_ready : begin
 				din_ready <= 1;
 				sink_state <= process_ctrl_packet;
 				//if( field_ident == field1 )
 					ptr_wr <= 0;
 				ready_to_send <= 0;
 				beat_index <= 0;
 				cols <= 0;
				rows <= 0;
 			end // send_first_ready :

 			process_ctrl_packet : begin
 				if( din_valid == 1 ) begin
 					if ( din_endofpacket == 1 ) begin
		 				if( din_data[19:16] == 4'hB /*Field0*/ )
		 					field_ident <= field0;
		 				else if( din_data[19:16] == 4'hF /*Field1*/ )
		 					field_ident <= field1;
		 				sink_state <= init_video_packet;
	 				end

	 				if( din_startofpacket == 1 )
	 					ready_to_send <= 1;

					mem[ptr_wr] <= din_data;
					ptr_wr <= ptr_wr + 1;
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
 					if( field_ident == field0 )
 						mem[ptr_wr] <= din_data;
					ptr_wr <= ptr_wr + 1;
					sink_state <= process_video_packet;
				end
 			end // init_video_packet :

 			process_video_packet : begin 
 				if( din_valid == 1 ) begin
 					if( field_ident == field0 )
 						mem[ptr_wr] <= din_data;
					ptr_wr <= ptr_wr + 1;

					if( cols == ( width - 1 ) ) begin
						if ( rows == ( half_height - 1 ) ) begin
							sink_state <= send_first_ready;
							//din_ready <= 0;
						end
						else
							rows <= rows + 1;
						cols <= 0;	
					end // if( cols == ( width - 1 ) )
					else
						cols <= cols + 1;

					if( cols == ( width - 2 ) )
						if( rows == ( half_height - 1 ) )
							din_ready <= 0;
				end
 			end // process_video_packet :

 		endcase
end

always_ff @(posedge clock or posedge reset) begin : source
	if(reset) begin
		dout_valid <= 0;
		dout_startofpacket <= 0;
		dout_endofpacket <= 0;
		ptr_rd <= 0;
		source_state <= wait_for_ready;
		num_of_pixel_in_line <= 0;
		num_of_line <= 0;
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
					ptr_rd <= 1;
					s_beat_index <= 1;
				end // if( dout_ready == 1 )
			end // wait_for_ready :

			form_ctrl_packet : begin 
				if( dout_ready == 1 ) begin 
					dout_valid <= 1;

					case (s_beat_index)

						1 : begin 
							dout_startofpacket <= 0;
							dout_data <= mem[ptr_rd];
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

					ptr_rd <= ptr_rd + 1;
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