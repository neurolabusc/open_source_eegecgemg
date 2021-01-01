//Reprogram BlueTooth module to operate at higher speeds
// Warning: it is possible to reset Bluetooth module to operate at a speed faster than you can re-connect to it in the future. 
//          Tested with Teensy2,Teensy3,ArduinoLeonardo,ArduinoDue -older Arduinos do not have hardware serial and can not support fast serial port speeds
//After uploading sketch to Arduino select Tools/SerialMonitor to start reprogramming module and observe progress
//----Typically no need to edit lines below---------------

char*  pin =         "0000";                    // Pairing Code for Module, 4 digits only.. (0000-9999)
#if defined(__SAM3X8E__) //if Arduino Due
  #define WiredSerial SerialUSB //Due Native port
  const long bps = 115200;//desired bps
  char* name =    "us115k0000bt";//"us922k0000bt"; //any name you want -Teensy/Arduino names start "usbmodem", so  "us" can help detect if Teensy is attached, you could also add pin number (0000)
  int led =         13;  // Pin of Blinking LED, pin 13 for Arduino/Teensy3, Pin 11 for Teensy2
  //For Due:  Connect BtRx to Tx1 (pin18) and BtTx to Rx1 (pin 19)
#elif defined(__MK20DX128__) //if Teensy 3.0...
  #define WiredSerial Serial
  const long bps =  460800;//desired bps
  char* name =    "us461k0000bt";//"us922k0000bt"; //any name you want -Teensy/Arduino names start "usbmodem", so  "us" can help detect if Teensy is attached, you could also add pin number (0000)
  int led =         13;  // Pin of Blinking LED, pin 13 for Arduino/Teensy3, Pin 11 for Teensy2
  #define Hardserial
  //For Teensy 3: Connect BtRx to Tx1 (pin1) and BtTx to Rx1 (pin 0)
#elif defined(__AVR_ATmega32U4__) && defined(CORE_TEENSY)  //if Teensy 2.0...
  #define WiredSerial Serial
  const long bps = 115200;//desired bps
  char* name =    "us115k0000bt";//"us922k0000bt"; //any name you want -Teensy/Arduino names start "usbmodem", so  "us" can help detect if Teensy is attached, you could also add pin number (0000)
  int led =         11;   // Pin of Blinking LED, pin 13 for Arduino/Teensy3, Pin 11 for Teensy2
  //For Teensy2:  Connect BtRx to Tx (pin8) and BtTx to Rx (pin 7)
#else //assume AVR devices like a Leonardo 
  #define WiredSerial Serial
  const long bps = 19200; //desired BPS
  char* name =    "us19k0000bt";//any name you want -Teensy/Arduino names start "usbmodem", so  "us" can help detect if Teensy is attached, you could also add pin number (0000)
  int led =         13;  // Pin of Blinking LED, pin 13 for Arduino/Teensy3, Pin 11 for Teensy2
  //For Leonardo:  Connect BtRx to Tx1 (pin1) and BtTx to Rx1 (pin 0)
#endif

#define bt Serial1 //Bluetooth module attached to Serial1 (pins TX1/RX1)
//HardwareSerial bt = HardwareSerial(); //If you get an error here, uncomment line #define Hardserial 
//#include <SoftwareSerial.h> //If you get an error here, comment this line
//SoftwareSerial    bt(0, 1);  //If you get an error here, comment out line #define Hardserial and uncomment "#include <SoftwareSerial.h>"


