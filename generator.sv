/*
	The generator creates a chessboard pattern
-----------------------------------------
|    |****|    |****|    |****|    |****|
|    |****|    |****|    |****|    |****|
|    |****|    |****|    |****|    |****|
-----------------------------------------
|****|    |****|    |****|    |****|    |
|****|    |****|    |****|    |****|    |
|****|    |****|    |****|    |****|    |
-----------------------------------------
|    |****|    |****|    |****|    |****|
|    |****|    |****|    |****|    |****|
|    |****|    |****|    |****|    |****|
-----------------------------------------
|****|    |****|    |****|    |****|    |
|****|    |****|    |****|    |****|    |
|****|    |****|    |****|    |****|    |
-----------------------------------------
|    |****|    |****|    |****|    |****|
|    |****|    |****|    |****|    |****|
|    |****|    |****|    |****|    |****|
-----------------------------------------
*/

`timescale 1 ns / 1 ns
module generator (
		input         clock,                  //    clock.clk
		input        reset,                  //    reset.reset
		output logic [23:0] aso_out0_data,          // aso_out0.data
		input  logic        aso_out0_ready,         //         .ready
		output logic        aso_out0_valid,         //         .valid
		output logic        aso_out0_startofpacket, //         .startofpacket
		output logic        aso_out0_endofpacket    //         .endofpacket
	);

enum {
	send_ctrl_packet_init, // Begin control packet transmission (send header - first 3 bytes 0x0F, 0x00, 0x00)
	send_ctrl_packet_main, // Send rest control packet data, including width, height and interlaced params
	send_data_packet_init, // Begin data packet transmission (send header - first 3 bytes 0x00, 0x00, 0x00)
	send_data_packet_main // Send rest data packet (line of frame)
} current_state;

/*
	Data packet is the whole frame.
*/

logic [1:0] counter;
integer rows, cols; 
logic rectangle_ident; // Defines, which rectangle of frame it is - odd or even

parameter white = 24'hFFFFFF; // White color
parameter black = 24'h000000; // Black color
parameter width = 270; // Width of frame
parameter height = 200; // Height of frame

always_ff @(posedge clock or posedge reset) begin
	if(reset) begin
			aso_out0_valid <= 1'b0;
			aso_out0_endofpacket <= 1'b0;
			aso_out0_startofpacket <= 1'b0;
			current_state <= send_ctrl_packet_init;
	end // if(reset)
	else 
		case (current_state)

			send_ctrl_packet_init : begin
				aso_out0_endofpacket <= 1'b0;
				if( aso_out0_ready == 1 ) begin 
					aso_out0_valid <= 1'b1;
					aso_out0_startofpacket <= 1'b1;
					aso_out0_data <= 24'h 00_00_0F; // Control packet identifier
					current_state <= send_ctrl_packet_main;
					counter <= 0;
				end // if( aso_out0_ready == 1 )
				else
					aso_out0_valid <= 1'b0;
			end // send_ctrl_packet_init :

			send_ctrl_packet_main : begin
				aso_out0_startofpacket <= 1'b0;
				if( aso_out0_ready == 1 ) begin
					aso_out0_valid <= 1'b1;
					case (counter)
						
						0 : begin
							aso_out0_data <= {4'h0, width[7:4], 4'h0, width[11:8], 4'h0, width[15:12]};
							counter <= counter + 1;
						end // 0 :

						1 : begin 
							aso_out0_data <= {4'h0, height[11:8], 4'h0, height[15:12], 4'h0, width[3:0]};
							counter <= counter + 1;
						end // 1 :

						2 : begin 
							aso_out0_data <= {4'h0, 4'h2, 4'h0, height[3:0], 4'h0, height[7:4]};
							aso_out0_endofpacket <= 1'b1;
							rows <= 0;
							cols <= 0;
							current_state <= send_data_packet_init;
						end // 2 :

					endcase
				end // if( aso_out0_ready == 1 )
				else
					aso_out0_valid <= 1'b0;
			end // send_ctrl_packet_main :

			send_data_packet_init : begin
				aso_out0_endofpacket <= 1'b0;
				if( aso_out0_ready == 1 ) begin
					aso_out0_valid <= 1'b1;
					aso_out0_startofpacket <= 1'b1;
					aso_out0_data <= 24'h 00_00_00; // Video packet identifier
					rectangle_ident <= 0;
					current_state <= send_data_packet_main;
				end // if( aso_out0_ready == 1 )
				else 
					aso_out0_valid <= 1'b0;
			end // send_data_packet_init :

			send_data_packet_main : begin
				aso_out0_startofpacket <= 1'b0;
				if( aso_out0_ready == 1 ) begin 
					aso_out0_valid <= 1'b1;
					
					// Change color of rectangle every 30 cols and 24 rows
					if( ( rows % 20 ) == 0 && rows != 0 && cols == ( width - 1) )
						rectangle_ident <= ~rectangle_ident;

					if( rectangle_ident == 0 )
						aso_out0_data <= white;
					else if( rectangle_ident == 1 )
						aso_out0_data <= black;

					if( ( cols % 10 ) == 9 )
						aso_out0_data <= {cols[7:0],cols[7:0],cols[7:0]};

					// If it is width-th column and height-th row - end packet and begin new frame
					if( cols == ( width - 1) ) begin
						if ( rows == ( height - 1 ) ) begin
							aso_out0_endofpacket <= 1'b1;	
							current_state <= send_ctrl_packet_init;
						end // if ( rows == height )
						else 
							rows <= rows + 1;
						cols <= 0;	
					end // if( cols == width )
					else
						cols <= cols + 1;
				end // if( aso_out0_ready == 1 )
				else
					aso_out0_valid <= 1'b0;
			end // send_data_packet_main :

			default : current_state <= send_ctrl_packet_init;

		endcase
end // always_ff @(posedge clock or posedge reset)

endmodule