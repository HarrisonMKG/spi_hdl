module spi_drv #(
    parameter integer               CLK_DIVIDE  = 100, // Clock divider to indicate frequency of SCLK
    parameter integer               SPI_MAXLEN  = 32   // Maximum SPI transfer length
) (
    input                           clk,
    input                           sresetn,        // active low reset, synchronous to clk
    
    // Command interface 
    input                           start_cmd,     // Start SPI transfer
    output                          spi_drv_rdy,   // Ready to begin a transfer
    input  [$clog2(SPI_MAXLEN):0]   n_clks,        // Number of bits (SCLK pulses) for the SPI transaction
    input  [SPI_MAXLEN-1:0]         tx_data,       // Data to be transmitted out on MOSI
    output [SPI_MAXLEN-1:0]         rx_miso,       // Data read in from MISO
    
    // SPI pins
    output                          SCLK,          // SPI clock sent to the slave
    output                          MOSI,          // Master out slave in pin (data output to the slave)
    input                           MISO,          // Master in slave out pin (data input from the slave)
    output                          SS_N           // Slave select, will be 0 during a SPI transaction
);


//IMPLEMENTATION:
//Clock Divider implemented by using a Counter and a flip flop. Once the counter reached, count_reached is 
//assserted which allows for SCLK to transition to it's inverse value through XOR (SCLK^count_reach == ~SCLK). MISO and MOSI are going to be latched through a level sensitive D latch. This was done
//because we want them to store the next bit to be read/transfered on every clock cycle, so they need to change every clock cycle. In addition, to ensure data is
//outputted in order, and seriallly, a shift register was used for tx_data and rx_miso.
//For first transfer, the flip flops will have a low enable, making them retain their state even on a clock trigger
//for an added clock cycle.  This is because there is no positive edge to allow for the data to be sampled when it is first asserted on the data line.

//TESTBENCH:
//SPI master will be tested through loop back (MOSI feeds into MISO)

// counter
reg[6:0] clk_div_counter = 0;
wire count_reached;
reg r_spi_drv_rdy, r_sclk, r_SS_N;
reg[SPI_MAXLEN-1:0] r_tx_data, r_rx_miso;
reg[5:0] bits_transfered; // 6 bits for 32 possible values

assign MOSI = r_tx_data[SPI_MAXLEN-1];
wire first_transfer;
 
assign SCLK = r_sclk;
assign SS_N = r_SS_N;
assign spi_drv_rdy = r_spi_drv_rdy;
assign count_reached = ((CLK_DIVIDE - 1) == clk_div_counter);
assign first_transfer = (bits_transfered == 0);
assign rx_miso = r_rx_miso;

// clk divide
always@ (posedge(r_sclk))
begin
    if(start_cmd)
    begin
        r_spi_drv_rdy <= 0;
        r_SS_N <= 0;
        r_tx_data <= tx_data << (SPI_MAXLEN - n_clks); // brings bits to transmit to front of register
    end
end

always@ (posedge(clk))
begin
    if(!sresetn) 
    begin
        r_spi_drv_rdy <= 1;
        r_SS_N <= 1;
        r_tx_data <= 0;
        r_rx_miso <= 0;
        r_sclk <= 0; 
        clk_div_counter <= 0;
        bits_transfered <=0;
    end
    else if(count_reached) 
    begin
        clk_div_counter <= 0;
        r_sclk <= !SCLK;
    end 
    else 
    begin
        clk_div_counter <= clk_div_counter + 1;
    end 
end
// end_clk divide

//Master out Slave in
assign transfer_complete = (bits_transfered == n_clks);
always@(negedge(r_sclk))
    if(!spi_drv_rdy)
        begin
            if(first_transfer)
            begin
                bits_transfered <= bits_transfered + 1;
            end
            else
            begin
                bits_transfered <= bits_transfered + 1;
                r_tx_data <= {r_tx_data[SPI_MAXLEN-2:0],1'b0}; // Feeds out data 1 bit at a time
            end
        end

//Master in Slave Out
always@(posedge(r_sclk))
    if(!r_spi_drv_rdy)
        begin
            r_rx_miso <= {r_rx_miso[SPI_MAXLEN-2:0],MISO}; 
        if (transfer_complete)
            begin
                bits_transfered <=0;
                r_spi_drv_rdy <= 1;
                r_SS_N <= 1;
            end
        end
endmodule