// Bluetooth Programming Sketch for Teensy 3.0 v0.9
// By: Chris Rorden based on Arduino code by Ryan Hunt <admin@nayr.net>
// License: CC-BY-SA
//
// Standalone Bluetooth Programer for setting up inexpensive bluetooth modules running linvor firmware.
// This Sketch expects a BT device to be plugged in upon start. 
// You can open Serial Monitor to watch the progress or wait for the LED to blink rapidly to signal programing is complete.
// If programming fails it will enter command where you can try to do it manually through the Arduino Serial Monitor.
// When programming is complete it will send a test message across the line, you can see the message by pairing and connecting
// with a terminal application. (screen for linux/osx, hyperterm for windows)
//
// Hookup BT-RX to PIN 1 (Arduino TX), BT-TX to PIN 0 (Arduino-RX), 5v and GND to your bluetooth module.
//
// WARNING: Some Arduino's (Uno) and Teensy 2 use 5v signalling, but Bluetooth expects 3.3v. For these devices use a voltage divider
//            http://www.instructables.com/id/Cheap-2-Way-Bluetooth-Connection-Between-Arduino-a/step3/Wiring-the-Arduino-Bluetooth-transceiver/
//         Fortunately,  Teensy3 and Leonardo use 3.3v signalling so they can be connected directly without resistors
//
// Defaults are for OpenEMG Use, For more information visit: http://wiki.openpilot.org/display/Doc/Serial+Bluetooth+Telemetry
//  For details see https://github.com/ArcBotics/Hexy/wiki/Bluetooth

 const int numPossibleBps = 12;
 long possibleBps[numPossibleBps] = {1200, 2400, 4800, 9600, 19200, 38400, 57600,115200, 230400, 460800, 921600, 1382400};
 long origBpsIndex = 3; //original BPS - typically 3rd index = 9600 bps
 int wait = 1000;
 void setup()
{
  pinMode(led, OUTPUT);
  digitalWrite(led, LOW); // Turn off LED to signal waiting for Terminal
  delay(1000);  // Catch Due reset problem
  WiredSerial.begin(9600); //use native port on Due
  while (WiredSerial.read() >= 0) {} //http://forum.arduino.cc/index.php?topic=134847.0
  delay(200);  // Catch Due reset probleme
  while (!WiredSerial) ; //Teensy2 users may need to comment this line - required by Leonardo http://arduino.cc/en/Serial/IfSerial (ads129n requires 3.3v signals, Leonardo is 5v)
  digitalWrite(led, HIGH);                 // Turn on LED to signal programming has started
  WiredSerial.println("Configuring bluetooth module for use with OpenEMG, please wait.");
  //attempt connection
  int index = origBpsIndex;
  bt.begin(possibleBps[index]);                          // Speed of your bluetooth module, 9600 is default from factory.
  delay(wait);
  bt.print("AT");
  delay(wait);
  //test for good connection
  int  resp =   bt.read();
  if (resp == -1) index = 0;
  while ((resp == -1) && (index < numPossibleBps)) {
     bt.begin(possibleBps[index]);// Speed of your bluetooth module, 9600 is default from factory.
     WiredSerial.print("Attempting to connect at "); WiredSerial.print(possibleBps[index]); WiredSerial.println("bps");
     delay(wait);
     bt.print("AT");
     delay(wait);
     resp = bt.read();
     if (resp == -1) index ++;
  } //while no response
  if (resp == -1) {
    WiredSerial.println("ERROR: no response from Bluetooth device. Please check connections and origbps ");
    digitalWrite(led, LOW);
  } else {
     WiredSerial.print("Successfully connected at "); WiredSerial.print(possibleBps[index]); WiredSerial.println("bps");  
  }   
  bt.print("AT+VERSION");
    delay(wait);
 
    
  WiredSerial.print("Setting PIN : ");WiredSerial.println(pin);
  bt.print("AT+PIN"); bt.print(pin); 
    delay(wait);
  WiredSerial.print("Setting NAME: "); WiredSerial.println(name);
  bt.print("AT+NAME");
  bt.print(name); 
    delay(wait);
  WiredSerial.print("Setting BAUD: "); WiredSerial.println(bps); //Report baud rate
  switch (bps) {
    case 1200:
      bt.print("AT+BAUD1");
      break;
    case 2400:
      bt.print("AT+BAUD2");
      break;
    case 4800:
      bt.print("AT+BAUD3");
      break;
    case 9600:
      bt.print("AT+BAUD4");
      break;
    case 19200:
      bt.print("AT+BAUD5");
      break;
    case 38400:
      bt.print("AT+BAUD6");
      break;
    case 57600:
      bt.print("AT+BAUD7");
      break;
    case 115200:
      bt.print("AT+BAUD8");
      break;
    case 230400:
       bt.print("AT+BAUD9");
       break;
    case 460800:
      bt.print("AT+BAUDA");
      break;
    case 921600:
      bt.print("AT+BAUDB");
      break;
    case 1382400:
      bt.print("AT+BAUDC");
      break;  
    default: 
      bt.print("AT+BAUD4"); //9600 
      WiredSerial.println("WARNING: Unknown baud rate - setting to default 9600bps"); 
  }
  delay(wait);
  WiredSerial.println("Hopefully bluetooth device is reset");
}

void loop() {
  // nothing to do, its all in the interrupt handler!
}  
 
