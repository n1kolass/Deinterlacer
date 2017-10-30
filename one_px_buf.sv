module one_px_buf (
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

logic [DATA_WIDTH-1:0] buffer;

assign 
	dout_startofpacket = din_startofpacket,
	dout_endofpacket = din_endofpacket,
	dout_ready = din_ready;

always_ff @(posedge clock or posedge reset) begin
	if(reset) begin
		 <= 0;
	end else begin
		 <= ;
	end
end

endmodule // one_px_buf