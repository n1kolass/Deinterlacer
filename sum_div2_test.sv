`timescale 1ns/1ns

module sum_div2_test (
	input logic clock,
	input logic reset,
	output logic [7:0] sum
);

integer counter;

logic [7:0] first, second, sum_out;

sum_div2 #(8) sd2 (
	.a (first),
	.b (second),
	.out (sum_out)
);

always_ff @(posedge clock or posedge reset) begin : 
	if(reset) begin
		counter <= 0;
		first <= 0;
		second <= 0;
	end else begin
		if (counter < 16) begin
			first <= counter;
			second <= counter;
			counter <= counter + 1;
		end else begin 
			counter <= 0;
		end
	end
end

endmodule