`timescale 1ns/1ns
`define MAX_SIZE 10

module FIFO_1K_test (
	reset,
	clock,

	rd_req,
	wr_req,
	full,
	empty_enable
);

input logic reset;
input logic clock;
input logic rd_req;
input logic wr_req;
output logic full;
input logic empty_enable;

logic [9:0] head, tail;
logic inner_full;

assign full = inner_full;

always_ff @(posedge clock or posedge reset) begin
	if(reset) begin
		head <= 0;
		tail <= 0;
		inner_full <= 0;
	end else begin
		if (~inner_full) begin 
			if (head == `MAX_SIZE-1) begin 
				inner_full <= 1;
				head <= 0;
			end else if (wr_req) begin 
				head <= head + 1;
			end
		end else begin 
			if (tail == `MAX_SIZE-1) begin 
				if (empty_enable)
					inner_full <= 0;
				tail <= 0;
			end else if (rd_req) begin 
				tail <= tail + 1;
			end
		end
	end
end

endmodule // FIFO_1K