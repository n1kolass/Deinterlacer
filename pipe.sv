`timescale 1ns/1ns

module pipe (
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

logic full;
logic [DATA_WIDTH-1:0] buff;
logic buff_startofpacket, buff_endofpacket;

assign dout_valid = full;
assign din_ready = !full;
assign dout_data = buff;
assign dout_startofpacket = buff_startofpacket;
assign dout_endofpacket = buff_endofpacket;

always_ff @(posedge clock or posedge reset) begin
	if(reset) begin
		full <= 0;
	end else begin
		if (full == 0) begin
			if (din_valid) begin
				full <= 1;
			end
		end else begin
			if (dout_ready)
				full <= 0;
		end
	end
end

always_ff @(posedge clock or posedge reset) begin
	if(reset) begin
		buff <= {DATA_WIDTH{0}};
		buff_startofpacket <= 0;
		buff_endofpacket <= 0;
	end else begin
		if (full == 0)
			if (din_valid) begin
				buff <= din_data;
				buff_startofpacket <= din_startofpacket;
				buff_endofpacket <= din_endofpacket;
			end
	end
end

endmodule // pipe