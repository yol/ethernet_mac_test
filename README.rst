ethernet_mac benchmark test application
=======================================

This project is intended to benchmark the performance of the ethernet_mac tri-mode full-duplex Ethernet MAC and test its function on hardware. The project targets the Xilinx Spartan 6 device, and more specifically, the `Trenz Electronic GigaBee platform <http://www.trenz-electronic.de/products/fpga-boards/trenz-electronic/te0600.html>`_.

The benchmark consists of two parts: A design for the FPGA and a C++ application running on a personal computer that is connected to the FPGA board via Ethernet. The C++ application was tested only on Linux, but should run on all POSIX operating systems that support raw sockets. The supported benchmarks are:

+ Full loopback: The PC continously sends packets as fast as it can, which are then looped back identically by the MAC.
+ FPGA max TX data rate: The FPGA continously sends packets on its own. The PC only monitors the incoming data rate.

Usually, the NIC and OS of the PC will not be fast enough to achieve full Gigabit Ethernet data rate transmission, so the second test is needed to measure the maximum 
data rate the FPGA can transmit.

Dependencies
============

You will need:

+ Xilinx ISE 14.7 (webpack edition is free)
+ A recent C++ compiler capable of C++11
+ cmake
+ Boost ASIO
+ ethernet_mac (included)
+ A Trenz Electronic GigaBee FPGA module (TE0600) and baseboard (TE0603)
+ git

Checkout
========

Clone the git repository with git::

    $ git clone https://github.com/pkerling/ethernet_mac_test
    $ cd ethernet_mac_test
    $ git submodule init
    $ git submodule update

Benchmark PC application compilation
====================================

To compile the C++ benchmark application running on the PC, issue the following commands in the project folder::

    $ mkdir pc/build
    $ cd pc/build
    $ cmake ..
    $ make

Build in ISE 
============

+ Open the project file ethernet_mac_test.xise in the ISE project navigator
+ Select the root node "xc6slx45-2fgg484" in the hierarchy view
+ Run the "Regenerate All Cores" process under "Design Utilities"
+ Select the "ethernet_mac_test" top module in the hierarchy view
+ Run the "Generate Programming File" process"
+ Download the generated file ethernet_mac_test.bit to the device using iMPACT or any other means

The default project settings are for an Spartan-6 XC6SLX45-2 FPGA. You need to modify
them if you have a different device.

Setup and Test
==============

::
        
        +----------------+                 +----------------+
        | PC             |                 | TE0603         |
        |                |   POWER =======>o                |
        |                |                 |                |
        |          JTAG  o<===============>o JTAG           |
        |                |                 |                |
        |          ETH0  o<===============>o ETHERNET       |
        +----------------+                 +----------------+

..

Connect the PC Ethernet port to the GigaBee baseboard.

To run the loopback benchmark, make sure the TEST_MODE constant in ethernet_mac_test.vhd is
set to TEST_LOOPBACK, the corresponding design was uploaded to the device and then execute::
    
    # pc/build/benchmark -i <Ethernet interface name> -t 60
    
This performs the loopback test for 60 seconds.

To run the TX benchmark, make sure the TEST_MODE constant in ethernet_mac_test.vhd is
set to TEST_TX, the corresponding design was uploaded to the device and then execute::

    # pc/build/benchmark -i <Ethernet interface name> -t 60 -r
    
You can execute the benchmark executable without any arguments to see all commandline
options available.
