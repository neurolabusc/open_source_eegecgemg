By default, Bluetooth modules are configured at 9600bps. The purpose of this script is to reprogram the Bluetooth module to communicate at a higher speed, which is crucial for applications where more bandwidth is needed (wireless oscilloscope, drone, electrophysiological recording). The script Bluetooth_Programmer_EMG is based on Ryan Hunt's Bluetooth_Programmer_v1_1 but includes a number of changes to support (a) Teensy 3 (hardware rather than software serial), (b) ability to detect original bps of bluetooth system, (c) additional transmission speeds. 


To use:
	1 Connect your bluetooth card to your Arduino
	  a.) connect ground of card to Arduino GND
          b.) If you have a JY-MCU or other card with 3.6-6v power, connect Vcc to Arduino 5v
	  c.) If you have a BC4 or other card with 3.3v power, connect Vcc to Arduino 3.3v
          d.) If you have an Arduino with 5v signals (e.g. Teensy2, Uno, Leonardo) connect the bluetooth module to your Arduino with a voltage divider 
		http://www.instructables.com/id/Cheap-2-Way-Bluetooth-Connection-Between-Arduino-a/step3/Wiring-the-Arduino-Bluetooth-transceiver/
	  e.) If you have an Arduino with 3.3v signals (e.g. Teensy 3, Due), you can directly wire the card RX to the Arduino TX and the card TX to the Arduino RX.
	2 Open the sketch "Bluetooth_Programmer_Ard" with the Arduino software. 
	3 Make sure the Tools/Board and Tools/SerialPort menus are set correctly
        4 Press the "Upload" button to run your sketch.
        5 Select Tools/SerialMonitor to check the progress of your changes.



Copyright CC-BY-SA by Ryan Hunt <admin@nayr.net>
 modified by Chris Rorden, 5/2013
More info: http://forums.openpilot.org/topic/15044-bluetooth-programming-sketch-for-arduino/